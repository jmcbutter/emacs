;;; live-test.el --- Debug test against a running AutoCAD -*- lexical-binding: t -*-

;;; Commentary:

;; Attaches to the only running AutoCAD, stops at a breakpoint in
;; live-test.lsp, steps, and disconnects.  AutoCAD freezes while stopped, so
;; every wait is limited and the end always continues and disconnects.
;;
;; emacs -Q --batch -L . -L JSONRPC -L DAPE -l test/live/live-test.el
;;
;; Attaching makes the adapter load live-test.lsp, which is what reaches the
;; breakpoint.  With LIVE_STAGE=attach no breakpoint is set.

;;; Code:

(require 'autolisp-mode)
(require 'dape)

(defvar live-dir (file-name-directory load-file-name))
(defvar live-failed nil)
(defvar live-stops nil "Bodies of stopped events, latest first.")
(defvar live-outputs nil)
(defvar live-attached nil)

(setq dape-debug t
      dape-start-hook (remq 'dape-info dape-start-hook)
      create-lockfiles nil make-backup-files nil
      enable-local-variables nil)

(defun live-log (ok format &rest args)
  (unless ok (setq live-failed t))
  (message "%s %s" (if ok "PASS" "FAIL") (apply #'format format args))
  ok)

(defun live-wait (pred seconds)
  (let ((end (+ (float-time) seconds)) ok)
    (while (and (not (setq ok (funcall pred))) (< (float-time) end))
      (accept-process-output nil 0.05))
    ok))

(defun live-conn () (dape--live-connection 'parent t))

(defun live-request (command args &optional seconds)
  "Send COMMAND with ARGS and return (BODY ERROR), or `timeout'."
  (let ((result 'timeout))
    (dape-request (live-conn) command args
                  (lambda (body error) (setq result (list body error))))
    (live-wait (lambda () (not (eq result 'timeout))) (or seconds 8))
    result))

(advice-add 'dape-handle-event :before
            (lambda (_conn event body)
              (pcase event
                ('stopped (push body live-stops))
                ('output (push (plist-get body :output) live-outputs)))))

(defun live-frames (thread)
  (plist-get (car-safe (live-request :stackTrace (list :threadId thread)))
             :stackFrames))

(defun live-variables (frame)
  "Return an alist of the variables of FRAME."
  (let (out)
    (seq-doseq (scope (plist-get (car-safe (live-request :scopes (list :frameId frame)))
                                 :scopes))
      (seq-doseq (v (plist-get (car-safe (live-request
                                          :variables
                                          (list :variablesReference
                                                (plist-get scope :variablesReference))))
                               :variables))
        (push (cons (plist-get v :name) (plist-get v :value)) out)))
    (nreverse out)))

(defun live-evaluate (expression &optional frame)
  (plist-get (car-safe (live-request :evaluate
                                     (append (and frame (list :frameId frame))
                                             (list :expression expression
                                                   :context "repl"))))
             :result))

(defun live-release ()
  "Leave AutoCAD running, whatever state the test is in."
  (ignore-errors (dape-breakpoint-remove-all))
  (live-wait #'ignore 0.5)
  (when (live-conn)
    (ignore-errors
      (dotimes (_ 3)
        (when (dape--stopped-threads (live-conn))
          (dape-continue (live-conn))
          (live-wait #'ignore 1.5))))
    (when (and live-attached (not (dape--stopped-threads (live-conn))))
      (ignore-errors (live-evaluate "(setq emacs:live-test nil)")))
    (ignore-errors
      (dape-disconnect-quit (live-conn)))
    (live-wait (lambda () (null (live-conn))) 5))
  (setq kill-emacs-hook nil)
  (live-log (null (live-conn)) "disconnected"))

(defun live-run ()
  (find-file (expand-file-name "live-test.lsp" live-dir))
  (unless (= 1 (length (autolisp-dape--pids)))
    (error "Need exactly one running AutoCAD, found %S" (autolisp-dape--pids)))
  (unless (equal (getenv "LIVE_STAGE") "attach")
    (goto-char (point-min))
    (search-forward "(setq b")
    (dape-breakpoint-toggle))
  (autolisp-debug-attach)
  (live-wait (lambda () (or (null (live-conn)) live-stops live-outputs)) 20)
  (setq live-attached (and (live-conn) t))
  (when (live-log live-attached "attached (thread %S)"
                  (and (live-conn) (dape--thread-id (live-conn))))
    (unless (equal (getenv "LIVE_STAGE") "attach")
      (message "Waiting up to 60 s for the breakpoint; AutoCAD may ask to load the file")
      (when (live-log (live-wait (lambda () live-stops) 60) "stopped at breakpoint: %S"
                      (car live-stops))
        (let* ((thread (or (plist-get (car live-stops) :threadId) 1))
               (frames (live-frames thread))
               (top (progn
                      ;; What dape shows as current.
                      (live-wait (lambda () (dape--current-stack-frame (live-conn))) 5)
                      (dape--current-stack-frame (live-conn)))))
          (live-log (equal 4 (plist-get top :line)) "line %S in %S (%d frames)"
                    (plist-get top :line) (plist-get top :name) (length frames))
          (message "     source %S" (plist-get top :source))
          (message "     variables %S" (live-variables (plist-get top :id)))
          (setq live-outputs nil)
          (live-evaluate "a" (plist-get top :id))
          (live-log (live-wait (lambda () (live-output-p "\\`40[\r\n]")) 5) "a = 40")
          (message "     hover %S" (live-request :evaluate
                                                 (list :frameId (plist-get top :id)
                                                       :expression "a" :context "hover")))
          (message "     watch %S" (live-request :evaluate
                                                 (list :frameId (plist-get top :id)
                                                       :expression "(+ a n)" :context "watch")))
          (setq live-stops nil)
          (dape-next (live-conn))
          (live-log (live-wait (lambda () live-stops) 10) "stepped")
          (let* ((frames (live-frames thread))
                 (top (seq-find (lambda (f) (plist-get f :source)) frames)))
            (message "     now at line %S" (plist-get top :line))
            (setq live-outputs nil)
            (live-evaluate "b" (plist-get top :id))
            (live-log (live-wait (lambda () (live-output-p "\\`41[\r\n]")) 5) "b = 41"))
          (dape-breakpoint-remove-all)
          (live-wait #'ignore 0.5)
          (dape-continue (live-conn))
          (live-log (live-wait (lambda () (null (dape--stopped-threads (live-conn)))) 10)
                    "continued")
          (live-wait #'ignore 1.5)
          (setq live-outputs nil)
          (live-evaluate "(+ 1 2)")
          (live-log (live-wait (lambda () (live-output-p "\\`3[\r\n]")) 5)
                    "evaluate while running printed %S" live-outputs)
          (live-errors)
          (live-reload))))))

(defun live-output-p (regexp)
  (seq-some (lambda (o) (string-match-p regexp (or o ""))) live-outputs))

(defun live-reload ()
  "Load a file, change it, and load it again."
  (let* ((dir (file-name-as-directory (make-temp-file "emacs-live" t)))
         (file (concat dir "reload.lsp")))
    (with-temp-file file (insert "(setq emacs:live-test 1)\n"))
    (with-current-buffer (find-file-noselect file)
      (setq live-outputs nil)
      (autolisp-load-file)
      (live-log (live-wait (lambda () (live-output-p "loaded from")) 10) "customLoad, new file")
      (setq live-outputs nil)
      (autolisp-load-file)
      (live-log (live-wait (lambda () (live-output-p "already loaded")) 10)
                "customLoad, unchanged file refused")
      ;; AutoCAD may compare modification times by the second.
      (live-wait #'ignore 2.5)
      (goto-char (point-max))
      (insert "(setq emacs:live-test 2)\n")
      (let ((save-silently t)) (save-buffer))
      (live-wait #'ignore 1.5)
      (setq live-outputs nil)
      (autolisp-load-file)
      ;; AutoCAD 2027 will not reload a changed file within one session.
      (live-log (live-wait (lambda () (live-output-p "can't be reloaded")) 10)
                "customLoad, changed file refused")
      (message "     %S" live-outputs))
    (delete-directory dir t)))

(defun live-errors ()
  "Raise an error from a file and check that it is marked."
  (let* ((dir (file-name-as-directory (make-temp-file "emacs-live" t)))
         (file (concat dir "fails.lsp")))
    (with-temp-file file
      (insert "(defun emacs:live-test ()\n  (car 5)\n)\n(emacs:live-test)\n"))
    (with-current-buffer (find-file-noselect file)
      (setq live-stops nil)
      (autolisp-load-file)
      (live-log (live-wait (lambda () live-stops) 10) "break on error: %S" (car live-stops))
      (live-log (live-wait (lambda () autolisp-dape--error-overlays) 5)
                "runtime error marked: %S"
                (mapcar (lambda (o) (list (overlay-get o 'autolisp-error)
                                          (with-current-buffer (overlay-buffer o)
                                            (buffer-substring (overlay-start o) (overlay-end o)))))
                        autolisp-dape--error-overlays))
      (dape-continue (live-conn))
      (live-log (live-wait (lambda () (null (dape--stopped-threads (live-conn)))) 10)
                "continued after the error")
      (live-wait #'ignore 1.5))
    (delete-directory dir t)))

(condition-case err
    (live-run)
  ((error quit) (live-log nil "%S" err)))
(defvar live-events
  (mapconcat (lambda (b)
               (if (string-search "events" (buffer-name b))
                   (with-current-buffer b (buffer-string))
                 ""))
             (buffer-list) ""))
(live-release)
(message "--- repl output: %S" (seq-take (reverse live-outputs) 20))
(message "--- events before release
%s" live-events)
(kill-emacs (if live-failed 1 0))

;;; live-test.el ends here
