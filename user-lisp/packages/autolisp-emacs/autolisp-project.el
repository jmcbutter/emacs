;;; autolisp-project.el --- Visual LISP .prj projects -*- lexical-binding: t -*-

;; SPDX-License-Identifier: Apache-2.0

;;; Commentary:

;; Open, create and edit Visual LISP project files, and search or replace
;; in the files they list.  Editing a project replaces only its :OWN-LIST,
;; so every other property is kept exactly as Visual LISP wrote it.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'xref)
(require 'fileloop)
(eval-and-compile
  (add-to-list
   'load-path
   (file-name-directory
    (or load-file-name
        (and (boundp 'byte-compile-current-file)
             byte-compile-current-file)
        buffer-file-name))))

(require 'autolisp-symbols)

(defvar autolisp-project-file nil
  "The active .prj file, or nil.")

(defun autolisp-project--own-list ()
  "Return the node of the :OWN-LIST value in the current buffer."
  (save-excursion
    (let* ((autolisp--comments nil)
           (project (seq-find (lambda (n)
                                (and (eq (autolisp-node-type n) 'list)
                                     (equal (autolisp--head-name n)
                                            "vlisp-project-list")))
                              (autolisp--read-all)))
           (kids (and project (cdr (autolisp-node-children project)))))
      (while (and kids (not (equal (autolisp-node-name (car kids)) ":own-list")))
        (setq kids (cddr kids)))
      (or (cadr kids)
          (user-error "Not a Visual LISP project file")))))

(defun autolisp-project--unquote (node)
  "Return the text of string NODE."
  (string-replace "\\\\" "\\"
                  (buffer-substring-no-properties (1+ (autolisp-node-beg node))
                                                  (1- (autolisp-node-end node)))))

(defun autolisp-project--entries (file)
  "Return the source entries of project FILE, as written."
  (with-temp-buffer
    (insert-file-contents file)
    (let ((list (autolisp-project--own-list)))
      (and (eq (autolisp-node-type list) 'list)
           (mapcar #'autolisp-project--unquote
                   (seq-filter (lambda (n) (eq (autolisp-node-type n) 'string))
                               (autolisp-node-children list)))))))

(defun autolisp-project--expand (entry prj)
  "Return the file that ENTRY of project PRJ stands for."
  (let ((file (expand-file-name (string-replace "\\" "/" entry)
                                (file-name-directory prj))))
    (if (file-name-extension file) file (concat file ".lsp"))))

(defun autolisp-project-files (&optional prj)
  "Return the files of PRJ, or of the active project."
  (when-let* ((prj (or prj autolisp-project-file))
              ((file-readable-p prj)))
    (delete-dups (mapcar (lambda (e) (autolisp-project--expand e prj))
                         (autolisp-project--entries prj)))))

(defun autolisp-project--active ()
  "Return the active project file, or signal an error."
  (or autolisp-project-file
      (user-error "No project is open (M-x autolisp-open-project)")))

;;;###autoload
(defun autolisp-open-project (file)
  "Make the .prj FILE the active project."
  (interactive
   (list (read-file-name "Open project: " nil nil t nil
                         (lambda (f) (or (file-directory-p f)
                                         (string-match-p "\\.prj\\'" (downcase f)))))))
  (setq file (expand-file-name file))
  (autolisp-project--entries file)      ; check that it parses
  (setq autolisp-project-file file)
  (message "Project %s: %d files" (file-name-base file)
           (length (autolisp-project-files))))

(defun autolisp-close-project ()
  "Forget the active project."
  (interactive)
  (setq autolisp-project-file nil))

;;;###autoload
(defun autolisp-create-project (file)
  "Create the empty project FILE and make it active."
  (interactive "FCreate project: ")
  (setq file (expand-file-name (if (string-match-p "\\.prj\\'" (downcase file)) file
                                 (concat file ".prj"))))
  (when (string-search " " (file-name-nondirectory file))
    (user-error "Visual LISP project names cannot contain spaces"))
  (when (file-exists-p file)
    (user-error "%s already exists" file))
  (let ((coding-system-for-write 'utf-8-dos))
    (with-temp-file file
      (insert (format ";;; VLisp project file [V2.0] %s saved to:[%s] at:[%s]\n"
                      (file-name-base file)
                      (directory-file-name (file-name-directory file))
                      (format-time-string "%m/%d/%Y"))
              "(VLISP-PROJECT-LIST\n  :NAME\n  " (file-name-base file)
              "\n  :OWN-LIST\n  nil\n  :FAS-DIRECTORY\n  nil\n"
              "  :TMP-DIRECTORY\n  nil\n  :PROJECT-KEYS\n  (:BUILD (:standard))\n"
              "  :CONTEXT-ID\n  :AUTOLISP\n)\n;;; EOF\n")))
  (autolisp-open-project file))

(defun autolisp-project--write-entries (prj entries)
  "Replace the source list of PRJ with ENTRIES."
  (with-current-buffer (find-file-noselect prj)
    (save-excursion
      (save-restriction
        (widen)
        (let ((list (autolisp-project--own-list)))
          (goto-char (autolisp-node-beg list))
          (delete-region (autolisp-node-beg list) (autolisp-node-end list))
          (insert (if entries
                      (concat "("
                              (mapconcat (lambda (e)
                                           (format "\"%s\"" (string-replace "\\" "\\\\" e)))
                                         entries "\n   ")
                              ")")
                    "nil")))))
    (save-buffer)))

(defun autolisp-project--entry-for (file prj)
  "Return how FILE should be written in PRJ."
  (let* ((relative (file-relative-name file (file-name-directory prj)))
         (entry (if (string-prefix-p ".." relative) (expand-file-name file) relative)))
    (if (equal (downcase (or (file-name-extension entry) "")) "lsp")
        (file-name-sans-extension entry)
      entry)))

(defun autolisp-add-to-project (file)
  "Add FILE to the active project."
  (interactive (list (read-file-name "Add to project: " nil buffer-file-name t)))
  (let* ((prj (autolisp-project--active))
         (file (expand-file-name file)))
    (unless (string-match-p "\\.lsp\\'" (downcase file))
      (user-error "Only .lsp files can be added to a project"))
    (when (seq-some (lambda (f) (file-equal-p f file)) (autolisp-project-files prj))
      (user-error "%s is already in the project" (file-name-nondirectory file)))
    (autolisp-project--write-entries
     prj (append (autolisp-project--entries prj)
                 (list (autolisp-project--entry-for file prj))))
    (message "Added %s" (file-name-nondirectory file))))

(defun autolisp-remove-from-project (entry)
  "Remove ENTRY from the active project.  The file itself is kept."
  (interactive
   (list (completing-read "Remove from project: "
                          (autolisp-project--entries (autolisp-project--active)) nil t)))
  (let ((prj (autolisp-project--active)))
    (autolisp-project--write-entries
     prj (remove entry (autolisp-project--entries prj)))
    (message "Removed %s" entry)))

(defun autolisp-find-project-file ()
  "Visit a file of the active project."
  (interactive)
  (let* ((prj (autolisp-project--active))
         (entries (autolisp-project--entries prj)))
    (find-file (autolisp-project--expand
                (completing-read "Project file: " entries nil t) prj))))

(defun autolisp-save-project ()
  "Save every modified buffer of the active project."
  (interactive)
  (let ((prj (autolisp-project--active)))
    (dolist (f (cons prj (autolisp-project-files prj)))
      (when-let* ((b (find-buffer-visiting f)) ((buffer-modified-p b)))
        (with-current-buffer b (save-buffer))))))

(defun autolisp-find-in-project (regexp)
  "Search the files of the active project for REGEXP."
  (interactive (list (read-regexp "Find in project" (thing-at-point 'symbol))))
  (let* ((files (seq-filter #'file-readable-p
                            (autolisp-project-files (autolisp-project--active))))
         (matches (and files (xref-matches-in-files regexp files))))
    (unless matches (user-error "No matches for %s" regexp))
    (xref-show-xrefs (lambda () matches) nil)))

(defun autolisp-replace-in-project (from to)
  "Replace regexp FROM with TO in the active project, asking each time."
  (interactive
   (let ((from (read-regexp "Replace in project" (thing-at-point 'symbol))))
     (list from (read-string (format "Replace %s with: " from)))))
  (fileloop-initialize-replace
   from to (seq-filter #'file-readable-p
                       (autolisp-project-files (autolisp-project--active)))
   'default)
  (fileloop-continue))

(provide 'autolisp-project)
;;; autolisp-project.el ends here
