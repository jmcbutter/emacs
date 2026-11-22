;;; routine-checklist.el --- Smart routine checklists for Emacs -*- lexical-binding: t -*-

;;; Commentary:

;; Entry points, customization group, keybindings, and pickers for
;; `routine-checklist'.

;;; Code:

(eval-and-compile
  (add-to-list
   'load-path
   (file-name-directory
    (or load-file-name
        (and (boundp 'byte-compile-current-file)
             byte-compile-current-file)
        buffer-file-name))))

(require 'seq)
(require 'subr-x)
(require 'routine-checklist-store)
(require 'routine-checklist-template-mode)

(defgroup routine-checklist nil
  "Routine checklists with smart per-item cadences."
  :group 'org
  :prefix "routine-checklist-")

(defcustom routine-checklist-data-directory "~/Dropbox/My Documents/Checklists/"
  "Root directory where routine checklist templates and runs are stored."
  :type 'directory
  :group 'routine-checklist)

(defcustom routine-checklist-default-not-due-visibility 'dimmed
  "Default visibility for not-due items when a template does not specify one."
  :type '(choice (const :tag "Dimmed in place" dimmed)
                 (const :tag "Hidden" hidden))
  :group 'routine-checklist)

(defvar routine-checklist-template-history nil
  "Minibuffer history for choosing routine checklist templates.")

;;;###autoload
(defvar-keymap routine-checklist-prefix-map
  :doc "Prefix keymap for Routine Checklist commands."
  "t" #'routine-checklist-manage-templates)

(defun routine-checklist--template-candidates (templates)
  "Return an alist of (DISPLAY . TEMPLATE) with unique display names."
  (let ((counts (make-hash-table :test #'equal)))
    (dolist (tpl templates)
      (let ((name (or (plist-get tpl :name) (plist-get tpl :id))))
        (puthash name (1+ (gethash name counts 0)) counts)))
    (mapcar
     (lambda (tpl)
       (let* ((name (or (plist-get tpl :name) (plist-get tpl :id)))
              (id (plist-get tpl :id))
              (display (if (> (gethash name counts 0) 1)
                           (format "%s (%s)" name id)
                         name)))
         (cons display tpl)))
     templates)))

(defun routine-checklist--template-annotation (tpl)
  "Return a completion annotation string summarizing template TPL."
  (let ((count (length (plist-get tpl :items)))
        (policy (or (plist-get tpl :run-policy) 'carry-over)))
    (format "  (%d %s, %s)"
            count
            (if (= count 1) "item" "items")
            policy)))

(defun routine-checklist-delete-template (template-id &optional no-confirm)
  "Delete template TEMPLATE-ID from disk and close any open editor buffer.
When NO-CONFIRM is non-nil, skip confirmation."
  (let* ((tpl (routine-checklist-store-load-template template-id t))
         (name (or (plist-get tpl :name) template-id)))
    (when (or no-confirm
              (yes-or-no-p (format "Delete routine template %S (%s)? "
                                   name template-id)))
      (routine-checklist-store-delete-template template-id)
      (when-let* ((buf (routine-checklist-template--find-buffer template-id)))
        (with-current-buffer buf
          (setq routine-checklist-template--dirty nil)
          (set-buffer-modified-p nil))
        (kill-buffer buf))
      (message "Deleted routine template %S" name)
      t)))

;;;###autoload
(defun routine-checklist-manage-templates ()
  "Open, create, or delete a routine checklist template."
  (interactive)
  (let* ((templates (routine-checklist-store-list-templates))
         (candidates (routine-checklist--template-candidates templates))
         (create-label "+ Create new template")
         (delete-label "- Delete a template")
         (entries (append (mapcar #'car candidates)
                          (list create-label)
                          (when templates (list delete-label))))
         (width (apply #'max 0 (mapcar #'string-width entries)))
         (annotate
          (lambda (choice)
            (let ((pad (make-string (max 1 (- (+ width 2) (string-width choice)))
                                    ?\s)))
              (cond
               ((equal choice create-label)
                (concat pad "Create a new checklist template"))
               ((equal choice delete-label)
                (concat pad "Delete an existing template"))
               (t
                (when-let* ((tpl (cdr (assoc choice candidates))))
                  (concat pad (routine-checklist--template-annotation tpl))))))))
         (table (lambda (string pred action)
                  (if (eq action 'metadata)
                      `(metadata
                        (display-sort-function . identity)
                        (annotation-function . ,annotate))
                    (complete-with-action action entries string pred))))
         (choice (completing-read "Routine template: " table nil t nil
                                  'routine-checklist-template-history)))
    (cond
     ((equal choice create-label)
      (let ((name (string-trim (read-string "New template name: "))))
        (when (string-empty-p name)
          (user-error "Template name must not be empty"))
        (routine-checklist-template-open
         (routine-checklist-store-make-template name)
         nil)))
     ((equal choice delete-label)
      (let* ((del-width (apply #'max 0 (mapcar (lambda (c) (string-width (car c)))
                                               candidates)))
             (del-annotate
              (lambda (item)
                (when-let* ((tpl (cdr (assoc item candidates))))
                  (concat (make-string (max 1 (- (+ del-width 2)
                                                 (string-width item)))
                                       ?\s)
                          (routine-checklist--template-annotation tpl)))))
             (del-table
              (lambda (string pred action)
                (if (eq action 'metadata)
                    `(metadata
                      (display-sort-function . identity)
                      (annotation-function . ,del-annotate))
                  (complete-with-action action candidates string pred))))
             (target (completing-read "Delete template: " del-table nil t))
             (tpl (cdr (assoc target candidates))))
        (routine-checklist-delete-template (plist-get tpl :id))))
     (t
      (when-let* ((tpl (cdr (assoc choice candidates))))
        (routine-checklist-template-open tpl t))))))

(provide 'routine-checklist)
;;; routine-checklist.el ends here
