;;; routine-checklist-mode.el --- Smart checklist runner major mode -*- lexical-binding: t -*-

;;; Commentary:

;; Major mode `routine-checklist-mode' for working through active
;; routine checklist runs and inspecting read-only archived runs.
;; Keeps not-due items in their natural template order (dimmed in place
;; or hidden via invisible overlays, toggled with `h') and persists
;; every run mutation atomically immediately.

;;; Code:

(eval-and-compile
  (add-to-list
   'load-path
   (file-name-directory
    (or load-file-name
        (and (boundp 'byte-compile-current-file)
             byte-compile-current-file)
        buffer-file-name))))

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'routine-checklist-store)
(require 'routine-checklist-cadence)

(defface routine-checklist-header-title
  '((t :weight bold :height 1.2))
  "Face for the checklist title in `routine-checklist-mode'."
  :group 'routine-checklist)

(defface routine-checklist-header-label
  '((t :inherit font-lock-keyword-face))
  "Face for header field labels in `routine-checklist-mode'."
  :group 'routine-checklist)

(defface routine-checklist-header-value
  '((t :inherit default :weight semibold))
  "Face for header field values in `routine-checklist-mode'."
  :group 'routine-checklist)

(defface routine-checklist-header-meta
  '((t :inherit shadow))
  "Face for metadata and key hints in `routine-checklist-mode'."
  :group 'routine-checklist)

(defface routine-checklist-archived-banner
  '((t :inherit warning :weight bold))
  "Face for the read-only archived banner in `routine-checklist-mode'."
  :group 'routine-checklist)

(defface routine-checklist-checkbox-checked
  '((t :inherit success :weight bold))
  "Face for `[X]' checkboxes."
  :group 'routine-checklist)

(defface routine-checklist-checkbox-skipped
  '((t :inherit shadow :weight bold))
  "Face for `[-]' checkboxes."
  :group 'routine-checklist)

(defface routine-checklist-item-due
  '((t :inherit default))
  "Face for pending due checklist items."
  :group 'routine-checklist)

(defface routine-checklist-item-checked
  '((t :inherit shadow :strike-through t))
  "Face for checked checklist items."
  :group 'routine-checklist)

(defface routine-checklist-item-skipped
  '((t :inherit shadow :slant italic))
  "Face for skipped checklist items."
  :group 'routine-checklist)

(defface routine-checklist-item-not-due
  '((t :inherit shadow))
  "Face for dimmed in-place not-due checklist items."
  :group 'routine-checklist)

(defface routine-checklist-badge-adhoc
  '((t :inherit font-lock-constant-face))
  "Face for `[ad-hoc]' badges."
  :group 'routine-checklist)

(defface routine-checklist-badge-not-due
  '((t :inherit shadow))
  "Face for `[not due]' badges."
  :group 'routine-checklist)

(defface routine-checklist-age
  '((t :inherit shadow))
  "Face for relative last-completed age labels."
  :group 'routine-checklist)

(defvar-local routine-checklist--run nil
  "In-memory run plist displayed in this `routine-checklist-mode' buffer.")

(defvar-local routine-checklist--run-path nil
  "Path to the `.eld' file backing this run buffer, if known.")

(defvar-local routine-checklist--not-due-overlays nil
  "List of invisible overlays hiding not-due pending items.")

(defvar routine-checklist-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "SPC") #'routine-checklist-toggle-check)
    (define-key map (kbd "RET") #'routine-checklist-toggle-check)
    (define-key map (kbd "s") #'routine-checklist-toggle-skip)
    (define-key map (kbd "h") #'routine-checklist-toggle-not-due)
    (define-key map (kbd "a") #'routine-checklist-add-ad-hoc-item)
    (define-key map (kbd "e") #'routine-checklist-edit-label)
    (define-key map (kbd "f") #'routine-checklist-finish)
    (define-key map (kbd "g") #'routine-checklist-refresh)
    (define-key map (kbd "q") #'quit-window)
    map)
  "Keymap for `routine-checklist-mode'.")

(define-derived-mode routine-checklist-mode special-mode
  "Routine-Checklist"
  "Major mode for working through a routine checklist run.

\\{routine-checklist-mode-map}"
  (setq-local truncate-lines t)
  (add-to-invisibility-spec 'routine-checklist-not-due))

(defun routine-checklist--ensure-mode ()
  "Signal a `user-error' unless inside `routine-checklist-mode'."
  (unless (derived-mode-p 'routine-checklist-mode)
    (user-error "Not in a routine checklist buffer")))

(defun routine-checklist--ensure-active ()
  "Signal a `user-error' unless the current checklist run is active."
  (routine-checklist--ensure-mode)
  (unless (eq (plist-get routine-checklist--run :status) 'active)
    (user-error "This checklist run is archived and read-only")))

(defun routine-checklist--buffer-name (run)
  "Return the display buffer name for RUN."
  (let ((tpl-name (or (plist-get run :template-name)
                      (plist-get run :template-id)
                      "Checklist"))
        (label (plist-get run :label))
        (status (plist-get run :status)))
    (format "*Routine Checklist: %s%s%s*"
            tpl-name
            (if (and label (not (string-empty-p label)))
                (format " — %s" label)
              "")
            (if (eq status 'active) "" " [ARCHIVED]"))))

(defun routine-checklist--format-timestamp-short (ts)
  "Format ISO-8601 TS concisely as `YYYY-MM-DD HH:MM'."
  (if (and (stringp ts)
           (string-match
            "\\`\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)T\\([0-9]\\{2\\}:[0-9]\\{2\\}\\)"
            ts))
      (format "%s %s" (match-string 1 ts) (match-string 2 ts))
    (or ts "")))

(defun routine-checklist--current-item-index ()
  "Return the 0-based run item index at point, or nil if not on an item."
  (get-text-property (line-beginning-position)
                     'routine-checklist-run-item-index))

(defun routine-checklist--require-item-index ()
  "Return the 0-based run item index at point or signal a `user-error'."
  (or (routine-checklist--current-item-index)
      (user-error "No checklist item at point")))

(defun routine-checklist--goto-item (index)
  "Move point to the checklist item line for 0-based INDEX."
  (when-let* ((pos (text-property-any (point-min) (point-max)
                                      'routine-checklist-run-item-index index)))
    (goto-char pos)))

(defun routine-checklist--find-run-buffer (run-id)
  "Return an open `routine-checklist-mode' buffer displaying RUN-ID."
  (seq-find
   (lambda (buf)
     (with-current-buffer buf
       (and (derived-mode-p 'routine-checklist-mode)
            (equal (plist-get routine-checklist--run :id) run-id))))
   (buffer-list)))

(defun routine-checklist--template-cadence-map (template)
  "Return a hash table mapping TemplateItem IDs to `:cadence' plists."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (titem (plist-get template :items))
      (when-let* ((id (plist-get titem :id)))
        (puthash id (plist-get titem :cadence) table)))
    table))

(defun routine-checklist--clear-not-due-overlays ()
  "Delete all invisible not-due overlays in the current buffer."
  (mapc #'delete-overlay routine-checklist--not-due-overlays)
  (setq routine-checklist--not-due-overlays nil))

(defun routine-checklist--render (&optional target-index)
  "Render `routine-checklist--run' into the current buffer.
Move point to TARGET-INDEX (or the nearest visible item) after rendering."
  (let* ((run routine-checklist--run)
         (tpl-id (plist-get run :template-id))
         (tpl-name (or (plist-get run :template-name) tpl-id "Checklist"))
         (label (plist-get run :label))
         (status (plist-get run :status))
         (active-p (eq status 'active))
         (started-at (plist-get run :started-at))
         (closed-at (plist-get run :closed-at))
         (not-due-visible (plist-get run :not-due-visible))
         (items (plist-get run :items))
         (summary (routine-checklist-progress-summary run))
         (template (and tpl-id
                        (routine-checklist-store-load-template tpl-id t)))
         (cadence-map (and template
                           (routine-checklist--template-cadence-map template)))
         (prev-index (or target-index (routine-checklist--current-item-index)))
         (visible-indices nil)
         (inhibit-read-only t))
    (routine-checklist--clear-not-due-overlays)
    (erase-buffer)
    (insert (propertize tpl-name 'face 'routine-checklist-header-title))
    (when (and label (not (string-empty-p label)))
      (insert (propertize (format " — %s" label)
                          'face 'routine-checklist-header-title)))
    (unless active-p
      (insert (propertize
               (format "  [ARCHIVED — %s (read-only)]"
                       (if (eq status 'archived-complete)
                           "COMPLETE"
                         "INCOMPLETE"))
               'face 'routine-checklist-archived-banner)))
    (insert "\n")
    (insert (propertize "Status: " 'face 'routine-checklist-header-label)
            (propertize (symbol-name status)
                        'face 'routine-checklist-header-value)
            "\n")
    (insert (propertize "Started: " 'face 'routine-checklist-header-label)
            (propertize (routine-checklist--format-timestamp-short started-at)
                        'face 'routine-checklist-header-meta)
            "\n")
    (when closed-at
      (insert (propertize "Closed: " 'face 'routine-checklist-header-label)
              (propertize (routine-checklist--format-timestamp-short closed-at)
                          'face 'routine-checklist-header-meta)
              "\n"))
    (insert (propertize "Progress: " 'face 'routine-checklist-header-label)
            (propertize
             (format "%d/%d due checked, %d remaining, %d skipped%s"
                     (plist-get summary :due-checked)
                     (plist-get summary :due)
                     (plist-get summary :remaining)
                     (plist-get summary :skipped)
                     (if (> (plist-get summary :not-due) 0)
                         (format "  (%d not due: %s)"
                                 (plist-get summary :not-due)
                                 (if not-due-visible "shown" "hidden"))
                       ""))
             'face 'routine-checklist-header-value)
            "\n\n")
    (if (null items)
        (insert (propertize "  (No items in this checklist.)"
                            'face 'routine-checklist-header-meta)
                "\n")
      (cl-loop
       for item in items
       for idx from 0
       do
       (let* ((state (plist-get item :state))
              (due-p (plist-get item :due-at-start))
              (ad-hoc-p (plist-get item :ad-hoc))
              (title (or (plist-get item :title) ""))
              (last-before (plist-get item :last-completed-before-run))
              (titem-id (plist-get item :template-item-id))
              (cadence (and cadence-map titem-id (gethash titem-id cadence-map)))
              (hidden-p (and (not due-p)
                             (eq state 'pending)
                             (not not-due-visible)))
              (checkbox (pcase state
                          ('checked (propertize "[X]" 'face
                                                'routine-checklist-checkbox-checked))
                          ('skipped (propertize "[-]" 'face
                                                'routine-checklist-checkbox-skipped))
                          (_ "[ ]")))
              (title-face (cond
                           ((eq state 'checked) 'routine-checklist-item-checked)
                           ((eq state 'skipped) 'routine-checklist-item-skipped)
                           ((not due-p) 'routine-checklist-item-not-due)
                           (t 'routine-checklist-item-due)))
              (line-start (point)))
         (unless hidden-p
           (push idx visible-indices))
         (insert "  " checkbox " " (propertize title 'face title-face))
         (when ad-hoc-p
           (insert "  " (propertize "[ad-hoc]" 'face
                                    'routine-checklist-badge-adhoc)))
         (unless due-p
           (insert "  " (propertize "[not due]" 'face
                                    'routine-checklist-badge-not-due)))
         (unless ad-hoc-p
           (insert "  "
                   (propertize
                    (format "(last: %s)"
                            (routine-checklist-format-relative-age
                             last-before nil cadence))
                    'face 'routine-checklist-age)))
         (put-text-property line-start (point)
                            'routine-checklist-run-item-index idx)
         (insert "\n")
         (when hidden-p
           (let ((ov (make-overlay line-start (point))))
             (overlay-put ov 'invisible 'routine-checklist-not-due)
             (push ov routine-checklist--not-due-overlays))))))
    (insert "\n"
            (propertize
             (if active-p
                 (concat "Keys: [SPC/RET] check  [s] skip  [h] show/hide not-due"
                         "  [a] add ad-hoc  [e] edit label\n"
                         "      [f] finish & archive  [g] refresh  [q] quit\n")
               "Keys: [h] show/hide not-due  [g] reload  [q] quit\n")
             'face 'routine-checklist-header-meta))
    (set-buffer-modified-p nil)
    (let ((ordered-visible (nreverse visible-indices)))
      (if ordered-visible
          (let* ((wanted (or target-index prev-index 0))
                 (dest (cond
                        ((member wanted ordered-visible) wanted)
                        ((seq-find (lambda (i) (>= i wanted)) ordered-visible))
                        (t (car (last ordered-visible))))))
            (routine-checklist--goto-item dest))
        (goto-char (point-min))))))

(defun routine-checklist-open-run-buffer (run &optional run-path)
  "Open RUN in a `routine-checklist-mode' buffer and return the buffer.
RUN-PATH optionally supplies the `.eld' path for refreshing archived runs."
  (let* ((id (plist-get run :id))
         (existing (and id (routine-checklist--find-run-buffer id)))
         (buf (or existing
                  (generate-new-buffer (routine-checklist--buffer-name run))))
         (resolved-path
          (or run-path
              (if (eq (plist-get run :status) 'active)
                  (routine-checklist-store-active-run-path id)
                (routine-checklist-store-archived-run-path
                 id (routine-checklist-store--archive-year run))))))
    (with-current-buffer buf
      (unless existing
        (routine-checklist-mode))
      (setq routine-checklist--run (copy-tree run)
            routine-checklist--run-path resolved-path)
      (rename-buffer (routine-checklist--buffer-name run) t)
      (routine-checklist--render))
    (pop-to-buffer-same-window buf)
    buf))

(defun routine-checklist--persist-mutation (result idx)
  "Persist run/template changes in RESULT and re-render at item IDX."
  (let ((new-run (plist-get result :run))
        (new-tpl (plist-get result :template))
        (tpl-changed (plist-get result :template-changed)))
    (routine-checklist-store-save-run new-run)
    (when (and tpl-changed new-tpl)
      (routine-checklist-store-save-template new-tpl))
    (setq routine-checklist--run new-run)
    (routine-checklist--render idx)))

(defun routine-checklist-toggle-check (&optional now)
  "Toggle checked/unchecked state on the item at point at NOW."
  (interactive)
  (routine-checklist--ensure-active)
  (let* ((idx (routine-checklist--require-item-index))
         (run routine-checklist--run)
         (item (nth idx (plist-get run :items)))
         (tpl-id (plist-get run :template-id))
         (template (and tpl-id
                        (routine-checklist-store-load-template tpl-id t)))
         (result (if (eq (plist-get item :state) 'checked)
                     (routine-checklist-apply-uncheck run template idx)
                   (routine-checklist-apply-check run template idx now))))
    (routine-checklist--persist-mutation result idx)))

(defun routine-checklist-toggle-skip ()
  "Toggle skipped state on the item at point without marking completion."
  (interactive)
  (routine-checklist--ensure-active)
  (let* ((idx (routine-checklist--require-item-index))
         (run routine-checklist--run)
         (tpl-id (plist-get run :template-id))
         (template (and tpl-id
                        (routine-checklist-store-load-template tpl-id t)))
         (result (routine-checklist-apply-skip run template idx)))
    (routine-checklist--persist-mutation result idx)))

(defun routine-checklist-toggle-not-due ()
  "Toggle visibility of not-due pending items in place."
  (interactive)
  (routine-checklist--ensure-mode)
  (let* ((idx (routine-checklist--current-item-index))
         (updated (routine-checklist-toggle-not-due-visible
                   routine-checklist--run)))
    (when (eq (plist-get updated :status) 'active)
      (routine-checklist-store-save-run updated))
    (setq routine-checklist--run updated)
    (routine-checklist--render idx)
    (message (if (plist-get updated :not-due-visible)
                 "Not-due items shown"
               "Not-due items hidden"))))

(defun routine-checklist-add-ad-hoc-item (title)
  "Add a run-only ad-hoc item titled TITLE after point (or at end)."
  (interactive
   (progn
     (routine-checklist--ensure-active)
     (list (read-string "Ad-hoc item title: "))))
  (routine-checklist--ensure-active)
  (let* ((idx (routine-checklist--current-item-index))
         (items (plist-get routine-checklist--run :items))
         (target-idx (if idx (min (length items) (1+ idx)) (length items)))
         (updated (routine-checklist-add-ad-hoc
                   routine-checklist--run title idx)))
    (routine-checklist-store-save-run updated)
    (setq routine-checklist--run updated)
    (routine-checklist--render target-idx)))

(defun routine-checklist-edit-label (new-label)
  "Edit the optional subject label of the current run to NEW-LABEL."
  (interactive
   (progn
     (routine-checklist--ensure-active)
     (list (read-string "Run label (empty to clear): "
                        (or (plist-get routine-checklist--run :label) "")))))
  (routine-checklist--ensure-active)
  (let* ((idx (routine-checklist--current-item-index))
         (updated (routine-checklist-set-run-label
                   routine-checklist--run new-label)))
    (routine-checklist-store-save-run updated)
    (setq routine-checklist--run updated)
    (rename-buffer (routine-checklist--buffer-name updated) t)
    (routine-checklist--render idx)))

(defun routine-checklist-finish (&optional no-confirm now)
  "Finish and archive the current active checklist run at NOW.
When due items remain pending and NO-CONFIRM is nil, prompt first."
  (interactive)
  (routine-checklist--ensure-active)
  (let* ((summary (routine-checklist-progress-summary routine-checklist--run))
         (remaining (plist-get summary :remaining)))
    (when (and (not no-confirm)
               (> remaining 0)
               (not (y-or-n-p
                     (format "%d due item(s) still pending. Finish and archive as incomplete? "
                             remaining))))
      (user-error "Finish canceled"))
    (let* ((archived (routine-checklist-finish-run routine-checklist--run now))
           (archive-path (routine-checklist-store-archive-run archived)))
      (setq routine-checklist--run archived
            routine-checklist--run-path archive-path)
      (rename-buffer (routine-checklist--buffer-name archived) t)
      (routine-checklist--render)
      (message "Archived run (%s) to %s"
               (plist-get archived :status)
               (abbreviate-file-name archive-path))
      archive-path)))

(defun routine-checklist-refresh ()
  "Reload the current run from disk and re-render."
  (interactive)
  (routine-checklist--ensure-mode)
  (let* ((id (plist-get routine-checklist--run :id))
         (status (plist-get routine-checklist--run :status))
         (loaded (if (eq status 'active)
                     (routine-checklist-store-load-run id)
                   (routine-checklist-store-load-archived-run
                    (or routine-checklist--run-path id)))))
    (setq routine-checklist--run (copy-tree loaded))
    (rename-buffer (routine-checklist--buffer-name loaded) t)
    (routine-checklist--render)
    (message "Refreshed run from disk")))

(provide 'routine-checklist-mode)
;;; routine-checklist-mode.el ends here
