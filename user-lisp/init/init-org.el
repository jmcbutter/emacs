;;; init-org.el --- Org Mode Configuration -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(require 'org)
(require 'org-protocol)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Global Variables
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defvar JMB/ORG-DIRECTORY (expand-file-name "Org" "~/"))
(defvar JMB/ORG-AGENDA-FILE (expand-file-name "todos.org" JMB/ORG-DIRECTORY))
(defvar JMB/ORG-LOG-FILE (expand-file-name "logs.org" JMB/ORG-DIRECTORY))
(defvar JMB/ORG-LIST-FILE (expand-file-name "lists.org" JMB/ORG-DIRECTORY))
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Org Configuration
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(with-eval-after-load 'org
  (setq-default org-directory JMB/ORG-DIRECTORY
        org-stuck-projects '("+PROJECT" ("TODO") nil nil)
        org-use-fast-todo-selection t
        org-enforce-todo-dependencies t
        org-agenda-files (list JMB/ORG-AGENDA-FILE)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Org Capture
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(with-eval-after-load 'org
  (setq-default org-capture-templates
                '(("a" "Appointment" entry
		   (file+olp JMB/ORG-AGENDA-FILE "Inbox")
		   "* %? %^T")
                  ("c" "Clocked In Task" item
                   (clock)
                   "- %?"
                   :clock-keep t
                   :unnarrowed t)
		  ("t" "Todo" entry
		   (file+olp JMB/ORG-AGENDA-FILE "Inbox")
		   "* TODO %?")
		  ("l" "Log" entry
		   (file+olp JMB/ORG-LOG-FILE "Inbox")
		   "* %U %?")
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


(defun jmb/build-org-agenda-custom-command (keys name &optional tags-todo-str)
  (list keys name
        (list jmb/org-agenda-base-agenda
              (jmb/build-org-agenda-base-todo (concat "TODO=\"TODO\"+TODAY" tags-todo-str) "Today")
              (jmb/build-org-agenda-base-todo (concat "TODO=\"TODO\"+THIS_WEEK" tags-todo-str) "This Week")
              (jmb/build-org-agenda-base-todo (concat "TODO=\"TODO\"+THIS_MONTH" tags-todo-str) "This Month")
              (jmb/build-org-agenda-base-todo (concat "TODO=\"TODO\"+THIS_QUARTER" tags-todo-str) "This Quarter")
              (jmb/build-org-agenda-base-todo (concat "TODO=\"TODO\"+THIS_YEAR" tags-todo-str) "This Year")
              (jmb/build-org-agenda-base-todo (concat "TODO=\"TODO\"+SOMETIME" tags-todo-str) "Sometime")
              (jmb/build-org-agenda-base-todo (concat "TODO=\"WAIT\"" tags-todo-str) "Waiting")
              (jmb/build-org-agenda-base-todo (concat "TODO=\"HOLD\"" tags-todo-str) "On Hold"))
	  '((org-agenda-span 1))))


(defvar jmb/org-agenda-custom-agenda-command
  '("a" "Agenda"
    ((agenda "" ((org-agenda-skip-function '(org-agenda-skip-entry-if 'todo '("WAIT" "HOLD")))
                (org-agenda-span 1))))))

(defvar jmb/org-agenda-custom-cleaning-command
  `("c" "Cleaning"
    ((agenda "" ((org-agenda-skip-function '(org-agenda-skip-entry-if 'todo '("WAIT" "HOLD")))
                (org-agenda-span 1)))
     (tags-todo "CATEGORY=\"Kitchen\"" ((org-agenda-overriding-header "Kitchen")))
     (tags-todo "CATEGORY=\"Bedroom\"" ((org-agenda-overriding-header "Bedroom")))
     (tags-todo "CATEGORY=\"Bathroom\"" ((org-agenda-overriding-header "Bathroom")))
     (tags-todo "CATEGORY=\"Common Rooms\"" ((org-agenda-overriding-header "Common Rooms")))
     (tags-todo "CATEGORY=\"Laundry Room\"" ((org-agenda-overriding-header "Daily")))
     (tags-todo "CATEGORY=\"Pantry\"" ((org-agenda-overriding-header "Pantry")))
     (tags-todo "CATEGORY=\"Office\"" ((org-agenda-overriding-header "Office")))
     (tags-todo "CATEGORY=\"Garage\"" ((org-agenda-overriding-header "Garage")))
     (tags-todo "CATEGORY=\"General\"" ((org-agenda-overriding-header "General")))
     (tags-todo "CATEGORY=\"Cars\"" ((org-agenda-overriding-header "Cars")))
     (tags-todo "CATEGORY=\"Yard\"" ((org-agenda-overriding-header "Yard"))))
    ((org-agenda-files '(,JMB/ORG-LIST-FILE))
     (org-agenda-span 1))))


(with-eval-after-load 'org
  (setq-default org-agenda-custom-commands
        (list (jmb/build-org-agenda-custom-command "a" "All")
              jmb/org-agenda-custom-cleaning-command
              (jmb/build-org-agenda-custom-command "w" "Work" "+Client={.+}"))))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Org Styling
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(with-eval-after-load 'org
  (setq-default org-edit-src-content-indentation 4)
  (let ((scale 1.075))
    (set-face-attribute 'org-level-1 nil :height (expt scale 5))
    (set-face-attribute 'org-level-2 nil :height (expt scale 4))
    (set-face-attribute 'org-level-3 nil :height (expt scale 3))
    (set-face-attribute 'org-level-4 nil :height (expt scale 2))
    (set-face-attribute 'org-level-5 nil :height (expt scale 1))
    (set-face-attribute 'org-level-6 nil :height (expt scale 0))
    (set-face-attribute 'org-level-7 nil :height (expt scale -1))
    (set-face-attribute 'org-level-8 nil :height (expt scale -2)))
  (add-hook 'org-mode-hook #'org-indent-mode))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Find Files
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(defun jmb/find-org-file ()
  (interactive)
  (let* ((directory (completing-read "File Type: " (directory-files JMB/ORG-DIRECTORY nil "^\\([^.]\\|\\.[^.]\\|\\.\\..\\)")))
         (filename
          (read-file-name "Find File: " (concat JMB/ORG-DIRECTORY directory "/"))))
    (if (and (directory-name-p filename)
             (member "index.org" (directory-files filename)))
        (find-file (expand-file-name (concat filename "index.org")))
      (find-file (expand-file-name filename)))))



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
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages nil))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
