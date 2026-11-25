;;; autolisp-dape.el --- Debug AutoLISP with dape -*- lexical-binding: t -*-

;; SPDX-License-Identifier: Apache-2.0

;;; Commentary:

;; Connects dape to AutoLispDebugAdapter.exe, which ships next to acad.exe
;; in AutoCAD 2021 and later and speaks the Debug Adapter Protocol.
;;
;;   M-x dape RET autolisp-attach   debug a running AutoCAD
;;   M-x dape RET autolisp-launch   start AutoCAD and debug it
;;
;; The adapter has no pause, conditional or data breakpoints, logpoints or
;; variable setting, and AutoCAD LT cannot be debugged.

;;; Code:

(require 'cl-lib)
(require 'seq)
(eval-and-compile
  (add-to-list
   'load-path
   (file-name-directory
    (or load-file-name
        (and (boundp 'byte-compile-current-file)
             byte-compile-current-file)
        buffer-file-name))))

(require 'autolisp-data)

(defvar dape-configs)
(defvar dape--connections)
(declare-function dape "dape")
(declare-function dape-request "dape")
(declare-function dape--live-connection "dape")
(declare-function dape-evaluate-expression "dape")
(declare-function dape--config "dape" t t)
(declare-function dape--current-thread "dape")
(declare-function dape--stopped-threads "dape")
(declare-function dape-kill "dape")
(declare-function dape-handle-event "dape")

(defcustom autolisp-autocad-program nil
  "Path to acad.exe, used by `autolisp-launch'.
When nil, use the newest AutoCAD found on this machine."
  :type '(choice (const :tag "Detect" nil) file)
  :group 'autolisp)

(defcustom autolisp-launch-parameters nil
  "Command-line switches given to AutoCAD by `autolisp-launch'.
A string passed as it stands, for example
\"/product C3D /p \\\"<<C3D_Imperial>>\\\"\"."
  :type '(choice (const :tag "None" nil) string)
  :group 'autolisp)

(defcustom autolisp-process-name "acad"
  "Name of the process to attach to, without its extension."
  :type 'string
  :group 'autolisp)

(defface autolisp-runtime-error
  '((t :inherit flymake-error))
  "Face for the code that raised a runtime error."
  :group 'autolisp)

;;;; Finding AutoCAD

(defun autolisp-dape--adapter (program)
  "Return the debug adapter next to acad.exe PROGRAM."
  (let ((adapter (expand-file-name "AutoLispDebugAdapter.exe"
                                   (file-name-directory program))))
    (unless (file-exists-p adapter)
      (user-error "No AutoLISP debug adapter at %s (AutoCAD 2021 or later needed)"
                  adapter))
    adapter))

(defun autolisp-dape--program ()
  "Return the acad.exe to launch."
  (let ((program (or autolisp-autocad-program
                     (car (autolisp-data-autocad-programs)))))
    (unless (and program (file-exists-p program))
      (user-error "AutoCAD not found; set `autolisp-autocad-program'"))
    program))

(defun autolisp-dape--pids ()
  "Return the process ids of running AutoCADs."
  (let ((name (concat (downcase autolisp-process-name) ".exe")))
    (seq-filter (lambda (pid)
                  (equal (downcase (or (alist-get 'comm (process-attributes pid)) ""))
                         name))
                (list-system-processes))))

(defun autolisp-dape--process-details (pids)
  "Return an alist of (PID PATH TITLE) for PIDS, using PowerShell.
Return nil if that fails."
  (when-let* ((shell (or (executable-find "pwsh") (executable-find "powershell"))))
    (with-temp-buffer
      (when (eql 0 (ignore-errors
                     (call-process
                      shell nil '(t nil) nil "-NoProfile" "-NonInteractive" "-Command"
                      (format "Get-Process -Id %s | ForEach-Object { '{0}|{1}|{2}' -f $_.Id, $_.Path, $_.MainWindowTitle }"
                              (mapconcat #'number-to-string pids ",")))))
        (mapcar (lambda (line)
                  (pcase-let ((`(,pid ,path . ,title) (split-string line "|")))
                    (list (string-to-number pid)
                          (and path (not (string-empty-p path)) path)
                          (string-join title "|"))))
                (split-string (buffer-string) "[\r\n]+" t))))))

(defun autolisp-dape--choose-process ()
  "Choose a running AutoCAD and return (PID PATH TITLE)."
  (let ((pids (autolisp-dape--pids)))
    (unless pids
      (user-error "No running %s.exe to attach to" autolisp-process-name))
    (let* ((details (or (autolisp-dape--process-details pids)
                        (mapcar (lambda (p) (list p nil "")) pids)))
           (choices (mapcar (lambda (d) (cons (format "%d  %s" (car d) (nth 2 d)) d))
                            details)))
      (if (cdr choices)
          (cdr (assoc (completing-read "Attach to: " choices nil t) choices))
        (cdar choices)))))

;;;; Configurations

(defun autolisp-dape--file-name (file)
  "Return FILE the way VS Code gives it to the adapter."
  (let ((file (expand-file-name file)))
    (if (eq system-type 'windows-nt)
        (string-replace "/" "\\" file)
      file)))

(defun autolisp-dape--source ()
  "Return the file to report as the program being debugged."
  (if buffer-file-name (autolisp-dape--file-name buffer-file-name) ""))

(defun autolisp-dape--remote-name (function conn file &rest args)
  "Call FUNCTION with CONN, FILE and ARGS, as advice for dape.
Give AutoLISP adapters native file names, so that breakpoints match."
  (let ((name (apply function conn file args)))
    (if (and (stringp name) (autolisp-dape--connection-p conn))
        (autolisp-dape--file-name name)
      name)))

(defun autolisp-dape--attach-config (config)
  "Fill in CONFIG for attaching to a running AutoCAD."
  (let* ((given (plist-get config :processId))
         (process (if (and given (not (equal given "")))
                      (or (assoc (string-to-number (format "%s" given))
                                 (autolisp-dape--process-details
                                  (list (string-to-number (format "%s" given)))))
                          (list given nil nil))
                    (autolisp-dape--choose-process)))
         (program (or (nth 1 process) (autolisp-dape--program))))
    (setq config (plist-put config 'command (autolisp-dape--adapter program)))
    ;; AutoLispExt sends the id as a string.
    (setq config (plist-put config :processId (format "%s" (car process))))
    (plist-put config :program (autolisp-dape--source))))

(defun autolisp-dape--launch-config (config)
  "Fill in CONFIG for launching AutoCAD."
  (let ((program (autolisp-dape--program)))
    (setq config (plist-put config 'command (autolisp-dape--adapter program)))
    (setq config (plist-put config 'command-args
                            `("--" ,(autolisp-dape--file-name program)
                              ,@(and autolisp-launch-parameters
                                     (list autolisp-launch-parameters)))))
    (plist-put config :program (autolisp-dape--source))))

(defun autolisp-dape--current-frame (function conn)
  "Call FUNCTION with CONN, as advice for `dape--current-stack-frame'.
AutoCAD reports frames of its own, such as :BREAK-POINT, with no source
and an id of 0.  Prefer the innermost frame of the user's code, so that
variables and evaluation refer to that."
  (let ((frame (funcall function conn)))
    (if (and frame conn (eql 0 (plist-get frame :id))
             (autolisp-dape--connection-p conn))
        (or (seq-find (lambda (f) (plist-get f :source))
                      (plist-get (dape--current-thread conn) :stackFrames))
            frame)
      frame)))

(defconst autolisp-dape-configs
  '((autolisp-attach
     modes (autolisp-mode autolisp-dcl-mode)
     fn autolisp-dape--attach-config
     :type "attachlisp"
     :name "AutoLISP Debug: Attach"
     :request "attach")
    (autolisp-launch
     modes (autolisp-mode autolisp-dcl-mode)
     fn autolisp-dape--launch-config
     :type "launchlisp"
     :name "AutoLISP Debug: Launch"
     :request "launch"))
  "Entries added to `dape-configs'.")

(defun autolisp-dape--start (key &rest properties)
  "Start the dape configuration KEY with PROPERTIES added."
  (unless (require 'dape nil t)
    (user-error "Install the `dape' package to debug AutoLISP"))
  (let ((config (copy-tree (alist-get key dape-configs))))
    (while properties
      (setq config (plist-put config (pop properties) (pop properties))))
    (dape config)))

;;;###autoload
(defun autolisp-debug-attach ()
  "Debug a running AutoCAD, loading the current file into it.
Everything in that AutoCAD waits while a breakpoint is stopped."
  (interactive)
  (autolisp-dape--start 'autolisp-attach))

;;;###autoload
(defun autolisp-debug-launch ()
  "Start AutoCAD and debug it."
  (interactive)
  (autolisp-dape--start 'autolisp-launch))

;;;; Requests

(defun autolisp-dape--connection ()
  "Return the live AutoLISP debug connection, or signal an error."
  (let ((conn (and (featurep 'dape) (dape--live-connection 'parent t))))
    (unless (and conn (autolisp-dape--connection-p conn))
      (user-error "Attach to or launch AutoCAD first (M-x autolisp-debug-attach)"))
    conn))

(defun autolisp-dape--connection-p (conn)
  "Return non-nil if CONN is debugging AutoLISP."
  (member (plist-get (dape--config conn) :type) '("attachlisp" "launchlisp")))

;;;###autoload
(defun autolisp-load-file ()
  "Load the current file into the AutoCAD being debugged.
Offers to save it first."
  (interactive)
  (let ((conn (autolisp-dape--connection)))
    (unless (and buffer-file-name
                 (string-match-p "\\.\\(?:lsp\\|mnl\\|dcl\\)\\'"
                                 (downcase buffer-file-name)))
      (user-error "Not visiting an LSP, MNL or DCL file"))
    (when (and (buffer-modified-p)
               (y-or-n-p (format "Save %s first? " (buffer-name))))
      (save-buffer))
    (autolisp-dape-clear-errors)
    (let ((name (file-name-nondirectory buffer-file-name)))
      (dape-request conn :customLoad
                    (autolisp-dape--file-name buffer-file-name)
                    (lambda (_body error)
                      ;; AutoCAD loads a file once per session; the REPL
                      ;; shows why it refused.
                      (message "%s"
                               (if error
                                   (substitute-command-keys
                                    (format "AutoCAD did not load %s (see *dape-repl*); \\[autolisp-reload-file] reconnects and loads it"
                                            name))
                                 (format "Loaded %s" name))))))))

;;;###autoload
(defun autolisp-reload-file ()
  "Reconnect to AutoCAD and load the current file again.
AutoCAD loads a file only once per debug session, even if it has changed
since, so this ends the session and attaches to the same AutoCAD again.
Breakpoints are kept."
  (interactive)
  (let* ((conn (autolisp-dape--connection))
         (config (dape--config conn))
         (buffer (current-buffer)))
    (unless (equal (plist-get config :type) "attachlisp")
      ;; Ending a launched session may close AutoCAD.
      (user-error "Only an attached session can be reconnected"))
    (when (dape--stopped-threads conn)
      (user-error "AutoCAD is stopped; continue first"))
    (unless buffer-file-name
      (user-error "Not visiting a file"))
    (when (and (buffer-modified-p)
               (y-or-n-p (format "Save %s first? " (buffer-name))))
      (save-buffer))
    (dape-kill conn
               (lambda (&rest _)
                 (with-current-buffer buffer
                   (autolisp-dape--start 'autolisp-attach
                                         :processId (plist-get config :processId)))))))

(defun autolisp-eval-region (beg end)
  "Evaluate the code between BEG and END in AutoCAD."
  (interactive "r")
  (dape-evaluate-expression (autolisp-dape--connection)
                            (buffer-substring-no-properties beg end) "repl"))

(defun autolisp-eval-last-sexp ()
  "Evaluate the expression before point in AutoCAD."
  (interactive)
  (autolisp-eval-region (save-excursion (backward-sexp) (point)) (point)))

(defun autolisp-eval-defun ()
  "Evaluate the top-level form around point in AutoCAD."
  (interactive)
  (save-excursion
    (end-of-defun)
    (let ((end (point)))
      (beginning-of-defun)
      (autolisp-eval-region (point) (progn (goto-char end)
                                           (skip-chars-backward " \t\n")
                                           (point))))))

;;;; Runtime errors

(defvar autolisp-dape--error-overlays nil)

(defun autolisp-dape-clear-errors ()
  "Remove the runtime error markers."
  (interactive)
  (mapc #'delete-overlay autolisp-dape--error-overlays)
  (setq autolisp-dape--error-overlays nil))

(defun autolisp-dape--position (line column)
  "Return the buffer position of one-based LINE and zero-based COLUMN."
  (save-excursion
    (goto-char (point-min))
    (forward-line (1- (max 1 (or line 1))))
    (min (line-end-position) (+ (point) (max 0 (or column 0))))))

(defun autolisp-dape--show-error (body)
  "Mark the runtime error described by event BODY."
  (let ((file (plist-get body :file))
        (text (or (plist-get body :message) "runtime error")))
    (if (not (and (stringp file) (file-readable-p file)))
        (message "AutoLISP error: %s" text)
      (with-current-buffer (find-file-noselect file)
        (save-restriction
          (widen)
          (let* ((beg (autolisp-dape--position (plist-get body :startline)
                                               (plist-get body :startcol)))
                 (end (max (min (1+ beg) (point-max))
                           (autolisp-dape--position (plist-get body :endline)
                                                    (plist-get body :endcol))))
                 (ov (make-overlay beg end)))
            (overlay-put ov 'face 'autolisp-runtime-error)
            (overlay-put ov 'help-echo text)
            (overlay-put ov 'autolisp-error text)
            (push ov autolisp-dape--error-overlays)
            (message "%s:%s: %s" (file-name-nondirectory file)
                     (plist-get body :startline) text)))))))

(defun autolisp-dape-error-at-point ()
  "Return the runtime error text at point, or nil."
  (seq-some (lambda (o) (overlay-get o 'autolisp-error)) (overlays-at (point))))

(with-eval-after-load 'dape
  (dolist (c autolisp-dape-configs)
    (setf (alist-get (car c) dape-configs) (copy-tree (cdr c))))
  (add-hook 'dape-start-hook #'autolisp-dape-clear-errors)
  (advice-add 'dape--file-name-remote :around #'autolisp-dape--remote-name)
  (advice-add 'dape--current-stack-frame :around #'autolisp-dape--current-frame)
  ;; Evaluated here because the generic function is defined by dape.
  (eval
   '(progn
      (cl-defmethod dape-handle-event (_conn (_event (eql runtimeerror)) body)
        "Mark an AutoLISP runtime error in its source."
        (autolisp-dape--show-error body))
      (cl-defmethod dape-handle-event (_conn (_event (eql acadnosupport)) _body)
        "Report an AutoCAD that cannot be debugged."
        (message "This AutoCAD cannot debug AutoLISP; 2021 or later is needed"))
      (cl-defmethod dape-handle-event (_conn (_event (eql dgbfatalerr)) body)
        "Report a fatal error in the AutoLISP debugger."
        (message "AutoLISP debugger: %s" (plist-get body :message))))
   t))

(provide 'autolisp-dape)
;;; autolisp-dape.el ends here
