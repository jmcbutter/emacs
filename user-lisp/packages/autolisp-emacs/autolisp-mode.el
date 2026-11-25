;;; autolisp-mode.el --- Major mode for AutoCAD AutoLISP -*- lexical-binding: t -*-

;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; Keywords: languages, lisp, tools
;; SPDX-License-Identifier: Apache-2.0

;;; Commentary:

;; Edit AutoLISP (.lsp, .mnl) in Emacs: highlighting, indentation,
;; completion, signatures, help, xref, rename and doc comments.  Debugging
;; is in autolisp-dape.el, DCL in autolisp-dcl-mode.el and .prj projects in
;; autolisp-project.el; loading this file sets all of them up.
;;
;; The feature set, scoping and indentation rules and reference data come
;; from Autodesk's AutoLispExt for VS Code (Apache-2.0).

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(eval-and-compile
  (add-to-list
   'load-path
   (file-name-directory
    (or load-file-name
        (and (boundp 'byte-compile-current-file)
             byte-compile-current-file)
        buffer-file-name))))

(require 'autolisp-data)
(require 'autolisp-symbols)

(defcustom autolisp-indent-offset 2
  "Columns to indent the body of a form."
  :type 'integer
  :group 'autolisp)

(defcustom autolisp-complete-commands-in
  '("command" "command-s" "vl-cmdf" "getvar" "setvar" "getcname"
    "vla-sendcommand" "vla-postcommand" "vla-getvariable" "vla-setvariable")
  "Functions whose string arguments complete command and variable names.
If t, complete them in every string, as AutoLispExt does."
  :type '(choice (const :tag "Every string" t) (repeat string))
  :group 'autolisp)

;;;; Syntax

(defvar autolisp-mode-syntax-table
  (let ((st (make-syntax-table)))
    (dolist (c (string-to-list "!#$%&*+,-./:<=>?@[]^_`{|}~"))
      (modify-syntax-entry c "_" st))
    (modify-syntax-entry ?\; "<" st)
    (modify-syntax-entry ?\n ">" st)
    (modify-syntax-entry ?\" "\"" st)
    (modify-syntax-entry ?\\ "\\" st)
    (modify-syntax-entry ?' "'" st)
    (modify-syntax-entry ?\( "()" st)
    (modify-syntax-entry ?\) ")(" st)
    st)
  "Syntax table for `autolisp-mode'.")

(defun autolisp--close-block-comment (end)
  "Find the end of the block comment around point, no further than END."
  (if (search-forward "|;" end 'move)
      (put-text-property (1- (point)) (point) 'syntax-table
                         (string-to-syntax "!"))
    (goto-char end)))

(defun autolisp-syntax-propertize (start end)
  "Mark ;| |; block comments between START and END."
  (goto-char start)
  (let ((state (syntax-ppss)))
    (when (eq (nth 7 state) 'syntax-table)
      (autolisp--close-block-comment end)))
  (while (search-forward ";|" end t)
    (let ((beg (match-beginning 0)))
      (unless (nth 8 (save-excursion (syntax-ppss beg)))
        (put-text-property beg (1+ beg) 'syntax-table (string-to-syntax "!"))
        (autolisp--close-block-comment end)))))

;;;; Font lock

(defconst autolisp--special-forms
  '("if" "cond" "while" "repeat" "foreach" "vlax-for" "progn" "lambda"
    "function" "quote" "setq" "set" "and" "or" "not"))

(defun autolisp--match-builtin (limit)
  "Match a built-in function in operator position before LIMIT."
  (let (found)
    (while (and (not found)
                (re-search-forward "(\\s-*\\(\\(?:\\sw\\|\\s_\\)+\\)" limit t))
      (setq found (save-match-data
                    (and (not (nth 8 (syntax-ppss (match-beginning 1))))
                         (autolisp-data-native-p (match-string 1))))))
    found))

(defvar autolisp-font-lock-keywords
  `((,(rx "(" (* space) (group (or "defun-q" "defun")) (+ space)
          (group (+ (or (syntax word) (syntax symbol)))))
     (1 font-lock-keyword-face) (2 font-lock-function-name-face))
    (,(concat "(\\s-*" (regexp-opt autolisp--special-forms t) "\\_>")
     (1 font-lock-keyword-face))
    (,(rx symbol-start (or "t" "nil" "pi" "*error*") symbol-end)
     (0 font-lock-constant-face))
    ("'\\(\\(?:\\sw\\|\\s_\\)+\\)" (1 font-lock-constant-face))
    (autolisp--match-builtin (1 font-lock-builtin-face))
    ("@\\(?:param\\|returns?\\|global\\|remarks?\\|example\\)\\_>"
     (0 font-lock-doc-markup-face prepend))
    (";#\\(?:end\\)?region\\_>" (0 font-lock-preprocessor-face prepend)))
  "Font lock keywords for `autolisp-mode'.")

;;;; Indentation

(defun autolisp--operands (open)
  "Read the list at OPEN up to point.
Return (OPERATOR . OPERANDS), each element (POS . TEXT); TEXT is nil for
lists and strings."
  (let ((limit (point)) items)
    (save-excursion
      (goto-char (1+ open))
      (condition-case nil
          (while (progn (forward-comment (buffer-size))
                        (and (< (point) limit) (not (eq (char-after) ?\)))))
            (let ((beg (point)))
              (forward-sexp 1)
              (push (cons beg (and (not (memq (char-after beg) '(?\( ?\" ?\')))
                                   (buffer-substring-no-properties beg (point))))
                    items)))
        (scan-error nil)))
    (nreverse items)))

(defun autolisp--column (pos)
  "Return the column of POS."
  (save-excursion (goto-char pos) (current-column)))

(defun autolisp--same-line-p (a b)
  "Return non-nil if positions A and B are on one line."
  (save-excursion (goto-char (min a b)) (<= (max a b) (line-end-position))))

(defun autolisp--in-arg-list-p (open)
  "Return non-nil if OPEN starts the argument list of a function."
  (when-let* ((outer (nth 1 (syntax-ppss open))))
    (save-excursion
      (goto-char open)
      (let* ((items (autolisp--operands outer))
             (op (and (cdar items) (downcase (cdar items)))))
        (or (and (member op '("defun" "defun-q")) (= (length items) 2))
            (and (equal op "lambda") (= (length items) 1)))))))

(defun autolisp-calculate-indent ()
  "Return the column for the current line, or nil to leave it alone."
  (save-excursion
    (beginning-of-line)
    (let* ((state (syntax-ppss)) (open (nth 1 state)))
      (cond
       ((nth 8 state) nil)              ; in a string or block comment
       ((null open) 0)
       (t
        (let* ((col (autolisp--column open))
               (body (+ col autolisp-indent-offset))
               (items (autolisp--operands open))
               (op (car items))
               (args (cdr items))
               (name (and (cdr op) (downcase (cdr op))))
               (quoted (eq (char-before open) ?\')))
          (skip-chars-forward " \t")
          (cond
           ((eq (char-after) ?\)) col)
           ((autolisp--in-arg-list-p open) (1+ col))
           ((null op) (1+ col))
           ((and quoted (not (equal name "lambda"))) (1+ col))
           ((null name) (autolisp--column (car op)))
           ((equal name "setq")
            (if (null args) body
              ;; A value on its own line sits one past its variable.
              (+ (autolisp--column (caar args)) (if (cl-oddp (length args)) 1 0))))
           ((and (member name '("defun" "defun-q")) (< (length args) 2))
            (if args (autolisp--column (caar args))
              (+ (autolisp--column (car op)) (length name) 1)))
           ((and (equal name "lambda") (null args))
            (+ (autolisp--column (car op)) (length name) 1))
           ((member name '("defun" "defun-q" "lambda" "if" "cond" "while"
                           "repeat" "foreach" "vlax-for" "progn"))
            body)
           ((and args (autolisp--same-line-p (car op) (caar args)))
            (autolisp--column (caar args)))
           (t body))))))))

(defun autolisp-indent-line ()
  "Indent the current line as AutoLISP."
  (let ((col (autolisp-calculate-indent)))
    (if (null col)
        'noindent
      (if (<= (current-column) (current-indentation))
          (indent-line-to col)
        (save-excursion (indent-line-to col))))))

;;;; The call around point

(defun autolisp--call-at-point ()
  "Return (NAME . INDEX) for the call around point.
INDEX is the zero-based argument point is in, or nil on the operator."
  (save-excursion
    (let* ((state (syntax-ppss))
           (pos (or (nth 8 state) (point)))
           (open (nth 1 state)))
      (when open
        (goto-char pos)
        (let* ((items (autolisp--operands open)) (op (car items)))
          (when (cdr op)
            (let ((n (length (cdr items))))
              (cons (cdr op)
                    (cond ((<= pos (+ (car op) (length (cdr op)))) nil)
                          ;; On or just after an argument, rather than between.
                          ((and (> n 0) (not (memq (char-before pos) '(?\s ?\t ?\n))))
                           (1- n))
                          (t n))))))))))

;;;; Completion

(defvar autolisp--upcased (make-hash-table :test #'eq))

(defun autolisp--match-case (names prefix)
  "Return NAMES in upper case if PREFIX ends in an upper-case letter."
  (let ((c (and (> (length prefix) 0) (aref prefix (1- (length prefix))))))
    (if (and c (/= c (downcase c)))
        (mapcar #'upcase names)
      names)))

(defun autolisp--doc-string (name)
  "Return help text for symbol NAME, or nil."
  (if-let* ((entries (autolisp-data-function-help name)))
      (mapconcat #'autolisp-data-format-entry entries "\n\n")
    (when-let* ((ref (cdar (autolisp-find-defuns name))))
      (concat (autolisp--defun-signature ref)
              (when-let* ((doc (autolisp-ref-doc ref)))
                (concat "\n\n" (autolisp--clean-doc doc)))))))

(defun autolisp--clean-doc (doc)
  "Strip the comment characters from DOC."
  (string-trim
   (replace-regexp-in-string
    "|;[ \t]*$\\|^[ \t]*;+|?[ \t]?\\|^[ \t]+" "" doc)))

(defun autolisp--doc-buffer (name)
  "Return a buffer documenting NAME, or nil."
  (when-let* ((doc (autolisp--doc-string name)))
    (with-current-buffer (get-buffer-create " *autolisp-doc*")
      (erase-buffer)
      (insert doc)
      (goto-char (point-min))
      (current-buffer))))

(defun autolisp--annotation (name)
  "Return a short annotation for completion candidate NAME."
  (if (autolisp-data-native-p name) " built-in" " user"))

(defun autolisp--short-signature (name)
  "Return a one-line signature for NAME, or nil."
  (if-let* ((e (car (autolisp-data-function-help name))))
      (autolisp-data-signature e)
    (when-let* ((ref (cdar (autolisp-find-defuns name))))
      (autolisp--defun-signature ref))))

(defun autolisp--complete-string (state)
  "Complete a command or system variable in the string of STATE."
  (let ((call (autolisp--call-at-point)))
    (when (or (eq autolisp-complete-commands-in t)
              (member (downcase (or (car call) "")) autolisp-complete-commands-in))
      (let ((end (point))
            ;; _ asks for the English name and . for the original command.
            (beg (save-excursion
                   (skip-chars-backward "A-Za-z0-9-" (1+ (nth 8 state))) (point))))
        (when (save-excursion
                (goto-char beg)
                (skip-chars-backward "._'" (1+ (nth 8 state)))
                (or (= (point) (1+ (nth 8 state)))
                    (memq (char-before) '(?\s ?\n))))
          (let* ((prefix (buffer-substring-no-properties beg end))
                 (names (autolisp-data-commands))
                 (c (and (not (string-empty-p prefix))
                         (aref prefix (1- (length prefix))))))
            (list beg
                  (save-excursion (skip-chars-forward "A-Za-z0-9-") (point))
                  (completion-table-case-fold
                   (if (and c (= c (downcase c)) (/= c (upcase c)))
                       (mapcar #'downcase names)
                     names))
                  :annotation-function (lambda (_) " command/sysvar")
                  :exclusive 'no)))))))

(defun autolisp-completion-at-point ()
  "Complete the AutoLISP symbol, command or variable at point."
  (let ((state (syntax-ppss)))
    (cond
     ((nth 3 state) (autolisp--complete-string state))
     ((nth 4 state) nil)
     (t
      (let* ((end (point))
             (beg (save-excursion (skip-syntax-backward "w_") (point)))
             (prefix (buffer-substring-no-properties beg end)))
        (when (< beg end)
          (list beg (save-excursion (skip-syntax-forward "w_") (point))
                (completion-table-case-fold
                 (completion-table-dynamic
                  (lambda (_)
                    (autolisp--match-case
                     (delete-dups
                      (append (autolisp--buffer-symbols beg)
                              (autolisp-all-defun-names)
                              (autolisp-data-functions)))
                     prefix))
                  t))
                :annotation-function #'autolisp--annotation
                :company-docsig #'autolisp--short-signature
                :company-doc-buffer #'autolisp--doc-buffer
                :exclusive 'no)))))))

(defun autolisp--buffer-symbols (except)
  "Return the user symbols in this buffer, apart from one only at EXCEPT."
  (let (out)
    (maphash (lambda (name refs)
               (unless (and (null (cdr refs))
                            (= (autolisp-ref-beg (car refs)) except))
                 (push name out)))
             (autolisp-analysis-table (autolisp-buffer-analysis)))
    out))

;;;; Eldoc and help

(defun autolisp--defun-signature (ref)
  "Return the signature of the defun REF."
  (format "(%s)" (string-join (cons (autolisp-ref-name ref) (autolisp-ref-args ref))
                              " ")))

(defun autolisp--highlight-argument (signature index)
  "Highlight argument INDEX of SIGNATURE."
  (if (null index) signature
    (let ((parts (split-string (substring signature 1 -1) " " t))
          (n 0))
      (concat "("
              (mapconcat (lambda (p)
                           (prog1 (if (= n (1+ index))
                                      (propertize p 'face 'eldoc-highlight-function-argument)
                                    p)
                             (setq n (1+ n))))
                         parts " ")
              ")"))))

(defun autolisp-eldoc-function (callback &rest _)
  "Show the signature of the call around point with CALLBACK."
  (or (when (fboundp 'autolisp-dape-error-at-point)
        (when-let* ((err (autolisp-dape-error-at-point)))
          (funcall callback err :face 'error)
          t))
      (when-let* ((call (autolisp--call-at-point))
                  (sig (autolisp--short-signature (car call))))
        (let ((entry (car (autolisp-data-function-help (car call)))))
          (funcall callback
                   (concat (autolisp--highlight-argument sig (cdr call))
                           (when-let* ((d (and entry (autolisp-data-description entry))))
                             (concat "  " (propertize d 'face 'shadow)))))
          t))))

(defun autolisp--read-symbol (prompt)
  "Read a symbol name with PROMPT, defaulting to the one at point."
  (let ((default (or (autolisp-symbol-at-point)
                     (car (autolisp--call-at-point))))
        (completion-ignore-case t))
    (completing-read (format-prompt prompt default)
                     (append (autolisp-all-defun-names) (autolisp-data-functions))
                     nil nil nil nil default)))

(defun autolisp-describe-symbol (name)
  "Show help for the built-in or user function NAME."
  (interactive (list (autolisp--read-symbol "Describe")))
  (let ((doc (autolisp--doc-string name)))
    (unless doc (user-error "No help for `%s'" name))
    (with-help-window (help-buffer)
      (princ doc)
      (when (autolisp-data-function-help name)
        (with-current-buffer standard-output
          (insert "\n\n")
          (insert-text-button "Open online help"
                              'action (lambda (_) (autolisp-open-web-help name))
                              'follow-link t))))))

(defun autolisp-open-web-help (name)
  "Open Autodesk's online help for NAME."
  (interactive (list (or (and (use-region-p)
                              (buffer-substring-no-properties (region-beginning)
                                                              (region-end)))
                         (autolisp-symbol-at-point)
                         (autolisp--read-symbol "Online help for"))))
  (browse-url (autolisp-data-lisp-url name)))

;;;; Editing commands

(defun autolisp-insert-doc-comment ()
  "Insert a documentation comment above the defun around point."
  (interactive)
  (let* ((pos (point))
         (ref (car (last
                    (seq-filter
                     (lambda (r) (and (eq (autolisp-ref-kind r) 'defun)
                                      (<= (autolisp--defun-start r) pos)
                                      (<= pos (autolisp--defun-end r))))
                     (autolisp-analysis-refs (autolisp-buffer-analysis)))))))
    (unless ref (user-error "Point is not in a defun"))
    (goto-char (autolisp--defun-start ref))
    (let ((indent (make-string (current-column) ?\s)) start)
      (insert ";|\n" indent "  ")
      (setq start (point-marker))
      (insert "description\n")
      (dolist (a (autolisp-ref-args ref))
        (insert indent "  @Param " a " ?\n"))
      (insert indent "  @Returns ?\n" indent "|;\n" indent)
      (goto-char start)
      (push-mark (line-end-position) t t))))

(defun autolisp--defun-start (ref)
  "Return the position of the paren that opens the defun of REF."
  (save-excursion
    (goto-char (autolisp-ref-beg ref))
    (nth 1 (syntax-ppss))))

(defun autolisp--defun-end (ref)
  "Return the end of the defun of REF."
  (condition-case nil
      (scan-sexps (autolisp--defun-start ref) 1)
    (scan-error (point-max))))

(defun autolisp-insert-region (beg end description)
  "Wrap BEG to END in a ;#region called DESCRIPTION."
  (interactive
   (append (if (use-region-p) (list (region-beginning) (region-end))
             (list (point) (point)))
           (list (read-string "Region description: "))))
  (let ((comment (if (derived-mode-p 'autolisp-dcl-mode) "//" ";")) (end (copy-marker end t)))
    (goto-char end)
    (unless (bolp) (insert "\n"))
    (insert comment "#endregion\n")
    (goto-char beg)
    (insert comment "#region " description "\n")
    (when (= (point) (marker-position end)) (save-excursion (insert "\n")))
    (set-marker end nil)))

(defconst autolisp--region-regexp "^[ \t]*\\(?:;+\\|//\\)#\\(end\\)?region\\_>")

(defun autolisp--region-bounds ()
  "Return (BEG . END) of the text inside the innermost region at point."
  (save-excursion
    (let ((case-fold-search t) (depth 1) beg)
      (end-of-line)
      (while (and (> depth 0)
                  (re-search-backward autolisp--region-regexp nil t))
        (setq depth (+ depth (if (match-beginning 1) 1 -1))))
      (when (= depth 0)
        (setq beg (line-end-position) depth 1)
        (goto-char beg)
        (while (and (> depth 0)
                    (re-search-forward autolisp--region-regexp nil t))
          (setq depth (+ depth (if (match-beginning 1) -1 1))))
        (when (= depth 0)
          (cons beg (line-end-position)))))))

(defun autolisp-toggle-region ()
  "Fold or unfold the ;#region around point."
  (interactive)
  (let ((bounds (or (autolisp--region-bounds)
                    (user-error "Not in a #region"))))
    (if-let* ((ov (seq-find (lambda (o) (eq (overlay-get o 'invisible) 'autolisp-region))
                            (overlays-in (car bounds) (cdr bounds)))))
        (delete-overlay ov)
      (add-to-invisibility-spec '(autolisp-region . t))
      (let ((ov (make-overlay (car bounds) (cdr bounds))))
        (overlay-put ov 'invisible 'autolisp-region)
        (overlay-put ov 'isearch-open-invisible #'delete-overlay)
        (overlay-put ov 'evaporate t))
      (goto-char (car bounds)))))

;;;; Mode

(defvar autolisp-imenu-generic-expression
  '((nil "^\\s-*(\\s-*defun\\(?:-q\\)?\\s-+\\(\\(?:\\sw\\|\\s_\\)+\\)" 1)
    ("Commands" "^\\s-*(\\s-*defun\\(?:-q\\)?\\s-+\\([cC]:\\(?:\\sw\\|\\s_\\)+\\)" 1)
    ("Regions" "^\\s-*;+#region\\s-+\\(.*\\)$" 1)))

(defvar-keymap autolisp-mode-map
  :doc "Keymap for `autolisp-mode'."
  "C-c C-d" #'autolisp-describe-symbol
  "C-c C-w" #'autolisp-open-web-help
  "C-c C-r" #'autolisp-rename-symbol
  "C-c C-;" #'autolisp-insert-doc-comment
  "C-c C-n" #'autolisp-insert-region
  "C-c C-f" #'autolisp-toggle-region
  "C-c C-a" #'autolisp-debug-attach
  "C-c C-l" #'autolisp-load-file
  "C-c C-k" #'autolisp-reload-file
  "C-c C-e" #'autolisp-eval-region
  "C-x C-e" #'autolisp-eval-last-sexp
  "C-M-x" #'autolisp-eval-defun
  "C-M-q" #'prog-indent-sexp)

(autoload 'autolisp-debug-attach "autolisp-dape" nil t)
(autoload 'autolisp-debug-launch "autolisp-dape" nil t)
(autoload 'autolisp-load-file "autolisp-dape" nil t)
(autoload 'autolisp-reload-file "autolisp-dape" nil t)
(autoload 'autolisp-eval-region "autolisp-dape" nil t)
(autoload 'autolisp-eval-last-sexp "autolisp-dape" nil t)
(autoload 'autolisp-eval-defun "autolisp-dape" nil t)
(autoload 'autolisp-dcl-mode "autolisp-dcl-mode" nil t)
(autoload 'autolisp-open-project "autolisp-project" nil t)
(autoload 'autolisp-create-project "autolisp-project" nil t)

(with-eval-after-load 'dape (require 'autolisp-dape))

;;;###autoload
(define-derived-mode autolisp-mode prog-mode "AutoLISP"
  "Major mode for editing AutoCAD AutoLISP.

\\{autolisp-mode-map}"
  (setq-local comment-start ";"
              comment-end ""
              comment-start-skip ";+[|#]?[ \t]*"
              comment-add 0
              parse-sexp-ignore-comments t
              parse-sexp-lookup-properties t
              open-paren-in-column-0-is-defun-start nil
              indent-tabs-mode nil
              tab-width 2
              indent-line-function #'autolisp-indent-line
              case-fold-search t
              imenu-case-fold-search t
              imenu-generic-expression autolisp-imenu-generic-expression
              syntax-propertize-function #'autolisp-syntax-propertize
              multibyte-syntax-as-symbol t
              electric-indent-chars (append '(?\)) electric-indent-chars))
  (setq font-lock-defaults '(autolisp-font-lock-keywords nil t))
  (add-hook 'completion-at-point-functions #'autolisp-completion-at-point nil t)
  (add-hook 'eldoc-documentation-functions #'autolisp-eldoc-function nil t)
  (add-hook 'xref-backend-functions #'autolisp-xref-backend nil t))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.\\(?:lsp\\|LSP\\|mnl\\|MNL\\)\\'" . autolisp-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.\\(?:dcl\\|DCL\\)\\'" . autolisp-dcl-mode))

(provide 'autolisp-mode)
;;; autolisp-mode.el ends here
