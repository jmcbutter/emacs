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
(require 'routine-checklist-cadence)
(require 'routine-checklist-template-mode)
(require 'routine-checklist-mode)

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

(defvar routine-checklist-run-history nil
  "Minibuffer history for choosing active routine checklist runs.")

(defvar routine-checklist-archive-history nil
  "Minibuffer history for choosing archived routine checklist runs.")

;;;###autoload
(defvar-keymap routine-checklist-prefix-map
  :doc "Prefix keymap for Routine Checklist commands."
  "t" #'routine-checklist-manage-templates
  "s" #'routine-checklist-start
  "o" #'routine-checklist-open
  "A" #'routine-checklist-open-archive)

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

;;;; Checklist runner entry points

(defun routine-checklist--pick-template ()
  "Prompt for an existing routine checklist template plist."
  (let ((templates (routine-checklist-store-list-templates)))
    (unless templates
      (user-error "No routine templates yet; press C-c o k t to create one"))
    (let* ((candidates (routine-checklist--template-candidates templates))
           (width (apply #'max 0 (mapcar (lambda (c) (string-width (car c)))
                                         candidates)))
           (annotate
            (lambda (choice)
              (when-let* ((tpl (cdr (assoc choice candidates))))
                (concat (make-string (max 1 (- (+ width 2)
                                               (string-width choice)))
                                     ?\s)
                        (routine-checklist--template-annotation tpl)))))
           (table (lambda (string pred action)
                    (if (eq action 'metadata)
                        `(metadata
                          (display-sort-function . identity)
                          (annotation-function . ,annotate))
                      (complete-with-action action candidates string pred))))
           (choice (completing-read "Start routine template: " table nil t nil
                                    'routine-checklist-template-history)))
      (cdr (assoc choice candidates)))))

(defun routine-checklist--format-run-summary (run &optional include-status)
  "Return a concise display summary for RUN.
When INCLUDE-STATUS is non-nil, include completion status badge."
  (let* ((tpl-name (or (plist-get run :template-name)
                       (plist-get run :template-id)
                       "Checklist"))
         (label (plist-get run :label))
         (ts (if include-status
                 (or (plist-get run :closed-at) (plist-get run :started-at))
               (plist-get run :started-at)))
         (ts-short (routine-checklist--format-timestamp-short ts))
         (summary (routine-checklist-progress-summary run))
         (status-badge (when include-status
                         (if (eq (plist-get run :status) 'archived-complete)
                             " [complete]"
                           " [incomplete]"))))
    (format "%s%s  (%s%s — %d/%d due checked, %d remaining)"
            tpl-name
            (if (and label (not (string-empty-p label)))
                (format " — %s" label)
              "")
            ts-short
            (or status-badge "")
            (plist-get summary :due-checked)
            (plist-get summary :due)
            (plist-get summary :remaining))))

(defun routine-checklist--run-candidates (runs &optional include-status)
  "Build unique (DISPLAY . RUN) alist from RUNS preserving order."
  (let ((seen (make-hash-table :test #'equal)))
    (mapcar
     (lambda (run)
       (let* ((base (routine-checklist--format-run-summary run include-status))
              (count (1+ (gethash base seen 0)))
              (_ (puthash base count seen))
              (display (if (> count 1)
                           (format "%s [%s]" base (plist-get run :id))
                         base)))
         (cons display run)))
     runs)))

(defun routine-checklist--pick-run (runs prompt history-var &optional include-status)
  "Prompt user with PROMPT to pick from RUNS using HISTORY-VAR."
  (let* ((candidates (routine-checklist--run-candidates runs include-status))
         (table (lambda (string pred action)
                  (if (eq action 'metadata)
                      '(metadata (display-sort-function . identity))
                    (complete-with-action action candidates string pred))))
         (choice (completing-read prompt table nil t nil history-var)))
    (cdr (assoc choice candidates))))

;;;###autoload
(defun routine-checklist-start (&optional template-id label now)
  "Start a smart checklist run from TEMPLATE-ID (or prompt for one).
Honors the template's `:run-policy' (`concurrent' always starts a parallel
run with optional LABEL; single-run policies offer to resume an existing
active run or start fresh)."
  (interactive)
  (let* ((interactive-picker (null template-id))
         (tpl (if template-id
                  (routine-checklist-store-load-template template-id)
                (routine-checklist--pick-template)))
         (tpl-id (plist-get tpl :id))
         (policy (or (plist-get tpl :run-policy) 'carry-over))
         (active-runs (routine-checklist-store-list-active-runs tpl-id))
         (resumed nil))
    (when (and active-runs
               (not (eq policy 'concurrent))
               (or interactive-picker (called-interactively-p 'any)))
      (let ((action (completing-read
                     (format "Active run exists for %s: "
                             (plist-get tpl :name))
                     '("Resume active run" "Start a fresh run")
                     nil t)))
        (when (equal action "Resume active run")
          (setq resumed
                (if (= (length active-runs) 1)
                    (car active-runs)
                  (routine-checklist--pick-run
                   active-runs "Resume run: "
                   'routine-checklist-run-history))))))
    (if resumed
        (routine-checklist-open-run-buffer resumed)
      (let* ((chosen-label
              (if (or label (and (not interactive-picker)
                                 (not (called-interactively-p 'any))))
                  label
                (read-string "Run label (optional): ")))
             (run (routine-checklist-instantiate-run tpl chosen-label now)))
        (routine-checklist-store-save-run run)
        (routine-checklist-open-run-buffer run)))))

;;;###autoload
(defun routine-checklist-open ()
  "Open an active routine checklist run."
  (interactive)
  (let ((runs (routine-checklist-store-list-active-runs)))
    (unless runs
      (user-error "No active routine checklist runs"))
    (let ((run (routine-checklist--pick-run
                runs "Open active run: " 'routine-checklist-run-history)))
      (routine-checklist-open-run-buffer run))))

;;;###autoload
(defun routine-checklist-open-archive ()
  "Open an archived routine checklist run read-only."
  (interactive)
  (let ((runs (routine-checklist-store-list-archived-runs)))
    (unless runs
      (user-error "No archived routine checklist runs"))
    (let* ((run (routine-checklist--pick-run
                 runs "Open archived run: "
                 'routine-checklist-archive-history t))
           (path (routine-checklist-store-archived-run-path
                  (plist-get run :id)
                  (routine-checklist-store--archive-year run))))
      (routine-checklist-open-run-buffer run path))))

(provide 'routine-checklist)
;;; routine-checklist.el ends here
