;;; autolisp-dcl-mode.el --- Major mode for AutoCAD DCL -*- lexical-binding: t -*-

;; SPDX-License-Identifier: Apache-2.0

;;; Commentary:

;; Dialog Control Language: highlighting, indentation, completion that knows
;; tiles from attributes from values, and help.

;;; Code:

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
(require 'autolisp-mode)

(defvar autolisp-dcl-mode-syntax-table
  (let ((st (make-syntax-table)))
    (modify-syntax-entry ?/ ". 124b" st)
    (modify-syntax-entry ?* ". 23" st)
    (modify-syntax-entry ?\n "> b" st)
    (modify-syntax-entry ?\" "\"" st)
    (modify-syntax-entry ?\\ "\\" st)
    (modify-syntax-entry ?_ "_" st)
    (modify-syntax-entry ?{ "(}" st)
    (modify-syntax-entry ?} "){" st)
    (dolist (c '(?: ?= ?\; ?@)) (modify-syntax-entry c "." st))
    st)
  "Syntax table for `autolisp-dcl-mode'.")

(defconst autolisp-dcl--values
  '("true" "false" "left" "right" "top" "bottom" "centered" "horizontal"
    "vertical" "filled" "black" "red" "yellow" "green" "cyan" "blue" "magenta"
    "white" "dialog_line" "dialog_foreground" "dialog_background"
    "graphics_background" "graphics_foreground"))

(defun autolisp-dcl--match-attribute (limit)
  "Match an attribute name before LIMIT."
  (re-search-forward "\\_<\\([a-z_0-9]+\\)\\s-*=" limit t))

(defvar autolisp-dcl-font-lock-keywords
  `(("^\\s-*\\([A-Za-z_][A-Za-z_0-9]*\\)\\s-*:\\s-*\\([a-z_0-9]+\\)"
     (1 font-lock-function-name-face) (2 font-lock-type-face))
    (":\\s-*\\([a-z_0-9]+\\)\\s-*{" (1 font-lock-type-face))
    (autolisp-dcl--match-attribute (1 font-lock-variable-name-face))
    ("@\\(include\\)\\_>" (1 font-lock-preprocessor-face))
    (,(regexp-opt autolisp-dcl--values 'symbols) (0 font-lock-constant-face))
    ("^\\s-*\\([a-z_0-9]+\\)\\s-*;" (1 font-lock-type-face)))
  "Font lock keywords for `autolisp-dcl-mode'.")

(defun autolisp-dcl-indent-line ()
  "Indent the current line as DCL."
  (let ((col (save-excursion
               (beginning-of-line)
               (let ((state (syntax-ppss)))
                 (unless (nth 8 state)
                   (let ((depth (car state)))
                     (skip-chars-forward " \t")
                     (when (eq (char-after) ?}) (setq depth (1- depth)))
                     (* (max 0 depth) autolisp-indent-offset)))))))
    (if (null col)
        'noindent
      (if (<= (current-column) (current-indentation))
          (indent-line-to col)
        (save-excursion (indent-line-to col))))))

;;;; Completion and help

(defun autolisp-dcl--enclosing-tile ()
  "Return the name of the tile whose braces surround point, or nil."
  (save-excursion
    (when-let* ((open (nth 1 (syntax-ppss))))
      (goto-char open)
      (forward-comment (- (buffer-size)))
      (let ((end (point)))
        (skip-chars-backward "A-Za-z0-9_")
        (and (< (point) end)
             (buffer-substring-no-properties (point) end))))))

(defun autolisp-dcl--value-candidates (attribute)
  "Return the values ATTRIBUTE accepts, or nil if unknown."
  (when-let* ((entry (autolisp-data-dcl-attribute attribute))
              (type (gethash "valueType" entry)))
    (or (gethash "enums" type)
        (and (equal (downcase (or (gethash "primitive" type) "")) "boolean")
             '("true" "false")))))

(defun autolisp-dcl--context ()
  "Return what can be typed at point: (tile), (value ATTRIBUTE) or (member)."
  (save-excursion
    (skip-chars-backward "A-Za-z0-9_")
    (forward-comment (- (buffer-size)))
    (pcase (char-before)
      (?: '(tile))
      (?= (backward-char 1)
          (forward-comment (- (buffer-size)))
          (let ((end (point)))
            (skip-chars-backward "A-Za-z0-9_")
            (list 'value (buffer-substring-no-properties (point) end))))
      (_ '(member)))))

(defun autolisp-dcl--candidates ()
  "Return the completions that fit at point."
  (pcase (autolisp-dcl--context)
    (`(tile) (autolisp-data-dcl-tiles))
    (`(value ,attribute) (autolisp-dcl--value-candidates attribute))
    (_ (when-let* ((tile (autolisp-dcl--enclosing-tile)))
         (append (if-let* ((entry (autolisp-data-dcl-tile tile)))
                     (gethash "attributes" entry)
                   (autolisp-data-dcl-attributes))
                 ;; A tile can also be used as a plain reference, as in
                 ;; "ok_cancel;".
                 (autolisp-data-dcl-tiles))))))

(defun autolisp-dcl--entry (name)
  "Return the help entry for NAME."
  (or (autolisp-data-dcl-attribute name) (autolisp-data-dcl-tile name)))

(defun autolisp-dcl--doc-buffer (name)
  "Return a buffer documenting NAME, or nil."
  (when-let* ((entry (autolisp-dcl--entry name)))
    (with-current-buffer (get-buffer-create " *autolisp-doc*")
      (erase-buffer)
      (insert (autolisp-data-format-entry entry))
      (goto-char (point-min))
      (current-buffer))))

(defun autolisp-dcl-completion-at-point ()
  "Complete the tile, attribute or value at point."
  (unless (nth 8 (syntax-ppss))
    (when-let* ((candidates (autolisp-dcl--candidates)))
      (list (save-excursion (skip-chars-backward "A-Za-z0-9_") (point))
            (save-excursion (skip-chars-forward "A-Za-z0-9_") (point))
            (autolisp-complete-table candidates
                                     (save-excursion
                                       (skip-chars-backward "A-Za-z0-9_") (point)))
            :annotation-function
            (lambda (n) (cond ((autolisp-data-dcl-attribute n) " attribute")
                              ((autolisp-data-dcl-tile n) " tile")))
            :company-docsig (lambda (n)
                              (when-let* ((e (autolisp-dcl--entry n)))
                                (autolisp-data-signature e)))
            :company-doc-buffer #'autolisp-dcl--doc-buffer))))

(defun autolisp-dcl--word-at-point ()
  "Return the DCL word at point, or nil."
  (thing-at-point 'symbol t))

(defun autolisp-dcl-eldoc-function (callback &rest _)
  "Describe the word at point with CALLBACK."
  (when-let* ((word (and (not (nth 8 (syntax-ppss))) (autolisp-dcl--word-at-point)))
              (entry (autolisp-dcl--entry word)))
    (funcall callback (autolisp-data-description entry)
             :thing word :face 'font-lock-keyword-face)
    t))

(defun autolisp-dcl-describe (name)
  "Show help for the DCL word NAME."
  (interactive
   (list (completing-read (format-prompt "Describe" (autolisp-dcl--word-at-point))
                          (autolisp-data-dcl-words) nil nil nil nil
                          (autolisp-dcl--word-at-point))))
  (let ((entry (or (autolisp-dcl--entry name) (user-error "No help for `%s'" name))))
    (with-help-window (help-buffer)
      (princ (autolisp-data-format-entry entry)))))

(defun autolisp-dcl-open-web-help (name)
  "Open Autodesk's online help for the DCL word NAME."
  (interactive (list (or (autolisp-dcl--word-at-point) "")))
  (browse-url (autolisp-data-dcl-url name)))

(defvar-keymap autolisp-dcl-mode-map
  :doc "Keymap for `autolisp-dcl-mode'."
  "<remap> <display-local-help>" #'autolisp-help-at-point
  "C-c C-d" #'autolisp-dcl-describe
  "C-c C-w" #'autolisp-dcl-open-web-help
  "C-c C-n" #'autolisp-insert-region
  "C-c C-f" #'autolisp-toggle-region
  "C-c C-l" #'autolisp-load-file)

;;;###autoload
(define-derived-mode autolisp-dcl-mode prog-mode "DCL"
  "Major mode for editing AutoCAD Dialog Control Language."
  (setq-local comment-start "// "
              comment-end ""
              comment-start-skip "\\(?://+\\|/\\*+\\)[ \t]*"
              indent-tabs-mode nil
              completion-ignore-case t
              indent-line-function #'autolisp-dcl-indent-line
              imenu-generic-expression
              '((nil "^\\s-*\\([A-Za-z_][A-Za-z_0-9]*\\)\\s-*:\\s-*dialog\\_>" 1))
              electric-indent-chars (append '(?}) electric-indent-chars))
  (setq font-lock-defaults '(autolisp-dcl-font-lock-keywords))
  (add-hook 'completion-at-point-functions #'autolisp-dcl-completion-at-point nil t)
  (add-hook 'eldoc-documentation-functions #'autolisp-dcl-eldoc-function nil t))

(provide 'autolisp-dcl-mode)
;;; autolisp-dcl-mode.el ends here
