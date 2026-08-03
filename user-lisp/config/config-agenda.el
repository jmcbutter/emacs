;;; config-agenda.el --- Org Mode Agenda Configuration -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(require 'org)
(require 'org-protocol)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Global Variables
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defvar JMB/ORG-DIRECTORY (expand-file-name "Agenda" "~/Dropbox/"))
(defvar JMB/ORG-AGENDA-FILE (expand-file-name "agenda.org" JMB/ORG-DIRECTORY))
(defvar JMB/ORG-CALENDAR-FILE (expand-file-name "calendar.org" JMB/ORG-DIRECTORY))
(defvar JMB/ORG-JOURNAL-FILE (expand-file-name "journal.org" JMB/ORG-DIRECTORY))
(defvar JMB/ORG-MEETINGS-FILE (expand-file-name "meetings.org" JMB/ORG-DIRECTORY))
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Org Configuration
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(with-eval-after-load 'org
  (setq-default org-directory JMB/ORG-DIRECTORY
        org-stuck-projects '("+PROJECT" ("TODO") nil nil)
        org-use-fast-todo-selection t
        org-enforce-todo-dependencies t
        org-agenda-files `(,JMB/ORG-DIRECTORY)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Org Capture
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(with-eval-after-load 'org
  (setq-default org-capture-templates
                '(("a" "Appointment" entry
                   (file+olp JMB/ORG-CALENDAR-FILE "CALENDAR")
                   "* %? %^T")
                  ("c" "Clocked In Task" item
                   (clock)
                   "- %?"
                   :clock-keep t
                   :unnarrowed t)
                  ("j" "Journal" entry
                   (file+datetree JMB/ORG-JOURNAL-FILE)
                   "* %?" :tree-type (year quarter month week day))
                  ("m" "Meeting" entry
                   (file+datetree JMB/ORG-MEETINGS-FILE)
                   "* %?" :tree-type (year quarter month week day))
                  ("t" "Task" entry
                   (file+olp JMB/ORG-AGENDA-FILE "INBOX")
                   "* TODO %?")
                  ("w"
                   "Website"
                   entry
                   (file ,(concat JMB/ORG-DIRECTORY "Lists/websites.org"))
                   "* %:annotation "
                   :prepend t))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Org Agenda
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(with-eval-after-load 'org
  (setq-default org-agenda-show-future-repeats nil
                org-agenda-compact-blocks t
                org-agenda-block-separator ?-
                org-priority-highest ?A
                org-priority-lowest ?E
                org-priority-default ?D
                org-habit-graph-column 120
                org-agenda-show-all-dates t
                org-agenda-skip-deadline-if-done t
                org-agenda-skip-scheduled-if-done t
                org-agenda-skip-deadline-prewarning-if-scheduled nil
                org-agenda-skip-scheduled-if-deadline-is-shown t
                org-agenda-skip-scheduled-repeats-after-deadline t
                org-agenda-persistent-marks t
                org-agenda-prefer-last-repeat t
                org-todo-repeat-to-state t
                org-agenda-todo-ignore-deadlines nil
                org-agenda-todo-ignore-scheduled 'future
                org-agenda-todo-ignore-timestamp nil
                org-agenda-deadline-leaders '("DUE: " "DUE IN %d DAYS: " "OVERDUE BY %d DAYS: ")
                org-agenda-scheduled-leaders '("TODAY: " "TODAY: ")
                org-agenda-fontify-priorities t
                org-agenda-restore-windows-after-quit t
                org-agenda-window-setup 'current-window
                org-agenda-dim-blocked-tasks t
                org-agenda-prefix-format '((agenda . " %i %-20:c%?-12t% s") (todo . " %i %-20:c")
                                           (tags . " %i %-20:c") (search . " %i %-20:c"))
                org-agenda-sorting-strategy '((agenda
                                               time-up
                                               priority-down
                                               deadline-down
                                               scheduled-down
                                               urgency-down
                                               habit-down
                                               category-keep)
                                              (todo
                                               urgency-down
                                               category-keep)
                                              (tags
                                               urgency-down
                                               category-keep)
                                              (search
                                               category-keep))))

;;; Org Agenda Custom Commands
(defcustom jmb/org-agenda-base-agenda
  '(agenda "" ((org-agenda-skip-function '(org-agenda-skip-entry-if 'todo '("WAIT" "HOLD")))
                (org-agenda-span 1)))
  "The base agenda layout")


(defun jmb/build-org-agenda-base-todo (tag-todo-str header)
  `(tags-todo ,tag-todo-str
              ((org-agenda-overriding-header ,header))))



(with-eval-after-load 'org
  (setq-default org-agenda-custom-commands
                '(("a" "All"
                   ((agenda "" ((org-agenda-skip-function '(org-agenda-skip-entry-if 'todo '("WAIT" "HOLD"))))
                            (org-agenda-span 1))
                    (tags-todo "+INBOX"
                               ((org-agenda-overriding-header "--- Inbox ---")))
                    (tags-todo "+WAIT"
                               ((org-agenda-overriding-header "--- Wait ---")))
                    (tags-todo "+TODAY-PAUSE"
                               ((org-agenda-overriding-header "--- Today ---")))
                    (tags-todo "+THIS_WEEK-TODAY-PAUSE"
                               ((org-agenda-overriding-header "--- This Week ---")))
                    (tags-todo "+THIS_MONTH-THIS_WEEK-PAUSE"
                               ((org-agenda-overriding-header "--- This Month ---")))
                    (tags-todo "+THIS_QUARTER-THIS_MONTH-PAUSE"
                               ((org-agenda-overriding-header "--- This Quarter ---")))
                    (tags-todo "+THIS_YEAR-THIS_QUARTER-PAUSE"
                               ((org-agenda-overriding-header "--- This Year ---")))
                    (tags-todo "-THIS_YEAR-INBOX-PAUSE"
                               ((org-agenda-overriding-header "--- Sometime ---")))
                    (tags-todo "+HOLD"
                               ((org-agenda-overriding-header "--- On Hold ---"))))
                   ((org-agenda-span 1))))))






;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Find Files
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun jmb/find-org-file ()
  (interactive)
  (find-file (read-file-name "Find Org File: " (concat JMB/ORG-DIRECTORY "/"))))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Keymap
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defvar jmb/org-global-prefix-map (make-sparse-keymap)
  "A keymap for handy global access to org helpers, particularly clocking.")
(define-key jmb/org-global-prefix-map (kbd "a") 'org-agenda)
(define-key jmb/org-global-prefix-map (kbd "c") 'org-capture)
(define-key jmb/org-global-prefix-map (kbd "f") 'jmb/find-org-file)
(define-key jmb/org-global-prefix-map (kbd "i") 'org-clock-in)
(define-key jmb/org-global-prefix-map (kbd "j") 'org-clock-goto)
(define-key jmb/org-global-prefix-map (kbd "l") 'org-store-link)
(define-key jmb/org-global-prefix-map (kbd "o") 'org-clock-out)
(define-key jmb/org-global-prefix-map (kbd "p") 'org-clock-in-last)

(define-key global-map (kbd "C-c o") jmb/org-global-prefix-map)


(provide 'config-agenda)
;;; config-agenda.el ends here
