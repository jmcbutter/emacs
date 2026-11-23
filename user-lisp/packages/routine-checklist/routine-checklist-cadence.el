;;; routine-checklist-cadence.el --- Pure cadence and run domain logic -*- lexical-binding: t -*-

;;; Commentary:

;; Pure domain logic for `routine-checklist': ISO-8601 timestamp
;; parsing/formatting, calendar and elapsed cadence due evaluation,
;; relative age labels, run instantiation, item state transitions
;; (check/uncheck/skip/ad-hoc), Law L-4 rollback guard, progress
;; summaries, and run completion.  Performs zero disk I/O and zero
;; buffer manipulation.

;;; Code:

(eval-and-compile
  (add-to-list
   'load-path
   (file-name-directory
    (or load-file-name
        (and (boundp 'byte-compile-current-file)
             byte-compile-current-file)
        buffer-file-name))))

(require 'calendar)
(require 'cl-lib)
(require 'parse-time)
(require 'seq)
(require 'subr-x)
(require 'routine-checklist-store)

(defvar routine-checklist-default-not-due-visibility 'dimmed
  "Default visibility for not-due items when a template does not specify one.")

(defun routine-checklist-time-format (&optional time)
  "Format TIME (default current time) as ISO-8601 local with offset."
  (format-time-string "%Y-%m-%dT%H:%M:%S%z" time))

(defun routine-checklist-time-parse (timestamp)
  "Parse ISO-8601 TIMESTAMP string into an Emacs time value.
Returns nil for nil, and passes through non-string Emacs time values."
  (cond
   ((null timestamp) nil)
   ((stringp timestamp)
    (or (parse-iso8601-time-string timestamp)
        (error "Invalid ISO-8601 timestamp: %S" timestamp)))
   (t timestamp)))

(defun routine-checklist--local-hour-index (time)
  "Return a monotonic local hour index for TIME."
  (+ (* (time-to-days time) 24)
     (decoded-time-hour (decode-time time))))

(defun routine-checklist--calendar-month-due-days (last-time months)
  "Return absolute calendar day when LAST-TIME plus MONTHS is due.
Clamps the day-of-month to the target month's last calendar day."
  (let* ((decoded (decode-time last-time))
         (year (decoded-time-year decoded))
         (month (decoded-time-month decoded))
         (day (decoded-time-day decoded))
         (total-months (+ (* year 12) (1- month) months))
         (due-year (/ total-months 12))
         (due-month (1+ (% total-months 12)))
         (max-day (calendar-last-day-of-month due-month due-year))
         (due-day (min day max-day)))
    (calendar-absolute-from-gregorian (list due-month due-day due-year))))

(defun routine-checklist-cadence-due-p (cadence last-completed &optional now)
  "Return non-nil if an item with CADENCE and LAST-COMPLETED is due at NOW.
An item with nil CADENCE or nil LAST-COMPLETED is always due."
  (if (or (null cadence) (null last-completed))
      t
    (routine-checklist-store--validate-cadence cadence)
    (let* ((last-time (routine-checklist-time-parse last-completed))
           (now-time (if now
                         (routine-checklist-time-parse now)
                       (current-time)))
           (every (plist-get cadence :every))
           (unit (plist-get cadence :unit))
           (boundary (plist-get cadence :boundary)))
      (pcase boundary
        ('calendar
         (pcase unit
           ('hours
            (>= (- (routine-checklist--local-hour-index now-time)
                   (routine-checklist--local-hour-index last-time))
                every))
           ('days
            (>= (- (time-to-days now-time) (time-to-days last-time))
                every))
           ('weeks
            (>= (- (time-to-days now-time) (time-to-days last-time))
                (* 7 every)))
           ('months
            (>= (time-to-days now-time)
                (routine-checklist--calendar-month-due-days last-time every)))))
        ('elapsed
         (let ((duration-sec
                (pcase unit
                  ('hours (* every 3600.0))
                  ('days (* every 86400.0))
                  ('weeks (* every 7 86400.0))
                  ('months (* every 30 86400.0)))))
           (>= (- (float-time now-time) (float-time last-time))
               duration-sec)))))))

(defun routine-checklist-format-relative-age
    (last-completed &optional now cadence)
  "Format LAST-COMPLETED relative to NOW (default current time).
When CADENCE uses elapsed hours and the elapsed delta is under 48 hours,
format as hours (`<1h ago' or `Nh ago')."
  (if (null last-completed)
      "never"
    (let* ((last-time (routine-checklist-time-parse last-completed))
           (now-time (if now
                         (routine-checklist-time-parse now)
                       (current-time)))
           (elapsed-sec (- (float-time now-time) (float-time last-time))))
      (if (and cadence
               (eq (plist-get cadence :unit) 'hours)
               (eq (plist-get cadence :boundary) 'elapsed)
               (>= elapsed-sec 0.0)
               (< elapsed-sec (* 48 3600.0)))
          (if (< elapsed-sec 3600.0)
              "<1h ago"
            (format "%dh ago" (floor (/ elapsed-sec 3600.0))))
        (let ((day-diff (- (time-to-days now-time) (time-to-days last-time))))
          (cond
           ((<= day-diff 0) "today")
           ((= day-diff 1) "yesterday")
           ((< day-diff 7) (format "%dd ago" day-diff))
           ((< day-diff 30) (format "%dw ago" (/ day-diff 7)))
           (t (format "%dmo ago" (/ day-diff 30)))))))))

(defun routine-checklist-effective-not-due-visibility (template)
  "Return the effective default not-due visibility symbol for TEMPLATE."
  (or (plist-get template :default-not-due-visibility)
      routine-checklist-default-not-due-visibility
      'dimmed))

(defun routine-checklist-instantiate-run (template &optional label now run-id)
  "Create a new active run plist from TEMPLATE at NOW with optional LABEL.
Optional RUN-ID overrides the generated run identifier."
  (let* ((now-time (if now
                       (routine-checklist-time-parse now)
                     (current-time)))
         (now-str (routine-checklist-time-format now-time))
         (tpl-id (plist-get template :id))
         (tpl-name (plist-get template :name))
         (trimmed-label (when (stringp label)
                          (let ((s (string-trim label)))
                            (unless (string-empty-p s) s))))
         (id (or run-id
                 (routine-checklist-store-generate-run-id tpl-id now-time)))
         (not-due-vis (routine-checklist-effective-not-due-visibility template))
         (run-items
          (mapcar
           (lambda (titem)
             (let* ((last-done (plist-get titem :last-completed))
                    (due-p (routine-checklist-cadence-due-p
                            (plist-get titem :cadence)
                            last-done
                            now-time)))
               (list :template-item-id (plist-get titem :id)
                     :title (plist-get titem :title)
                     :ad-hoc nil
                     :due-at-start (and due-p t)
                     :state 'pending
                     :last-completed-before-run last-done
                     :completed-at nil)))
           (plist-get template :items))))
    (list :schema-version routine-checklist-store-schema-version
          :id id
          :template-id tpl-id
          :template-name tpl-name
          :label trimmed-label
          :status 'active
          :started-at now-str
          :closed-at nil
          :not-due-visible (not (eq not-due-vis 'hidden))
          :org-scope nil
          :items run-items)))

(defun routine-checklist--update-run-item (run idx fn)
  "Return a copy of RUN with item at IDX transformed by FN."
  (let* ((items (copy-sequence (plist-get run :items)))
         (len (length items)))
    (unless (and (integerp idx) (>= idx 0) (< idx len))
      (error "Run item index out of range: %S" idx))
    (setf (nth idx items) (funcall fn (nth idx items)))
    (routine-checklist-store--plist-put run :items items)))

(defun routine-checklist--update-template-item (template item-id fn)
  "If TEMPLATE has an item with ITEM-ID, transform it via FN.
Return (UPDATED-TEMPLATE . CHANGED-P)."
  (if (or (null template) (null item-id))
      (cons template nil)
    (let ((items (copy-sequence (plist-get template :items)))
          (found nil)
          (changed nil))
      (setq items
            (mapcar
             (lambda (titem)
               (if (and (not found) (equal (plist-get titem :id) item-id))
                   (progn
                     (setq found t)
                     (let ((updated (funcall fn titem)))
                       (unless (equal updated titem)
                         (setq changed t))
                       updated))
                 titem))
             items))
      (if changed
          (cons (routine-checklist-store--plist-put template :items items) t)
        (cons template nil)))))

(defun routine-checklist-apply-check (run template idx &optional now)
  "Check item at IDX in RUN and update TEMPLATE `:last-completed' at NOW.
Returns a plist (:run RUN :template TEMPLATE :template-changed BOOL)."
  (let* ((now-str (routine-checklist-time-format
                   (when now (routine-checklist-time-parse now))))
         (item (nth idx (plist-get run :items)))
         (new-run (routine-checklist--update-run-item
                   run idx
                   (lambda (it)
                     (let ((u (routine-checklist-store--plist-put
                               it :state 'checked)))
                       (routine-checklist-store--plist-put
                        u :completed-at now-str)))))
         (tpl-res
          (if (and (not (plist-get item :ad-hoc))
                   (plist-get item :template-item-id))
              (routine-checklist--update-template-item
               template
               (plist-get item :template-item-id)
               (lambda (titem)
                 (routine-checklist-store--plist-put
                  titem :last-completed now-str)))
            (cons template nil))))
    (list :run new-run
          :template (car tpl-res)
          :template-changed (cdr tpl-res))))

(defun routine-checklist-apply-uncheck (run template idx)
  "Uncheck item at IDX in RUN, enforcing the Law L-4 rollback guard.
Reverts TemplateItem `:last-completed' to `:last-completed-before-run'
only if TemplateItem `:last-completed' still equals RunItem `:completed-at'.
Returns a plist (:run RUN :template TEMPLATE :template-changed BOOL)."
  (let* ((item (nth idx (plist-get run :items)))
         (prev-completed-at (plist-get item :completed-at))
         (before-run (plist-get item :last-completed-before-run))
         (new-run (routine-checklist--update-run-item
                   run idx
                   (lambda (it)
                     (let ((u (routine-checklist-store--plist-put
                               it :state 'pending)))
                       (routine-checklist-store--plist-put
                        u :completed-at nil)))))
         (tpl-res
          (if (and (not (plist-get item :ad-hoc))
                   (plist-get item :template-item-id)
                   prev-completed-at)
              (routine-checklist--update-template-item
               template
               (plist-get item :template-item-id)
               (lambda (titem)
                 (if (equal (plist-get titem :last-completed) prev-completed-at)
                     (routine-checklist-store--plist-put
                      titem :last-completed before-run)
                   titem)))
            (cons template nil))))
    (list :run new-run
          :template (car tpl-res)
          :template-changed (cdr tpl-res))))

(defun routine-checklist-apply-skip (run template idx)
  "Toggle skipped state on item at IDX in RUN without recording completion.
If the item was checked, rolls back its completion timestamp first via
`routine-checklist-apply-uncheck'.  Returns (:run :template :template-changed)."
  (let* ((item (nth idx (plist-get run :items)))
         (state (plist-get item :state)))
    (if (eq state 'checked)
        (let* ((uncheck-res (routine-checklist-apply-uncheck run template idx))
               (skipped-run (routine-checklist--update-run-item
                             (plist-get uncheck-res :run) idx
                             (lambda (it)
                               (routine-checklist-store--plist-put
                                it :state 'skipped)))))
          (list :run skipped-run
                :template (plist-get uncheck-res :template)
                :template-changed (plist-get uncheck-res :template-changed)))
      (let* ((next-state (if (eq state 'skipped) 'pending 'skipped))
             (new-run (routine-checklist--update-run-item
                       run idx
                       (lambda (it)
                         (let ((u (routine-checklist-store--plist-put
                                   it :state next-state)))
                           (routine-checklist-store--plist-put
                            u :completed-at nil))))))
        (list :run new-run
              :template template
              :template-changed nil)))))

(defun routine-checklist-add-ad-hoc (run title &optional after-index)
  "Add a run-only ad-hoc item with TITLE to RUN after AFTER-INDEX or at end."
  (let ((trimmed (string-trim (or title ""))))
    (when (string-empty-p trimmed)
      (user-error "Item title must not be empty"))
    (let* ((items (copy-sequence (plist-get run :items)))
           (insert-pos (if after-index
                           (min (length items) (1+ after-index))
                         (length items)))
           (ad-hoc-item (list :template-item-id nil
                              :title trimmed
                              :ad-hoc t
                              :due-at-start t
                              :state 'pending
                              :last-completed-before-run nil
                              :completed-at nil))
           (new-items (append (seq-take items insert-pos)
                              (list ad-hoc-item)
                              (nthcdr insert-pos items))))
      (routine-checklist-store--plist-put run :items new-items))))

(defun routine-checklist-set-run-label (run label)
  "Return a copy of RUN with `:label' set to trimmed LABEL (or nil if empty)."
  (let ((trimmed (when (stringp label)
                   (let ((s (string-trim label)))
                     (unless (string-empty-p s) s)))))
    (routine-checklist-store--plist-put run :label trimmed)))

(defun routine-checklist-toggle-not-due-visible (run)
  "Return a copy of RUN with `:not-due-visible' toggled."
  (routine-checklist-store--plist-put
   run :not-due-visible (not (plist-get run :not-due-visible))))

(defun routine-checklist-progress-summary (run)
  "Return a progress summary plist for RUN."
  (let ((checked 0)
        (due 0)
        (due-checked 0)
        (remaining 0)
        (skipped 0)
        (not-due 0)
        (total 0))
    (dolist (item (plist-get run :items))
      (let ((state (plist-get item :state))
            (due-p (plist-get item :due-at-start)))
        (cl-incf total)
        (when (eq state 'checked)
          (cl-incf checked))
        (when (eq state 'skipped)
          (cl-incf skipped))
        (if due-p
            (progn
              (cl-incf due)
              (cond
               ((eq state 'checked) (cl-incf due-checked))
               ((eq state 'pending) (cl-incf remaining))))
          (cl-incf not-due))))
    (list :checked checked
          :due due
          :due-checked due-checked
          :remaining remaining
          :skipped skipped
          :not-due not-due
          :total total)))

(defun routine-checklist-finish-run (run &optional now)
  "Transition RUN to archived status at NOW without modifying any template.
Sets `:status' to `archived-complete' if all due items are `checked',
otherwise `archived-incomplete'."
  (let* ((now-str (routine-checklist-time-format
                   (when now (routine-checklist-time-parse now))))
         (all-due-checked
          (cl-every
           (lambda (item)
             (or (not (plist-get item :due-at-start))
                 (eq (plist-get item :state) 'checked)))
           (plist-get run :items)))
         (status (if all-due-checked
                     'archived-complete
                   'archived-incomplete))
         (updated (routine-checklist-store--plist-put run :status status)))
    (routine-checklist-store--plist-put updated :closed-at now-str)))

(provide 'routine-checklist-cadence)
;;; routine-checklist-cadence.el ends here
