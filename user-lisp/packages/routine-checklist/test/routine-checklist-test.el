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
(require 'routine-checklist-cadence)
(require 'routine-checklist-template-mode)
(require 'routine-checklist-mode)
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
             (cond
              ((derived-mode-p 'routine-checklist-template-mode)
               (setq routine-checklist-template--dirty nil)
               (set-buffer-modified-p nil)
               (kill-buffer buf))
              ((derived-mode-p 'routine-checklist-mode)
               (set-buffer-modified-p nil)
               (kill-buffer buf))))))
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
  (should (eq #'routine-checklist-start
              (key-binding (kbd "C-c o k s"))))
  (should (eq #'routine-checklist-open
              (key-binding (kbd "C-c o k o"))))
  (should (eq #'routine-checklist-open-archive
              (key-binding (kbd "C-c o k A"))))
  (should (eq #'routine-checklist-manage-templates
              (lookup-key jmb/org-global-prefix-map (kbd "k t"))))
  (should (eq #'routine-checklist-start
              (lookup-key jmb/org-global-prefix-map (kbd "k s"))))
  (should (eq #'routine-checklist-open
              (lookup-key jmb/org-global-prefix-map (kbd "k o"))))
  (should (eq #'routine-checklist-open-archive
              (lookup-key jmb/org-global-prefix-map (kbd "k A"))))
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

;;;; SLICE-02 & SLICE-03 tests

(ert-deftest routine-checklist-cadence-law-l2-calendar-and-elapsed ()
  ;; nil cadence or nil last-completed is always due.
  (should (routine-checklist-cadence-due-p
           nil "2026-11-22T23:00:00-0600" "2026-11-22T23:05:00-0600"))
  (should (routine-checklist-cadence-due-p
           '(:every 14 :unit days :boundary calendar)
           nil "2026-11-22T23:05:00-0600"))
  ;; Calendar daily: 23:00 -> 07:00 next day is due; same day is not due.
  (should (routine-checklist-cadence-due-p
           '(:every 1 :unit days :boundary calendar)
           "2026-11-22T23:00:00-0600"
           "2026-11-23T07:00:00-0600"))
  (should-not (routine-checklist-cadence-due-p
               '(:every 1 :unit days :boundary calendar)
               "2026-11-22T01:00:00-0600"
               "2026-11-22T23:30:00-0600"))
  ;; Calendar N days and weeks.
  (should-not (routine-checklist-cadence-due-p
               '(:every 3 :unit days :boundary calendar)
               "2026-11-20T10:00:00-0600"
               "2026-11-22T23:00:00-0600"))
  (should (routine-checklist-cadence-due-p
           '(:every 3 :unit days :boundary calendar)
           "2026-11-20T22:00:00-0600"
           "2026-11-23T06:00:00-0600"))
  (should-not (routine-checklist-cadence-due-p
               '(:every 2 :unit weeks :boundary calendar)
               "2026-11-09T12:00:00-0600"
               "2026-11-22T12:00:00-0600"))
  (should (routine-checklist-cadence-due-p
           '(:every 2 :unit weeks :boundary calendar)
           "2026-11-08T23:00:00-0600"
           "2026-11-22T08:00:00-0600"))
  ;; Calendar months with end-of-month clamping (non-leap & leap years + year rollover).
  (should-not (routine-checklist-cadence-due-p
               '(:every 1 :unit months :boundary calendar)
               "2026-01-31T10:00:00-0600"
               "2026-02-27T18:00:00-0600"))
  (should (routine-checklist-cadence-due-p
           '(:every 1 :unit months :boundary calendar)
           "2026-01-31T10:00:00-0600"
           "2026-02-28T08:00:00-0600"))
  (should-not (routine-checklist-cadence-due-p
               '(:every 1 :unit months :boundary calendar)
               "2028-01-31T10:00:00-0600"
               "2028-02-28T23:00:00-0600"))
  (should (routine-checklist-cadence-due-p
           '(:every 1 :unit months :boundary calendar)
           "2028-01-31T10:00:00-0600"
           "2028-02-29T07:00:00-0600"))
  (should (routine-checklist-cadence-due-p
           '(:every 2 :unit months :boundary calendar)
           "2026-12-15T10:00:00-0600"
           "2027-02-15T08:00:00-0600"))
  ;; Calendar hours.
  (should-not (routine-checklist-cadence-due-p
               '(:every 4 :unit hours :boundary calendar)
               "2026-11-22T10:50:00-0600"
               "2026-11-22T13:10:00-0600"))
  (should (routine-checklist-cadence-due-p
           '(:every 4 :unit hours :boundary calendar)
           "2026-11-22T10:50:00-0600"
           "2026-11-22T14:05:00-0600"))
  ;; Elapsed hours and elapsed days.
  (should-not (routine-checklist-cadence-due-p
               '(:every 24 :unit hours :boundary elapsed)
               "2026-11-21T10:00:00-0600"
               "2026-11-22T09:59:59-0600"))
  (should (routine-checklist-cadence-due-p
           '(:every 24 :unit hours :boundary elapsed)
           "2026-11-21T10:00:00-0600"
           "2026-11-22T10:00:00-0600"))
  (should-not (routine-checklist-cadence-due-p
               '(:every 1 :unit days :boundary elapsed)
               "2026-11-22T23:00:00-0600"
               "2026-11-23T07:00:00-0600"))
  (should (routine-checklist-cadence-due-p
           '(:every 1 :unit days :boundary elapsed)
           "2026-11-22T07:00:00-0600"
           "2026-11-23T07:00:00-0600"))
  ;; Relative age formatting.
  (let ((now "2026-11-22T15:00:00-0600"))
    (should (equal "never" (routine-checklist-format-relative-age nil now)))
    (should (equal "today" (routine-checklist-format-relative-age
                            "2026-11-22T08:00:00-0600" now)))
    (should (equal "yesterday" (routine-checklist-format-relative-age
                                "2026-11-21T22:00:00-0600" now)))
    (should (equal "3d ago" (routine-checklist-format-relative-age
                             "2026-11-19T10:00:00-0600" now)))
    (should (equal "2w ago" (routine-checklist-format-relative-age
                             "2026-11-08T10:00:00-0600" now)))
    (should (equal "2mo ago" (routine-checklist-format-relative-age
                              "2026-09-20T10:00:00-0600" now)))
    (should (equal "5h ago" (routine-checklist-format-relative-age
                             "2026-11-22T10:00:00-0600" now
                             '(:every 6 :unit hours :boundary elapsed))))))

(ert-deftest routine-checklist-law-l3-only-checked-template-items-update-last-completed ()
  (routine-checklist-test--with-data-dir
   (let* ((old-ts "2026-11-10T09:00:00-0600")
          (check-ts "2026-11-22T10:30:00-0600")
          (item1 (routine-checklist-store-make-item "Vacuum" nil "it1" old-ts))
          (item2 (routine-checklist-store-make-item "Mop" nil "it2" old-ts))
          (item3 (routine-checklist-store-make-item "Windows" nil "it3" nil))
          (tpl (routine-checklist-store-make-template
                "Cleaning" "cleaning" 'carry-over 'dimmed
                (list item1 item2 item3))))
     (routine-checklist-store-save-template tpl)
     (let* ((run (routine-checklist-instantiate-run
                  tpl "Sunday" "2026-11-22T10:00:00-0600"))
            (buf (routine-checklist-open-run-buffer run)))
       (routine-checklist-store-save-run run)
       (with-current-buffer buf
         ;; Skip item 0, check item 1, leave item 2 pending, add & check ad-hoc item 3.
         (routine-checklist--goto-item 0)
         (routine-checklist-toggle-skip)
         (routine-checklist--goto-item 1)
         (routine-checklist-toggle-check check-ts)
         (routine-checklist--goto-item 2)
         (routine-checklist-add-ad-hoc-item "Buy sponges")
         (routine-checklist--goto-item 3)
         (routine-checklist-toggle-check check-ts)
         ;; Finish partially without touching skipped/pending items.
         (routine-checklist-finish t "2026-11-22T11:00:00-0600"))
       (let* ((reloaded (routine-checklist-store-load-template "cleaning"))
              (items (plist-get reloaded :items)))
         (should (= 3 (length items)))
         (should (equal old-ts (plist-get (nth 0 items) :last-completed)))
         (should (equal check-ts (plist-get (nth 1 items) :last-completed)))
         (should-not (plist-get (nth 2 items) :last-completed)))))))

(ert-deftest routine-checklist-law-l4-uncheck-timestamp-rollback-guard ()
  (routine-checklist-test--with-data-dir
   (let* ((prior "2026-11-10T09:00:00-0600")
          (ts-a "2026-11-22T10:00:00-0600")
          (ts-b "2026-11-22T12:00:00-0600")
          (item (routine-checklist-store-make-item "Run smoke test" nil "it1" prior))
          (tpl (routine-checklist-store-make-template
                "QA" "qa" 'concurrent 'dimmed (list item))))
     (routine-checklist-store-save-template tpl)
     ;; Single run check then uncheck restores prior timestamp.
     (let* ((run-a (routine-checklist-instantiate-run tpl "Run A" ts-a))
            (res1 (routine-checklist-apply-check run-a tpl 0 ts-a)))
       (should (equal ts-a (plist-get (car (plist-get (plist-get res1 :template) :items))
                                      :last-completed)))
       (let ((res2 (routine-checklist-apply-uncheck
                    (plist-get res1 :run) (plist-get res1 :template) 0)))
         (should (plist-get res2 :template-changed))
         (should (equal prior (plist-get (car (plist-get (plist-get res2 :template) :items))
                                         :last-completed)))))
     ;; Concurrent Run A checked -> Run B checked newer -> uncheck Run A preserves Run B.
     (let* ((run-a (routine-checklist-instantiate-run tpl "Run A" ts-a "run-a"))
            (run-b (routine-checklist-instantiate-run tpl "Run B" ts-b "run-b"))
            (res-a (routine-checklist-apply-check run-a tpl 0 ts-a))
            (tpl-after-a (plist-get res-a :template))
            (res-b (routine-checklist-apply-check run-b tpl-after-a 0 ts-b))
            (tpl-after-b (plist-get res-b :template))
            (uncheck-a (routine-checklist-apply-uncheck
                        (plist-get res-a :run) tpl-after-b 0)))
       (should-not (plist-get uncheck-a :template-changed))
       (should (equal ts-b
                      (plist-get (car (plist-get (plist-get uncheck-a :template) :items))
                                 :last-completed)))
       ;; Graceful rollback if template is nil or item was deleted from template.
       (let ((deleted-res (routine-checklist-apply-uncheck
                           (plist-get res-a :run) nil 0)))
         (should-not (plist-get deleted-res :template-changed))
         (should (eq 'pending (plist-get (car (plist-get (plist-get deleted-res :run) :items))
                                         :state))))))))

(ert-deftest routine-checklist-law-l5-immediate-atomic-persistence ()
  (routine-checklist-test--with-data-dir
   (let* ((t1 (routine-checklist-store-make-item "Step 1" nil "i1" nil))
          (t2 (routine-checklist-store-make-item "Step 2" nil "i2" nil))
          (t3 (routine-checklist-store-make-item
               "Step 3" '(:every 7 :unit days :boundary calendar)
               "i3" "2026-11-21T09:00:00-0600"))
          (tpl (routine-checklist-store-make-template
                "Morning" "morning" 'fresh-per-repetition 'hidden (list t1 t2 t3))))
     (routine-checklist-store-save-template tpl)
     (let* ((run (routine-checklist-instantiate-run
                  tpl "Initial" "2026-11-22T08:00:00-0600" "run-persist-1"))
            (buf (routine-checklist-open-run-buffer run)))
       (routine-checklist-store-save-run run)
       (with-current-buffer buf
         (routine-checklist--goto-item 0)
         (routine-checklist-toggle-check "2026-11-22T08:05:00-0600")
         (routine-checklist--goto-item 1)
         (routine-checklist-toggle-skip)
         (routine-checklist-add-ad-hoc-item "Extra stretch")
         (routine-checklist-edit-label "Sunday Morning")
         (routine-checklist-toggle-not-due))
       ;; Simulate closing buffer / restarting Emacs and verify zero temp files.
       (kill-buffer buf)
       (should (equal '("run-persist-1.eld")
                      (directory-files (routine-checklist-store-active-runs-dir)
                                       nil "\\`[^.]\\|^\\.[^.]")))
       (let* ((reloaded (routine-checklist-store-load-run "run-persist-1"))
              (items (plist-get reloaded :items)))
         (should (equal "Sunday Morning" (plist-get reloaded :label)))
         (should (eq t (plist-get reloaded :not-due-visible)))
         (should (eq nil (plist-get reloaded :org-scope)))
         (should (= 4 (length items)))
         (should (eq 'checked (plist-get (nth 0 items) :state)))
         (should (eq 'skipped (plist-get (nth 1 items) :state)))
         (should (equal "Extra stretch" (plist-get (nth 2 items) :title)))
         (should (plist-get (nth 2 items) :ad-hoc))
         (should (eq 'pending (plist-get (nth 3 items) :state)))
         ;; Reopening via open-run-buffer restores exact buffer representation.
         (let ((reopened (routine-checklist-open-run-buffer reloaded)))
           (with-current-buffer reopened
             (should (equal "Sunday Morning"
                            (plist-get routine-checklist--run :label)))
             (should (string-match-p "Extra stretch" (buffer-string))))))))))

(ert-deftest routine-checklist-law-l7-concurrent-runs-never-collide ()
  (routine-checklist-test--with-data-dir
   (let* ((item (routine-checklist-store-make-item "Verify auth" nil "it1" nil))
          (tpl (routine-checklist-store-make-template
                "QA Checklist" "qa-checklist" 'concurrent 'dimmed (list item))))
     (routine-checklist-store-save-template tpl)
     (let ((buf-a (routine-checklist-start
                   "qa-checklist" "Project A" "2026-11-22T09:00:00-0600"))
           (buf-b (routine-checklist-start
                   "qa-checklist" "Project B" "2026-11-22T09:05:00-0600")))
       (should-not (eq buf-a buf-b))
       (with-current-buffer buf-b
         (should (equal "Project B" (plist-get routine-checklist--run :label))))
       (with-current-buffer buf-a
         (routine-checklist--goto-item 0)
         (routine-checklist-toggle-check "2026-11-22T09:10:00-0600"))
       (let ((active (routine-checklist-store-list-active-runs "qa-checklist")))
         (should (= 2 (length active)))
         (should (equal '("Project B" "Project A")
                        (mapcar (lambda (r) (plist-get r :label)) active)))
         (should (eq 'pending (plist-get (car (plist-get (nth 0 active) :items)) :state)))
         (should (eq 'checked (plist-get (car (plist-get (nth 1 active) :items)) :state))))))
   ;; Single-run template offers resume vs fresh when an active run exists.
   (let* ((item (routine-checklist-store-make-item "Make bed" nil "it1" nil))
          (tpl (routine-checklist-store-make-template
                "Morning" "morning" 'carry-over 'dimmed (list item))))
     (routine-checklist-store-save-template tpl)
     (routine-checklist-start "morning" "Run 1" "2026-11-22T07:00:00-0600")
     (cl-letf (((symbol-function 'completing-read)
                (lambda (prompt &rest _args)
                  (if (string-prefix-p "Active run exists" prompt)
                      "Resume active run"
                    "Morning"))))
       (let ((resumed-buf (routine-checklist-start)))
         (with-current-buffer resumed-buf
           (should (equal "Run 1" (plist-get routine-checklist--run :label))))
         (should (= 1 (length (routine-checklist-store-list-active-runs "morning")))))))))

(ert-deftest routine-checklist-law-l8-in-place-not-due-visibility-and-early-check ()
  (routine-checklist-test--with-data-dir
   (let* ((now "2026-11-22T12:00:00-0600")
          (due-1 (routine-checklist-store-make-item "First due" nil "d1" nil))
          (not-due (routine-checklist-store-make-item
                    "Middle not due" '(:every 14 :unit days :boundary calendar)
                    "nd1" "2026-11-20T10:00:00-0600"))
          (due-2 (routine-checklist-store-make-item "Last due" nil "d2" nil))
          ;; Inherit global default ('hidden here) and stay in natural order.
          (tpl (routine-checklist-store-make-template
                "In Place" "in-place" 'carry-over nil (list due-1 not-due due-2)))
          (routine-checklist-default-not-due-visibility 'hidden))
     (routine-checklist-store-save-template tpl)
     (let ((buf (routine-checklist-start "in-place" nil now)))
       (with-current-buffer buf
         (should-not (plist-get routine-checklist--run :not-due-visible))
         ;; Middle item keeps natural order (index 1) and has invisible overlay.
         (should (equal '("First due" "Middle not due" "Last due")
                        (mapcar (lambda (i) (plist-get i :title))
                                (plist-get routine-checklist--run :items))))
         (should (= 1 (length routine-checklist--not-due-overlays)))
         (routine-checklist--goto-item 1)
         (should (eq 'routine-checklist-not-due
                     (get-char-property (point) 'invisible)))
         ;; Toggle visibility with `h': removes overlay, order untouched.
         (routine-checklist-toggle-not-due)
         (should (plist-get routine-checklist--run :not-due-visible))
         (should (null routine-checklist--not-due-overlays))
         (routine-checklist--goto-item 1)
         (should-not (get-char-property (point) 'invisible))
         ;; Early check of not-due item works and preserves item order & neighbors.
         (routine-checklist-toggle-check "2026-11-22T12:05:00-0600")
         (let ((items (plist-get routine-checklist--run :items)))
           (should (equal '("First due" "Middle not due" "Last due")
                          (mapcar (lambda (i) (plist-get i :title)) items)))
           (should (eq 'pending (plist-get (nth 0 items) :state)))
           (should (eq 'checked (plist-get (nth 1 items) :state)))
           (should (eq 'pending (plist-get (nth 2 items) :state)))
           ;; Even toggling `h' back keeps early-checked not-due item visible.
           (routine-checklist-toggle-not-due)
           (should (null routine-checklist--not-due-overlays))))))))

(ert-deftest routine-checklist-slice-03-finish-complete-and-partial ()
  (routine-checklist-test--with-data-dir
   (let* ((it1 (routine-checklist-store-make-item "Step A" nil "a1" nil))
          (it2 (routine-checklist-store-make-item "Step B" nil "a2" "2026-11-01T10:00:00-0600"))
          (tpl (routine-checklist-store-make-template
                "Deploy" "deploy" 'concurrent 'dimmed (list it1 it2))))
     (routine-checklist-store-save-template tpl)
     ;; Partial finish: prompts when due items remain pending.
     (let ((buf1 (routine-checklist-start "deploy" "Release 1" "2026-11-22T09:00:00-0600"))
           (prompted nil))
       (with-current-buffer buf1
         (routine-checklist--goto-item 0)
         (routine-checklist-toggle-check "2026-11-22T09:05:00-0600")
         (cl-letf (((symbol-function 'y-or-n-p)
                    (lambda (_p) (setq prompted t) nil)))
           (should-error (routine-checklist-finish) :type 'user-error))
         (should prompted)
         (cl-letf (((symbol-function 'y-or-n-p) (lambda (_p) t)))
           (let ((archive-path (routine-checklist-finish nil "2026-11-22T09:10:00-0600")))
             (should (file-exists-p archive-path))
             (should (string-match-p "/runs/archive/2026/" archive-path))
             (should (eq 'archived-incomplete
                         (plist-get routine-checklist--run :status)))))))
     ;; Unchecked Step B keeps its older last-completed timestamp.
     (let* ((reloaded-tpl (routine-checklist-store-load-template "deploy"))
            (tpl-it2 (nth 1 (plist-get reloaded-tpl :items))))
       (should (equal "2026-11-01T10:00:00-0600"
                      (plist-get tpl-it2 :last-completed))))
     ;; Full finish: all due items checked -> archived-complete without prompt.
     (let ((buf2 (routine-checklist-start "deploy" "Release 2" "2026-11-22T10:00:00-0600")))
       (with-current-buffer buf2
         (routine-checklist--goto-item 0)
         (routine-checklist-toggle-check "2026-11-22T10:05:00-0600")
         (routine-checklist--goto-item 1)
         (routine-checklist-toggle-check "2026-11-22T10:06:00-0600")
         (cl-letf (((symbol-function 'y-or-n-p)
                    (lambda (&rest _) (error "Unexpected prompt"))))
           (routine-checklist-finish nil "2026-11-22T10:10:00-0600"))
         (should (eq 'archived-complete
                     (plist-get routine-checklist--run :status)))))
     ;; Active list is empty; archive lists newest first.
     (should-not (routine-checklist-store-list-active-runs))
     (let ((archived (routine-checklist-store-list-archived-runs)))
       (should (= 2 (length archived)))
       (should (equal '("Release 2" "Release 1")
                      (mapcar (lambda (r) (plist-get r :label)) archived)))))))

(ert-deftest routine-checklist-law-l6-archive-immutability-and-hot-path-isolation ()
  (routine-checklist-test--with-data-dir
   (let* ((it1 (routine-checklist-store-make-item "Original Item Title" nil "orig1" nil))
          (it2 (routine-checklist-store-make-item
                "Not Due Item" '(:every 10 :unit days :boundary calendar)
                "orig2" "2026-11-20T10:00:00-0600"))
          (tpl (routine-checklist-store-make-template
                "Original Template" "orig-tpl" 'carry-over 'dimmed (list it1 it2))))
     (routine-checklist-store-save-template tpl)
     (let ((buf (routine-checklist-start "orig-tpl" "Snapshot Run" "2026-11-22T09:00:00-0600")))
       (with-current-buffer buf
         (routine-checklist--goto-item 0)
         (routine-checklist-toggle-check "2026-11-22T09:05:00-0600")
         (routine-checklist-finish t "2026-11-22T09:10:00-0600"))
       ;; Now edit the template title + item title, save, then delete the template.
       (let ((tbuf (routine-checklist-template-open
                    (routine-checklist-store-load-template "orig-tpl") t)))
         (with-current-buffer tbuf
           (routine-checklist-template-rename "Mutated Template")
           (routine-checklist-template--goto-item 0)
           (routine-checklist-template-edit-item-title "Mutated Item Title")
           (routine-checklist-template-save)))
       (routine-checklist-delete-template "orig-tpl" t)
       ;; Hot-path active listing returns nil; active picker errors cleanly.
       (should-not (routine-checklist-store-list-active-runs))
       (should-error (routine-checklist-open) :type 'user-error)
       ;; Reopen from archive read-only; frozen titles intact and mutations blocked.
       (kill-buffer buf)
       (cl-letf (((symbol-function 'completing-read)
                  (lambda (_p coll &rest _args)
                    (car (all-completions "" coll)))))
         (let ((arch-buf (routine-checklist-open-archive)))
           (with-current-buffer arch-buf
             (should (string-match-p "Original Template" (buffer-string)))
             (should (string-match-p "Original Item Title" (buffer-string)))
             (should (string-match-p "ARCHIVED" (buffer-string)))
             (routine-checklist--goto-item 0)
             (should-error (routine-checklist-toggle-check) :type 'user-error)
             (should-error (routine-checklist-toggle-skip) :type 'user-error)
             (should-error (routine-checklist-add-ad-hoc-item "Nope") :type 'user-error)
             (should-error (routine-checklist-edit-label "Nope") :type 'user-error)
             (should-error (routine-checklist-finish) :type 'user-error)
             ;; `h' remains usable in archived view without altering archived disk file.
             (let ((before (copy-tree (car (routine-checklist-store-list-archived-runs)))))
               (routine-checklist-toggle-not-due)
               (should (equal before
                              (car (routine-checklist-store-list-archived-runs))))))))))))

(ert-deftest routine-checklist-phase-1-end-to-end-lifecycle ()
  (routine-checklist-test--with-data-dir
   ;; 1. Create template via routine-checklist-manage-templates and save.
   (cl-letf (((symbol-function 'completing-read)
              (lambda (&rest _) "+ Create new template"))
             ((symbol-function 'read-string)
              (lambda (&rest _) "Workday Kickoff")))
     (let ((tbuf (routine-checklist-manage-templates)))
       (with-current-buffer tbuf
         (routine-checklist-template-add-item "Review calendar")
         (routine-checklist-template-add-item "Check inbox")
         (routine-checklist-template-set-run-policy 'fresh-per-repetition)
         (routine-checklist-template-save))))
   ;; 2. Start run, check first item, add ad-hoc item, kill buffer.
   (let ((run-buf (routine-checklist-start
                   "workday-kickoff" "Monday" "2026-11-22T08:00:00-0600")))
     (with-current-buffer run-buf
       (routine-checklist--goto-item 0)
       (routine-checklist-toggle-check "2026-11-22T08:02:00-0600")
       (routine-checklist-add-ad-hoc-item "Prep standup notes"))
     (kill-buffer run-buf))
   ;; 3. Reopen via routine-checklist-open, check remaining items, finish.
   (cl-letf (((symbol-function 'completing-read)
              (lambda (_p coll &rest _args)
                (car (all-completions "" coll)))))
     (let ((reopened (routine-checklist-open)))
       (with-current-buffer reopened
         (should (= 3 (length (plist-get routine-checklist--run :items))))
         (routine-checklist--goto-item 1)
         (routine-checklist-toggle-check "2026-11-22T08:05:00-0600")
         (routine-checklist--goto-item 2)
         (routine-checklist-toggle-check "2026-11-22T08:06:00-0600")
         (routine-checklist-finish nil "2026-11-22T08:10:00-0600")
         (should (eq 'archived-complete
                     (plist-get routine-checklist--run :status))))
       (kill-buffer reopened)))
   ;; 4. Browse archived run read-only.
   (should-not (routine-checklist-store-list-active-runs))
   (cl-letf (((symbol-function 'completing-read)
              (lambda (_p coll &rest _args)
                (car (all-completions "" coll)))))
     (let ((arch (routine-checklist-open-archive)))
       (with-current-buffer arch
         (should (derived-mode-p 'routine-checklist-mode))
         (should (eq 'archived-complete
                     (plist-get routine-checklist--run :status))))))))

(provide 'routine-checklist-test)
;;; routine-checklist-test.el ends here
