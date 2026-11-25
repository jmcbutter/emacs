;;; autolisp-help.el --- Help at point for AutoLISP and DCL -*- lexical-binding: t -*-

;; SPDX-License-Identifier: Apache-2.0

;;; Commentary:

;; `autolisp-help-at-point' says what is at point without asking: a runtime
;; error, a built-in, one of the user's own symbols, a constant, an ActiveX
;; member, or failing those the call around point.  The modes put it on the
;; key of `display-local-help', C-h . by default.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'help-mode)

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
(require 'autolisp-complete)

(declare-function autolisp--clean-doc "autolisp-mode")
(declare-function autolisp--defun-signature "autolisp-mode")
(declare-function autolisp--short-signature "autolisp-mode")
(declare-function autolisp--call-at-point "autolisp-mode")
(declare-function autolisp-dape-error-at-point "autolisp-dape")
(declare-function autolisp-dcl--entry "autolisp-dcl-mode")
(declare-function autolisp-dcl--enclosing-tile "autolisp-dcl-mode")
(declare-function autolisp-dcl--word-at-point "autolisp-dcl-mode")

;; Help is a plist: :text, and optionally :url, and :location, a
;; (FILE-OR-BUFFER . POSITION) to visit.

;;;; Built-ins

(defun autolisp-help--builtin (name)
  "Return help for the built-in function NAME, or nil."
  (when-let* ((entries (autolisp-data-function-help name)))
    (list :text (mapconcat #'autolisp-data-format-entry entries "\n\n")
          :url (autolisp-data-lisp-url name))))

(defun autolisp-help--constant (name)
  "Return help for the constant NAME, or nil."
  (when-let* ((owner (gethash (downcase name)
                              (autolisp-data--section "enumerators"))))
    (let ((help (autolisp-help--builtin owner)))
      (list :text (concat (format "%s is a value used with %s." name owner)
                          (and help (concat "\n\n" (plist-get help :text))))
            :url (autolisp-data-lisp-url owner)))))

(defun autolisp-help--member (name call)
  "Return help for the ActiveX member NAME used in CALL, or nil."
  (when (and (string-prefix-p "vlax-" (or (car call) "")) (eql (cadr call) 1))
    (seq-some #'autolisp-help--builtin
              (mapcar (lambda (prefix) (concat prefix (downcase name)))
                      (if (string-match-p "put" (car call))
                          '("vla-put-" "vla-get-" "vla-")
                        '("vla-get-" "vla-put-" "vla-"))))))

;;;; The user's symbols

(defun autolisp-help--line (file pos)
  "Return (LINE . TEXT) for POS in FILE, a file name or buffer."
  (cl-flet ((at () (save-excursion
                     (save-restriction
                       (widen)
                       (goto-char pos)
                       (cons (line-number-at-pos)
                             (string-trim (buffer-substring-no-properties
                                           (line-beginning-position)
                                           (line-end-position))))))))
    (if-let* ((buffer (if (bufferp file) file (get-file-buffer file))))
        (with-current-buffer buffer (at))
      (with-temp-buffer
        (ignore-error file-error (insert-file-contents file))
        (at)))))

(defun autolisp-help--place (entry)
  "Return where ENTRY, a (FILE . REF) pair, is."
  (let ((file (car entry))
        (line (autolisp-help--line (car entry) (autolisp-ref-beg (cdr entry)))))
    (format "%s:%d: %s"
            (if (bufferp file) (buffer-name file) (file-name-nondirectory file))
            (car line) (cdr line))))

(defun autolisp-help--assignments (entries)
  "Return text that lists where ENTRIES are assigned."
  (let ((set (seq-filter (lambda (e) (eq (autolisp-ref-kind (cdr e)) 'setq)) entries)))
    (when set
      (concat "\n\nSet in:\n"
              (mapconcat (lambda (e) (concat "  " (autolisp-help--place e)))
                         (seq-take set 8) "\n")
              (and (> (length set) 8)
                   (format "\n  and %d more" (- (length set) 8)))))))

(defun autolisp-help--parameter-doc (defun-ref name)
  "Return what the comment of DEFUN-REF says about parameter NAME, or nil."
  (let ((case-fold-search t) (doc (autolisp-ref-doc defun-ref)))
    (when (and doc (string-match (concat "@param[ \t]+" (regexp-quote name)
                                         "[ \t]+\\([^\n|]+\\)")
                                 doc))
      (string-trim (match-string 1 doc)))))

(defun autolisp-help--local (ref)
  "Return help for the localized REF."
  (let* ((scope (autolisp-ref-scope ref))
         (owner (autolisp-scope-defun-ref scope))
         (name (autolisp-ref-name ref))
         (argument (and owner (member name (mapcar #'downcase
                                                   (autolisp-ref-args owner)))))
         (doc (and argument (autolisp-help--parameter-doc owner name)))
         (here (or buffer-file-name (current-buffer))))
    (list :text
          (concat
           (format "%s is %s." (autolisp-ref-text ref)
                   (cond (argument (format "an argument of %s" (autolisp-ref-text owner)))
                         (owner (format "a local variable of %s" (autolisp-ref-text owner)))
                         (t "local to the enclosing lambda, foreach or vlax-for")))
           (and doc (concat "\n\n" doc))
           (autolisp-help--assignments (autolisp-references ref)))
          :location (cons here
                          (autolisp-ref-beg (cdar (autolisp-definitions-at-point)))))))

(defun autolisp-help--global (ref)
  "Return help for REF, which nothing localizes, or nil if it is undefined."
  (let* ((entries (autolisp-references ref))
         (defuns (seq-filter (lambda (e) (eq (autolisp-ref-kind (cdr e)) 'defun))
                             entries))
         (set (seq-filter (lambda (e) (eq (autolisp-ref-kind (cdr e)) 'setq)) entries))
         (first (or (car defuns) (car set))))
    (when first
      (list :text
            (if defuns
                (mapconcat
                 (lambda (e)
                   (let ((doc (autolisp-ref-doc (cdr e))))
                     (concat (autolisp--defun-signature (cdr e))
                             (and doc (concat "\n\n" (autolisp--clean-doc doc)))
                             "\n\nDefined in:\n  " (autolisp-help--place e))))
                 defuns "\n\n")
              (concat (format "%s is a global variable." (autolisp-ref-text ref))
                      (autolisp-help--assignments entries)))
            :location (cons (car first) (autolisp-ref-beg (cdr first)))))))

(defun autolisp-help--user ()
  "Return help for the user's symbol at point, or nil."
  (when-let* ((ref (autolisp-ref-at-point)))
    (if (autolisp-ref-scope ref)
        (autolisp-help--local ref)
      (autolisp-help--global ref))))

;;;; At point

(defun autolisp-help--call ()
  "Return help for the call around point, or nil."
  (when-let* ((name (car (autolisp--call-at-point))))
    (or (autolisp-help--builtin name)
        (when-let* ((entry (car (autolisp-find-defuns name))))
          (autolisp-help--global (cdr entry))))))

(defun autolisp-help--string (start)
  "Return help for the string that starts at START, or nil."
  (let ((call (autolisp-complete--call start))
        (text (save-excursion
                (goto-char (1+ start))
                (buffer-substring-no-properties
                 (point) (progn (skip-chars-forward "^\"\n") (point))))))
    (or (autolisp-help--member text call)
        (autolisp-help--call))))

(defun autolisp-help--symbol ()
  "Return help for the symbol at point, or nil."
  (when-let* ((bounds (autolisp-symbol-bounds)))
    (let ((name (buffer-substring-no-properties (car bounds) (cdr bounds))))
      (or (and (eq (char-before (car bounds)) ?\')
               (autolisp-help--member
                name (autolisp-complete--call (1- (car bounds)))))
          ;; The user may have redefined a built-in.
          (autolisp-help--user)
          (autolisp-help--builtin name)
          (autolisp-help--constant name)
          (when (and (autolisp-data-native-p name)
                     (not (member (downcase name) '("t" "nil" "pi"))))
            (list :text (format "%s is built in, but Autodesk does not document it."
                                name)))))))

(defun autolisp-help--lisp ()
  "Return help for what is at point in an AutoLISP buffer, or nil."
  (let* ((state (syntax-ppss))
         (problem (and (fboundp 'autolisp-dape-error-at-point)
                       (autolisp-dape-error-at-point)))
         (help (cond ((nth 3 state) (autolisp-help--string (nth 8 state)))
                     ((nth 4 state) nil)
                     (t (or (autolisp-help--symbol) (autolisp-help--call))))))
    (if problem
        (plist-put (copy-sequence help) :text
                   (concat "Error: " problem
                           (and help (concat "\n\n" (plist-get help :text)))))
      help)))

(defun autolisp-help--dcl ()
  "Return help for what is at point in a DCL buffer, or nil."
  (unless (nth 4 (syntax-ppss))
    (let ((name (seq-find (lambda (n) (and n (autolisp-dcl--entry n)))
                          (list (autolisp-dcl--word-at-point)
                                ;; A value: the attribute on this line.
                                (save-excursion
                                  (and (re-search-backward
                                        "\\_<\\([a-z_]+\\)\\s-*=[^;{}]*\\="
                                        (line-beginning-position) t)
                                       (match-string-no-properties 1)))
                                (autolisp-dcl--enclosing-tile)))))
      (when name
        (list :text (autolisp-data-format-entry (autolisp-dcl--entry name))
              :url (autolisp-data-dcl-url name))))))

(defun autolisp-help--visit (location)
  "Go to LOCATION, a (FILE-OR-BUFFER . POSITION) pair."
  (pop-to-buffer (if (bufferp (car location)) (car location)
                   (find-file-noselect (car location))))
  (goto-char (cdr location)))

(defun autolisp-help-show (help)
  "Show HELP in the help window."
  (help-setup-xref (list #'autolisp-help-show help)
                   (called-interactively-p 'interactive))
  (with-help-window (help-buffer)
    (with-current-buffer standard-output
      (insert (plist-get help :text) "\n")
      (when-let* ((location (plist-get help :location)))
        (insert "\n")
        (insert-text-button "Go to definition" 'follow-link t
                            'action (lambda (_) (autolisp-help--visit location))))
      (when-let* ((url (plist-get help :url)))
        (insert "\n")
        (insert-text-button "Open online help" 'follow-link t
                            'action (lambda (_) (browse-url url)))))))

(defun autolisp-help-at-point ()
  "Show help for what is at point."
  (interactive)
  (let ((help (if (derived-mode-p 'autolisp-dcl-mode)
                  (autolisp-help--dcl)
                (autolisp-help--lisp))))
    (cond (help (autolisp-help-show help))
          ;; Breakpoints and the like have help of their own.
          (t (call-interactively #'display-local-help)))))

(provide 'autolisp-help)
;;; autolisp-help.el ends here
