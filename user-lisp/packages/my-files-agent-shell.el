;;; my-files-agent-shell.el --- Browse areas, projects, and agent chats -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jordan
;; Author: Jordan
;; Keywords: convenience, tools
;; Package-Requires: ((emacs "29.1") (agent-shell "0.55") (codex-ide "0.3.2"))

;; This file is not part of GNU Emacs.

;;; Commentary:

;; `my-files-agent-shell-toggle' opens a four-column workspace:
;;
;;   Areas | Projects | Agent chats | Main chat
;;
;; Areas are immediate children of `my-files-agent-shell-root-directory'
;; containing `.area.toml'.  Projects are descendants of the selected area
;; containing `.project.toml'.  The chat panel combines live `agent-shell'
;; buffers, their saved transcripts, and Codex tasks whose working directories
;; belong to the selected project or area.  Every non-archived conversation
;; appears in Active Conversations and in one user-assigned workflow stage:
;; In Progress, Review, Staged, or Completed.  Archiving is a non-destructive
;; browser classification that leaves the conversation only under Archived.
;; Runtime status remains visible on each row but never changes workflow stage.

;;; Code:

(require 'agent-shell)
(require 'button)
(require 'cl-lib)
(require 'hl-line)
(require 'json)
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

(defcustom my-files-agent-shell-codex-refresh-interval 10
  "Seconds between Codex task refreshes while the browser is visible."
  :type 'number
  :group 'my-files-agent-shell)

(defcustom my-files-agent-shell-state-file
  (locate-user-emacs-file "var/my-files-agent-shell-state.json")
  "File that stores user-assigned conversation stages and archive state."
  :type 'file
  :group 'my-files-agent-shell)

(defcustom my-files-agent-shell-session-restore-verbosity 'first-last
  "How much prior chat history Agent Shell should render when resuming.

The agent resumes the complete session context regardless of this display
setting.  `first-last' keeps large histories responsive while showing enough
of the conversation to confirm that the correct session was restored."
  :type '(choice (const :tag "Last turn" last)
                 (const :tag "First and last turns" first-last)
                 (const :tag "Full visible history" full))
  :group 'my-files-agent-shell)

(defface my-files-agent-shell-heading
  '((t :inherit font-lock-keyword-face :weight bold))
  "Face used for panel headings."
  :group 'my-files-agent-shell)

(defface my-files-agent-shell-selected
  '((t :inherit highlight :weight bold))
  "Face used for the selected area and project."
  :group 'my-files-agent-shell)

(defface my-files-agent-shell-selected-inactive
  '((((class color) (background light))
     :background "gray90" :weight bold)
    (((class color) (background dark))
     :background "gray25" :weight bold)
    (t :inherit shadow :weight bold))
  "Face used for a selected item in an unfocused panel."
  :group 'my-files-agent-shell)

(defface my-files-agent-shell-cursor-inactive
  '((((class color) (background light)) :background "gray92" :extend t)
    (((class color) (background dark)) :background "gray22" :extend t)
    (t :inherit shadow :extend t))
  "Face used for the keyboard cursor row in an unfocused panel."
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
(defvar my-files-agent-shell--codex-refresh-timer nil)
(defvar my-files-agent-shell--codex-session nil)
(defvar my-files-agent-shell--codex-session-initialized nil)
(defvar my-files-agent-shell--codex-refreshing nil)
(defvar my-files-agent-shell--codex-threads nil)
(defvar my-files-agent-shell--codex-error nil)
(defvar my-files-agent-shell--codex-last-refresh-time nil)
(defvar my-files-agent-shell--known-chat-buffers nil)
(defvar my-files-agent-shell--conversation-states
  (make-hash-table :test #'equal))
(defvar my-files-agent-shell--conversation-states-loaded nil)
(defvar my-files-agent-shell--conversation-state-load-error nil)
(defvar my-files-agent-shell--transcript-metadata-cache
  (make-hash-table :test #'equal))
(defvar-local my-files-agent-shell--subscribed-events nil)
(defvar-local my-files-agent-shell--collapsed-chat-sections nil)
(defvar-local my-files-agent-shell--assigned-project nil)
(defvar-local my-files-agent-shell--highlighted-button-key nil)
(defvar-local my-files-agent-shell--selected-path-button nil)
(defvar my-files-agent-shell--rendering-section nil)

(defconst my-files-agent-shell--workflow-stages
  '((in-progress . "In Progress")
    (review . "Review")
    (staged . "Staged")
    (completed . "Completed"))
  "User-assigned workflow stages in display order.")

(defconst my-files-agent-shell--chat-sections
  `((active . "Active Conversations")
    ,@my-files-agent-shell--workflow-stages
    (archived . "Archived"))
  "Conversation sections in display order.")

(defconst my-files-agent-shell--chat-refresh-events
  '(input-submitted
    turn-complete
    prompt-ready
    permission-request
    permission-response
    session-title-changed
    error)
  "Agent-shell events that can change a chat row's operational status.")

(declare-function agent-shell-buffers "agent-shell")
(declare-function agent-shell-cwd "agent-shell-project")
(declare-function agent-shell-resume-session "agent-shell")
(declare-function agent-shell-start "agent-shell")
(declare-function agent-shell-status "agent-shell")
(declare-function agent-shell-subscribe-to "agent-shell")
(declare-function agent-shell--resolved-agent-configs "agent-shell")
(declare-function codex-ide--create-query-session "codex-ide-session")
(declare-function codex-ide--query-only-session-for-directory
                  "codex-ide-session")
(declare-function codex-ide--request-async "codex-ide-protocol")
(declare-function codex-ide--set-session-status "codex-ide-core")
(declare-function codex-ide-session-process "codex-ide-core")
(declare-function codex-ide-session-status "codex-ide-core")
(defvar agent-shell--state)
(defvar agent-shell-session-restore-verbosity)
(defvar codex-ide-cli-path)

(defun my-files-agent-shell--workflow-stage-p (stage)
  "Return non-nil when STAGE is a supported workflow stage."
  (and (assq stage my-files-agent-shell--workflow-stages) t))

(defun my-files-agent-shell--workflow-stage-label (stage)
  "Return the display label for workflow STAGE."
  (or (alist-get stage my-files-agent-shell--workflow-stages)
      (error "Unsupported conversation workflow stage: %S" stage)))

(defun my-files-agent-shell--load-conversation-states ()
  "Load persisted conversation states once and return their table."
  (unless my-files-agent-shell--conversation-states-loaded
    (setq my-files-agent-shell--conversation-states-loaded t
          my-files-agent-shell--conversation-state-load-error nil)
    (clrhash my-files-agent-shell--conversation-states)
    (when (file-exists-p my-files-agent-shell-state-file)
      (condition-case error-data
          (with-temp-buffer
            (insert-file-contents my-files-agent-shell-state-file)
            (let* ((data
                    (json-parse-buffer
                     :object-type 'alist
                     :array-type 'list
                     :null-object nil
                     :false-object :json-false))
                   (version (alist-get 'version data))
                   (conversations (alist-get 'conversations data))
                   (seen (make-hash-table :test #'equal)))
              (skip-chars-forward " \t\r\n")
              (unless (eobp)
                (error "Unexpected data after conversation state"))
              (unless (equal version 1)
                (error "Unsupported state version: %S" version))
              (unless (listp conversations)
                (error "Conversation state list is invalid"))
              (dolist (entry conversations)
                (let ((key (alist-get 'key entry))
                      (stage-name (alist-get 'stage entry))
                      (archived-value (alist-get 'archived entry)))
                  (unless (and (stringp key)
                               (not (string-empty-p key))
                               (stringp stage-name)
                               (memq archived-value '(:json-false t)))
                    (error "Invalid conversation state: %S" entry))
                  (when (gethash key seen)
                    (error "Duplicate conversation state: %s" key))
                  (let ((stage (intern-soft stage-name))
                        (archived (eq archived-value t)))
                    (unless (my-files-agent-shell--workflow-stage-p stage)
                      (error "Invalid workflow stage for %s: %S" key stage))
                    (puthash key t seen)
                    (puthash key
                             (list :stage stage :archived archived)
                             my-files-agent-shell--conversation-states))))))
        (error
         (setq my-files-agent-shell--conversation-state-load-error
               (error-message-string error-data))
         (display-warning
          'my-files-agent-shell
          (format "Could not load %s: %s"
                  my-files-agent-shell-state-file
                  my-files-agent-shell--conversation-state-load-error)
          :warning)))))
  my-files-agent-shell--conversation-states)

(defun my-files-agent-shell--conversation-state-data ()
  "Return persisted conversation states in a deterministic form."
  (let (conversations)
    (maphash
     (lambda (key state)
       (push `((key . ,key)
               (stage . ,(symbol-name (plist-get state :stage)))
               (archived . ,(if (plist-get state :archived)
                                t
                              :json-false)))
             conversations))
     my-files-agent-shell--conversation-states)
    `((version . 1)
      (conversations
       . ,(vconcat
           (sort conversations
                 (lambda (left right)
                   (string< (alist-get 'key left)
                            (alist-get 'key right)))))))))

(defun my-files-agent-shell--save-conversation-states ()
  "Atomically persist user-assigned conversation states."
  (when my-files-agent-shell--conversation-state-load-error
    (user-error
     "Cannot overwrite unreadable conversation state: %s"
     my-files-agent-shell--conversation-state-load-error))
  (let* ((file (expand-file-name my-files-agent-shell-state-file))
         (directory (file-name-directory file))
         temp-file)
    (make-directory directory t)
    (setq temp-file
          (make-temp-file
           (expand-file-name ".my-files-agent-shell-state-" directory)))
    (unwind-protect
        (progn
          (with-temp-file temp-file
            (insert
             (json-serialize
              (my-files-agent-shell--conversation-state-data)
              :null-object nil
              :false-object :json-false))
            (insert "\n"))
          (rename-file temp-file file t)
          (setq temp-file nil)
          (set-file-modes file #o600))
      (when (and temp-file (file-exists-p temp-file))
        (delete-file temp-file)))))

(defun my-files-agent-shell--conversation-state (key)
  "Return the persisted state for conversation KEY."
  (my-files-agent-shell--load-conversation-states)
  (or (and key (gethash key my-files-agent-shell--conversation-states))
      '(:stage in-progress :archived nil)))

(defun my-files-agent-shell--store-conversation-state (key state)
  "Persist STATE for conversation KEY, rolling back on failure."
  (unless key
    (user-error "This conversation is still starting and has no stable ID"))
  (let* ((missing (make-symbol "missing"))
         (previous (gethash key my-files-agent-shell--conversation-states
                            missing))
         (default-state (equal state '(:stage in-progress :archived nil))))
    (if default-state
        (remhash key my-files-agent-shell--conversation-states)
      (puthash key state my-files-agent-shell--conversation-states))
    (condition-case error-data
        (my-files-agent-shell--save-conversation-states)
      (error
       (if (eq previous missing)
           (remhash key my-files-agent-shell--conversation-states)
         (puthash key previous my-files-agent-shell--conversation-states))
       (signal (car error-data) (cdr error-data))))))

(defun my-files-agent-shell--set-conversation-stage (key stage)
  "Assign workflow STAGE to conversation KEY."
  (unless (my-files-agent-shell--workflow-stage-p stage)
    (error "Unsupported conversation workflow stage: %S" stage))
  (let ((state (copy-sequence
                (my-files-agent-shell--conversation-state key))))
    (my-files-agent-shell--store-conversation-state
     key (plist-put state :stage stage))))

(defun my-files-agent-shell--set-conversation-archived (key archived)
  "Set conversation KEY's archive state to ARCHIVED."
  (let ((state (copy-sequence
                (my-files-agent-shell--conversation-state key))))
    (my-files-agent-shell--store-conversation-state
     key (plist-put state :archived (and archived t)))))

(defun my-files-agent-shell--conversation-key (kind identifier)
  "Return a stable conversation key for KIND and IDENTIFIER."
  (when identifier
    (format "%s:%s" kind identifier)))

(defun my-files-agent-shell--live-conversation-key (buffer)
  "Return the stable conversation key for live Agent Shell BUFFER."
  (my-files-agent-shell--conversation-key
   'agent (my-files-agent-shell--live-session-id buffer)))

(defun my-files-agent-shell--saved-conversation-key (entry)
  "Return the stable conversation key for saved transcript ENTRY."
  (my-files-agent-shell--conversation-key
   'agent (plist-get entry :session-id)))

(defun my-files-agent-shell--codex-conversation-key (thread)
  "Return the stable conversation key for Codex THREAD."
  (my-files-agent-shell--conversation-key 'codex (alist-get 'id thread)))

(defvar-keymap my-files-agent-shell-mode-map
  :doc "Keymap shared by My Files browser panels."
  "n" #'my-files-agent-shell-next-item
  "C-n" #'my-files-agent-shell-next-item
  "<down>" #'my-files-agent-shell-next-item
  "p" #'my-files-agent-shell-previous-item
  "C-p" #'my-files-agent-shell-previous-item
  "<up>" #'my-files-agent-shell-previous-item
  "TAB" #'my-files-agent-shell-next-item
  "<backtab>" #'my-files-agent-shell-previous-item
  "C-f" #'my-files-agent-shell-next-panel
  "<right>" #'my-files-agent-shell-next-panel
  "C-b" #'my-files-agent-shell-previous-panel
  "<left>" #'my-files-agent-shell-previous-panel
  "1" #'my-files-agent-shell-focus-areas
  "2" #'my-files-agent-shell-focus-projects
  "3" #'my-files-agent-shell-focus-chats
  "4" #'my-files-agent-shell-focus-main
  "a" #'my-files-agent-shell-archive-at-point
  "m" #'my-files-agent-shell-move-at-point
  "u" #'my-files-agent-shell-restore-at-point
  "RET" #'push-button
  "g" #'my-files-agent-shell-refresh
  "q" #'my-files-agent-shell-close)

(define-derived-mode my-files-agent-shell-mode special-mode "My Files"
  "Base mode for My Files browser panels."
  (setq-local truncate-lines t
              cursor-type nil
              mode-line-format nil
              hl-line-sticky-flag t
              hl-line-face 'my-files-agent-shell-cursor-inactive)
  (hl-line-mode 1)
  (add-hook 'post-command-hook
            #'my-files-agent-shell--remember-panel-selection nil t))

(define-derived-mode my-files-agent-shell-area-mode
  my-files-agent-shell-mode "Areas"
  "Mode for the My Files area panel.")

(define-derived-mode my-files-agent-shell-project-mode
  my-files-agent-shell-mode "Projects"
  "Mode for the My Files project panel.")

(define-derived-mode my-files-agent-shell-chat-mode
  my-files-agent-shell-mode "Agent Chats"
  "Mode for the My Files agent-shell chat panel.")

(defun my-files-agent-shell--visible-buttons ()
  "Return visible buttons in the current buffer in display order."
  (let ((button (next-button (point-min)))
        buttons)
    (while button
      (unless (or (invisible-p (button-start button))
                  (button-get button 'my-files-agent-shell-secondary-action))
        (push button buttons))
      (setq button (next-button (button-end button))))
    (nreverse buttons)))

(defun my-files-agent-shell--button-selection-key (button)
  "Return a stable selection key for primary BUTTON, or nil."
  (cond
   ((button-get button 'my-files-agent-shell-conversation-key)
    (list 'conversation
          (button-get button 'my-files-agent-shell-conversation-key)
          (button-get button 'my-files-agent-shell-section)))
   ((button-get button 'my-files-agent-shell-path)
    (list 'path (button-get button 'my-files-agent-shell-path)))
   ((button-get button 'my-files-agent-shell-buffer)
    (list 'buffer (button-get button 'my-files-agent-shell-buffer)))
   ((button-get button 'my-files-agent-shell-entry)
    (list 'saved
          (plist-get (button-get button 'my-files-agent-shell-entry)
                     :session-id)))
   ((button-get button 'my-files-agent-shell-codex-entry)
    (list 'codex
          (alist-get 'id
                     (button-get button 'my-files-agent-shell-codex-entry))))
   ((button-get button 'my-files-agent-shell-category)
    (list 'category
          (button-get button 'my-files-agent-shell-category)))
   ((button-get button 'action)
    (list 'action (button-get button 'action)))))

(defun my-files-agent-shell--selected-button-key ()
  "Return the current primary button's stable selection key, or nil."
  (or (when-let* ((button (button-at (point))))
        (unless (button-get button 'my-files-agent-shell-secondary-action)
          (my-files-agent-shell--button-selection-key button)))
      my-files-agent-shell--highlighted-button-key))

(defun my-files-agent-shell--remember-panel-selection ()
  "Remember the primary button currently highlighted in this panel."
  (when-let* ((button (button-at (point))))
    (unless (button-get button 'my-files-agent-shell-secondary-action)
      (setq my-files-agent-shell--highlighted-button-key
            (my-files-agent-shell--button-selection-key button)))))

(defun my-files-agent-shell--restore-button-selection (key)
  "Restore point to the visible primary button matching KEY."
  (goto-char (point-min))
  (let* ((buttons (my-files-agent-shell--visible-buttons))
         (conversation-key
          (and (eq (car-safe key) 'conversation) (nth 1 key)))
         (button
          (and key
               (or (seq-find
                    (lambda (candidate)
                      (equal (my-files-agent-shell--button-selection-key
                              candidate)
                             key))
                    buttons)
                   (and conversation-key
                        (seq-find
                         (lambda (candidate)
                           (equal
                            (button-get
                             candidate
                             'my-files-agent-shell-conversation-key)
                            conversation-key))
                         buttons))))))
    (setq my-files-agent-shell--highlighted-button-key
          (and button
               (my-files-agent-shell--button-selection-key button)))
    (when button
      (goto-char (button-start button)))))

(defun my-files-agent-shell--move-item (direction)
  "Move to the next visible item in DIRECTION, wrapping at the ends."
  (let* ((buttons (my-files-agent-shell--visible-buttons))
         (current (button-at (point)))
         (position (if current (button-start current) (point)))
         (ordered (if (> direction 0) buttons (reverse buttons)))
         (candidate
          (seq-find
           (lambda (button)
             (if (> direction 0)
                 (> (button-start button) position)
               (< (button-start button) position)))
           ordered)))
    (when-let* ((button (or candidate (car ordered))))
      (goto-char (button-start button))
      (my-files-agent-shell--remember-panel-selection))))

(defun my-files-agent-shell-next-item ()
  "Move to the next actionable item, wrapping within the panel."
  (interactive)
  (my-files-agent-shell--move-item 1))

(defun my-files-agent-shell-previous-item ()
  "Move to the previous actionable item, wrapping within the panel."
  (interactive)
  (my-files-agent-shell--move-item -1))

(defun my-files-agent-shell--preferred-panel-button ()
  "Return the primary button that should receive focus in this panel."
  (let ((buttons (my-files-agent-shell--visible-buttons)))
    (or (and my-files-agent-shell--highlighted-button-key
             (seq-find
              (lambda (button)
                (equal (my-files-agent-shell--button-selection-key button)
                       my-files-agent-shell--highlighted-button-key))
              buttons))
        (and-let* ((button (button-at (point))))
          (and (memq button buttons) button))
        (seq-find
         (lambda (button)
           (button-get button 'my-files-agent-shell-selected))
         buttons)
        (car buttons))))

(defun my-files-agent-shell--update-panel-focus-faces (&optional frame)
  "Update active and inactive panel faces for FRAME."
  (let ((selected (frame-selected-window (or frame (selected-frame)))))
    (dolist (window (list my-files-agent-shell--area-window
                          my-files-agent-shell--project-window
                          my-files-agent-shell--chat-window))
      (when (window-live-p window)
        (with-current-buffer (window-buffer window)
          (let ((active (eq window selected))
                (inhibit-read-only t))
            (setq-local hl-line-face
                        (if active
                            'hl-line
                          'my-files-agent-shell-cursor-inactive))
            (when (overlayp hl-line-overlay)
              (overlay-put hl-line-overlay 'face hl-line-face))
            (when my-files-agent-shell--selected-path-button
              (button-put
               my-files-agent-shell--selected-path-button 'face
               (if active
                   'my-files-agent-shell-selected
                 'my-files-agent-shell-selected-inactive)))))))))

(defun my-files-agent-shell--focus-window (window)
  "Select WINDOW at its currently highlighted actionable item."
  (unless (window-live-p window)
    (user-error "The My Files browser is not open"))
  (let* ((panel (window-parameter window 'my-files-agent-shell-panel))
         (position
          (and panel
               (with-current-buffer (window-buffer window)
                 (when-let* ((button
                              (my-files-agent-shell--preferred-panel-button)))
                   (button-start button))))))
    (when position
      (set-window-point window position))
    (select-window window)
    (when position
      (goto-char position)
      (my-files-agent-shell--remember-panel-selection))
    (my-files-agent-shell--update-panel-focus-faces)))

;;;###autoload
(defun my-files-agent-shell-focus-browser ()
  "Open the browser if needed, then focus its Areas panel."
  (interactive)
  (unless (my-files-agent-shell--visible-p)
    (my-files-agent-shell-open))
  (my-files-agent-shell-focus-areas))

(defun my-files-agent-shell-focus-areas ()
  "Focus the Areas panel."
  (interactive)
  (my-files-agent-shell--focus-window my-files-agent-shell--area-window))

(defun my-files-agent-shell-focus-projects ()
  "Focus the Projects panel."
  (interactive)
  (my-files-agent-shell--focus-window my-files-agent-shell--project-window))

(defun my-files-agent-shell-focus-chats ()
  "Focus the Chats panel."
  (interactive)
  (my-files-agent-shell--focus-window my-files-agent-shell--chat-window))

(defun my-files-agent-shell-focus-main ()
  "Focus the main chat window."
  (interactive)
  (my-files-agent-shell--focus-window my-files-agent-shell--main-window))

(defun my-files-agent-shell-next-panel ()
  "Move focus one panel to the right, wrapping after the main window."
  (interactive)
  (my-files-agent-shell--focus-window
   (cond
    ((eq (selected-window) my-files-agent-shell--area-window)
     my-files-agent-shell--project-window)
    ((eq (selected-window) my-files-agent-shell--project-window)
     my-files-agent-shell--chat-window)
    ((eq (selected-window) my-files-agent-shell--chat-window)
     my-files-agent-shell--main-window)
    (t my-files-agent-shell--area-window))))

(defun my-files-agent-shell-previous-panel ()
  "Move focus one panel to the left, wrapping before the Areas panel."
  (interactive)
  (my-files-agent-shell--focus-window
   (cond
    ((eq (selected-window) my-files-agent-shell--main-window)
     my-files-agent-shell--chat-window)
    ((eq (selected-window) my-files-agent-shell--chat-window)
     my-files-agent-shell--project-window)
    ((eq (selected-window) my-files-agent-shell--project-window)
     my-files-agent-shell--area-window)
    (t my-files-agent-shell--main-window))))

(defun my-files-agent-shell--canonical-directory (directory)
  "Return DIRECTORY as a canonical directory name."
  (file-name-as-directory (file-truename (expand-file-name directory))))

(defun my-files-agent-shell--directory-in-scope-p (directory scope)
  "Return non-nil when DIRECTORY is SCOPE or is contained by it."
  (condition-case nil
      (let ((directory-root
             (my-files-agent-shell--canonical-directory directory))
            (scope-root (my-files-agent-shell--canonical-directory scope)))
        (or (equal directory-root scope-root)
            (file-in-directory-p directory-root scope-root)))
    (file-error nil)))

(defun my-files-agent-shell-agent-data-directory (subdir)
  "Return the centralized agent-shell directory for SUBDIR.

When the agent's working directory is below a structured workspace, store
agent-shell data below the nearest ancestor containing `.project.toml'.
Otherwise retain agent-shell's normal behavior and store data below its CWD."
  (let* ((cwd (agent-shell-cwd))
         (workspace (locate-dominating-file
                     cwd my-files-agent-shell-project-marker)))
    (expand-file-name (file-name-concat ".agent-shell" subdir)
                      (or workspace cwd))))

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
     (mapcar
      #'my-files-agent-shell--canonical-directory
      (seq-filter
       (lambda (entry)
         (and (file-directory-p entry)
              (file-regular-p
               (expand-file-name my-files-agent-shell-area-marker entry))))
       (directory-files root t directory-files-no-dot-files-regexp t)))
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

(defun my-files-agent-shell--scope-chat-buffers (scope &optional buffers)
  "Return live agent-shell BUFFERS whose directories belong to SCOPE.

When BUFFERS is nil, use all live buffers returned by `agent-shell-buffers'."
  (when scope
    (seq-filter
     (lambda (buffer)
       (when (buffer-live-p buffer)
         (let ((assigned-project
                (buffer-local-value
                 'my-files-agent-shell--assigned-project buffer))
               (directory (buffer-local-value 'default-directory buffer)))
           (when-let* ((chat-directory (or assigned-project directory)))
             (my-files-agent-shell--directory-in-scope-p
              chat-directory scope)))))
     (or buffers (agent-shell-buffers)))))

(defun my-files-agent-shell--project-chat-buffers (project &optional buffers)
  "Return live agent-shell BUFFERS whose directories belong to PROJECT.

When BUFFERS is nil, use all live buffers returned by `agent-shell-buffers'."
  (my-files-agent-shell--scope-chat-buffers project buffers))

(defun my-files-agent-shell--area-chat-buffers (area &optional buffers)
  "Return live agent-shell BUFFERS whose directories belong to AREA.

When BUFFERS is nil, use all live buffers returned by `agent-shell-buffers'."
  (my-files-agent-shell--scope-chat-buffers area buffers))

(defun my-files-agent-shell--scope-codex-threads (scope threads)
  "Return Codex THREADS whose working directories belong to SCOPE."
  (when scope
    (seq-filter
     (lambda (thread)
       (when-let* ((directory (alist-get 'cwd thread)))
         (my-files-agent-shell--directory-in-scope-p directory scope)))
     threads)))

(defun my-files-agent-shell--project-codex-threads (project threads)
  "Return Codex THREADS whose working directories belong to PROJECT."
  (my-files-agent-shell--scope-codex-threads project threads))

(defun my-files-agent-shell--area-codex-threads (area threads)
  "Return Codex THREADS whose working directories belong to AREA."
  (my-files-agent-shell--scope-codex-threads area threads))

(defun my-files-agent-shell--codex-thread-status (thread)
  "Return THREAD's Codex status as a string."
  (let ((status (alist-get 'type (alist-get 'status thread))))
    (if status (format "%s" status) "notLoaded")))

(defun my-files-agent-shell--codex-thread-title (thread)
  "Return a concise display title for Codex THREAD."
  (let ((title (or (alist-get 'name thread)
                   (alist-get 'preview thread)
                   "Untitled Codex task")))
    (or (car (split-string (string-trim title) "\n" t))
        "Untitled Codex task")))

(defun my-files-agent-shell--codex-session-live-p ()
  "Return non-nil when the browser's Codex query session is live."
  (and my-files-agent-shell--codex-session
       (process-live-p
        (codex-ide-session-process my-files-agent-shell--codex-session))))

(defun my-files-agent-shell--codex-error-text (error-data)
  "Return a concise display string for Codex ERROR-DATA."
  (cond
   ((stringp error-data) error-data)
   ((and (consp error-data)
         (symbolp (car error-data))
         (get (car error-data) 'error-conditions))
    (error-message-string error-data))
   ((ignore-errors (alist-get 'message error-data))
    (format "%s" (alist-get 'message error-data)))
   (t (format "%S" error-data))))

(defun my-files-agent-shell--codex-refresh-failed (error-data)
  "Finish a Codex refresh that failed with ERROR-DATA."
  (setq my-files-agent-shell--codex-refreshing nil
        my-files-agent-shell--codex-last-refresh-time (float-time)
        my-files-agent-shell--codex-error
        (my-files-agent-shell--codex-error-text error-data))
  (my-files-agent-shell--schedule-refresh))

(defun my-files-agent-shell--codex-list-page (session cursor threads)
  "Fetch one Codex task page using SESSION after CURSOR and THREADS."
  (codex-ide--request-async
   session
   "thread/list"
   (delq nil
         `((archived . :json-false)
           (useStateDbOnly . t)
           (limit . 100)
           (sortKey . "updated_at")
           (sortDirection . "desc")
           ,@(when cursor `((cursor . ,cursor)))))
   (lambda (result error-data)
     (if error-data
         (my-files-agent-shell--codex-refresh-failed error-data)
       (let* ((page (append (alist-get 'data result) nil))
              (all-threads (nconc threads page))
              (next-cursor (alist-get 'nextCursor result)))
         (if next-cursor
             (my-files-agent-shell--codex-list-page
              session next-cursor all-threads)
           (setq my-files-agent-shell--codex-threads all-threads
                 my-files-agent-shell--codex-error nil
                 my-files-agent-shell--codex-refreshing nil
                 my-files-agent-shell--codex-last-refresh-time (float-time))
           (my-files-agent-shell--schedule-refresh)))))))

(defun my-files-agent-shell--codex-list-threads (session)
  "Refresh cached Codex tasks using initialized SESSION."
  (my-files-agent-shell--codex-list-page session nil nil))

(defun my-files-agent-shell--codex-initialize (session)
  "Initialize Codex query SESSION, then load its tasks."
  (codex-ide--request-async
   session
   "initialize"
   '((clientInfo . ((name . "my-files-agent-shell")
                    (title . "My Files Agent Chats")
                    (version . "1.0")))
     (capabilities . ((experimentalApi . t))))
   (lambda (_result error-data)
     (if error-data
         (my-files-agent-shell--codex-refresh-failed error-data)
       (setq my-files-agent-shell--codex-session-initialized t)
       (codex-ide--set-session-status session "idle" 'initialized)
       (my-files-agent-shell--codex-list-threads session)))))

(defun my-files-agent-shell--codex-refresh-due-p ()
  "Return non-nil when cached Codex tasks should be refreshed."
  (or (null my-files-agent-shell--codex-last-refresh-time)
      (>= (- (float-time) my-files-agent-shell--codex-last-refresh-time)
          my-files-agent-shell-codex-refresh-interval)))

(defun my-files-agent-shell--refresh-codex-threads (&optional force)
  "Refresh cached Codex tasks asynchronously.

When FORCE is non-nil, ignore the normal refresh interval."
  (when (and (not my-files-agent-shell--codex-refreshing)
             (or force (my-files-agent-shell--codex-refresh-due-p)))
    (setq my-files-agent-shell--codex-refreshing t
          my-files-agent-shell--codex-error nil)
    (condition-case error-data
        (progn
          (unless (require 'codex-ide nil t)
            (user-error "Codex IDE is not installed"))
          (unless (my-files-agent-shell--codex-session-live-p)
            (let* ((directory
                    (my-files-agent-shell--canonical-directory
                     my-files-agent-shell-root-directory))
                   (existing
                    (codex-ide--query-only-session-for-directory directory)))
              (setq my-files-agent-shell--codex-session
                    (or existing
                        (let ((default-directory directory))
                          (unless (executable-find codex-ide-cli-path)
                            (user-error "Codex CLI is not available"))
                          (codex-ide--create-query-session)))
                    my-files-agent-shell--codex-session-initialized
                    (and existing
                         (string= (codex-ide-session-status existing)
                                  "idle")))))
          (if my-files-agent-shell--codex-session-initialized
              (my-files-agent-shell--codex-list-threads
               my-files-agent-shell--codex-session)
            (my-files-agent-shell--codex-initialize
             my-files-agent-shell--codex-session)))
      (error
       (my-files-agent-shell--codex-refresh-failed error-data)))))

(defun my-files-agent-shell--live-session-id (buffer)
  "Return the agent session ID associated with live BUFFER."
  (with-current-buffer buffer
    (and (boundp 'agent-shell--state)
         (or (map-nested-elt agent-shell--state '(:session :id))
             (map-elt agent-shell--state :resume-session-id)))))

(defun my-files-agent-shell--transcript-field (label)
  "Return the value of bold transcript header field LABEL at point."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward
           (format "^\\*\\*%s:\\*\\*[ \\t]+\\(.+\\)$"
                   (regexp-quote label))
           nil t)
      (string-trim (match-string-no-properties 1)))))

(defun my-files-agent-shell--transcript-title ()
  "Return a saved transcript's first non-empty user-prompt line."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^## User\\(?: ([^)]+)\\)?[ \\t]*$" nil t)
      (forward-line 1)
      (while (and (not (eobp))
                  (looking-at-p "^[ \\t]*$"))
        (forward-line 1))
      (unless (eobp)
        (truncate-string-to-width
         (string-trim
          (buffer-substring-no-properties
           (line-beginning-position) (line-end-position)))
         80 nil nil "…")))))

(defun my-files-agent-shell--read-transcript (file project)
  "Return saved chat metadata parsed from transcript FILE in PROJECT."
  (let* ((attributes (file-attributes file))
         (modified (file-attribute-modification-time attributes))
         (stamp (list modified (file-attribute-size attributes)))
         (cached (gethash file
                          my-files-agent-shell--transcript-metadata-cache)))
    (if (equal stamp (car-safe cached))
        (cdr cached)
      (let ((entry
             (with-temp-buffer
               ;; Session metadata and the first prompt are near the start.
               ;; Bounding and caching this read keeps long, tool-heavy
               ;; transcripts out of routine panel refreshes.
               (insert-file-contents file nil 0 65536)
               (when-let* ((session-id
                            (my-files-agent-shell--transcript-field
                             "Session ID")))
                 (list :session-id session-id
                       :agent (my-files-agent-shell--transcript-field "Agent")
                       :started (my-files-agent-shell--transcript-field
                                 "Started")
                       :title (or (my-files-agent-shell--transcript-title)
                                  (file-name-base file))
                       :transcript file
                       :project project
                       :modified (float-time modified))))))
        (puthash file (cons stamp entry)
                 my-files-agent-shell--transcript-metadata-cache)
        entry))))

(defun my-files-agent-shell--discover-saved-chats (project live-session-ids)
  "Return saved PROJECT chats, excluding LIVE-SESSION-IDS and duplicates."
  (let ((directory (expand-file-name ".agent-shell/transcripts" project))
        entries
        (seen (make-hash-table :test #'equal)))
    (when (file-directory-p directory)
      (dolist (file (directory-files directory t "\\.md\\'" t))
        (when-let* ((entry
                     (condition-case nil
                         (my-files-agent-shell--read-transcript file project)
                       (file-error nil))))
          (push entry entries)))
      (setq entries
            (sort entries
                  (lambda (left right)
                    (> (plist-get left :modified)
                       (plist-get right :modified)))))
      (seq-filter
       (lambda (entry)
         (let ((session-id (plist-get entry :session-id)))
           (when (and (not (member session-id live-session-ids))
                      (not (gethash session-id seen)))
             (puthash session-id t seen)
             t)))
       entries))))

(defun my-files-agent-shell--discover-saved-chats-in-directories
    (directories live-session-ids)
  "Return unique saved chats below DIRECTORIES, excluding LIVE-SESSION-IDS."
  (let ((entries
         (apply #'append
                (mapcar
                 (lambda (directory)
                   (my-files-agent-shell--discover-saved-chats
                    directory live-session-ids))
                 directories)))
        (seen (make-hash-table :test #'equal)))
    (seq-filter
     (lambda (entry)
       (let ((session-id (plist-get entry :session-id)))
         (unless (gethash session-id seen)
           (puthash session-id t seen)
           t)))
     (sort entries
           (lambda (left right)
             (> (plist-get left :modified)
                (plist-get right :modified)))))))

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
  (let ((start (point)))
    (insert-text-button
     (concat (if selected "● " "  ") label)
     'action action
     'my-files-agent-shell-path path
     'my-files-agent-shell-selected selected
     'follow-link t
     'help-echo (or help path)
     'face (if selected 'my-files-agent-shell-selected 'default))
    (when selected
      (setq my-files-agent-shell--selected-path-button
            (button-at start))))
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

(defun my-files-agent-shell--chat-status-symbol (buffer)
  "Return the status symbol for agent-shell BUFFER."
  (or (ignore-errors (agent-shell-status :shell-buffer buffer))
      'starting))

(defun my-files-agent-shell--chat-status (buffer)
  "Return a display status for agent-shell BUFFER."
  (symbol-name (my-files-agent-shell--chat-status-symbol buffer)))

(defun my-files-agent-shell--conversation-stage (key)
  "Return conversation KEY's user-assigned workflow stage."
  (plist-get (my-files-agent-shell--conversation-state key) :stage))

(defun my-files-agent-shell--conversation-archived-p (key)
  "Return non-nil when conversation KEY is archived."
  (plist-get (my-files-agent-shell--conversation-state key) :archived))

(defun my-files-agent-shell--insert-conversation-action
    (label action key help)
  "Insert a secondary LABEL button invoking ACTION for KEY with HELP text."
  (insert "  ")
  (insert-text-button
   label
   'action action
   'my-files-agent-shell-conversation-key key
   'my-files-agent-shell-section my-files-agent-shell--rendering-section
   'my-files-agent-shell-secondary-action t
   'follow-link t
   'help-echo help
   'face 'my-files-agent-shell-muted))

(defun my-files-agent-shell--insert-conversation-actions (key)
  "Insert workflow and visibility actions for conversation KEY."
  (let ((stage (my-files-agent-shell--conversation-stage key))
        (archived (my-files-agent-shell--conversation-archived-p key)))
    (insert (propertize
             (format "  {%s}"
                     (my-files-agent-shell--workflow-stage-label stage))
             'face 'my-files-agent-shell-muted))
    (if (not key)
        (insert (propertize "  Waiting for session ID"
                            'face 'my-files-agent-shell-muted))
      (my-files-agent-shell--insert-conversation-action
       "Move" #'my-files-agent-shell--move-conversation-button key
       "Assign a workflow stage")
      (if archived
          (my-files-agent-shell--insert-conversation-action
           "Restore" #'my-files-agent-shell--restore-conversation-button key
           "Return this conversation to Active Conversations")
        (my-files-agent-shell--insert-conversation-action
         "Archive" #'my-files-agent-shell--archive-conversation-button key
         "Show this conversation only under Archived")))))

(defun my-files-agent-shell--insert-chat-button (buffer)
  "Insert a button that opens agent-shell BUFFER."
  (let* ((title (my-files-agent-shell--chat-title buffer))
         (key (my-files-agent-shell--live-conversation-key buffer))
         (status-label (concat "[" (my-files-agent-shell--chat-status buffer)
                               "]")))
    (insert " ")
    (insert-text-button
     (format "%s %s" status-label title)
     'action #'my-files-agent-shell--open-chat
     'my-files-agent-shell-buffer buffer
     'my-files-agent-shell-conversation-key key
     'my-files-agent-shell-section my-files-agent-shell--rendering-section
     'my-files-agent-shell-action 'open
     'follow-link t
     'help-echo (format "Open %s" (buffer-name buffer))
     'face 'default)
    (my-files-agent-shell--insert-conversation-actions key)
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

(defun my-files-agent-shell--insert-codex-chat-button (thread)
  "Insert a workflow-controlled row for Codex THREAD."
  (let* ((title (my-files-agent-shell--codex-thread-title thread))
         (key (my-files-agent-shell--codex-conversation-key thread))
         (status (my-files-agent-shell--codex-thread-status thread))
         (status-label (if (string= status "active")
                           "[codex:active]"
                         "[codex]")))
    (insert " ")
    (insert-text-button
     (format "%s %s" status-label title)
     'action #'my-files-agent-shell--open-codex-chat
     'my-files-agent-shell-codex-entry thread
     'my-files-agent-shell-conversation-key key
     'my-files-agent-shell-section my-files-agent-shell--rendering-section
     'my-files-agent-shell-action 'open
     'follow-link t
     'help-echo "Resume this Codex task in Agent Shell"
     'face 'default)
    (my-files-agent-shell--insert-conversation-actions key)
    (insert "\n")))

(defun my-files-agent-shell--open-codex-chat (button)
  "Resume the Codex task represented by BUTTON in Agent Shell."
  (let* ((thread (button-get button 'my-files-agent-shell-codex-entry))
         (thread-id (alist-get 'id thread))
         (directory (or (alist-get 'cwd thread)
                        my-files-agent-shell--selected-project
                        my-files-agent-shell--selected-area)))
    (unless thread-id
      (user-error "That Codex task has no thread id"))
    (my-files-agent-shell--start-resumed-chat
     thread-id "Codex" directory)))

(defun my-files-agent-shell--conversation-key-at-point ()
  "Return the stable key of the highlighted conversation."
  (or (and-let* ((button (button-at (point))))
        (button-get button 'my-files-agent-shell-conversation-key))
      (user-error "Highlight a conversation with a stable session ID first")))

(defun my-files-agent-shell--read-workflow-stage (current)
  "Prompt for a workflow stage, defaulting to CURRENT."
  (let* ((labels (mapcar #'cdr my-files-agent-shell--workflow-stages))
         (current-label (my-files-agent-shell--workflow-stage-label current))
         (selected
          (completing-read "Move conversation to: " labels nil t nil nil
                           current-label)))
    (car (rassoc selected my-files-agent-shell--workflow-stages))))

(defun my-files-agent-shell--move-conversation (key)
  "Prompt for and persist conversation KEY's workflow stage."
  (let* ((current (my-files-agent-shell--conversation-stage key))
         (stage (my-files-agent-shell--read-workflow-stage current)))
    (unless (eq current stage)
      (my-files-agent-shell--set-conversation-stage key stage)
      (my-files-agent-shell--schedule-refresh)
      (message "Moved conversation to %s"
               (my-files-agent-shell--workflow-stage-label stage)))))

(defun my-files-agent-shell--move-conversation-button (button)
  "Move the conversation represented by BUTTON to a workflow stage."
  (my-files-agent-shell--move-conversation
   (button-get button 'my-files-agent-shell-conversation-key)))

(defun my-files-agent-shell-move-at-point ()
  "Move the highlighted conversation to a user-selected workflow stage."
  (interactive)
  (my-files-agent-shell--move-conversation
   (my-files-agent-shell--conversation-key-at-point)))

(defun my-files-agent-shell-archive-at-point ()
  "Show the highlighted conversation only under Archived."
  (interactive)
  (let ((key (my-files-agent-shell--conversation-key-at-point)))
    (when (my-files-agent-shell--conversation-archived-p key)
      (user-error "That conversation is already archived"))
    (when (yes-or-no-p "Archive this conversation? ")
      (my-files-agent-shell--set-conversation-archived key t)
      (my-files-agent-shell--schedule-refresh)
      (message "Archived conversation"))))

(defun my-files-agent-shell--archive-conversation-button (button)
  "Archive the conversation represented by BUTTON."
  (let ((key (button-get button 'my-files-agent-shell-conversation-key)))
    (when (yes-or-no-p "Archive this conversation? ")
      (my-files-agent-shell--set-conversation-archived key t)
      (my-files-agent-shell--schedule-refresh)
      (message "Archived conversation"))))

(defun my-files-agent-shell--restore-conversation (key)
  "Restore archived conversation KEY to the active lists."
  (unless (my-files-agent-shell--conversation-archived-p key)
    (user-error "That conversation is not archived"))
  (my-files-agent-shell--set-conversation-archived key nil)
  (my-files-agent-shell--schedule-refresh)
  (message "Restored conversation"))

(defun my-files-agent-shell--restore-conversation-button (button)
  "Restore the archived conversation represented by BUTTON."
  (my-files-agent-shell--restore-conversation
   (button-get button 'my-files-agent-shell-conversation-key)))

(defun my-files-agent-shell-restore-at-point ()
  "Restore the highlighted archived conversation."
  (interactive)
  (my-files-agent-shell--restore-conversation
   (my-files-agent-shell--conversation-key-at-point)))

(defun my-files-agent-shell--agent-config (agent-name)
  "Return the installed agent-shell config matching AGENT-NAME."
  (when agent-name
    (seq-find
     (lambda (config)
       (seq-some
        (lambda (key)
          (when-let* ((value (map-elt config key)))
            (string-equal-ignore-case agent-name (format "%s" value))))
        '(:mode-line-name :buffer-name :identifier)))
     (ignore-errors (agent-shell--resolved-agent-configs)))))

(defun my-files-agent-shell--ensure-agent-shell-ready ()
  "Signal an actionable error when agent-shell's dependency is incompatible."
  (unless (fboundp 'shell-maker-start-v2)
    (user-error
     (concat "agent-shell requires shell-maker 0.97.2 or newer; "
             "upgrade shell-maker and restart Emacs"))))

(defun my-files-agent-shell--start-resumed-chat
    (session-id agent-name directory)
  "Resume SESSION-ID for AGENT-NAME in DIRECTORY and show it in the main pane."
  (my-files-agent-shell--ensure-agent-shell-ready)
  (unless (window-live-p my-files-agent-shell--main-window)
    (user-error "The My Files main window is no longer available"))
  (unless directory
    (user-error "That chat has no working directory"))
  (let* ((config (my-files-agent-shell--agent-config agent-name))
         (resume-directory
          (my-files-agent-shell--canonical-directory directory))
         (agent-shell-session-restore-verbosity
          my-files-agent-shell-session-restore-verbosity)
         (buffer
          (with-selected-window my-files-agent-shell--main-window
            (let ((default-directory resume-directory))
              (if config
                  (agent-shell-start :config config :session-id session-id)
                (let ((agent-shell-preferred-agent-config nil))
                  (agent-shell-resume-session session-id)))))))
    ;; Agent startup completes asynchronously.  Keep the display policy
    ;; buffer-local so session/load callbacks see it after this call returns.
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (setq-local agent-shell-session-restore-verbosity
                    my-files-agent-shell-session-restore-verbosity))
      (set-window-buffer my-files-agent-shell--main-window buffer)
      (select-window my-files-agent-shell--main-window))
    (my-files-agent-shell--schedule-refresh)
    buffer))

(defun my-files-agent-shell--resume-chat (button)
  "Resume the saved agent-shell session represented by BUTTON."
  (let* ((entry (button-get button 'my-files-agent-shell-entry))
         (session-id (plist-get entry :session-id))
         (agent-name (plist-get entry :agent))
         (directory (plist-get entry :project)))
    (my-files-agent-shell--start-resumed-chat
     session-id agent-name directory)))

(defun my-files-agent-shell--new-chat (_button)
  "Start a new agent-shell chat for the selected project."
  (my-files-agent-shell--ensure-agent-shell-ready)
  (unless my-files-agent-shell--selected-project
    (user-error "Select a project first"))
  (unless (window-live-p my-files-agent-shell--main-window)
    (user-error "The My Files main window is no longer available"))
  (let* ((project
          (my-files-agent-shell--canonical-directory
           my-files-agent-shell--selected-project))
         (buffer
          (with-selected-window my-files-agent-shell--main-window
            (let ((default-directory project)
                  (agent-shell-session-strategy 'new))
              (agent-shell '(4))))))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (setq-local my-files-agent-shell--assigned-project project))))
  (my-files-agent-shell--schedule-refresh))

(defun my-files-agent-shell--main-agent-chat-buffer ()
  "Return the live agent-shell buffer displayed in the main window."
  (when (window-live-p my-files-agent-shell--main-window)
    (let ((buffer (window-buffer my-files-agent-shell--main-window)))
      (and (memq buffer (agent-shell-buffers)) buffer))))

(defun my-files-agent-shell--assign-main-chat-to-project (_button)
  "Assign the main window's agent-shell chat to the selected project."
  (unless my-files-agent-shell--selected-project
    (user-error "Select a project first"))
  (let ((buffer (my-files-agent-shell--main-agent-chat-buffer))
        (project
         (my-files-agent-shell--canonical-directory
          my-files-agent-shell--selected-project)))
    (unless buffer
      (user-error "The main window is not showing a live agent-shell chat"))
    (with-current-buffer buffer
      (setq-local my-files-agent-shell--assigned-project project))
    (my-files-agent-shell--schedule-refresh)
    (message "Assigned %s to %s"
             (my-files-agent-shell--chat-title buffer)
             (my-files-agent-shell--path-name project))))

(defun my-files-agent-shell--subscribe-chat (buffer)
  "Refresh the browser when BUFFER changes lifecycle state or is killed."
  (with-current-buffer buffer
    (dolist (event my-files-agent-shell--chat-refresh-events)
      (unless (memq event my-files-agent-shell--subscribed-events)
        (agent-shell-subscribe-to
         :shell-buffer buffer
         :event event
         :on-event (lambda (_event)
                     (my-files-agent-shell--schedule-refresh)))
        (push event my-files-agent-shell--subscribed-events)))
    (add-hook 'kill-buffer-hook
              #'my-files-agent-shell--schedule-refresh nil t)))

(defun my-files-agent-shell--render-areas (areas)
  "Render the area panel using AREAS."
  (with-current-buffer
      (my-files-agent-shell--panel-buffer
       my-files-agent-shell--area-buffer-name
       #'my-files-agent-shell-area-mode)
    (let ((selection-key (my-files-agent-shell--selected-button-key))
          (inhibit-read-only t))
      (erase-buffer)
      (setq my-files-agent-shell--selected-path-button nil)
      (my-files-agent-shell--insert-heading "AREAS")
      (if areas
          (dolist (area areas)
            (my-files-agent-shell--insert-path-button
             (my-files-agent-shell--path-name area)
             area
             (equal area my-files-agent-shell--selected-area)
             #'my-files-agent-shell--select-area))
        (my-files-agent-shell--insert-empty "No areas found"))
      (my-files-agent-shell--restore-button-selection selection-key))))

(defun my-files-agent-shell--render-projects (projects)
  "Render the project panel using PROJECTS."
  (with-current-buffer
      (my-files-agent-shell--panel-buffer
       my-files-agent-shell--project-buffer-name
       #'my-files-agent-shell-project-mode)
    (let ((selection-key (my-files-agent-shell--selected-button-key))
          (inhibit-read-only t))
      (erase-buffer)
      (setq my-files-agent-shell--selected-path-button nil)
      (my-files-agent-shell--insert-heading "PROJECTS")
      (if my-files-agent-shell--selected-area
          (progn
            (my-files-agent-shell--insert-path-button
             "All area chats"
             my-files-agent-shell--selected-area
             (null my-files-agent-shell--selected-project)
             #'my-files-agent-shell--select-area
             "Show chats from every project in this area")
            (if projects
                (dolist (project projects)
                  (my-files-agent-shell--insert-path-button
                   (directory-file-name
                    (file-relative-name project
                                        my-files-agent-shell--selected-area))
                   project
                   (equal project my-files-agent-shell--selected-project)
                   #'my-files-agent-shell--select-project))
              (my-files-agent-shell--insert-empty "No projects found")))
        (my-files-agent-shell--insert-empty
         "Select an area"))
      (my-files-agent-shell--restore-button-selection selection-key))))

(defun my-files-agent-shell--insert-saved-chat-button (entry)
  "Insert a button that resumes saved chat ENTRY."
  (let ((key (my-files-agent-shell--saved-conversation-key entry))
        (title (plist-get entry :title))
        (agent (or (plist-get entry :agent) "Agent"))
        (started (plist-get entry :started)))
    (insert " ")
    (insert-text-button
     (format "%-8s %s" "[saved]" title)
     'action #'my-files-agent-shell--resume-chat
     'my-files-agent-shell-entry entry
     'my-files-agent-shell-conversation-key key
     'my-files-agent-shell-section my-files-agent-shell--rendering-section
     'follow-link t
     'help-echo (format "Resume %s session%s"
                        agent
                        (if started (format " from %s" started) ""))
     'face 'default)
    (my-files-agent-shell--insert-conversation-actions key)
    (insert "\n")))

(defun my-files-agent-shell--conversation-records
    (chats saved-chats codex-threads)
  "Return normalized records for CHATS, SAVED-CHATS, and CODEX-THREADS."
  (append
   (mapcar
    (lambda (chat)
      (my-files-agent-shell--subscribe-chat chat)
      (list :kind 'live
            :value chat
            :key (my-files-agent-shell--live-conversation-key chat)))
    chats)
   (mapcar
    (lambda (entry)
      (list :kind 'saved
            :value entry
            :key (my-files-agent-shell--saved-conversation-key entry)))
    saved-chats)
   (mapcar
    (lambda (thread)
      (list :kind 'codex
            :value thread
            :key (my-files-agent-shell--codex-conversation-key thread)))
    codex-threads)))

(defun my-files-agent-shell--records-for-section (section records)
  "Return RECORDS belonging to conversation SECTION."
  (seq-filter
   (lambda (record)
     (let* ((key (plist-get record :key))
            (archived (my-files-agent-shell--conversation-archived-p key)))
       (pcase section
         ('active (not archived))
         ('archived archived)
         (_ (and (not archived)
                 (eq (my-files-agent-shell--conversation-stage key)
                     section))))))
   records))

(defun my-files-agent-shell--insert-conversation-record (record)
  "Insert normalized conversation RECORD."
  (pcase (plist-get record :kind)
    ('live
     (my-files-agent-shell--insert-chat-button (plist-get record :value)))
    ('saved
     (my-files-agent-shell--insert-saved-chat-button
      (plist-get record :value)))
    ('codex
     (my-files-agent-shell--insert-codex-chat-button
      (plist-get record :value)))
    (_ (error "Unsupported conversation record: %S" record))))

(defun my-files-agent-shell--chat-section-collapsed-p (category)
  "Return non-nil when chat CATEGORY is collapsed in this buffer."
  (memq category my-files-agent-shell--collapsed-chat-sections))

(defun my-files-agent-shell--set-chat-section-button-state
    (button collapsed)
  "Display BUTTON as COLLAPSED or expanded."
  (let ((inhibit-read-only t))
    (put-text-property (button-start button)
                       (1+ (button-start button))
                       'display (if collapsed "▸" "▾"))
    (button-put button 'help-echo
                (format "%s %s"
                        (if collapsed "Expand" "Collapse")
                        (button-get button 'my-files-agent-shell-title)))))

(defun my-files-agent-shell--toggle-chat-section (button)
  "Toggle the chat section represented by BUTTON."
  (let* ((category (button-get button 'my-files-agent-shell-category))
         (body (button-get button 'my-files-agent-shell-body-overlay))
         (collapsed (not (overlay-get body 'invisible))))
    (unless (overlay-buffer body)
      (user-error "That chat section is no longer available"))
    (overlay-put body 'invisible collapsed)
    (if collapsed
        (cl-pushnew category my-files-agent-shell--collapsed-chat-sections)
      (setq my-files-agent-shell--collapsed-chat-sections
            (delq category my-files-agent-shell--collapsed-chat-sections)))
    (my-files-agent-shell--set-chat-section-button-state button collapsed)
    (goto-char (button-start button))
    (my-files-agent-shell--resize-panels-to-content)))

(defun my-files-agent-shell--insert-chat-section
    (category title count insert-items)
  "Insert collapsible chat CATEGORY named TITLE containing COUNT items.

Call INSERT-ITEMS to render the section body when COUNT is positive."
  (let ((collapsed (my-files-agent-shell--chat-section-collapsed-p category))
        button)
    (insert " ")
    (let ((button-start (point)))
      (insert-text-button
       (format "▾ %s (%d)" title count)
       'action #'my-files-agent-shell--toggle-chat-section
       'my-files-agent-shell-category category
       'my-files-agent-shell-title title
       'follow-link t
       'face 'my-files-agent-shell-heading)
      (setq button (button-at button-start)))
    (insert "\n")
    (let ((body-start (point)))
      (if (> count 0)
          (let ((my-files-agent-shell--rendering-section category))
            (funcall insert-items))
        (my-files-agent-shell--insert-empty "No chats"))
      (insert "\n")
      (let ((body (make-overlay body-start (point) nil t nil)))
        (overlay-put body 'invisible collapsed)
        (overlay-put body 'evaporate t)
        (button-put button 'my-files-agent-shell-body-overlay body)
        (my-files-agent-shell--set-chat-section-button-state
         button collapsed)))))

(defun my-files-agent-shell--render-chat-lists
    (chats saved-chats &optional codex-threads)
  "Render live CHATS, SAVED-CHATS, and CODEX-THREADS in the chat panel."
  (with-current-buffer
      (my-files-agent-shell--panel-buffer
       my-files-agent-shell--chat-buffer-name
       #'my-files-agent-shell-chat-mode)
    (let ((selection-key (my-files-agent-shell--selected-button-key))
          (inhibit-read-only t))
      (erase-buffer)
      (my-files-agent-shell--insert-heading "AGENT CHATS")
      (if (or my-files-agent-shell--selected-project
              my-files-agent-shell--selected-area)
          (progn
            (when my-files-agent-shell--selected-project
              (insert " ")
              (insert-text-button
               "+ New chat"
               'action #'my-files-agent-shell--new-chat
               'follow-link t
               'help-echo "Start a new agent-shell chat for this project"
               'face 'font-lock-keyword-face)
              (insert "\n")
              (when-let* ((main-chat
                           (my-files-agent-shell--main-agent-chat-buffer)))
                (unless (memq main-chat chats)
                  (insert " ")
                  (insert-text-button
                   "+ Assign current chat here"
                   'action #'my-files-agent-shell--assign-main-chat-to-project
                   'follow-link t
                   'help-echo
                   "Show the main window's live agent-shell chat in this project"
                   'face 'font-lock-keyword-face)
                  (insert "\n"))))
            (my-files-agent-shell--insert-empty
             "m moves stage · a archives · u restores")
            (when my-files-agent-shell--codex-error
              (my-files-agent-shell--insert-empty
               (format "Codex refresh failed: %s"
                       my-files-agent-shell--codex-error)))
            (insert "\n")
            (let ((records
                   (my-files-agent-shell--conversation-records
                    chats saved-chats codex-threads)))
              (dolist (section my-files-agent-shell--chat-sections)
                (let* ((category (car section))
                       (section-records
                        (my-files-agent-shell--records-for-section
                         category records)))
                  (my-files-agent-shell--insert-chat-section
                   category (cdr section) (length section-records)
                   (lambda ()
                     (dolist (record section-records)
                       (my-files-agent-shell--insert-conversation-record
                        record))))))))
        (my-files-agent-shell--insert-empty "Select an area"))
      (my-files-agent-shell--restore-button-selection selection-key))))

;;;###autoload
(defun my-files-agent-shell-refresh ()
  "Rescan projects, agent-shell chats, and cached Codex tasks."
  (interactive)
  (let* ((force-codex-refresh (called-interactively-p 'interactive))
         (areas (my-files-agent-shell--discover-areas))
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
      (setq my-files-agent-shell--selected-project selected-project)
      (let* ((all-chat-buffers (agent-shell-buffers))
             (scope (or my-files-agent-shell--selected-project
                        my-files-agent-shell--selected-area))
             (chats
              (my-files-agent-shell--scope-chat-buffers
               scope all-chat-buffers))
             (saved-chat-directories
              (if my-files-agent-shell--selected-project
                  (list my-files-agent-shell--selected-project)
                (and my-files-agent-shell--selected-area
                     (cons my-files-agent-shell--selected-area projects))))
             (saved-chats
              (and saved-chat-directories
                   (my-files-agent-shell--discover-saved-chats-in-directories
                    saved-chat-directories
                    (delq nil (mapcar #'my-files-agent-shell--live-session-id
                                      chats)))))
             (codex-threads
              (my-files-agent-shell--scope-codex-threads
               scope
               my-files-agent-shell--codex-threads)))
        (setq my-files-agent-shell--known-chat-buffers all-chat-buffers)
        (my-files-agent-shell--render-areas areas)
        (my-files-agent-shell--render-projects projects)
        (my-files-agent-shell--render-chat-lists
         chats saved-chats codex-threads)
        (my-files-agent-shell--update-panel-focus-faces)
        (my-files-agent-shell--resize-panels-to-content)
        (my-files-agent-shell--refresh-codex-threads
         force-codex-refresh)))))

(defun my-files-agent-shell--same-buffer-set-p (left right)
  "Return non-nil when LEFT and RIGHT contain the same buffer objects."
  (and (= (length left) (length right))
       (seq-every-p (lambda (buffer) (memq buffer right)) left)))

(defun my-files-agent-shell--buffer-list-updated ()
  "Refresh only when the set of Agent Shell buffers changed."
  (let ((buffers (agent-shell-buffers)))
    (unless (my-files-agent-shell--same-buffer-set-p
             buffers my-files-agent-shell--known-chat-buffers)
      (setq my-files-agent-shell--known-chat-buffers buffers)
      (my-files-agent-shell--schedule-refresh))))

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

(defun my-files-agent-shell--start-codex-refresh-timer ()
  "Start periodic Codex task refreshes for the visible browser."
  (when (timerp my-files-agent-shell--codex-refresh-timer)
    (cancel-timer my-files-agent-shell--codex-refresh-timer))
  (setq my-files-agent-shell--codex-refresh-timer
        (run-at-time
         my-files-agent-shell-codex-refresh-interval
         my-files-agent-shell-codex-refresh-interval
         (lambda ()
           (when (my-files-agent-shell--visible-p)
             (my-files-agent-shell--refresh-codex-threads t))))))

(defun my-files-agent-shell--visible-line-width ()
  "Return the display width of visible text on the current line."
  (let ((position (line-beginning-position))
        (end (line-end-position))
        (width 0))
    (while (< position end)
      (let ((next (next-char-property-change position end)))
        (unless (invisible-p position)
          (setq width
                (+ width
                   (string-width
                    (buffer-substring-no-properties position next)))))
        (setq position next)))
    width))

(defun my-files-agent-shell--panel-content-width (buffer)
  "Return the widest visible line in panel BUFFER."
  (if (not (buffer-live-p buffer))
      0
    (with-current-buffer buffer
      (save-excursion
        (save-restriction
          (widen)
          (goto-char (point-min))
          (let ((width 0))
            (while (not (eobp))
              (setq width (max width
                               (my-files-agent-shell--visible-line-width)))
              (forward-line 1))
            width))))))

(defun my-files-agent-shell--desired-panel-widths ()
  "Return preferred panel widths based on their visible text."
  (cl-mapcar
   (lambda (minimum name)
     (max minimum
          (1+ (my-files-agent-shell--panel-content-width
               (get-buffer name)))))
   (list my-files-agent-shell-area-width
         my-files-agent-shell-project-width
         my-files-agent-shell-chat-width)
   (list my-files-agent-shell--area-buffer-name
         my-files-agent-shell--project-buffer-name
         my-files-agent-shell--chat-buffer-name)))

(defun my-files-agent-shell--scaled-panel-widths
    (total-width &optional requested-widths)
  "Return three panel widths suitable for TOTAL-WIDTH.

REQUESTED-WIDTHS defaults to the three configured preferred widths.  The
combined result never exceeds half of TOTAL-WIDTH."
  (let* ((requested
          (mapcar
           (lambda (width)
             (max my-files-agent-shell-minimum-panel-width width))
           (or requested-widths
               (list my-files-agent-shell-area-width
                     my-files-agent-shell-project-width
                     my-files-agent-shell-chat-width))))
         (available
          (min (floor total-width 2)
               (- total-width my-files-agent-shell-minimum-main-width)))
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

(defun my-files-agent-shell--resize-panels-to-content ()
  "Resize live browser panels to fit text within half the workspace."
  (when (my-files-agent-shell--visible-p)
    (let* ((windows (list my-files-agent-shell--area-window
                          my-files-agent-shell--project-window
                          my-files-agent-shell--chat-window
                          my-files-agent-shell--main-window))
           (total-width (apply #'+ (mapcar #'window-total-width windows)))
           (widths
            (my-files-agent-shell--scaled-panel-widths
             total-width (my-files-agent-shell--desired-panel-widths)))
           (ignore-window-parameters t))
      ;; The panel windows are nested from left to right.  Resizing in that
      ;; order preserves earlier widths and takes any adjustment from main.
      (cl-mapc
       (lambda (window width)
         (let ((delta (- width (window-total-width window))))
           (unless (zerop delta)
             (window-resize window delta t))))
       (butlast windows)
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
      (my-files-agent-shell--focus-window my-files-agent-shell--area-window)
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
                      #'my-files-agent-shell--buffer-list-updated)
            (add-hook 'window-selection-change-functions
                      #'my-files-agent-shell--update-panel-focus-faces)
            (my-files-agent-shell-refresh)
            (my-files-agent-shell--start-codex-refresh-timer)
            (my-files-agent-shell-focus-areas))
        (error
         (remove-hook 'buffer-list-update-hook
                      #'my-files-agent-shell--buffer-list-updated)
         (remove-hook 'window-selection-change-functions
                      #'my-files-agent-shell--update-panel-focus-faces)
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
               #'my-files-agent-shell--buffer-list-updated)
  (remove-hook 'window-selection-change-functions
               #'my-files-agent-shell--update-panel-focus-faces)
  (when (timerp my-files-agent-shell--refresh-timer)
    (cancel-timer my-files-agent-shell--refresh-timer))
  (when (timerp my-files-agent-shell--codex-refresh-timer)
    (cancel-timer my-files-agent-shell--codex-refresh-timer))
  (setq my-files-agent-shell--refresh-timer nil
        my-files-agent-shell--codex-refresh-timer nil)
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
