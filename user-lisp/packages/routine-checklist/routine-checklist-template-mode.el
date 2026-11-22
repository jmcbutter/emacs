;;; routine-checklist-template-mode.el --- Template editor major mode -*- lexical-binding: t -*-

;;; Commentary:

;; Major mode `routine-checklist-template-mode' for creating, editing,
;; reordering, configuring cadences and policies on, and saving
;; routine checklist templates while preserving stable item IDs and
;; completion history.

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

(defvar routine-checklist-default-not-due-visibility 'dimmed
  "Default visibility for not-due items when a template does not specify one.")

(defface routine-checklist-template-title
  '((t :weight bold :height 1.2))
  "Face for the template title in `routine-checklist-template-mode'."
  :group 'routine-checklist)

(defface routine-checklist-template-label
  '((t :inherit font-lock-keyword-face))
  "Face for metadata field labels in `routine-checklist-template-mode'."
  :group 'routine-checklist)

(defface routine-checklist-template-value
  '((t :inherit default :weight semibold))
  "Face for metadata field values in `routine-checklist-template-mode'."
  :group 'routine-checklist)

(defface routine-checklist-template-cadence
  '((t :inherit font-lock-type-face))
  "Face for item cadence badges in `routine-checklist-template-mode'."
  :group 'routine-checklist)

(defface routine-checklist-template-meta
  '((t :inherit shadow))
  "Face for secondary annotations and hints in `routine-checklist-template-mode'."
  :group 'routine-checklist)

(defface routine-checklist-template-modified
  '((t :inherit warning))
  "Face for the unsaved-changes indicator in `routine-checklist-template-mode'."
  :group 'routine-checklist)

(defvar-local routine-checklist-template--data nil
  "In-memory template plist currently edited in this buffer.")

(defvar-local routine-checklist-template--dirty nil
  "Non-nil when the template buffer has unsaved changes.")

(defvar-local routine-checklist-template--persisted-p nil
  "Non-nil when the template has been saved to disk at least once.")

(defvar routine-checklist-template-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "a") #'routine-checklist-template-add-item)
    (define-key map (kbd "e") #'routine-checklist-template-edit-item-title)
    (define-key map (kbd "RET") #'routine-checklist-template-edit-item-title)
    (define-key map (kbd "c") #'routine-checklist-template-set-cadence)
    (define-key map (kbd "M-<up>") #'routine-checklist-template-move-item-up)
    (define-key map (kbd "M-<down>") #'routine-checklist-template-move-item-down)
    (define-key map (kbd "d") #'routine-checklist-template-delete-item)
    (define-key map (kbd "p") #'routine-checklist-template-set-run-policy)
    (define-key map (kbd "v") #'routine-checklist-template-set-not-due-visibility)
    (define-key map (kbd "r") #'routine-checklist-template-rename)
    (define-key map (kbd "o") #'routine-checklist-template-open-raw)
    (define-key map (kbd "C-c C-s") #'routine-checklist-template-save)
    (define-key map [remap save-buffer] #'routine-checklist-template-save)
    (define-key map (kbd "g") #'routine-checklist-template-reload)
    (define-key map (kbd "q") #'routine-checklist-template-quit)
    map)
  "Keymap for `routine-checklist-template-mode'.")

(define-derived-mode routine-checklist-template-mode special-mode
  "Routine-Template"
  "Major mode for editing a routine checklist template.

\\{routine-checklist-template-mode-map}"
  (setq-local truncate-lines t))

(defun routine-checklist-template--ensure-mode ()
  "Signal a `user-error' unless inside `routine-checklist-template-mode'."
  (unless (derived-mode-p 'routine-checklist-template-mode)
    (user-error "Not in a routine checklist template buffer")))

(defun routine-checklist-template--format-cadence (cadence)
  "Format CADENCE plist (or nil) into a human-readable label."
  (if (null cadence)
      "every run"
    (let* ((every (plist-get cadence :every))
           (unit (plist-get cadence :unit))
           (boundary (plist-get cadence :boundary))
           (unit-name (symbol-name unit))
           (unit-label (if (= every 1)
                           (pcase unit
                             ('hours "hour")
                             ('days "day")
                             ('weeks "week")
                             ('months "month")
                             (_ unit-name))
                         unit-name)))
      (format "every %d %s (%s)" every unit-label boundary))))

(defun routine-checklist-template--format-visibility (vis)
  "Format default not-due visibility VIS for display."
  (if vis
      (symbol-name vis)
    (format "inherit (%s)" routine-checklist-default-not-due-visibility)))

(defun routine-checklist-template--buffer-name (template)
  "Return the editor buffer name for TEMPLATE."
  (format "*Routine Template: %s*"
          (or (plist-get template :name)
              (plist-get template :id)
              "Untitled")))

(defun routine-checklist-template--current-item-index ()
  "Return the 0-based item index at point, or nil if not on an item line."
  (get-text-property (line-beginning-position) 'routine-checklist-item-index))

(defun routine-checklist-template--require-item-index ()
  "Return the 0-based item index at point or signal a `user-error'."
  (or (routine-checklist-template--current-item-index)
      (user-error "No item at point")))

(defun routine-checklist-template--goto-item (index)
  "Move point to the item with 0-based INDEX if present in the buffer."
  (when-let* ((pos (text-property-any (point-min) (point-max)
                                      'routine-checklist-item-index index)))
    (goto-char pos)))

(defun routine-checklist-template--mark-dirty ()
  "Mark the template buffer as having unsaved changes."
  (setq routine-checklist-template--dirty t)
  (set-buffer-modified-p t))

(defun routine-checklist-template--find-buffer (template-id)
  "Return an open `routine-checklist-template-mode' buffer for TEMPLATE-ID."
  (seq-find
   (lambda (buf)
     (with-current-buffer buf
       (and (derived-mode-p 'routine-checklist-template-mode)
            (equal (plist-get routine-checklist-template--data :id)
                   template-id))))
   (buffer-list)))

(defun routine-checklist-template--render (&optional target-index)
  "Render `routine-checklist-template--data' into the current buffer.
If TARGET-INDEX is non-nil, move point to that item after rendering."
  (let* ((data routine-checklist-template--data)
         (id (plist-get data :id))
         (name (plist-get data :name))
         (policy (plist-get data :run-policy))
         (vis (plist-get data :default-not-due-visibility))
         (items (plist-get data :items))
         (prev-index (or target-index
                         (routine-checklist-template--current-item-index)))
         (inhibit-read-only t))
    (erase-buffer)
    (insert (propertize (or name "") 'face 'routine-checklist-template-title))
    (when routine-checklist-template--dirty
      (insert (propertize "  [unsaved]" 'face 'routine-checklist-template-modified)))
    (insert "\n")
    (insert (propertize "ID: " 'face 'routine-checklist-template-label)
            (propertize (or id "") 'face 'routine-checklist-template-meta)
            "\n")
    (insert (propertize "Run policy: " 'face 'routine-checklist-template-label)
            (propertize (symbol-name (or policy 'carry-over))
                        'face 'routine-checklist-template-value)
            "\n")
    (insert (propertize "Not-due visibility: " 'face 'routine-checklist-template-label)
            (propertize (routine-checklist-template--format-visibility vis)
                        'face 'routine-checklist-template-value)
            "\n")
    (when id
      (insert (propertize "File: " 'face 'routine-checklist-template-label)
              (propertize (abbreviate-file-name
                           (routine-checklist-store-template-path id))
                          'face 'routine-checklist-template-meta)
              "\n"))
    (insert "\n"
            (propertize (format "Items (%d):" (length items))
                        'face 'routine-checklist-template-label)
            "\n")
    (if (null items)
        (insert (propertize "  (No items yet. Press `a' to add one.)"
                            'face 'routine-checklist-template-meta)
                "\n")
      (cl-loop
       for item in items
       for idx from 0
       do
       (let ((start (point))
             (title (or (plist-get item :title) ""))
             (cadence (plist-get item :cadence))
             (last-done (plist-get item :last-completed)))
         (insert (format "  %2d. %s" (1+ idx) title)
                 "  "
                 (propertize
                  (format "[%s]" (routine-checklist-template--format-cadence cadence))
                  'face 'routine-checklist-template-cadence))
         (when (and (stringp last-done) (not (string-empty-p last-done)))
           (insert (propertize
                    (format "  (last: %s)"
                            (substring last-done 0 (min 10 (length last-done))))
                    'face 'routine-checklist-template-meta)))
         (put-text-property start (point) 'routine-checklist-item-index idx)
         (insert "\n"))))
    (insert "\n"
            (propertize
             (concat "Keys: [a] add  [e/RET] edit title  [c] cadence"
                     "  [M-up/M-down] reorder  [d] delete\n"
                     "      [p] policy  [v] visibility  [r] rename"
                     "  [o] raw .eld  [C-c C-s] save  [g] reload  [q] quit\n")
             'face 'routine-checklist-template-meta))
    (set-buffer-modified-p routine-checklist-template--dirty)
    (if items
        (let ((dest (cond
                     ((and target-index (>= target-index 0)
                           (< target-index (length items)))
                      target-index)
                     ((and prev-index (>= prev-index 0))
                      (min prev-index (1- (length items))))
                     (t 0))))
          (routine-checklist-template--goto-item dest))
      (goto-char (point-min)))))

(defun routine-checklist-template-open (template &optional persisted-p)
  "Open TEMPLATE in a `routine-checklist-template-mode' buffer.
PERSISTED-P non-nil indicates TEMPLATE matches an existing file on disk.
Return the template editor buffer."
  (let* ((id (plist-get template :id))
         (existing (and id (routine-checklist-template--find-buffer id)))
         (buf (or existing
                  (generate-new-buffer
                   (routine-checklist-template--buffer-name template)))))
    (with-current-buffer buf
      (unless existing
        (routine-checklist-template-mode)
        (setq routine-checklist-template--data (copy-tree template)
              routine-checklist-template--persisted-p (and persisted-p t)
              routine-checklist-template--dirty (not persisted-p))
        (routine-checklist-template--render))
      (when (and existing persisted-p (not routine-checklist-template--dirty))
        (setq routine-checklist-template--data (copy-tree template)
              routine-checklist-template--persisted-p t)
        (rename-buffer (routine-checklist-template--buffer-name template) t)
        (routine-checklist-template--render)))
    (pop-to-buffer-same-window buf)
    buf))

(defun routine-checklist-template-add-item (title)
  "Add a new item with TITLE to the template after point (or at the end)."
  (interactive
   (progn
     (routine-checklist-template--ensure-mode)
     (list (read-string "Item title: "))))
  (routine-checklist-template--ensure-mode)
  (let* ((trimmed (string-trim (or title ""))))
    (when (string-empty-p trimmed)
      (user-error "Item title must not be empty"))
    (let* ((items (copy-sequence
                   (plist-get routine-checklist-template--data :items)))
           (idx (routine-checklist-template--current-item-index))
           (new-item (routine-checklist-store-make-item trimmed))
           (insert-pos (if idx (1+ idx) (length items)))
           (new-items (append (seq-take items insert-pos)
                              (list new-item)
                              (nthcdr insert-pos items))))
      (setq routine-checklist-template--data
            (routine-checklist-store--plist-put
             routine-checklist-template--data :items new-items))
      (routine-checklist-template--mark-dirty)
      (routine-checklist-template--render insert-pos))))

(defun routine-checklist-template-edit-item-title (new-title)
  "Edit the title of the item at point to NEW-TITLE.
Preserves `:id', `:cadence', `:last-completed', and any unknown keys."
  (interactive
   (progn
     (routine-checklist-template--ensure-mode)
     (let* ((idx (routine-checklist-template--require-item-index))
            (item (nth idx (plist-get routine-checklist-template--data :items))))
       (list (read-string "Edit item title: " (plist-get item :title))))))
  (routine-checklist-template--ensure-mode)
  (let* ((idx (routine-checklist-template--require-item-index))
         (trimmed (string-trim (or new-title "")))
         (items (copy-sequence
                 (plist-get routine-checklist-template--data :items)))
         (item (nth idx items)))
    (when (string-empty-p trimmed)
      (user-error "Item title must not be empty"))
    (setf (nth idx items)
          (routine-checklist-store--plist-put item :title trimmed))
    (setq routine-checklist-template--data
          (routine-checklist-store--plist-put
           routine-checklist-template--data :items items))
    (routine-checklist-template--mark-dirty)
    (routine-checklist-template--render idx)))

(defun routine-checklist-template--read-cadence (&optional current)
  "Prompt for a cadence plist (or nil for every run), defaulting from CURRENT."
  (let* ((units '("none (every run)" "hours" "days" "weeks" "months"))
         (default-unit (if current
                           (symbol-name (plist-get current :unit))
                         "days"))
         (unit-str (completing-read "Cadence unit: " units nil t
                                    nil nil default-unit)))
    (if (equal unit-str "none (every run)")
        nil
      (let* ((unit-sym (intern unit-str))
             (default-every (or (plist-get current :every) 1))
             (every (read-number (format "Every how many %s: " unit-str)
                                 default-every))
             (_ (unless (and (integerp every) (> every 0))
                  (user-error "Interval must be a positive integer")))
             (default-boundary
              (if (and current
                       (eq (plist-get current :unit) unit-sym)
                       (plist-get current :boundary))
                  (symbol-name (plist-get current :boundary))
                (if (eq unit-sym 'hours) "elapsed" "calendar")))
             (boundary-str (completing-read "Cadence boundary: "
                                            '("calendar" "elapsed")
                                            nil t nil nil default-boundary)))
        (list :every every
              :unit unit-sym
              :boundary (intern boundary-str))))))

(defun routine-checklist-template-set-cadence (cadence)
  "Set or clear CADENCE on the template item at point."
  (interactive
   (progn
     (routine-checklist-template--ensure-mode)
     (let* ((idx (routine-checklist-template--require-item-index))
            (item (nth idx (plist-get routine-checklist-template--data :items))))
       (list (routine-checklist-template--read-cadence
              (plist-get item :cadence))))))
  (routine-checklist-template--ensure-mode)
  (let ((idx (routine-checklist-template--require-item-index)))
    (routine-checklist-store--validate-cadence cadence)
    (let* ((items (copy-sequence
                   (plist-get routine-checklist-template--data :items)))
           (item (nth idx items)))
      (setf (nth idx items)
            (routine-checklist-store--plist-put item :cadence cadence))
      (setq routine-checklist-template--data
            (routine-checklist-store--plist-put
             routine-checklist-template--data :items items))
      (routine-checklist-template--mark-dirty)
      (routine-checklist-template--render idx))))

(defun routine-checklist-template--move-item (delta)
  "Move the item at point by DELTA positions (-1 up, +1 down)."
  (routine-checklist-template--ensure-mode)
  (let* ((idx (routine-checklist-template--require-item-index))
         (items (copy-sequence
                 (plist-get routine-checklist-template--data :items)))
         (new-idx (+ idx delta)))
    (if (or (< new-idx 0) (>= new-idx (length items)))
        (message "Item is already at the %s" (if (< delta 0) "top" "bottom"))
      (let ((tmp (nth new-idx items)))
        (setf (nth new-idx items) (nth idx items)
              (nth idx items) tmp))
      (setq routine-checklist-template--data
            (routine-checklist-store--plist-put
             routine-checklist-template--data :items items))
      (routine-checklist-template--mark-dirty)
      (routine-checklist-template--render new-idx))))

(defun routine-checklist-template-move-item-up ()
  "Move the item at point one position up."
  (interactive)
  (routine-checklist-template--move-item -1))

(defun routine-checklist-template-move-item-down ()
  "Move the item at point one position down."
  (interactive)
  (routine-checklist-template--move-item 1))

(defun routine-checklist-template-delete-item (&optional no-confirm)
  "Delete the template item at point.
When NO-CONFIRM is non-nil, skip confirmation."
  (interactive
   (progn
     (routine-checklist-template--ensure-mode)
     (routine-checklist-template--require-item-index)
     (list nil)))
  (routine-checklist-template--ensure-mode)
  (let* ((idx (routine-checklist-template--require-item-index))
         (items (plist-get routine-checklist-template--data :items))
         (item (nth idx items)))
    (when (or no-confirm
              (y-or-n-p (format "Delete item %S? " (plist-get item :title))))
      (let ((new-items (cl-loop for entry in items
                                for i from 0
                                unless (= i idx)
                                collect entry)))
        (setq routine-checklist-template--data
              (routine-checklist-store--plist-put
               routine-checklist-template--data :items new-items))
        (routine-checklist-template--mark-dirty)
        (routine-checklist-template--render
         (when new-items (min idx (1- (length new-items)))))))))

(defun routine-checklist-template-set-run-policy (policy)
  "Set the template's `:run-policy' to POLICY."
  (interactive
   (progn
     (routine-checklist-template--ensure-mode)
     (let* ((cur (symbol-name
                  (or (plist-get routine-checklist-template--data :run-policy)
                      'carry-over)))
            (choice (completing-read
                     "Run policy: "
                     '("carry-over" "fresh-per-repetition" "concurrent")
                     nil t nil nil cur)))
       (list (intern choice)))))
  (routine-checklist-template--ensure-mode)
  (let ((sym (if (stringp policy) (intern policy) policy)))
    (unless (memq sym routine-checklist-store-valid-run-policies)
      (user-error "Invalid run policy: %S" policy))
    (setq routine-checklist-template--data
          (routine-checklist-store--plist-put
           routine-checklist-template--data :run-policy sym))
    (routine-checklist-template--mark-dirty)
    (routine-checklist-template--render)))

(defun routine-checklist-template-set-not-due-visibility (visibility)
  "Set the template's `:default-not-due-visibility' to VISIBILITY."
  (interactive
   (progn
     (routine-checklist-template--ensure-mode)
     (let* ((cur-val (plist-get routine-checklist-template--data
                                :default-not-due-visibility))
            (cur (if cur-val (symbol-name cur-val) "inherit"))
            (choice (completing-read
                     "Default not-due visibility: "
                     '("inherit" "dimmed" "hidden")
                     nil t nil nil cur)))
       (list (if (equal choice "inherit") nil (intern choice))))))
  (routine-checklist-template--ensure-mode)
  (let ((vis (pcase visibility
               ((or "inherit" 'nil) nil)
               ((pred stringp) (intern visibility))
               (_ visibility))))
    (unless (memq vis routine-checklist-store-valid-visibilities)
      (user-error "Invalid visibility setting: %S" visibility))
    (setq routine-checklist-template--data
          (routine-checklist-store--plist-put
           routine-checklist-template--data
           :default-not-due-visibility vis))
    (routine-checklist-template--mark-dirty)
    (routine-checklist-template--render)))

(defun routine-checklist-template-rename (new-name)
  "Rename the current template to NEW-NAME without changing its `:id'."
  (interactive
   (progn
     (routine-checklist-template--ensure-mode)
     (list (read-string "Rename template: "
                        (plist-get routine-checklist-template--data :name)))))
  (routine-checklist-template--ensure-mode)
  (let ((trimmed (string-trim (or new-name ""))))
    (when (string-empty-p trimmed)
      (user-error "Template name must not be empty"))
    (setq routine-checklist-template--data
          (routine-checklist-store--plist-put
           routine-checklist-template--data :name trimmed))
    (routine-checklist-template--mark-dirty)
    (rename-buffer (routine-checklist-template--buffer-name
                    routine-checklist-template--data)
                   t)
    (routine-checklist-template--render)))

(defun routine-checklist-template-save ()
  "Atomically save the template to disk and return the saved file path."
  (interactive)
  (routine-checklist-template--ensure-mode)
  (let ((path (routine-checklist-store-save-template
               routine-checklist-template--data)))
    (setq routine-checklist-template--dirty nil
          routine-checklist-template--persisted-p t)
    (set-buffer-modified-p nil)
    (routine-checklist-template--render)
    (message "Saved template %S to %s"
             (plist-get routine-checklist-template--data :name)
             (abbreviate-file-name path))
    path))

(defun routine-checklist-template-open-raw ()
  "Open the underlying `.eld' file for this template in `lisp-data-mode'."
  (interactive)
  (routine-checklist-template--ensure-mode)
  (let* ((id (plist-get routine-checklist-template--data :id))
         (path (routine-checklist-store-template-path id)))
    (cond
     ((not (file-exists-p path))
      (if (y-or-n-p "Template not saved yet. Save before opening raw .eld? ")
          (routine-checklist-template-save)
        (user-error "Template has not been saved to disk yet")))
     (routine-checklist-template--dirty
      (when (y-or-n-p "Save changes before opening raw .eld? ")
        (routine-checklist-template-save))))
    (let ((buf (find-file path)))
      (with-current-buffer buf
        (unless (derived-mode-p 'lisp-data-mode)
          (lisp-data-mode)))
      buf)))

(defun routine-checklist-template-reload ()
  "Reload the template from disk, prompting if there are unsaved changes."
  (interactive)
  (routine-checklist-template--ensure-mode)
  (when (and routine-checklist-template--dirty
             (not (y-or-n-p "Discard unsaved changes and reload from disk? ")))
    (user-error "Reload canceled"))
  (let* ((id (plist-get routine-checklist-template--data :id))
         (loaded (routine-checklist-store-load-template id t)))
    (unless loaded
      (user-error "Template file does not exist on disk yet"))
    (setq routine-checklist-template--data (copy-tree loaded)
          routine-checklist-template--dirty nil
          routine-checklist-template--persisted-p t)
    (set-buffer-modified-p nil)
    (rename-buffer (routine-checklist-template--buffer-name
                    routine-checklist-template--data)
                   t)
    (routine-checklist-template--render)
    (message "Reloaded template %S from disk" (plist-get loaded :name))))

(defun routine-checklist-template-quit ()
  "Quit the template editor buffer, prompting if unsaved changes exist."
  (interactive)
  (routine-checklist-template--ensure-mode)
  (if (not routine-checklist-template--dirty)
      (quit-window)
    (cond
     ((y-or-n-p "Unsaved changes. Save before closing? ")
      (routine-checklist-template-save)
      (quit-window))
     ((y-or-n-p "Discard unsaved changes and quit? ")
      (setq routine-checklist-template--dirty nil)
      (set-buffer-modified-p nil)
      (quit-window t))
     (t
      (user-error "Quit canceled")))))

(provide 'routine-checklist-template-mode)
;;; routine-checklist-template-mode.el ends here
