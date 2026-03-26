;;; init-org.el --- Org Mode Configuration -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(require 'org)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Global Variables
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq JMB/ORG-DIRECTORY (expand-file-name "Org/" "~/Dropbox/"))
(setq JMB/ORG-ADMIN-DIRECTORY (expand-file-name "Admin/" JMB/ORG-DIRECTORY))
(setq JMB/ORG-AREAS-DIRECTORY (expand-file-name "Areas/" JMB/ORG-DIRECTORY))
(setq JMB/ORG-CLIENT-DIRECTORY (expand-file-name "Clients/" JMB/ORG-DIRECTORY))
(setq JMB/ORG-PROJECT-DIRECTORY (expand-file-name "Projects/" JMB/ORG-DIRECTORY))
(setq JMB/ORG-SKILLS-DIRECTORY (expand-file-name "Skills/" JMB/ORG-DIRECTORY))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Org Configuration
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq org-directory JMB/ORG-DIRECTORY
      org-agenda-files
      (append
       (file-expand-wildcards (concat JMB/ORG-DIRECTORY "/**/**/index.org") t)
       (file-expand-wildcards (concat JMB/ORG-DIRECTORY "/Admin/*.org") t))
      org-stuck-projects '("+PROJECT" ("TODO") nil nil)
      org-use-fast-todo-selection t
      org-enforce-todo-dependencies t
      org-tag-alist
      '(("WAITING" . ?w)
        ("MAYBE" . ?m)
        ("PROJECT" . ?j)
        (:startgrouptag)
        ("@context")
        (:grouptags)
        ("@home" . ?h)
        ("@errand" . ?e)
        ("@computer" . ?c)
        ("@backpack" . ?b)
        ("@phone" . ?p)
        (:endgroup)
        (:endgroup)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Org Capture
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun jmb/find-org-file-for-capture ()
  (interactive)
  (let* ((org-filetype (completing-read "File Type: " '("admin" "area" "client" "project" "skill")))
         (directory
          (cond ((string= org-filetype "admin") JMB/ORG-ADMIN-DIRECTORY)
                ((string= org-filetype "area") JMB/ORG-AREAS-DIRECTORY)
                ((string= org-filetype "client") JMB/ORG-CLIENT-DIRECTORY)
                ((string= org-filetype "project") JMB/ORG-PROJECT-DIRECTORY)
                ((string= org-filetype "skill") JMB/ORG-SKILLS-DIRECTORY)))
         (filename
          (read-file-name "Find File: " directory)))
    (if (string= org-filetype "admin")
        (expand-file-name "" filename)
      (expand-file-name "index.org" filename))))

(setq jmb/org-appointment-capture-template
      '("a" "Appointment"
        entry
        (file+olp jmb/find-org-file-for-capture "Appointments")
        "*  %?  %^T"
        :prepend t))

(setq jmb/org-meeting-capture-template
      '("m" "Meeting"
        entry
        (file+olp+datetree jmb/find-org-file-for-capture "Logs")
        "* %? \n%^T"))

(setq jmb/org-note-capture-template
      '("n" "Note"
        entry
        (file+olp+datetree jmb/find-org-file-for-capture "Logs")
        "* %? \n%l"))

(setq jmb/org-todo-capture-template
      '("t"
        "Todo"
        entry
        (file+olp jmb/find-org-file-for-capture "Tasks")
        "* TODO %? "
        :prepend t))

(setq org-capture-templates (list jmb/org-todo-capture-template
                                  jmb/org-appointment-capture-template
                                  jmb/org-meeting-capture-template
                                  jmb/org-anniversary-capture-template
                                  jmb/org-question-capture-template
                                  jmb/org-log-capture-template
                                  jmb/org-test-capture-template)
      org-refile-targets '((nil . (:maxlevel . 1))
                           (nil . (:todo . "TODO"))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Org Agenda
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq org-agenda-show-future-repeats nil
      org-priority-highest ?A
      org-priority-lowest ?E
      org-priority-default ?D
      org-habit-graph-column 80
      org-agenda-show-all-dates t
      org-agenda-skip-deadline-if-done t
      org-agenda-skip-scheduled-if-done t
      org-agenda-skip-deadline-prewarning-if-scheduled nil
      org-agenda-skip-scheduled-if-deadline-is-shown 'not-today
      org-agenda-persistent-marks t
      org-agenda-prefer-last-repeat t
      org-agenda-todo-ignore-deadlines 'all
      org-agenda-todo-ignore-scheduled 'all
      org-agenda-todo-ignore-timestamp 'all
      org-agenda-deadline-leaders '("DUE: " "DUE IN %d DAYS: " "OVERDUE BY %d DAYS: ")
      org-agenda-scheduled-leaders '("TODAY: " "RESCHEDULE (-%d)")
      org-agenda-fontify-priorities t
      org-agenda-restore-windows-after-quit t
      org-agenda-window-setup 'current-window
      org-agenda-dim-blocked-tasks 'invisible
      org-agenda-prefix-format '((agenda . " %i %-20:c%?-12t% s") (todo . " %i %-20:c")
                                 (tags . " %i %-20:c") (search . " %i %-20:c"))
      org-agenda-sorting-strategy '((agenda
                                     time-up
                                     priority-up
                                     deadline-up
                                     scheduled-up
                                     urgency-up
                                     habit-down
                                     category-keep)
                                    (todo
                                     urgency-down
                                     category-keep)
                                    (tags
                                     urgency-down
                                     category-keep)
                                    (search
                                     category-keep)))

;;; Org Agenda Custom Commands
(setq jmb/org-agenda-custom-agenda-command
      '("a" "Agenda"
        ((agenda "" ((org-agenda-skip-function '(org-agenda-skip-entry-if 'regexp ":WAITING:"))))
         (tags-todo "+WAITING"))
        ((org-agenda-category-filter-preset '("-Cleaning"))
         (org-agenda-span 1))))

(setq jmb/org-agenda-custom-cleaning-command
      '("c" "Cleaning"
        ((agenda "" ((org-agenda-skip-function '(org-agenda-skip-entry-if 'regexp ":WAITING:"))))
         (tags-todo "+WAITING"))
        ((org-agenda-category-filter-preset '("+Cleaning"))
         (org-agenda-span 1))))

(setq jmb/org-agenda-custom-work-command
      '("w" "Work"
        ((agenda "" ((org-agenda-skip-function '(org-agenda-skip-entry-if 'regexp ":WAITING:"))))
         (tags-todo "+WAITING"))
        ((org-agenda-category-filter-preset '("+Clients" "+Business"))
         (org-agenda-span 1))))

(setq jmb/org-agenda-custom-personal-command
      '("p" "Personal"
      ((agenda "" ((org-agenda-skip-function '(org-agenda-skip-entry-if 'regexp ":WAITING:"))))
       (tags-todo "+WAITING"))
      ((org-agenda-category-filter-preset '("-Clients" "-Business" "-Cleaning"))
       (org-agenda-span 1))))

(setq org-agenda-custom-commands
      (list jmb/org-agenda-custom-agenda-command
            jmb/org-agenda-custom-cleaning-command
            jmb/org-agenda-custom-work-command
            jmb/org-agenda-custom-personal-command))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Org Styling
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(setq org-edit-src-content-indentation 4)

(with-eval-after-load 'org
  (let ((scale 1.025))
    (set-face-attribute 'org-level-1 nil :height (expt scale 8))
    (set-face-attribute 'org-level-2 nil :height (expt scale 7))
    (set-face-attribute 'org-level-3 nil :height (expt scale 6))
    (set-face-attribute 'org-level-4 nil :height (expt scale 5))
    (set-face-attribute 'org-level-5 nil :height (expt scale 4))
    (set-face-attribute 'org-level-6 nil :height (expt scale 3))
    (set-face-attribute 'org-level-7 nil :height (expt scale 2))
    (set-face-attribute 'org-level-8 nil :height (expt scale 1))))

(add-hook 'org-mode-hook #'org-indent-mode)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Find Files
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun jmb/find-org-file ()
  (interactive)
  (let* ((org-filetype (completing-read "File Type: " '("admin" "area" "client" "project" "skill")))
         (directory
          (cond ((string= org-filetype "admin") JMB/ORG-ADMIN-DIRECTORY)
                ((string= org-filetype "area") JMB/ORG-AREAS-DIRECTORY)
                ((string= org-filetype "client") JMB/ORG-CLIENT-DIRECTORY)
                ((string= org-filetype "project") JMB/ORG-PROJECT-DIRECTORY)
                ((string= org-filetype "skill") JMB/ORG-SKILLS-DIRECTORY)))
         (filename
          (read-file-name "Find File: " directory)))
    (if (string= org-filetype "admin")
        (find-file filename)
      (find-file (expand-file-name "index.org" filename)))))

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


(provide 'init-org)
;;; init-org.el ends here
