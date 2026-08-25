;;; my-files-agent-shell.el --- Browse areas, projects, and agent chats -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jordan
;; Author: Jordan
;; Keywords: convenience, tools
;; Package-Requires: ((emacs "29.1") (agent-shell "0.55"))

;; This file is not part of GNU Emacs.

;;; Commentary:

;; `my-files-agent-shell-toggle' opens a four-column workspace:
;;
;;   Areas | Projects | Agent chats | Main chat
;;
;; Areas are immediate children of `my-files-agent-shell-root-directory'
;; containing `.area.toml'.  Projects are descendants of the selected area
;; containing `.project.toml'.  The chat panel shows live `agent-shell'
;; buffers whose working directories belong to the selected project.

;;; Code:

(require 'agent-shell)
(require 'button)
(require 'cl-lib)
(require 'map)
(require 'seq)
(require 'subr-x)

(defgroup my-files-agent-shell nil
  "Browse My Files areas, projects, and agent-shell chats."
  :group 'tools
  :prefix "my-files-agent-shell-")

(defcustom my-files-agent-shell-root-directory
  (expand-file-name "~/My Files")
  "Directory whose immediate children contain area marker files."
  :type 'directory
  :group 'my-files-agent-shell)

(defcustom my-files-agent-shell-area-marker ".area.toml"
  "File whose presence identifies an area directory."
  :type 'string
  :group 'my-files-agent-shell)

(defcustom my-files-agent-shell-project-marker ".project.toml"
  "File whose presence identifies a project directory."
  :type 'string
  :group 'my-files-agent-shell)

(defcustom my-files-agent-shell-ignored-directory-regexp
  (rx string-start
      (or (seq "." (* anything))
          "node_modules" "vendor" "dist" "build" "target")
      string-end)
  "Regexp matching directory names excluded while discovering projects.

Hidden directories are ignored by default.  This avoids treating templates,
worktrees, dependency trees, and implementation details as projects and keeps
discovery quick."
  :type 'regexp
  :group 'my-files-agent-shell)

(defcustom my-files-agent-shell-area-width 18
  "Preferred width, in columns, of the Areas window."
  :type 'natnum
  :group 'my-files-agent-shell)

(defcustom my-files-agent-shell-project-width 24
  "Preferred width, in columns, of the Projects window."
  :type 'natnum
  :group 'my-files-agent-shell)

(defcustom my-files-agent-shell-chat-width 32
  "Preferred width, in columns, of the Chats window."
  :type 'natnum
  :group 'my-files-agent-shell)

(defcustom my-files-agent-shell-minimum-panel-width 12
  "Minimum width, in columns, allocated to each browser panel."
  :type 'natnum
  :group 'my-files-agent-shell)

(defcustom my-files-agent-shell-minimum-main-width 40
  "Minimum width, in columns, reserved for the main chat window."
  :type 'natnum
  :group 'my-files-agent-shell)

(defface my-files-agent-shell-heading
  '((t :inherit font-lock-keyword-face :weight bold))
  "Face used for panel headings."
  :group 'my-files-agent-shell)

(defface my-files-agent-shell-selected
  '((t :inherit highlight :weight bold))
  "Face used for the selected area and project."
  :group 'my-files-agent-shell)

(defface my-files-agent-shell-muted
  '((t :inherit shadow))
  "Face used for secondary and empty-state text."
  :group 'my-files-agent-shell)

(defconst my-files-agent-shell--area-buffer-name " *My Files Areas*")
(defconst my-files-agent-shell--project-buffer-name " *My Files Projects*")
(defconst my-files-agent-shell--chat-buffer-name " *My Files Agent Chats*")

(defvar my-files-agent-shell--area-window nil)
(defvar my-files-agent-shell--project-window nil)
(defvar my-files-agent-shell--chat-window nil)
(defvar my-files-agent-shell--main-window nil)
(defvar my-files-agent-shell--saved-window-configuration nil)
(defvar my-files-agent-shell--selected-area nil)
(defvar my-files-agent-shell--selected-project nil)
(defvar my-files-agent-shell--refresh-timer nil)
(defvar-local my-files-agent-shell--subscribed nil)

(declare-function agent-shell-buffers "agent-shell")
(declare-function agent-shell-status "agent-shell")
(declare-function agent-shell-subscribe-to "agent-shell")
(defvar agent-shell--state)

(defvar-keymap my-files-agent-shell-mode-map
  :doc "Keymap shared by My Files browser panels."
  "n" #'forward-button
  "p" #'backward-button
  "TAB" #'forward-button
  "<backtab>" #'backward-button
  "RET" #'push-button
  "g" #'my-files-agent-shell-refresh
  "q" #'my-files-agent-shell-close)

(define-derived-mode my-files-agent-shell-mode special-mode "My Files"
  "Base mode for My Files browser panels."
  (setq-local truncate-lines t
              cursor-type nil
              mode-line-format nil
              window-size-fixed 'width))

(define-derived-mode my-files-agent-shell-area-mode
  my-files-agent-shell-mode "Areas"
  "Mode for the My Files area panel.")

(define-derived-mode my-files-agent-shell-project-mode
  my-files-agent-shell-mode "Projects"
  "Mode for the My Files project panel.")

(define-derived-mode my-files-agent-shell-chat-mode
  my-files-agent-shell-mode "Agent Chats"
  "Mode for the My Files agent-shell chat panel.")

(defun my-files-agent-shell--canonical-directory (directory)
  "Return DIRECTORY as a canonical directory name."
  (file-name-as-directory (file-truename (expand-file-name directory))))

(defun my-files-agent-shell--path-name (directory)
  "Return the final directory component of DIRECTORY."
  (file-name-nondirectory (directory-file-name directory)))

(defun my-files-agent-shell--path-less-p (left right)
  "Return non-nil when LEFT should sort before RIGHT."
  (string-collate-lessp (downcase left) (downcase right)))

(defun my-files-agent-shell--discover-areas ()
  "Return sorted area directories below the configured root."
  (let ((root (my-files-agent-shell--canonical-directory
               my-files-agent-shell-root-directory)))
    (unless (file-directory-p root)
      (user-error "My Files root does not exist: %s" root))
    (sort
     (seq-filter
      (lambda (entry)
        (and (file-directory-p entry)
             (file-regular-p
              (expand-file-name my-files-agent-shell-area-marker entry))))
      (directory-files root t directory-files-no-dot-files-regexp t))
     (lambda (left right)
       (my-files-agent-shell--path-less-p
        (my-files-agent-shell--path-name left)
        (my-files-agent-shell--path-name right))))))

(defun my-files-agent-shell--discover-projects (area)
  "Return sorted project directories found recursively below AREA."
  (let (projects)
    (cl-labels
        ((visit (directory)
           (if (file-regular-p
                (expand-file-name my-files-agent-shell-project-marker
                                  directory))
               (push (my-files-agent-shell--canonical-directory directory)
                     projects)
             ;; A marker establishes the project boundary.  Do not descend
             ;; into repositories, worktrees, or dependencies below it.
             (dolist (entry (directory-files
                             directory t directory-files-no-dot-files-regexp t))
               (when (and (file-directory-p entry)
                          (not (file-symlink-p entry))
                          (not (string-match-p
                                my-files-agent-shell-ignored-directory-regexp
                                (my-files-agent-shell--path-name entry))))
                 (visit entry))))))
      (visit (my-files-agent-shell--canonical-directory area)))
    (sort (delete-dups projects)
          (lambda (left right)
            (my-files-agent-shell--path-less-p
             (file-relative-name left area)
             (file-relative-name right area))))))

(defun my-files-agent-shell--project-chat-buffers (project &optional buffers)
  "Return live agent-shell BUFFERS whose directories belong to PROJECT.

When BUFFERS is nil, use all live buffers returned by `agent-shell-buffers'."
  (when project
    (let ((project-root (my-files-agent-shell--canonical-directory project)))
      (seq-filter
       (lambda (buffer)
         (when (buffer-live-p buffer)
           (let ((directory (buffer-local-value 'default-directory buffer)))
             (and directory
                  (condition-case nil
                      (let ((chat-root
                             (my-files-agent-shell--canonical-directory directory)))
                        (or (equal chat-root project-root)
                            (file-in-directory-p chat-root project-root)))
                    (file-error nil))))))
       (or buffers (agent-shell-buffers))))))

(defun my-files-agent-shell--visible-p ()
  "Return non-nil when all browser panel windows are live."
  (and (window-live-p my-files-agent-shell--area-window)
       (window-live-p my-files-agent-shell--project-window)
       (window-live-p my-files-agent-shell--chat-window)
       (window-live-p my-files-agent-shell--main-window)))

(defun my-files-agent-shell--panel-buffer (name mode)
  "Return panel buffer NAME initialized with MODE."
  (let ((buffer (get-buffer-create name)))
    (with-current-buffer buffer
      (unless (eq major-mode mode)
        (funcall mode)))
    buffer))

(defun my-files-agent-shell--insert-heading (text)
  "Insert panel heading TEXT."
  (insert (propertize (concat " " text "\n\n")
                      'face 'my-files-agent-shell-heading)))

(defun my-files-agent-shell--insert-empty (text)
  "Insert empty-state TEXT."
  (insert (propertize (concat " " text "\n")
                      'face 'my-files-agent-shell-muted)))

(defun my-files-agent-shell--insert-path-button
    (label path selected action &optional help)
  "Insert a LABEL button for PATH invoking ACTION.

SELECTED controls the row face.  HELP, when non-nil, is its tooltip."
  (insert " ")
  (insert-text-button
   (concat (if selected "● " "  ") label)
   'action action
   'my-files-agent-shell-path path
   'follow-link t
   'help-echo (or help path)
   'face (if selected 'my-files-agent-shell-selected 'default))
  (insert "\n"))

(defun my-files-agent-shell--select-area (button)
  "Select the area represented by BUTTON."
  (setq my-files-agent-shell--selected-area
        (button-get button 'my-files-agent-shell-path)
        my-files-agent-shell--selected-project nil)
  (my-files-agent-shell-refresh))

(defun my-files-agent-shell--select-project (button)
  "Select the project represented by BUTTON."
  (setq my-files-agent-shell--selected-project
        (button-get button 'my-files-agent-shell-path))
  (my-files-agent-shell-refresh))

(defun my-files-agent-shell--chat-title (buffer)
  "Return a concise display title for agent-shell BUFFER."
  (with-current-buffer buffer
    (let ((title (and (boundp 'agent-shell--state)
                      (map-nested-elt agent-shell--state
                                      '(:session :title)))))
      (or (and (stringp title)
               (not (string-empty-p (string-trim title)))
               (car (split-string (string-trim title) "\n" t)))
          (buffer-name buffer)))))

(defun my-files-agent-shell--chat-status (buffer)
  "Return a display status for agent-shell BUFFER."
  (with-current-buffer buffer
    (or (ignore-errors
          (symbol-name (agent-shell-status :shell-buffer buffer)))
        "starting")))

(defun my-files-agent-shell--insert-chat-button (buffer)
  "Insert a button that opens agent-shell BUFFER."
  (let* ((title (my-files-agent-shell--chat-title buffer))
         (status (my-files-agent-shell--chat-status buffer))
         (label (format "%-8s %s" (concat "[" status "]") title)))
    (insert " ")
    (insert-text-button
     label
     'action #'my-files-agent-shell--open-chat
     'my-files-agent-shell-buffer buffer
     'follow-link t
     'help-echo (format "Open %s" (buffer-name buffer))
     'face 'default)
    (insert "\n")))

(defun my-files-agent-shell--open-chat (button)
  "Open the agent-shell buffer represented by BUTTON in the main window."
  (let ((buffer (button-get button 'my-files-agent-shell-buffer)))
    (unless (buffer-live-p buffer)
      (my-files-agent-shell-refresh)
      (user-error "That agent chat is no longer open"))
    (unless (window-live-p my-files-agent-shell--main-window)
      (user-error "The My Files main window is no longer available"))
    (set-window-buffer my-files-agent-shell--main-window buffer)
    (select-window my-files-agent-shell--main-window)))

(defun my-files-agent-shell--new-chat (_button)
  "Start a new agent-shell chat for the selected project."
  (unless my-files-agent-shell--selected-project
    (user-error "Select a project first"))
  (unless (window-live-p my-files-agent-shell--main-window)
    (user-error "The My Files main window is no longer available"))
  (let ((default-directory my-files-agent-shell--selected-project)
        (agent-shell-session-strategy 'new))
    (with-selected-window my-files-agent-shell--main-window
      (agent-shell '(4))))
  (my-files-agent-shell--schedule-refresh))

(defun my-files-agent-shell--subscribe-chat (buffer)
  "Refresh the browser when BUFFER's session title changes or it is killed."
  (with-current-buffer buffer
    (unless my-files-agent-shell--subscribed
      (setq-local my-files-agent-shell--subscribed t)
      (agent-shell-subscribe-to
       :shell-buffer buffer
       :event 'session-title-changed
       :on-event (lambda (_event)
                   (my-files-agent-shell--schedule-refresh)))
      (add-hook 'kill-buffer-hook
                #'my-files-agent-shell--schedule-refresh nil t))))

(defun my-files-agent-shell--render-areas (areas)
  "Render the area panel using AREAS."
  (with-current-buffer
      (my-files-agent-shell--panel-buffer
       my-files-agent-shell--area-buffer-name
       #'my-files-agent-shell-area-mode)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (my-files-agent-shell--insert-heading "AREAS")
      (if areas
          (dolist (area areas)
            (my-files-agent-shell--insert-path-button
             (my-files-agent-shell--path-name area)
             area
             (equal area my-files-agent-shell--selected-area)
             #'my-files-agent-shell--select-area))
        (my-files-agent-shell--insert-empty "No areas found"))
      (goto-char (point-min)))))

(defun my-files-agent-shell--render-projects (projects)
  "Render the project panel using PROJECTS."
  (with-current-buffer
      (my-files-agent-shell--panel-buffer
       my-files-agent-shell--project-buffer-name
       #'my-files-agent-shell-project-mode)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (my-files-agent-shell--insert-heading "PROJECTS")
      (if projects
          (dolist (project projects)
            (my-files-agent-shell--insert-path-button
             (directory-file-name
              (file-relative-name project
                                  my-files-agent-shell--selected-area))
             project
             (equal project my-files-agent-shell--selected-project)
             #'my-files-agent-shell--select-project))
        (my-files-agent-shell--insert-empty
         (if my-files-agent-shell--selected-area
             "No projects found"
           "Select an area")))
      (goto-char (point-min)))))

(defun my-files-agent-shell--render-chats (chats)
  "Render the agent chat panel using CHATS."
  (with-current-buffer
      (my-files-agent-shell--panel-buffer
       my-files-agent-shell--chat-buffer-name
       #'my-files-agent-shell-chat-mode)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (my-files-agent-shell--insert-heading "AGENT CHATS")
      (if my-files-agent-shell--selected-project
          (progn
            (insert " ")
            (insert-text-button
             "+ New chat"
             'action #'my-files-agent-shell--new-chat
             'follow-link t
             'help-echo "Start a new agent-shell chat for this project"
             'face 'font-lock-keyword-face)
            (insert "\n\n")
            (if chats
                (dolist (chat chats)
                  (my-files-agent-shell--subscribe-chat chat)
                  (my-files-agent-shell--insert-chat-button chat))
              (my-files-agent-shell--insert-empty "No open chats")))
        (my-files-agent-shell--insert-empty "Select a project"))
      (goto-char (point-min)))))

;;;###autoload
(defun my-files-agent-shell-refresh ()
  "Rescan areas, projects, and open agent-shell chats."
  (interactive)
  (let* ((areas (my-files-agent-shell--discover-areas))
         (selected-area
          (and my-files-agent-shell--selected-area
               (seq-find
                (lambda (area)
                  (equal area my-files-agent-shell--selected-area))
                areas))))
    (setq my-files-agent-shell--selected-area
          (or selected-area (car areas)))
    (let* ((projects
            (and my-files-agent-shell--selected-area
                 (my-files-agent-shell--discover-projects
                  my-files-agent-shell--selected-area)))
           (selected-project
            (and my-files-agent-shell--selected-project
                 (seq-find
                  (lambda (project)
                    (equal project my-files-agent-shell--selected-project))
                  projects))))
      (setq my-files-agent-shell--selected-project
            (or selected-project (car projects)))
      (let ((chats
             (my-files-agent-shell--project-chat-buffers
              my-files-agent-shell--selected-project)))
        (my-files-agent-shell--render-areas areas)
        (my-files-agent-shell--render-projects projects)
        (my-files-agent-shell--render-chats chats)))))

(defun my-files-agent-shell--schedule-refresh (&rest _ignored)
  "Schedule a browser refresh after current buffer activity settles."
  (when (my-files-agent-shell--visible-p)
    (when (timerp my-files-agent-shell--refresh-timer)
      (cancel-timer my-files-agent-shell--refresh-timer))
    (setq my-files-agent-shell--refresh-timer
          (run-with-idle-timer
           0.1 nil
           (lambda ()
             (setq my-files-agent-shell--refresh-timer nil)
             (when (my-files-agent-shell--visible-p)
               (my-files-agent-shell-refresh)))))))

(defun my-files-agent-shell--scaled-panel-widths (total-width)
  "Return three panel widths suitable for TOTAL-WIDTH."
  (let* ((requested (list my-files-agent-shell-area-width
                          my-files-agent-shell-project-width
                          my-files-agent-shell-chat-width))
         (available (- total-width my-files-agent-shell-minimum-main-width))
         (minimum-total (* 3 my-files-agent-shell-minimum-panel-width))
         (requested-total (apply #'+ requested)))
    (when (< available minimum-total)
      (user-error
       "Frame is too narrow: need at least %d columns"
       (+ minimum-total my-files-agent-shell-minimum-main-width)))
    (if (<= requested-total available)
        requested
      (let* ((extra (- available minimum-total))
             (requested-extra
              (mapcar (lambda (width)
                        (max 0 (- width my-files-agent-shell-minimum-panel-width)))
                      requested))
             (requested-extra-total (max 1 (apply #'+ requested-extra)))
             (widths
              (mapcar
               (lambda (width-extra)
                 (+ my-files-agent-shell-minimum-panel-width
                    (floor (* extra width-extra)
                           requested-extra-total)))
               requested-extra)))
        ;; Rounding down can leave a few columns unused.  Give them to chats.
        (setf (nth 2 widths)
              (+ (nth 2 widths) (- available (apply #'+ widths))))
        widths))))

(defun my-files-agent-shell--prepare-panel-window (window buffer)
  "Display BUFFER in dedicated panel WINDOW."
  (set-window-buffer window buffer)
  (set-window-dedicated-p window t)
  (set-window-parameter window 'no-delete-other-windows t)
  (set-window-parameter window 'my-files-agent-shell-panel t))

;;;###autoload
(defun my-files-agent-shell-open ()
  "Open the Areas, Projects, Chats, and main chat workspace."
  (interactive)
  (if (my-files-agent-shell--visible-p)
      (select-window my-files-agent-shell--area-window)
    (when my-files-agent-shell--saved-window-configuration
      (my-files-agent-shell-close))
    (let* ((main (selected-window))
           (configuration (current-window-configuration))
           widths
           area-window project-window chat-window)
      (condition-case error-data
          (progn
            (let ((ignore-window-parameters t))
              (delete-other-windows main))
            (setq widths (my-files-agent-shell--scaled-panel-widths
                          (window-total-width main)))
            (setq area-window (split-window main (- (nth 0 widths)) 'left)
                  project-window (split-window main (- (nth 1 widths)) 'left)
                  chat-window (split-window main (- (nth 2 widths)) 'left))
            (setq my-files-agent-shell--saved-window-configuration configuration
                  my-files-agent-shell--area-window area-window
                  my-files-agent-shell--project-window project-window
                  my-files-agent-shell--chat-window chat-window
                  my-files-agent-shell--main-window main)
            (my-files-agent-shell--prepare-panel-window
             area-window
             (my-files-agent-shell--panel-buffer
              my-files-agent-shell--area-buffer-name
              #'my-files-agent-shell-area-mode))
            (my-files-agent-shell--prepare-panel-window
             project-window
             (my-files-agent-shell--panel-buffer
              my-files-agent-shell--project-buffer-name
              #'my-files-agent-shell-project-mode))
            (my-files-agent-shell--prepare-panel-window
             chat-window
             (my-files-agent-shell--panel-buffer
              my-files-agent-shell--chat-buffer-name
              #'my-files-agent-shell-chat-mode))
            (add-hook 'buffer-list-update-hook
                      #'my-files-agent-shell--schedule-refresh)
            (my-files-agent-shell-refresh)
            (select-window area-window))
        (error
         (remove-hook 'buffer-list-update-hook
                      #'my-files-agent-shell--schedule-refresh)
         (set-window-configuration configuration)
         (setq my-files-agent-shell--saved-window-configuration nil
               my-files-agent-shell--area-window nil
               my-files-agent-shell--project-window nil
               my-files-agent-shell--chat-window nil
               my-files-agent-shell--main-window nil)
         (signal (car error-data) (cdr error-data)))))))

;;;###autoload
(defun my-files-agent-shell-close ()
  "Close the browser and restore the previous window configuration."
  (interactive)
  (remove-hook 'buffer-list-update-hook
               #'my-files-agent-shell--schedule-refresh)
  (when (timerp my-files-agent-shell--refresh-timer)
    (cancel-timer my-files-agent-shell--refresh-timer))
  (setq my-files-agent-shell--refresh-timer nil)
  (let ((configuration my-files-agent-shell--saved-window-configuration))
    (setq my-files-agent-shell--saved-window-configuration nil
          my-files-agent-shell--area-window nil
          my-files-agent-shell--project-window nil
          my-files-agent-shell--chat-window nil
          my-files-agent-shell--main-window nil)
    (when (window-configuration-p configuration)
      (set-window-configuration configuration))))

;;;###autoload
(defun my-files-agent-shell-toggle ()
  "Toggle the My Files agent-shell browser workspace."
  (interactive)
  (if (my-files-agent-shell--visible-p)
      (my-files-agent-shell-close)
    (my-files-agent-shell-open)))

(provide 'my-files-agent-shell)
;;; my-files-agent-shell.el ends here
