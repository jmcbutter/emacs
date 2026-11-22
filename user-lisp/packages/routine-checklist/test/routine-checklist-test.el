;;; routine-checklist-test.el --- ERT tests for routine-checklist -*- lexical-binding: t -*-

;;; Commentary:

;; Standalone ERT suite for `routine-checklist' (SLICE-01: Storage
;; and Template Editor).

;;; Code:

(eval-and-compile
  (let ((test-dir (file-name-directory
                   (or load-file-name
                       (and (boundp 'byte-compile-current-file)
                            byte-compile-current-file)
                       buffer-file-name))))
    (add-to-list 'load-path (expand-file-name ".." test-dir))
    (add-to-list 'load-path (expand-file-name "../../../config" test-dir))))

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'routine-checklist-store)
(require 'routine-checklist-template-mode)
(require 'routine-checklist)
(require 'config-agenda)

(defmacro routine-checklist-test--with-data-dir (&rest body)
  "Run BODY with `routine-checklist-data-directory' bound to a temp dir."
  `(let ((routine-checklist-data-directory
          (file-name-as-directory (make-temp-file "rc-test-" t))))
     (unwind-protect
         (progn ,@body)
       (dolist (buf (buffer-list))
         (when (buffer-live-p buf)
           (with-current-buffer buf
             (when (derived-mode-p 'routine-checklist-template-mode)
               (setq routine-checklist-template--dirty nil)
               (set-buffer-modified-p nil)
               (kill-buffer buf)))))
       (delete-directory routine-checklist-data-directory t))))

(defun routine-checklist-test--read-raw (path)
  "Return the raw string contents of PATH."
  (with-temp-buffer
    (insert-file-contents path)
    (buffer-string)))

(ert-deftest routine-checklist-store-round-trip-and-unknown-keys ()
  (routine-checklist-test--with-data-dir
   (let* ((item1 (list :id "3f9a1c82"
                       :title "Wipe kitchen counters"
                       :cadence '(:every 1 :unit days :boundary calendar)
                       :last-completed "2026-11-22T09:10:00-0600"
                       :future-item-meta "keep-me"))
          (item2 (list :id "8b2e4d10"
                       :title "Inspect water filter"
                       :cadence '(:every 12 :unit hours :boundary elapsed)
                       :last-completed nil))
          (tpl (list :schema-version 1
                     :id "house-cleaning"
                     :name "House Cleaning"
                     :run-policy 'concurrent
                     :default-not-due-visibility 'hidden
                     :future-org-key '(:reserved t)
                     :items (list item1 item2)))
          (saved-path (routine-checklist-store-save-template tpl))
          (reloaded (routine-checklist-store-load-template "house-cleaning")))
     (should (file-directory-p (routine-checklist-store-templates-dir)))
     (should (file-directory-p (routine-checklist-store-active-runs-dir)))
     (should (file-directory-p (routine-checklist-store-archive-runs-dir)))
     (should (file-exists-p saved-path))
     (should (equal tpl reloaded))
     (should (equal "keep-me"
                    (plist-get (car (plist-get reloaded :items))
                               :future-item-meta)))
     (should (equal '(:reserved t)
                    (plist-get reloaded :future-org-key))))))

(ert-deftest routine-checklist-store-atomic-write-and-safe-read ()
  (routine-checklist-test--with-data-dir
   (let* ((tpl (routine-checklist-store-make-template
                "Morning Routine" "morning-routine"))
          (path (routine-checklist-store-save-template tpl))
          (raw (routine-checklist-test--read-raw path))
          (entries (directory-files (routine-checklist-store-templates-dir)
                                    nil "\\`[^.]\\|^\\.[^.]")))
     (should (string-prefix-p routine-checklist-store-file-header raw))
     (should (equal '("morning-routine.eld") entries))
     ;; Missing or wrong schema-version is rejected.
     (let ((bad-ver (expand-file-name "bad-ver.eld"
                                      (routine-checklist-store-templates-dir))))
       (with-temp-file bad-ver
         (insert "(:schema-version 99 :id \"bad-ver\" :name \"Bad\")\n"))
       (should-error (routine-checklist-store--read-file bad-ver)))
     ;; Read-time evaluation #. is blocked and never executed.
     (let ((evil-file (expand-file-name "evil.eld"
                                        (routine-checklist-store-templates-dir)))
           (marker nil))
       (with-temp-file evil-file
         (insert (format "(:schema-version 1 :id \"evil\" :bad #.(setq %s t))\n"
                         'marker)))
       (should-error (routine-checklist-store--read-file evil-file))
       (should-not marker)))))

(ert-deftest routine-checklist-store-id-and-slugify ()
  (routine-checklist-test--with-data-dir
   (let ((ids (cl-loop repeat 25 collect (routine-checklist-store-generate-id))))
     (should (= 25 (length (seq-uniq ids))))
     (dolist (id ids)
       (should (string-match-p "\\`[0-9a-f]\\{8\\}\\'" id))))
   (should (equal "house-cleaning"
                  (routine-checklist-store-slugify "  House & Cleaning! ")))
   (should (equal "template"
                  (routine-checklist-store-slugify "!!!")))
   (should (equal "qa-checklist-3"
                  (routine-checklist-store-slugify
                   "QA Checklist" '("qa-checklist" "qa-checklist-2"))))
   ;; Collision avoidance against files on disk.
   (routine-checklist-store-save-template
    (routine-checklist-store-make-template "Daily Review" "daily-review"))
   (should (equal "daily-review-2"
                  (routine-checklist-store-slugify "Daily Review")))))

(ert-deftest routine-checklist-store-delete-template ()
  (routine-checklist-test--with-data-dir
   (routine-checklist-store-save-template
    (routine-checklist-store-make-template "Alpha" "alpha"))
   (routine-checklist-store-save-template
    (routine-checklist-store-make-template "Beta" "beta"))
   (should (= 2 (length (routine-checklist-store-list-templates))))
   (should (routine-checklist-store-delete-template "alpha"))
   (should-not (routine-checklist-store-delete-template "alpha"))
   (should-not (file-exists-p (routine-checklist-store-template-path "alpha")))
   (let ((remaining (routine-checklist-store-list-templates)))
     (should (= 1 (length remaining)))
     (should (equal "beta" (plist-get (car remaining) :id))))))

(ert-deftest routine-checklist-template-law-l1-rename-item-preserves-id-and-history ()
  (routine-checklist-test--with-data-dir
   (let* ((item (list :id "3f9a1c82"
                      :title "Wipe kitchen counters"
                      :cadence '(:every 2 :unit days :boundary calendar)
                      :last-completed "2026-11-15T14:20:00-0600"
                      :custom-item-prop 'keep))
          (tpl (routine-checklist-store-make-template
                "House Cleaning" "house-cleaning" 'carry-over 'dimmed
                (list item))))
     (routine-checklist-store-save-template tpl)
     (let ((buf (routine-checklist-template-open
                 (routine-checklist-store-load-template "house-cleaning") t)))
       (with-current-buffer buf
         (routine-checklist-template--goto-item 0)
         (routine-checklist-template-edit-item-title "Sanitize kitchen counters")
         (routine-checklist-template-save)))
     (let* ((reloaded (routine-checklist-store-load-template "house-cleaning"))
            (reloaded-item (car (plist-get reloaded :items))))
       (should (equal "Sanitize kitchen counters"
                      (plist-get reloaded-item :title)))
       (should (equal "3f9a1c82" (plist-get reloaded-item :id)))
       (should (equal "2026-11-15T14:20:00-0600"
                      (plist-get reloaded-item :last-completed)))
       (should (equal '(:every 2 :unit days :boundary calendar)
                      (plist-get reloaded-item :cadence)))
       (should (eq 'keep (plist-get reloaded-item :custom-item-prop)))))))

(ert-deftest routine-checklist-template-mode-item-and-metadata-editing ()
  (routine-checklist-test--with-data-dir
   ;; Verify all mode keybindings.
   (dolist (binding '(("a" . routine-checklist-template-add-item)
                      ("e" . routine-checklist-template-edit-item-title)
                      ("RET" . routine-checklist-template-edit-item-title)
                      ("c" . routine-checklist-template-set-cadence)
                      ("M-<up>" . routine-checklist-template-move-item-up)
                      ("M-<down>" . routine-checklist-template-move-item-down)
                      ("d" . routine-checklist-template-delete-item)
                      ("p" . routine-checklist-template-set-run-policy)
                      ("v" . routine-checklist-template-set-not-due-visibility)
                      ("r" . routine-checklist-template-rename)
                      ("o" . routine-checklist-template-open-raw)
                      ("C-c C-s" . routine-checklist-template-save)
                      ("g" . routine-checklist-template-reload)
                      ("q" . routine-checklist-template-quit)))
     (should (eq (cdr binding)
                 (lookup-key routine-checklist-template-mode-map
                             (kbd (car binding))))))
   ;; Verify cadence reader boundary defaults (hours -> elapsed, days/weeks/months -> calendar).
   (cl-letf (((symbol-function 'completing-read)
              (lambda (_prompt coll &rest args)
                (let ((def (nth 4 args)))
                  (cond
                   ((member "hours" coll) "hours")
                   (t def)))))
             ((symbol-function 'read-number)
              (lambda (_prompt &optional def) (or def 6))))
     (should (equal '(:every 1 :unit hours :boundary elapsed)
                    (routine-checklist-template--read-cadence nil))))
   (cl-letf (((symbol-function 'completing-read)
              (lambda (_prompt coll &rest args)
                (let ((def (nth 4 args)))
                  (cond
                   ((member "weeks" coll) "weeks")
                   (t def)))))
             ((symbol-function 'read-number)
              (lambda (_prompt &optional _def) 2)))
     (should (equal '(:every 2 :unit weeks :boundary calendar)
                    (routine-checklist-template--read-cadence nil))))
   (cl-letf (((symbol-function 'completing-read)
              (lambda (_prompt _coll &rest _args) "none (every run)")))
     (should-not (routine-checklist-template--read-cadence
                  '(:every 3 :unit days :boundary calendar))))

   (let* ((tpl (routine-checklist-store-make-template "QA" "qa"))
          (buf (routine-checklist-template-open tpl nil)))
     (with-current-buffer buf
       (should routine-checklist-template--dirty)
       ;; Add items and check cursor placement + order.
       (routine-checklist-template-add-item "First")
       (routine-checklist-template-add-item "Second")
       (routine-checklist-template-add-item "Third")
       (should (equal '("First" "Second" "Third")
                      (mapcar (lambda (i) (plist-get i :title))
                              (plist-get routine-checklist-template--data :items))))
       ;; Reorder up and down, including top/bottom boundary no-ops.
       (routine-checklist-template--goto-item 1)
       (routine-checklist-template-move-item-up)
       (should (equal '("Second" "First" "Third")
                      (mapcar (lambda (i) (plist-get i :title))
                              (plist-get routine-checklist-template--data :items))))
       (should (= 0 (routine-checklist-template--current-item-index)))
       (routine-checklist-template-move-item-up)
       (should (= 0 (routine-checklist-template--current-item-index)))
       (routine-checklist-template-move-item-down)
       (should (equal '("First" "Second" "Third")
                      (mapcar (lambda (i) (plist-get i :title))
                              (plist-get routine-checklist-template--data :items))))
       ;; Set and clear cadence.
       (routine-checklist-template--goto-item 0)
       (routine-checklist-template-set-cadence
        '(:every 7 :unit days :boundary calendar))
       (should (equal '(:every 7 :unit days :boundary calendar)
                      (plist-get (car (plist-get routine-checklist-template--data :items))
                                 :cadence)))
       (routine-checklist-template-set-cadence nil)
       (should-not (plist-get (car (plist-get routine-checklist-template--data :items))
                              :cadence))
       ;; Delete middle item.
       (routine-checklist-template--goto-item 1)
       (routine-checklist-template-delete-item t)
       (should (equal '("First" "Third")
                      (mapcar (lambda (i) (plist-get i :title))
                              (plist-get routine-checklist-template--data :items))))
       ;; Run policy and visibility.
       (dolist (pol '(carry-over fresh-per-repetition concurrent))
         (routine-checklist-template-set-run-policy pol)
         (should (eq pol (plist-get routine-checklist-template--data :run-policy))))
       (dolist (vis '(dimmed hidden nil))
         (routine-checklist-template-set-not-due-visibility vis)
         (should (eq vis (plist-get routine-checklist-template--data
                                    :default-not-due-visibility))))
       ;; Rename template preserves :id.
       (routine-checklist-template-rename "QA Release")
       (should (equal "qa" (plist-get routine-checklist-template--data :id)))
       (should (equal "QA Release"
                      (plist-get routine-checklist-template--data :name)))
       (should (equal "*Routine Template: QA Release*" (buffer-name)))
       ;; Save clears dirty and persists; editing and reloading restores disk state.
       (routine-checklist-template-save)
       (should-not routine-checklist-template--dirty)
       (routine-checklist-template-add-item "Unsaved Item")
       (should routine-checklist-template--dirty)
       (cl-letf (((symbol-function 'y-or-n-p) (lambda (_prompt) t)))
         (routine-checklist-template-reload))
       (should-not routine-checklist-template--dirty)
       (should (equal '("First" "Third")
                      (mapcar (lambda (i) (plist-get i :title))
                              (plist-get routine-checklist-template--data :items))))
       ;; Quit when dirty prompts and cancels when user declines both save & discard.
       (routine-checklist-template-add-item "Pending Exit")
       (cl-letf (((symbol-function 'y-or-n-p) (lambda (_prompt) nil)))
         (should-error (routine-checklist-template-quit) :type 'user-error))))))

(ert-deftest routine-checklist-template-open-raw-lisp-data-mode ()
  (routine-checklist-test--with-data-dir
   (let* ((tpl (routine-checklist-store-make-template "Raw Test" "raw-test"))
          (path (routine-checklist-store-save-template tpl))
          (buf (routine-checklist-template-open
                (routine-checklist-store-load-template "raw-test") t))
          (raw-buf nil))
     (unwind-protect
         (progn
           (setq raw-buf
                 (with-current-buffer buf
                   (routine-checklist-template-open-raw)))
           (should (equal (file-truename path)
                          (file-truename (buffer-file-name raw-buf))))
           (with-current-buffer raw-buf
             (should (derived-mode-p 'lisp-data-mode))))
       (when (buffer-live-p raw-buf)
         (kill-buffer raw-buf))))))

(ert-deftest routine-checklist-manage-templates-flows ()
  (routine-checklist-test--with-data-dir
   ;; Create via completing-read -> "+ Create new template".
   (cl-letf (((symbol-function 'completing-read)
              (lambda (&rest _args) "+ Create new template"))
             ((symbol-function 'read-string)
              (lambda (&rest _args) "Evening Wind Down")))
     (let ((buf (routine-checklist-manage-templates)))
       (with-current-buffer buf
         (should (derived-mode-p 'routine-checklist-template-mode))
         (should (equal "evening-wind-down"
                        (plist-get routine-checklist-template--data :id)))
         (routine-checklist-template-add-item "Journal")
         (routine-checklist-template-save))))
   ;; Open existing template.
   (cl-letf (((symbol-function 'completing-read)
              (lambda (&rest _args) "Evening Wind Down")))
     (let ((buf (routine-checklist-manage-templates)))
       (with-current-buffer buf
         (should (equal "Evening Wind Down"
                        (plist-get routine-checklist-template--data :name))))))
   ;; Delete via "- Delete a template".
   (let ((prompts nil))
     (cl-letf (((symbol-function 'completing-read)
                (lambda (prompt &rest _args)
                  (push prompt prompts)
                  (if (string-prefix-p "Delete" prompt)
                      "Evening Wind Down"
                    "- Delete a template")))
               ((symbol-function 'yes-or-no-p) (lambda (_prompt) t)))
       (routine-checklist-manage-templates))
     (should-not (routine-checklist-store-list-templates)))))

(ert-deftest routine-checklist-global-keymap-no-collisions ()
  (should (eq #'routine-checklist-manage-templates
              (key-binding (kbd "C-c o k t"))))
  (should (eq #'routine-checklist-manage-templates
              (lookup-key jmb/org-global-prefix-map (kbd "k t"))))
  (dolist (pair '(("a" . org-agenda)
                  ("c" . org-capture)
                  ("f" . jmb/find-org-file)
                  ("i" . org-clock-in)
                  ("j" . org-clock-goto)
                  ("l" . org-store-link)
                  ("o" . org-clock-out)
                  ("p" . org-clock-in-last)
                  ("n" . jmb/new-project)
                  ("N" . jmb/new-area)
                  ("s" . jmb/new-spec-doc)
                  ("S" . jmb/find-spec-doc)))
    (should (eq (cdr pair)
                (lookup-key jmb/org-global-prefix-map (kbd (car pair)))))))

(provide 'routine-checklist-test)
;;; routine-checklist-test.el ends here
