;;; my-files-agent-shell.el --- Browse areas, projects, and agent chats -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jordan
;; Author: Jordan
;; Keywords: convenience, tools
;; Package-Requires: ((emacs "29.1") (agent-shell "0.55") (codex-ide "0.3.2"))

;; This file is not part of GNU Emacs.

;;; Commentary:

;; `my-files-agent-shell-toggle' opens a two-column workspace:
;;
;;   Agent chats | Main chat
;;
;; Press v to reveal a shallow navigation row above it:
;;
;;   Areas      | Projects
;;   Agent chats | Main chat
;;
;; Areas are immediate children of `my-files-agent-shell-root-directory'
;; containing `.area.toml'.  Projects are descendants of the selected area
;; containing `.project.toml'.  The chat panel combines live `agent-shell'
;; buffers, their saved transcripts, and Codex tasks whose working directories
;; belong to the selected project or area.  Every non-archived, non-deleted
;; conversation appears in Active Conversations and in one workflow stage:
;; In Progress, Review, Staged, or Completed.  Archiving is a non-destructive
;; browser classification that leaves the conversation only under Archived.
;; Runtime status remains visible on each row but never changes workflow stage.
;; Pressing i limits the Areas and Projects panels to scopes that contain an
;; active conversation in the In Progress workflow stage.
;; Codex-generated session titles name both live chat rows and their Emacs
;; buffers.  Agent conversations use a centered, fixed-width column: replies
;; stay left-aligned, submitted user turns use a tinted block and accent gutter,
;; and activity such as thoughts and edits starts collapsed behind a compact
;; rule.
;; A leading `▶' identifies the conversation in the main window, `●' marks
;; conversations with open buffers, and `*' marks conversations selected for a
;; batch workflow action.  Space toggles a mark and U clears all marks.  Delete
;; hides archived conversations permanently from this browser without erasing
;; their underlying Codex history or transcript.
;; Hovering displays the complete title as help text; keyboard highlighting
;; displays it in the echo area.

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

(defcustom my-files-agent-shell-chat-width 32
  "Preferred width, in columns, of the Chats window."
  :type 'natnum
  :group 'my-files-agent-shell)

(defcustom my-files-agent-shell-chat-content-maximum-width 48
  "Maximum width used when Chats grows to fit rendered content.

An explicitly configured `my-files-agent-shell-chat-width' can still exceed
this value."
  :type 'natnum
  :group 'my-files-agent-shell)

(defcustom my-files-agent-shell-navigation-height 8
  "Maximum height, in lines, of the Areas and Projects row."
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
  "File that stores conversation workflow, archive, and deletion state."
  :type 'file
  :group 'my-files-agent-shell)

(defcustom my-files-agent-shell-session-restore-verbosity 'first-last
  "How much prior chat history Agent Shell should render when resuming.

The agent resumes the complete session context regardless of this display
setting.  `first-last' keeps large histories responsive while showing enough
of the conversation to confirm that the correct session was restored.  When
Codex cannot replay a paginated history, the conversation is resumed without
visible history instead of being replaced by a new session."
  :type '(choice (const :tag "Last turn" last)
                 (const :tag "First and last turns" first-last)
                 (const :tag "Full visible history" full))
  :group 'my-files-agent-shell)

(defcustom my-files-agent-shell-chat-style-enabled t
  "Whether Agent Shell buffers use the conversation-oriented chat style."
  :type 'boolean
  :group 'my-files-agent-shell)

(defcustom my-files-agent-shell-chat-message-width 80
  "Maximum width, in columns, of user and agent messages.

The conversation column is centered when its window is wider than this.
Both user and agent turns are left-aligned.  Set this to 120 for a wider
transcript."
  :type '(integer :tag "Columns")
  :safe (lambda (value) (and (integerp value) (> value 0)))
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

(defface my-files-agent-shell-user-message
  '((((class color) (background light)) :background "gray94")
    (((class color) (background dark)) :background "gray20")
    (t :inherit highlight))
  "Face used to distinguish submitted user messages from agent replies."
  :group 'my-files-agent-shell)

(defface my-files-agent-shell-user-message-accent
  '((((class color) (background light))
     :foreground "RoyalBlue4" :weight bold)
    (((class color) (background dark))
     :foreground "LightSkyBlue" :weight bold)
    (t :inherit font-lock-keyword-face :weight bold))
  "Face used for the left gutter beside submitted user messages."
  :group 'my-files-agent-shell)

(defface my-files-agent-shell-activity-separator
  '((t :inherit shadow :weight bold :height 0.85))
  "Face used for collapsed Thought/Edit activity separators."
  :group 'my-files-agent-shell)

(defface my-files-agent-shell-activity-detail
  '((t :inherit shadow :height 0.8))
  "Face used for activity items revealed below a separator."
  :group 'my-files-agent-shell)

(defface my-files-agent-shell-activity-rule
  '((t :inherit shadow :strike-through t))
  "Face used to extend an activity separator to the column edge."
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
(defvar my-files-agent-shell--in-progress-only nil)
(defvar my-files-agent-shell--conversation-states
  (make-hash-table :test #'equal))
(defvar my-files-agent-shell--conversation-states-loaded nil)
(defvar my-files-agent-shell--conversation-state-load-error nil)
(defvar my-files-agent-shell--transcript-metadata-cache
  (make-hash-table :test #'equal))
(defconst my-files-agent-shell--transcript-metadata-cache-version 2
  "Schema version for cached transcript metadata entries.")
(defvar-local my-files-agent-shell--subscribed-events nil)
(defvar-local my-files-agent-shell--collapsed-chat-sections nil)
(defvar-local my-files-agent-shell--assigned-project nil)
(defvar-local my-files-agent-shell--highlighted-button-key nil)
(defvar-local my-files-agent-shell--selected-path-button nil)
(defvar-local my-files-agent-shell--marked-conversation-keys nil)
(defvar-local my-files-agent-shell--pending-selection-key nil)
(defvar-local my-files-agent-shell-chat-style-mode nil)
(defvar-local my-files-agent-shell--saved-expansion-settings nil)
(defvar my-files-agent-shell--rendering-section nil)
(defvar my-files-agent-shell--rendering-live-buffers nil)
(defvar my-files-agent-shell--rendering-main-chat nil)
(defvar my-files-agent-shell--echoed-conversation-title nil
  "Last browser-owned conversation title displayed in the echo area.")
(defvar my-files-agent-shell--adjusting-chat-window-margins nil)

(defconst my-files-agent-shell--workflow-stages
  '((in-progress . "In Progress")
    (review . "Review")
    (staged . "Staged")
    (completed . "Completed"))
  "User-assigned workflow stages in display order.")

(defconst my-files-agent-shell--chat-sections
  `(,@my-files-agent-shell--workflow-stages
    (active . "Active Conversations")
    (archived . "Archived"))
  "Conversation sections in display order.")

(defconst my-files-agent-shell--chat-status-events
  '(input-submitted
    turn-complete
    prompt-ready
    permission-request
    permission-response
    error)
  "Agent-shell events that change only a chat row's operational status.")

(defconst my-files-agent-shell--chat-refresh-events
  `(,@my-files-agent-shell--chat-status-events session-title-changed)
  "Agent-shell events observed by the conversation browser.")

(declare-function agent-shell-buffers "agent-shell")
(declare-function agent-shell--auto-preferred-config "agent-shell")
(declare-function agent-shell--make-boxed-message "agent-shell")
(declare-function agent-shell-cwd "agent-shell-project")
(declare-function agent-shell--send-request "agent-shell")
(declare-function agent-shell-select-config "agent-shell")
(declare-function agent-shell-start "agent-shell")
(declare-function agent-shell-status "agent-shell")
(declare-function agent-shell-subscribe-to "agent-shell")
(declare-function agent-shell--update-bootstrapping-fragment "agent-shell")
(declare-function agent-shell--resolved-agent-configs "agent-shell")
(declare-function agent-shell-chat--relabel "agent-shell-chat-mode")
(declare-function agent-shell-ui--set-group-collapsed "agent-shell-ui")
(declare-function acp-make-session-resume-request "acp")
(declare-function shell-maker-set-buffer-name "shell-maker")
(declare-function codex-ide--create-query-session "codex-ide-session")
(declare-function codex-ide--query-only-session-for-directory
                  "codex-ide-session")
(declare-function codex-ide--request-async "codex-ide-protocol")
(declare-function codex-ide--set-session-status "codex-ide-core")
(declare-function codex-ide-session-process "codex-ide-core")
(declare-function codex-ide-session-status "codex-ide-core")
(defvar agent-shell--state)
(defvar agent-shell-activity-group-expand-by-default)
(defvar agent-shell-cwd-function)
(defvar agent-shell-section-functions)
(defvar agent-shell-session-restore-verbosity)
(defvar agent-shell-thought-process-expand-by-default)
(defvar agent-shell-tool-use-expand-by-default)
(defvar codex-ide-cli-path)

(defun my-files-agent-shell--chat-column-margins (available-width)
  "Return centered margins for AVAILABLE-WIDTH columns.

The usable conversation column is no wider than
`my-files-agent-shell-chat-message-width'."
  (let* ((column-width
          (min available-width
               (max 1 my-files-agent-shell-chat-message-width)))
         (extra (max 0 (- available-width column-width)))
         (left (/ extra 2)))
    (cons left (- extra left))))

(defun my-files-agent-shell--restore-chat-window-margins (window)
  "Restore WINDOW margins saved before chat styling took ownership."
  (when-let* ((state
              (window-parameter window
                                'my-files-agent-shell-chat-column)))
    (let ((base (plist-get state :base)))
      (set-window-margins window (car base) (cdr base))
      (set-window-parameter window
                            'my-files-agent-shell-chat-column nil))))

(defun my-files-agent-shell--update-chat-window-column (window)
  "Center the styled conversation column shown in WINDOW.

When WINDOW no longer shows a styled Agent Shell buffer, restore the margins
that existed before this package changed them."
  (when (and (window-live-p window)
             (not my-files-agent-shell--adjusting-chat-window-margins))
    (let ((my-files-agent-shell--adjusting-chat-window-margins t)
          (buffer (window-buffer window)))
      (if (and (buffer-live-p buffer)
               (buffer-local-value
                'my-files-agent-shell-chat-style-mode buffer))
          (let* ((state
                  (window-parameter
                   window 'my-files-agent-shell-chat-column))
                 (current (window-margins window))
                 (available
                  (+ (window-body-width window)
                     (or (car current) 0)
                     (or (cdr current) 0)))
                 (margins
                  (with-current-buffer buffer
                    (my-files-agent-shell--chat-column-margins
                     available)))
                 (base (or (plist-get state :base) current)))
            (set-window-margins
             window
             (and (> (car margins) 0) (car margins))
             (and (> (cdr margins) 0) (cdr margins)))
            (set-window-parameter
             window 'my-files-agent-shell-chat-column
             (list :buffer buffer :base base)))
        (my-files-agent-shell--restore-chat-window-margins window)))))

(defun my-files-agent-shell--update-visible-chat-columns (&optional _frame)
  "Update the chat column in every window showing the current buffer."
  (dolist (window (get-buffer-window-list (current-buffer) nil t))
    (my-files-agent-shell--update-chat-window-column window)))

(defun my-files-agent-shell--release-chat-window-columns ()
  "Release every window margin currently owned by this chat buffer."
  (dolist (frame (frame-list))
    (dolist (window (window-list frame 'no-minibuffer))
      (when-let* ((state
                  (window-parameter
                   window 'my-files-agent-shell-chat-column))
                  ((eq (plist-get state :buffer) (current-buffer))))
        (my-files-agent-shell--restore-chat-window-margins window)))))

(defun my-files-agent-shell--chat-overlay-p (overlay category)
  "Return non-nil when OVERLAY belongs to chat CATEGORY."
  (eq (overlay-get overlay 'category) category))

(defun my-files-agent-shell--user-message-prefix ()
  "Return the left gutter used to distinguish a submitted user turn."
  (propertize "│ " 'face 'my-files-agent-shell-user-message-accent))

(defun my-files-agent-shell--style-chat-overlays ()
  "Style existing submitted user turns in the current chat buffer."
  (when my-files-agent-shell-chat-style-mode
    (let ((prefix (my-files-agent-shell--user-message-prefix)))
      (dolist (input (overlays-in (point-min) (point-max)))
        (when (my-files-agent-shell--chat-overlay-p
               input 'agent-shell-chat-me-input)
          (overlay-put input 'line-prefix prefix)
          (overlay-put input 'wrap-prefix prefix)
          (overlay-put input 'face
                       'my-files-agent-shell-user-message))))))

(defun my-files-agent-shell--activity-id-p (identifier)
  "Return non-nil when IDENTIFIER names an Agent Shell activity group."
  (and (stringp identifier)
       (string-match-p (rx "activity-" (+ digit) string-end)
                       identifier)))

(defun my-files-agent-shell--activity-state-p (state)
  "Return non-nil when Agent Shell fragment STATE belongs to activity."
  (or (my-files-agent-shell--activity-id-p
       (map-elt state :group-id))
      (and (eq (map-elt state :kind) 'group)
           (my-files-agent-shell--activity-id-p
            (map-elt state :qualified-id)))))

(defun my-files-agent-shell--style-activity-block (start end)
  "Style the activity fragment beginning at START and ending by END."
  (when-let* ((state (get-text-property start 'agent-shell-ui-state))
              ((my-files-agent-shell--activity-state-p state)))
    (let* ((header-end
            (min end
                 (save-excursion
                   (goto-char start)
                   (line-end-position))))
           (group (eq (map-elt state :kind) 'group)))
      (remove-overlays
       start (max header-end (min end (1+ start)))
       'category 'my-files-agent-shell-activity-separator)
      (when (< start header-end)
        (let ((overlay (make-overlay start header-end nil t nil)))
          (overlay-put overlay 'category
                       'my-files-agent-shell-activity-separator)
          (overlay-put overlay 'evaporate t)
          (overlay-put
           overlay 'face
           (if group
               'my-files-agent-shell-activity-separator
             'my-files-agent-shell-activity-detail))
          (when group
            (overlay-put
             overlay 'after-string
             (propertize
              " " 'display '(space :align-to right-fringe)
              'face 'my-files-agent-shell-activity-rule))))))))

(defun my-files-agent-shell--style-activity-section (range)
  "Style activity blocks described by Agent Shell RANGE."
  (when my-files-agent-shell-chat-style-mode
    (dolist (key '(:group-header :block))
      (when-let* ((block (map-elt range key))
                  (start (map-elt block :start))
                  (end (map-elt block :end)))
        (my-files-agent-shell--style-activity-block start end)))))

(defun my-files-agent-shell--activity-state-ranges ()
  "Return Agent Shell activity state ranges in the current buffer."
  (save-excursion
    (goto-char (point-min))
    (let (ranges match)
      (while (setq match
                   (text-property-search-forward
                    'agent-shell-ui-state nil
                    (lambda (_value state)
                      (my-files-agent-shell--activity-state-p state))))
        (push (list (prop-match-beginning match)
                    (prop-match-end match)
                    (prop-match-value match))
              ranges))
      (nreverse ranges))))

(defun my-files-agent-shell--collapse-existing-activity-groups ()
  "Collapse activity groups already rendered in the current buffer."
  (let (qualified-ids)
    (dolist (range (my-files-agent-shell--activity-state-ranges))
      (let ((state (nth 2 range)))
        (when (and (eq (map-elt state :kind) 'group)
                   (not (map-elt state :collapsed)))
          (cl-pushnew (map-elt state :qualified-id)
                      qualified-ids :test #'equal))))
    (dolist (qualified-id qualified-ids)
      (let ((inhibit-read-only t)
            (buffer-undo-list t))
        (agent-shell-ui--set-group-collapsed qualified-id t)))))

(defun my-files-agent-shell--style-existing-activity-fragments ()
  "Apply compact styling to all existing Agent Shell activity fragments."
  (dolist (range (my-files-agent-shell--activity-state-ranges))
    (my-files-agent-shell--style-activity-block
     (nth 0 range) (nth 1 range))))

(defun my-files-agent-shell--save-and-collapse-expansion-settings ()
  "Save Agent Shell expansion defaults and make activity compact."
  (unless my-files-agent-shell--saved-expansion-settings
    (setq-local
     my-files-agent-shell--saved-expansion-settings
     (mapcar
      (lambda (variable)
        (list variable (local-variable-p variable) (symbol-value variable)))
      '(agent-shell-activity-group-expand-by-default
        agent-shell-thought-process-expand-by-default
        agent-shell-tool-use-expand-by-default))))
  (setq-local agent-shell-activity-group-expand-by-default nil)
  (setq-local agent-shell-thought-process-expand-by-default nil)
  (setq-local agent-shell-tool-use-expand-by-default nil))

(defun my-files-agent-shell--restore-expansion-settings ()
  "Restore expansion defaults saved before enabling chat styling."
  (dolist (setting my-files-agent-shell--saved-expansion-settings)
    (let ((variable (nth 0 setting))
          (was-local (nth 1 setting))
          (value (nth 2 setting)))
      (if was-local
          (set (make-local-variable variable) value)
        (kill-local-variable variable))))
  (setq-local my-files-agent-shell--saved-expansion-settings nil))

(defun my-files-agent-shell--after-chat-relabel (&rest _ignored)
  "Reapply user-turn alignment after Agent Shell refreshes chat labels."
  (when my-files-agent-shell-chat-style-mode
    (my-files-agent-shell--style-chat-overlays)))

(defun my-files-agent-shell--enable-chat-style ()
  "Enable conversation styling in the current Agent Shell buffer."
  (my-files-agent-shell--save-and-collapse-expansion-settings)
  (add-hook 'agent-shell-section-functions
            #'my-files-agent-shell--style-activity-section nil t)
  (add-hook 'window-size-change-functions
            #'my-files-agent-shell--update-chat-window-column nil t)
  (add-hook 'window-buffer-change-functions
            #'my-files-agent-shell--update-chat-window-column nil t)
  (add-hook 'kill-buffer-hook
            #'my-files-agent-shell--release-chat-window-columns nil t)
  (my-files-agent-shell--collapse-existing-activity-groups)
  (my-files-agent-shell--style-existing-activity-fragments)
  (when (fboundp 'agent-shell-chat--relabel)
    (agent-shell-chat--relabel))
  (my-files-agent-shell--style-chat-overlays)
  (my-files-agent-shell--update-visible-chat-columns))

(defun my-files-agent-shell--disable-chat-style ()
  "Remove conversation styling from the current Agent Shell buffer."
  (remove-hook 'agent-shell-section-functions
               #'my-files-agent-shell--style-activity-section t)
  (remove-hook 'window-size-change-functions
               #'my-files-agent-shell--update-chat-window-column t)
  (remove-hook 'window-buffer-change-functions
               #'my-files-agent-shell--update-chat-window-column t)
  (remove-hook 'kill-buffer-hook
               #'my-files-agent-shell--release-chat-window-columns t)
  (remove-overlays (point-min) (point-max)
                   'category 'my-files-agent-shell-activity-separator)
  (dolist (overlay (overlays-in (point-min) (point-max)))
    (when (my-files-agent-shell--chat-overlay-p
           overlay 'agent-shell-chat-me-input)
      (overlay-put overlay 'face nil)
      (overlay-put overlay 'my-files-agent-shell-message-width nil)))
  (my-files-agent-shell--restore-expansion-settings)
  (my-files-agent-shell--release-chat-window-columns)
  (when (fboundp 'agent-shell-chat--relabel)
    (agent-shell-chat--relabel)))

(define-minor-mode my-files-agent-shell-chat-style-mode
  "Use a compact, visually separated conversation layout."
  :lighter nil
  :group 'my-files-agent-shell
  (cond
   ((not my-files-agent-shell-chat-style-mode)
    (my-files-agent-shell--disable-chat-style))
   ((derived-mode-p 'agent-shell-mode)
    (my-files-agent-shell--enable-chat-style))
   (t
    (setq my-files-agent-shell-chat-style-mode nil)
    (user-error "Chat styling only applies to Agent Shell buffers"))))

(defun my-files-agent-shell--maybe-enable-chat-style ()
  "Enable manager chat styling when configured."
  (when my-files-agent-shell-chat-style-enabled
    (my-files-agent-shell-chat-style-mode 1)))

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
                      (archived-value (alist-get 'archived entry))
                      (deleted-value (alist-get 'deleted entry)))
                  (unless (and (stringp key)
                               (not (string-empty-p key))
                               (stringp stage-name)
                               (memq archived-value '(:json-false t))
                               (memq deleted-value '(nil :json-false t)))
                    (error "Invalid conversation state: %S" entry))
                  (when (gethash key seen)
                    (error "Duplicate conversation state: %s" key))
                  (let ((stage (intern-soft stage-name))
                        (archived (eq archived-value t))
                        (deleted (eq deleted-value t)))
                    (unless (my-files-agent-shell--workflow-stage-p stage)
                      (error "Invalid workflow stage for %s: %S" key stage))
                    (puthash key t seen)
                    (puthash key
                             (list :stage stage
                                   :archived archived
                                   :deleted deleted)
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
                              :json-false))
               (deleted . ,(if (plist-get state :deleted)
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
      '(:stage in-progress :archived nil :deleted nil)))

(defun my-files-agent-shell--store-conversation-state (key state)
  "Persist STATE for conversation KEY, rolling back on failure."
  (unless key
    (user-error "This conversation is still starting and has no stable ID"))
  (let* ((missing (make-symbol "missing"))
         (previous (gethash key my-files-agent-shell--conversation-states
                            missing))
         (default-state
          (equal state '(:stage in-progress :archived nil :deleted nil))))
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

(defun my-files-agent-shell--set-conversation-deleted (key deleted)
  "Set conversation KEY's local tombstone state to DELETED."
  (let ((state (copy-sequence
                (my-files-agent-shell--conversation-state key))))
    (my-files-agent-shell--store-conversation-state
     key (plist-put state :deleted (and deleted t)))))

(defun my-files-agent-shell--conversation-key (kind identifier)
  "Return a stable conversation key for KIND and IDENTIFIER."
  (when identifier
    (format "%s:%s" kind identifier)))

(defun my-files-agent-shell--known-codex-session-p (session-id)
  "Return non-nil when SESSION-ID belongs to a cached Codex task."
  (and session-id
       (seq-some
        (lambda (thread)
          (equal (alist-get 'id thread) session-id))
        my-files-agent-shell--codex-threads)))

(defun my-files-agent-shell--session-conversation-key
    (session-id &optional codex-session)
  "Return the canonical conversation key for SESSION-ID.

CODEX-SESSION is non-nil when the caller knows the ID came from Codex.  A
persisted Agent Shell key takes precedence for compatibility with workflow
changes made before live and cached representations were coalesced."
  (when session-id
    (my-files-agent-shell--load-conversation-states)
    (let ((agent-key
           (my-files-agent-shell--conversation-key 'agent session-id))
          (codex-key
           (my-files-agent-shell--conversation-key 'codex session-id)))
      (cond
       ((gethash agent-key my-files-agent-shell--conversation-states)
        agent-key)
       ((gethash codex-key my-files-agent-shell--conversation-states)
        codex-key)
       ((or codex-session
            (my-files-agent-shell--known-codex-session-p session-id))
        codex-key)
       (agent-key)))))

(defun my-files-agent-shell--live-conversation-key (buffer)
  "Return the stable conversation key for live Agent Shell BUFFER."
  (my-files-agent-shell--session-conversation-key
   (my-files-agent-shell--live-session-id buffer)))

(defun my-files-agent-shell--saved-conversation-key (entry)
  "Return the stable conversation key for saved transcript ENTRY."
  (my-files-agent-shell--session-conversation-key
   (plist-get entry :session-id)))

(defun my-files-agent-shell--codex-conversation-key (thread)
  "Return the stable conversation key for Codex THREAD."
  (my-files-agent-shell--session-conversation-key
   (alist-get 'id thread) t))

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
  "v" #'my-files-agent-shell-toggle-navigation-panels
  "SPC" #'my-files-agent-shell-toggle-mark-at-point
  "i" #'my-files-agent-shell-toggle-in-progress-filter
  "a" #'my-files-agent-shell-archive-at-point
  "d" #'my-files-agent-shell-delete-at-point
  "m" #'my-files-agent-shell-move-at-point
  "u" #'my-files-agent-shell-restore-at-point
  "U" #'my-files-agent-shell-unmark-all
  "RET" #'push-button
  "g" #'my-files-agent-shell-refresh
  "q" #'my-files-agent-shell-close)

(defun my-files-agent-shell--highlighted-conversation-title (&optional frame)
  "Return the selected conversation title in FRAME, or nil."
  (let ((window (frame-selected-window (or frame (selected-frame)))))
    (when (window-live-p window)
      (with-current-buffer (window-buffer window)
        (when (derived-mode-p 'my-files-agent-shell-chat-mode)
          (when-let* ((button (button-at (window-point window))))
            (button-get
             button 'my-files-agent-shell-conversation-title)))))))

(defun my-files-agent-shell--clear-conversation-echo ()
  "Clear the echo area when it still contains the browser-owned title."
  (when my-files-agent-shell--echoed-conversation-title
    (when (equal (current-message)
                 my-files-agent-shell--echoed-conversation-title)
      (let ((message-log-max nil))
        (message nil)))
    (setq my-files-agent-shell--echoed-conversation-title nil)))

(defun my-files-agent-shell--update-conversation-echo (&optional frame)
  "Show FRAME's highlighted conversation title in the echo area."
  (if-let* ((title (my-files-agent-shell--highlighted-conversation-title
                    frame)))
      (progn
        (setq my-files-agent-shell--echoed-conversation-title title)
        (unless (equal (current-message) title)
          (let ((message-log-max nil))
            (message "%s" title))))
    (my-files-agent-shell--clear-conversation-echo)))

(define-derived-mode my-files-agent-shell-mode special-mode "My Files"
  "Base mode for My Files browser panels."
  (setq-local truncate-lines t
              cursor-type nil
              mode-line-format '(" " mode-name " ")
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
  "Mode for the My Files agent-shell chat panel."
  (add-hook 'post-command-hook
            #'my-files-agent-shell--update-conversation-echo nil t))

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
  (let* ((window (get-buffer-window (current-buffer) t))
         (position (if (window-live-p window)
                       (window-point window)
                     (point))))
    (or (when-let* ((button (and position (button-at position))))
        (unless (button-get button 'my-files-agent-shell-secondary-action)
          (my-files-agent-shell--button-selection-key button)))
        my-files-agent-shell--highlighted-button-key)))

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
      (let ((position (button-start button)))
        (goto-char position)
        (dolist (window (get-buffer-window-list (current-buffer) nil t))
          (set-window-point window position)
          (when hl-line-mode
            (with-selected-window window
              (goto-char position)
              (hl-line-highlight))))))))

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
                 'my-files-agent-shell-selected-inactive)))))))
    (my-files-agent-shell--update-conversation-echo frame)))

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
  "Open the browser if needed, then focus its Chats panel."
  (interactive)
  (unless (my-files-agent-shell--visible-p)
    (my-files-agent-shell-open))
  (my-files-agent-shell-focus-chats))

(defun my-files-agent-shell-focus-areas ()
  "Reveal the navigation row and focus the Areas panel."
  (interactive)
  (unless (my-files-agent-shell--navigation-visible-p)
    (my-files-agent-shell--show-navigation-panels))
  (my-files-agent-shell--focus-window my-files-agent-shell--area-window))

(defun my-files-agent-shell-focus-projects ()
  "Reveal the navigation row and focus the Projects panel."
  (interactive)
  (unless (my-files-agent-shell--navigation-visible-p)
    (my-files-agent-shell--show-navigation-panels))
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
  "Move focus through visible panels, wrapping after the main window."
  (interactive)
  (my-files-agent-shell--focus-window
   (cond
    ((and (my-files-agent-shell--navigation-visible-p)
          (eq (selected-window) my-files-agent-shell--area-window))
     my-files-agent-shell--project-window)
    ((and (my-files-agent-shell--navigation-visible-p)
          (eq (selected-window) my-files-agent-shell--project-window))
     my-files-agent-shell--chat-window)
    ((eq (selected-window) my-files-agent-shell--chat-window)
     my-files-agent-shell--main-window)
    ((my-files-agent-shell--navigation-visible-p)
     my-files-agent-shell--area-window)
    (t my-files-agent-shell--chat-window))))

(defun my-files-agent-shell-previous-panel ()
  "Move focus backward through visible panels, wrapping at the start."
  (interactive)
  (my-files-agent-shell--focus-window
   (cond
    ((eq (selected-window) my-files-agent-shell--main-window)
     my-files-agent-shell--chat-window)
    ((and (my-files-agent-shell--navigation-visible-p)
          (eq (selected-window) my-files-agent-shell--chat-window))
     my-files-agent-shell--project-window)
    ((and (my-files-agent-shell--navigation-visible-p)
          (eq (selected-window) my-files-agent-shell--project-window))
     my-files-agent-shell--area-window)
    (t my-files-agent-shell--main-window))))

(defun my-files-agent-shell-toggle-in-progress-filter ()
  "Toggle whether Areas and Projects show only scopes with In Progress chats."
  (interactive)
  (setq my-files-agent-shell--in-progress-only
        (not my-files-agent-shell--in-progress-only))
  (my-files-agent-shell-refresh)
  (message "%s projects and areas with In Progress chats"
           (if my-files-agent-shell--in-progress-only
               "Showing only"
             "Showing all")))

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

(defun my-files-agent-shell--codex-thread-status-label (thread)
  "Return a useful bracketed runtime status for Codex THREAD."
  (if (string= (my-files-agent-shell--codex-thread-status thread) "active")
      "[busy]"
    "[closed]"))

(defun my-files-agent-shell--codex-thread-title (thread)
  "Return a concise display title for Codex THREAD."
  (let ((title (or (alist-get 'name thread)
                   (alist-get 'preview thread)
                   "Untitled Codex task")))
    (or (car (split-string (string-trim title) "\n" t))
        "Untitled Codex task")))

(defun my-files-agent-shell--codex-thread-render-signature (thread)
  "Return the row-layout fields for Codex THREAD, excluding runtime status."
  (list (alist-get 'id thread)
        (alist-get 'cwd thread)
        (my-files-agent-shell--codex-thread-title thread)))

(defun my-files-agent-shell--same-codex-row-layout-p (left right)
  "Return non-nil when LEFT and RIGHT render the same Codex task rows."
  (and
   (= (length left) (length right))
   (let ((right-by-id (make-hash-table :test #'equal)))
     (dolist (thread right)
       (puthash (alist-get 'id thread)
                (my-files-agent-shell--codex-thread-render-signature thread)
                right-by-id))
     (seq-every-p
      (lambda (thread)
        (equal
         (my-files-agent-shell--codex-thread-render-signature thread)
         (gethash (alist-get 'id thread) right-by-id 'missing)))
      left))))

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
  (my-files-agent-shell--schedule-refresh)
  (my-files-agent-shell--start-codex-refresh-timer))

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
           (let ((same-layout
                  (and (not my-files-agent-shell--codex-error)
                       (my-files-agent-shell--same-codex-row-layout-p
                        my-files-agent-shell--codex-threads
                        all-threads))))
             (setq my-files-agent-shell--codex-threads all-threads
                   my-files-agent-shell--codex-error nil
                   my-files-agent-shell--codex-refreshing nil
                   my-files-agent-shell--codex-last-refresh-time
                   (float-time))
             (if same-layout
                 (progn
                   (my-files-agent-shell--update-codex-status-labels
                    all-threads)
                   (my-files-agent-shell--update-chat-row-indicators))
               (my-files-agent-shell--schedule-refresh))
             (my-files-agent-shell--start-codex-refresh-timer))))))))

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
        (string-trim
         (buffer-substring-no-properties
          (line-beginning-position) (line-end-position)))))))

(defun my-files-agent-shell--read-transcript (file project)
  "Return saved chat metadata parsed from transcript FILE in PROJECT."
  (let* ((attributes (file-attributes file))
         (modified (file-attribute-modification-time attributes))
         (stamp (list my-files-agent-shell--transcript-metadata-cache-version
                      modified (file-attribute-size attributes)))
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
                 (let ((title
                        (or (my-files-agent-shell--transcript-title)
                            (file-name-base file))))
                   (list :session-id session-id
                         :agent
                         (my-files-agent-shell--transcript-field "Agent")
                         :started
                         (my-files-agent-shell--transcript-field "Started")
                         :title
                         (truncate-string-to-width title 80 nil nil "…")
                         :full-title title
                         :transcript file
                         :project project
                         :modified (float-time modified)))))))
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
  "Return non-nil when the browser's persistent windows are live."
  (and (window-live-p my-files-agent-shell--chat-window)
       (window-live-p my-files-agent-shell--main-window)))

(defun my-files-agent-shell--navigation-visible-p ()
  "Return non-nil when both optional navigation windows are live."
  (and (window-live-p my-files-agent-shell--area-window)
       (window-live-p my-files-agent-shell--project-window)))

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

(defun my-files-agent-shell--clean-chat-title (title)
  "Return TITLE's first non-empty trimmed line, or nil."
  (when (stringp title)
    (let ((line (car (split-string
                      (string-trim (substring-no-properties title))
                      "\n" t))))
      (and line (not (string-empty-p line)) line))))

(defun my-files-agent-shell--session-title (buffer)
  "Return the generated session title stored for agent-shell BUFFER."
  (with-current-buffer buffer
    (my-files-agent-shell--clean-chat-title
     (and (boundp 'agent-shell--state)
          (map-nested-elt agent-shell--state '(:session :title))))))

(defun my-files-agent-shell--chat-title (buffer)
  "Return a concise display title for agent-shell BUFFER."
  (or (my-files-agent-shell--session-title buffer)
      (buffer-name buffer)))

(defun my-files-agent-shell--buffer-name-matches-title-p (name title)
  "Return non-nil when NAME is TITLE or Emacs's unique variant of it."
  (or (equal name title)
      (string-match-p
       (format "\\`%s<[0-9]+>\\'" (regexp-quote title)) name)))

(defun my-files-agent-shell--rename-chat-buffer (buffer title)
  "Rename live agent-shell BUFFER to a clean form of TITLE."
  (when (buffer-live-p buffer)
    (when-let* ((title (my-files-agent-shell--clean-chat-title title)))
      (unless (my-files-agent-shell--buffer-name-matches-title-p
               (buffer-name buffer) title)
        (if (fboundp 'shell-maker-set-buffer-name)
            (shell-maker-set-buffer-name buffer title)
          (with-current-buffer buffer
            (rename-buffer title t)))))))

(defun my-files-agent-shell--sync-chat-buffer-name (buffer)
  "Rename live agent-shell BUFFER to its generated session title."
  (when (buffer-live-p buffer)
    (my-files-agent-shell--rename-chat-buffer
     buffer (my-files-agent-shell--session-title buffer))))

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

(defun my-files-agent-shell--conversation-deleted-p (key)
  "Return non-nil when conversation KEY is hidden by a local tombstone."
  (plist-get (my-files-agent-shell--conversation-state key) :deleted))

(defun my-files-agent-shell--conversation-in-progress-p (key)
  "Return non-nil when conversation KEY is active and In Progress."
  (and (not (my-files-agent-shell--conversation-deleted-p key))
       (not (my-files-agent-shell--conversation-archived-p key))
       (eq (my-files-agent-shell--conversation-stage key) 'in-progress)))

(defun my-files-agent-shell--scope-has-in-progress-chat-p
    (scope live-buffers saved-chats codex-threads)
  "Return non-nil when SCOPE contains an In Progress conversation.

LIVE-BUFFERS, SAVED-CHATS, and CODEX-THREADS are complete browser data sets;
the persisted workflow and archive state remains authoritative."
  (or
   (seq-some
    (lambda (buffer)
      (my-files-agent-shell--conversation-in-progress-p
       (my-files-agent-shell--live-conversation-key buffer)))
    (my-files-agent-shell--scope-chat-buffers scope live-buffers))
   (seq-some
    (lambda (entry)
      (when-let* ((directory (plist-get entry :project)))
        (and (my-files-agent-shell--directory-in-scope-p directory scope)
             (my-files-agent-shell--conversation-in-progress-p
              (my-files-agent-shell--saved-conversation-key entry)))))
    saved-chats)
   (seq-some
    (lambda (thread)
      (my-files-agent-shell--conversation-in-progress-p
       (my-files-agent-shell--codex-conversation-key thread)))
    (my-files-agent-shell--scope-codex-threads scope codex-threads))))

(defun my-files-agent-shell--scopes-with-in-progress-chats
    (scopes live-buffers saved-chats codex-threads)
  "Filter SCOPES to those containing an In Progress conversation."
  (seq-filter
   (lambda (scope)
     (my-files-agent-shell--scope-has-in-progress-chat-p
      scope live-buffers saved-chats codex-threads))
   scopes))

(defun my-files-agent-shell--buffer-with-session-id (session-id buffers)
  "Return the member of BUFFERS whose session ID is SESSION-ID."
  (and session-id
       (seq-find
        (lambda (buffer)
          (equal (my-files-agent-shell--live-session-id buffer) session-id))
        buffers)))

(defun my-files-agent-shell--conversation-row-state
    (buffer session-id live-buffers main-chat)
  "Return the display state for a conversation row.

BUFFER is its live buffer when known, SESSION-ID is its resumable identifier,
LIVE-BUFFERS are all open Agent Shell buffers, and MAIN-CHAT is the Agent Shell
buffer displayed in the main browser window."
  (let ((open-buffer
         (or (and (buffer-live-p buffer) buffer)
             (my-files-agent-shell--buffer-with-session-id
              session-id live-buffers))))
    (cond
     ((and main-chat
           (or (eq open-buffer main-chat)
               (and session-id
                    (equal session-id
                           (my-files-agent-shell--live-session-id
                            main-chat)))))
      'current)
     (open-buffer 'open)
     (t nil))))

(defun my-files-agent-shell--row-state-character (state)
  "Return the one-character row indicator for STATE."
  (pcase state
    ('current "▶")
    ('open "●")
    (_ " ")))

(defun my-files-agent-shell--row-state-face (state)
  "Return the face for conversation row STATE."
  (pcase state
    ('current 'font-lock-keyword-face)
    ('open 'success)
    (_ 'default)))

(defun my-files-agent-shell--insert-conversation-prefix
    (key &optional buffer session-id)
  "Insert batch and open-state indicators for conversation KEY.

BUFFER and SESSION-ID identify a live or resumable conversation."
  (let ((state
         (my-files-agent-shell--conversation-row-state
          buffer session-id
          my-files-agent-shell--rendering-live-buffers
          my-files-agent-shell--rendering-main-chat)))
    (insert " ")
    (insert
     (propertize
      (if (member key my-files-agent-shell--marked-conversation-keys)
          "*"
        " ")
      'my-files-agent-shell-mark-key key
      'face (if (member key my-files-agent-shell--marked-conversation-keys)
                'font-lock-warning-face
              'default)))
    (insert " ")
    (insert
     (propertize
      (my-files-agent-shell--row-state-character state)
      'my-files-agent-shell-indicator-key key
      'my-files-agent-shell-indicator-buffer buffer
      'my-files-agent-shell-indicator-session-id session-id
      'face (my-files-agent-shell--row-state-face state)))
    (insert " ")))

(defun my-files-agent-shell--replace-property-character
    (position character face)
  "Replace the character at POSITION with CHARACTER and apply FACE.

All other text properties at POSITION are preserved."
  (let ((properties (text-properties-at position))
        (inhibit-read-only t))
    (setq properties (plist-put properties 'face face))
    (save-excursion
      (goto-char position)
      (delete-char 1)
      (insert (apply #'propertize character properties)))))

(defun my-files-agent-shell--update-chat-row-indicators (&optional _frame)
  "Update open-buffer and current-window indicators without rebuilding rows."
  (when-let* ((panel (get-buffer my-files-agent-shell--chat-buffer-name)))
    (let* ((live-buffers (agent-shell-buffers))
           (main-buffer
            (and (window-live-p my-files-agent-shell--main-window)
                 (window-buffer my-files-agent-shell--main-window)))
           (main-chat (and (memq main-buffer live-buffers) main-buffer)))
      (with-current-buffer panel
        (let ((position (point-min)))
          (while (< position (point-max))
            (let ((key (get-text-property
                        position 'my-files-agent-shell-indicator-key)))
              (if (not key)
                  (setq position
                        (or (next-single-property-change
                             position
                             'my-files-agent-shell-indicator-key
                             nil (point-max))
                            (point-max)))
                (let* ((buffer
                        (get-text-property
                         position 'my-files-agent-shell-indicator-buffer))
                       (session-id
                        (get-text-property
                         position
                         'my-files-agent-shell-indicator-session-id))
                       (state
                        (my-files-agent-shell--conversation-row-state
                         buffer session-id live-buffers main-chat)))
                  (my-files-agent-shell--replace-property-character
                   position
                   (my-files-agent-shell--row-state-character state)
                   (my-files-agent-shell--row-state-face state))
                  (setq position (1+ position)))))))))))

(defun my-files-agent-shell--add-status-properties (start label key)
  "Mark the status LABEL beginning at START as belonging to conversation KEY."
  (add-text-properties
   start (+ start (length label))
   (list 'my-files-agent-shell-status-key key)))

(defun my-files-agent-shell--replace-status-labels (key label)
  "Replace only the bracketed status text for conversation KEY with LABEL."
  (when-let* ((panel (get-buffer my-files-agent-shell--chat-buffer-name)))
    (with-current-buffer panel
      (let ((selection-key (my-files-agent-shell--selected-button-key))
            (position (point-min))
            (inhibit-read-only t))
        (while (< position (point-max))
          (let* ((value (get-text-property
                         position 'my-files-agent-shell-status-key))
                 (end
                  (or (next-single-property-change
                       position 'my-files-agent-shell-status-key
                       nil (point-max))
                      (point-max))))
            (if (not (equal value key))
                (setq position end)
              (let ((properties (text-properties-at position))
                    (start position))
                (delete-region start end)
                (goto-char start)
                (insert (apply #'propertize label properties))
                (setq position (+ start (length label)))))))
        (my-files-agent-shell--restore-button-selection selection-key)))))

(defun my-files-agent-shell--update-live-chat-status (buffer)
  "Update only the bracketed runtime status for live Agent Shell BUFFER."
  (when-let* ((key (my-files-agent-shell--live-conversation-key buffer)))
    (my-files-agent-shell--replace-status-labels
     key (format "[%s]" (my-files-agent-shell--chat-status buffer)))))

(defun my-files-agent-shell--update-codex-status-labels (threads)
  "Update only bracketed Codex status labels for THREADS."
  (dolist (thread threads)
    (my-files-agent-shell--replace-status-labels
     (my-files-agent-shell--codex-conversation-key thread)
     (my-files-agent-shell--codex-thread-status-label thread))))

(defun my-files-agent-shell--update-conversation-markers ()
  "Update batch-selection markers without rebuilding conversation rows."
  (when-let* ((panel (get-buffer my-files-agent-shell--chat-buffer-name)))
    (with-current-buffer panel
      (let ((position (point-min)))
        (while (< position (point-max))
          (let ((key (get-text-property
                      position 'my-files-agent-shell-mark-key)))
            (if (not key)
                (setq position
                      (or (next-single-property-change
                           position 'my-files-agent-shell-mark-key
                           nil (point-max))
                          (point-max)))
              (let ((marked
                     (member key
                             my-files-agent-shell--marked-conversation-keys)))
                (my-files-agent-shell--replace-property-character
                 position (if marked "*" " ")
                 (if marked 'font-lock-warning-face 'default))
                (setq position (1+ position))))))))))

(defun my-files-agent-shell--visible-marked-conversation-keys ()
  "Return marked conversation keys that are visible in this panel."
  (delete-dups
   (delq
    nil
    (mapcar
     (lambda (button)
       (let ((key
              (button-get button
                          'my-files-agent-shell-conversation-key)))
         (and (member key my-files-agent-shell--marked-conversation-keys)
              key)))
     (my-files-agent-shell--visible-buttons)))))

(defun my-files-agent-shell--conversation-keys-for-action ()
  "Return marked conversation keys, or the highlighted key when none are marked."
  (or (my-files-agent-shell--visible-marked-conversation-keys)
      (list (my-files-agent-shell--conversation-key-at-point))))

(defun my-files-agent-shell-toggle-mark-at-point ()
  "Toggle batch selection for the highlighted conversation."
  (interactive)
  (let ((key (my-files-agent-shell--conversation-key-at-point)))
    (if (member key my-files-agent-shell--marked-conversation-keys)
        (setq my-files-agent-shell--marked-conversation-keys
              (delete key my-files-agent-shell--marked-conversation-keys))
      (push key my-files-agent-shell--marked-conversation-keys))
    (my-files-agent-shell--update-conversation-markers)
    (my-files-agent-shell-next-item)))

(defun my-files-agent-shell-unmark-all ()
  "Clear all batch-selected conversations in the chat panel."
  (interactive)
  (setq my-files-agent-shell--marked-conversation-keys nil)
  (my-files-agent-shell--update-conversation-markers)
  (message "Cleared conversation selection"))

(defun my-files-agent-shell--selection-key-after-removal (keys section)
  "Return a nearby selection key after KEYS leave conversation SECTION."
  (let* ((current (button-at (point)))
         (position (and current (button-start current)))
         (buttons (my-files-agent-shell--visible-buttons))
         (eligible
          (seq-filter
           (lambda (button)
             (let ((key
                    (button-get
                     button 'my-files-agent-shell-conversation-key)))
               (and key
                    (eq (button-get button 'my-files-agent-shell-section)
                        section)
                    (not (member key keys)))))
           buttons))
         (next
          (and position
               (seq-find
                (lambda (button) (> (button-start button) position))
                eligible)))
         (previous
          (and position
               (car
                (last
                 (seq-filter
                  (lambda (button) (< (button-start button) position))
                  eligible)))))
         (heading
          (seq-find
           (lambda (button)
             (eq (button-get button 'my-files-agent-shell-category) section))
           buttons)))
    (when-let* ((button (or next previous heading)))
      (my-files-agent-shell--button-selection-key button))))

(defun my-files-agent-shell--prepare-selection-before-removal
    (keys retained-sections)
  "Anchor selection before KEYS leave every section but RETAINED-SECTIONS."
  (when-let* ((button (button-at (point)))
              (key (button-get
                    button 'my-files-agent-shell-conversation-key))
              (section (button-get button 'my-files-agent-shell-section)))
    (when (and (member key keys) (not (memq section retained-sections)))
      (setq my-files-agent-shell--pending-selection-key
            (my-files-agent-shell--selection-key-after-removal
             keys section)))))

(defun my-files-agent-shell--clear-marks (keys)
  "Remove conversation KEYS from the batch selection."
  (dolist (key keys)
    (setq my-files-agent-shell--marked-conversation-keys
          (delete key my-files-agent-shell--marked-conversation-keys)))
  (my-files-agent-shell--update-conversation-markers))

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
          (progn
            (my-files-agent-shell--insert-conversation-action
             "Restore" #'my-files-agent-shell--restore-conversation-button key
             "Return this conversation to Active Conversations")
            (my-files-agent-shell--insert-conversation-action
             "Delete" #'my-files-agent-shell--delete-conversation-button key
             "Permanently hide this archived conversation from the manager"))
        (my-files-agent-shell--insert-conversation-action
         "Archive" #'my-files-agent-shell--archive-conversation-button key
         "Show this conversation only under Archived")))))

(defun my-files-agent-shell--insert-chat-button (buffer)
  "Insert a button that opens agent-shell BUFFER."
  (let* ((session-id (my-files-agent-shell--live-session-id buffer))
         (directory (buffer-local-value 'default-directory buffer))
         (agent-config
          (with-current-buffer buffer
            (and (boundp 'agent-shell--state)
                 (map-elt agent-shell--state :agent-config))))
         (title (my-files-agent-shell--chat-title buffer))
         (key (my-files-agent-shell--live-conversation-key buffer))
         (status-label (concat "[" (my-files-agent-shell--chat-status buffer)
                               "]")))
    (my-files-agent-shell--insert-conversation-prefix
     key buffer (my-files-agent-shell--live-session-id buffer))
    (let ((start (point)))
      (insert-text-button
       (format "%s %s" status-label title)
       'action #'my-files-agent-shell--open-chat
       'my-files-agent-shell-buffer buffer
       'my-files-agent-shell-session-id session-id
       'my-files-agent-shell-directory directory
       'my-files-agent-shell-agent-config agent-config
       'my-files-agent-shell-conversation-key key
       'my-files-agent-shell-conversation-title title
       'my-files-agent-shell-section my-files-agent-shell--rendering-section
       'my-files-agent-shell-action 'open
       'follow-link t
       'help-echo (format "%s\nOpen this live conversation" title)
       'face 'default)
      (my-files-agent-shell--add-status-properties start status-label key))
    (my-files-agent-shell--insert-conversation-actions key)
    (insert "\n")))

(defun my-files-agent-shell--display-chat-buffer (buffer)
  "Display live Agent Shell BUFFER in the browser's main window."
  (unless (buffer-live-p buffer)
    (my-files-agent-shell-refresh)
    (user-error "That agent chat is no longer open"))
  (unless (window-live-p my-files-agent-shell--main-window)
    (user-error "The My Files main window is no longer available"))
  (set-window-buffer my-files-agent-shell--main-window buffer)
  (my-files-agent-shell--update-chat-window-column
   my-files-agent-shell--main-window)
  (select-window my-files-agent-shell--main-window)
  (my-files-agent-shell--update-chat-row-indicators)
  buffer)

(defun my-files-agent-shell--open-chat (button)
  "Open the Agent Shell buffer represented by BUTTON in the main window."
  (let ((buffer (button-get button 'my-files-agent-shell-buffer)))
    (if (buffer-live-p buffer)
        (my-files-agent-shell--display-chat-buffer buffer)
      (let ((session-id
             (button-get button 'my-files-agent-shell-session-id)))
        (unless session-id
          (my-files-agent-shell-refresh)
          (user-error "That conversation is still starting and cannot resume"))
        (let ((resumed
               (my-files-agent-shell--start-resumed-chat
                session-id nil
                (button-get button 'my-files-agent-shell-directory)
                (button-get button 'my-files-agent-shell-agent-config))))
          (my-files-agent-shell--rename-chat-buffer
           resumed
           (button-get button 'my-files-agent-shell-conversation-title))
          resumed)))))

(defun my-files-agent-shell--insert-codex-chat-button (thread)
  "Insert a workflow-controlled row for Codex THREAD."
  (let* ((title (my-files-agent-shell--codex-thread-title thread))
         (key (my-files-agent-shell--codex-conversation-key thread))
         (status-label
          (my-files-agent-shell--codex-thread-status-label thread)))
    (my-files-agent-shell--insert-conversation-prefix
     key nil (alist-get 'id thread))
    (let ((start (point)))
      (insert-text-button
       (format "%s %s" status-label title)
       'action #'my-files-agent-shell--open-codex-chat
       'my-files-agent-shell-codex-entry thread
       'my-files-agent-shell-conversation-key key
       'my-files-agent-shell-conversation-title title
       'my-files-agent-shell-section my-files-agent-shell--rendering-section
       'my-files-agent-shell-action 'open
       'follow-link t
       'help-echo (format "%s\nResume this Codex task in Agent Shell" title)
       'face 'default)
      (my-files-agent-shell--add-status-properties start status-label key))
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
    (let ((buffer
           (my-files-agent-shell--start-resumed-chat
            thread-id "Codex" directory)))
      (my-files-agent-shell--rename-chat-buffer
       buffer (my-files-agent-shell--codex-thread-title thread))
      buffer)))

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

(defun my-files-agent-shell--move-conversations (keys)
  "Prompt once and persist a workflow stage for conversation KEYS."
  (let* ((current
          (my-files-agent-shell--conversation-stage (car keys)))
         (stage (my-files-agent-shell--read-workflow-stage current))
         (changed
          (seq-filter
           (lambda (key)
             (not (eq (my-files-agent-shell--conversation-stage key)
                      stage)))
           keys)))
    (when changed
      (my-files-agent-shell--prepare-selection-before-removal
       changed (list 'active 'archived stage))
      (dolist (key changed)
        (my-files-agent-shell--set-conversation-stage key stage))
      (my-files-agent-shell--clear-marks keys)
      (my-files-agent-shell--schedule-refresh)
      (message "Moved %s to %s"
               (if (= (length changed) 1)
                   "conversation"
                 (format "%d conversations" (length changed)))
               (my-files-agent-shell--workflow-stage-label stage)))))

(defun my-files-agent-shell--move-conversation (key)
  "Prompt for and persist conversation KEY's workflow stage."
  (my-files-agent-shell--move-conversations (list key)))

(defun my-files-agent-shell--move-conversation-button (button)
  "Move the conversation represented by BUTTON to a workflow stage."
  (goto-char (button-start button))
  (my-files-agent-shell--move-conversation
   (button-get button 'my-files-agent-shell-conversation-key)))

(defun my-files-agent-shell-move-at-point ()
  "Move marked conversations, or the highlighted conversation, to a stage."
  (interactive)
  (my-files-agent-shell--move-conversations
   (my-files-agent-shell--conversation-keys-for-action)))

(defun my-files-agent-shell--archive-conversations (keys)
  "Archive non-archived conversation KEYS after one confirmation."
  (let ((active
         (seq-remove
          #'my-files-agent-shell--conversation-archived-p keys)))
    (unless active
      (user-error "The selected conversations are already archived"))
    (when (yes-or-no-p
           (if (= (length active) 1)
               "Archive this conversation? "
             (format "Archive %d conversations? " (length active))))
      (my-files-agent-shell--prepare-selection-before-removal
       active '(archived))
      (dolist (key active)
        (my-files-agent-shell--set-conversation-archived key t))
      (my-files-agent-shell--clear-marks keys)
      (my-files-agent-shell--schedule-refresh)
      (message "Archived %s"
               (if (= (length active) 1)
                   "conversation"
                 (format "%d conversations" (length active)))))))

(defun my-files-agent-shell-archive-at-point ()
  "Archive marked conversations, or the highlighted conversation."
  (interactive)
  (my-files-agent-shell--archive-conversations
   (my-files-agent-shell--conversation-keys-for-action)))

(defun my-files-agent-shell--archive-conversation-button (button)
  "Archive the conversation represented by BUTTON."
  (goto-char (button-start button))
  (my-files-agent-shell--archive-conversations
   (list (button-get button 'my-files-agent-shell-conversation-key))))

(defun my-files-agent-shell--delete-conversations (keys)
  "Permanently hide archived conversation KEYS from this manager."
  (unless (seq-every-p
           #'my-files-agent-shell--conversation-archived-p keys)
    (user-error "Archive conversations before deleting them"))
  (when (yes-or-no-p
         (if (= (length keys) 1)
             (concat "Delete this conversation from the manager? "
                     "Its underlying history will remain intact. ")
           (format
            (concat "Delete %d conversations from the manager? "
                    "Their underlying history will remain intact. ")
            (length keys))))
    (my-files-agent-shell--prepare-selection-before-removal keys nil)
    (dolist (key keys)
      (my-files-agent-shell--set-conversation-deleted key t))
    (my-files-agent-shell--clear-marks keys)
    (my-files-agent-shell--schedule-refresh)
    (message "Deleted %s from the manager"
             (if (= (length keys) 1)
                 "conversation"
               (format "%d conversations" (length keys))))))

(defun my-files-agent-shell-delete-at-point ()
  "Delete marked archived conversations, or the highlighted one."
  (interactive)
  (my-files-agent-shell--delete-conversations
   (my-files-agent-shell--conversation-keys-for-action)))

(defun my-files-agent-shell--delete-conversation-button (button)
  "Delete the archived conversation represented by BUTTON from the manager."
  (goto-char (button-start button))
  (my-files-agent-shell--delete-conversations
   (list (button-get button 'my-files-agent-shell-conversation-key))))

(defun my-files-agent-shell--restore-conversations (keys)
  "Restore archived conversation KEYS."
  (let ((archived
         (seq-filter
          #'my-files-agent-shell--conversation-archived-p keys)))
    (unless archived
      (user-error "The selected conversations are not archived"))
    (my-files-agent-shell--prepare-selection-before-removal archived nil)
    (dolist (key archived)
      (my-files-agent-shell--set-conversation-archived key nil))
    (my-files-agent-shell--clear-marks keys)
    (my-files-agent-shell--schedule-refresh)
    (message "Restored %s"
             (if (= (length archived) 1)
                 "conversation"
               (format "%d conversations" (length archived))))))

(defun my-files-agent-shell--restore-conversation (key)
  "Restore archived conversation KEY to the active lists."
  (my-files-agent-shell--restore-conversations (list key)))

(defun my-files-agent-shell--restore-conversation-button (button)
  "Restore the archived conversation represented by BUTTON."
  (goto-char (button-start button))
  (my-files-agent-shell--restore-conversation
   (button-get button 'my-files-agent-shell-conversation-key)))

(defun my-files-agent-shell-restore-at-point ()
  "Restore marked conversations, or the highlighted conversation."
  (interactive)
  (my-files-agent-shell--restore-conversations
   (my-files-agent-shell--conversation-keys-for-action)))

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

(defun my-files-agent-shell--agent-config-for-start
    (&optional agent-name agent-config)
  "Return AGENT-CONFIG, or resolve one using AGENT-NAME and user preferences."
  (or agent-config
      (and agent-name (my-files-agent-shell--agent-config agent-name))
      (and (null agent-name) (agent-shell--auto-preferred-config))
      (agent-shell-select-config
       :prompt (if agent-name
                   (format "Resume %s conversation with agent: " agent-name)
                 "Start new agent: "))))

(defun my-files-agent-shell--display-buffer-in-main-window (buffer _alist)
  "Display BUFFER in the browser's main window for `display-buffer'."
  (when (window-live-p my-files-agent-shell--main-window)
    (set-window-buffer my-files-agent-shell--main-window buffer)
    (my-files-agent-shell--update-chat-window-column
     my-files-agent-shell--main-window)
    my-files-agent-shell--main-window))

(defun my-files-agent-shell--codex-history-load-request-p (state request)
  "Return non-nil when STATE and REQUEST describe a resumable Codex load."
  (and (eq (map-nested-elt state '(:agent-config :identifier)) 'codex)
       (map-elt state :supports-session-resume)
       (equal (map-elt request :method) "session/load")))

(defun my-files-agent-shell--resume-request-without-history (load-request)
  "Return a resume request preserving parameters from LOAD-REQUEST."
  (let ((params (map-elt load-request :params)))
    (acp-make-session-resume-request
     :session-id (map-elt params 'sessionId)
     :cwd (map-elt params 'cwd)
     :mcp-servers (map-elt params 'mcpServers)
     :meta (map-elt params '_meta))))

(defun my-files-agent-shell--send-request-with-codex-resume-fallback
    (original &rest arguments)
  "Send an Agent Shell request, retrying failed Codex history loads.

ORIGINAL is `agent-shell--send-request' and ARGUMENTS are its keyword
arguments.  Codex rejects `session/load' for paginated task histories even
though the same task supports `session/resume'.  When a Codex history load
fails, retry it once without history replay before invoking Agent Shell's
original failure handler."
  (let* ((state (plist-get arguments :state))
         (request (plist-get arguments :request)))
    (if (not (my-files-agent-shell--codex-history-load-request-p
              state request))
        (apply original arguments)
      (let ((client (plist-get arguments :client))
            (buffer (plist-get arguments :buffer))
            (on-success (plist-get arguments :on-success))
            (on-failure (plist-get arguments :on-failure))
            (sync (plist-get arguments :sync))
            (resume-request
             (my-files-agent-shell--resume-request-without-history request)))
        (setq arguments
              (plist-put
               (copy-sequence arguments)
               :on-failure
               (lambda (load-error load-raw-message)
                 (if (not (buffer-live-p buffer))
                     (when on-failure
                       (funcall on-failure load-error load-raw-message))
                   (with-current-buffer buffer
                     (map-put! state :pending-restore nil)
                     (agent-shell--update-bootstrapping-fragment
                      :state state
                      :block-id "restore_fallback"
                      :body
                      (agent-shell--make-boxed-message
                       :text
                       "History unavailable. Resuming without history replay."))
                     (funcall
                      original
                      :state state
                      :client client
                      :request resume-request
                      :buffer buffer
                      :on-success on-success
                      :on-failure on-failure
                      :sync sync))))))
        (apply original arguments)))))

(defun my-files-agent-shell--start-resumed-chat
    (session-id agent-name directory &optional agent-config)
  "Resume SESSION-ID for AGENT-NAME in DIRECTORY and show it in the main pane."
  (unless (window-live-p my-files-agent-shell--main-window)
    (user-error "The My Files main window is no longer available"))
  (if-let* ((buffer
             (my-files-agent-shell--buffer-with-session-id
              session-id (agent-shell-buffers))))
      (progn
        (my-files-agent-shell--display-chat-buffer buffer)
        (my-files-agent-shell--schedule-refresh)
        buffer)
    (my-files-agent-shell--ensure-agent-shell-ready)
    (unless directory
      (user-error "That chat has no working directory"))
    (let* ((config
            (my-files-agent-shell--agent-config-for-start
             agent-name agent-config))
           (resume-directory
            (my-files-agent-shell--canonical-directory directory))
           (agent-shell-session-restore-verbosity
            my-files-agent-shell-session-restore-verbosity)
           (buffer
            (with-selected-window my-files-agent-shell--main-window
              (let ((default-directory resume-directory)
                    (agent-shell-cwd-function
                     (lambda () resume-directory))
                    (agent-shell-session-strategy 'new)
                    (display-buffer-overriding-action
                     '(my-files-agent-shell--display-buffer-in-main-window)))
                (agent-shell-start
                 :config config :session-id session-id)))))
      ;; Agent startup completes asynchronously.  Keep the display policy
      ;; buffer-local so session/load callbacks see it after this call returns.
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (setq-local agent-shell-session-restore-verbosity
                      my-files-agent-shell-session-restore-verbosity)
          (setq-local agent-shell-cwd-function
                      (lambda () resume-directory)))
        (my-files-agent-shell--display-chat-buffer buffer))
      (my-files-agent-shell--schedule-refresh)
      buffer)))

(defun my-files-agent-shell--resume-chat (button)
  "Resume the saved agent-shell session represented by BUTTON."
  (let* ((entry (button-get button 'my-files-agent-shell-entry))
         (session-id (plist-get entry :session-id))
         (agent-name (plist-get entry :agent))
         (directory (plist-get entry :project)))
    (let ((buffer
           (my-files-agent-shell--start-resumed-chat
            session-id agent-name directory)))
      (my-files-agent-shell--rename-chat-buffer
       buffer (or (plist-get entry :full-title)
                  (plist-get entry :title)))
      buffer)))

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
         (config (my-files-agent-shell--agent-config-for-start))
         (buffer
          (with-selected-window my-files-agent-shell--main-window
            (let ((default-directory project)
                  (agent-shell-cwd-function (lambda () project))
                  (agent-shell-session-strategy 'new)
                  (display-buffer-overriding-action
                   '(my-files-agent-shell--display-buffer-in-main-window)))
              (agent-shell-start :config config)))))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (setq-local my-files-agent-shell--assigned-project project)
        (setq-local agent-shell-cwd-function (lambda () project)))
      (my-files-agent-shell--display-chat-buffer buffer)))
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
  "Track BUFFER status in place and refresh when its row structure changes."
  (my-files-agent-shell--sync-chat-buffer-name buffer)
  (with-current-buffer buffer
    (dolist (event my-files-agent-shell--chat-refresh-events)
      (unless (memq event my-files-agent-shell--subscribed-events)
        (agent-shell-subscribe-to
         :shell-buffer buffer
         :event event
         :on-event
         (cond
          ((memq event my-files-agent-shell--chat-status-events)
           (lambda (_event)
             (my-files-agent-shell--update-live-chat-status buffer)))
          ((eq event 'session-title-changed)
           (lambda (_event)
             (my-files-agent-shell--sync-chat-buffer-name buffer)
             (my-files-agent-shell--schedule-refresh)))
          (t
           (lambda (_event)
             (my-files-agent-shell--schedule-refresh)))))
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
      (my-files-agent-shell--insert-heading
       (if my-files-agent-shell--in-progress-only
           "AREAS · IN PROGRESS ONLY"
         "AREAS"))
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
      (my-files-agent-shell--insert-heading
       (if my-files-agent-shell--in-progress-only
           "PROJECTS · IN PROGRESS ONLY"
         "PROJECTS"))
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
        (full-title (or (plist-get entry :full-title)
                        (plist-get entry :title)))
        (agent (or (plist-get entry :agent) "Agent"))
        (started (plist-get entry :started))
        (status-label "[saved]"))
    (my-files-agent-shell--insert-conversation-prefix
     key nil (plist-get entry :session-id))
    (let ((start (point)))
      (insert-text-button
       (format "%-8s %s" status-label title)
       'action #'my-files-agent-shell--resume-chat
       'my-files-agent-shell-entry entry
       'my-files-agent-shell-conversation-key key
       'my-files-agent-shell-conversation-title full-title
       'my-files-agent-shell-section my-files-agent-shell--rendering-section
       'follow-link t
       'help-echo (format "%s\nResume %s session%s"
                          full-title agent
                          (if started (format " from %s" started) ""))
       'face 'default)
      (my-files-agent-shell--add-status-properties start status-label key))
    (my-files-agent-shell--insert-conversation-actions key)
    (insert "\n")))

(defun my-files-agent-shell--conversation-records
    (chats saved-chats codex-threads)
  "Return one normalized record per conversation in the supplied sources.

When a session occurs in multiple sources, prefer a live buffer, then a cached
Codex task, then a saved transcript."
  (let ((records
         (append
          (mapcar
           (lambda (chat)
             (my-files-agent-shell--subscribe-chat chat)
             (list :kind 'live
                   :value chat
                   :session-id
                   (my-files-agent-shell--live-session-id chat)
                   :key
                   (my-files-agent-shell--live-conversation-key chat)))
           chats)
          (mapcar
           (lambda (thread)
             (list :kind 'codex
                   :value thread
                   :session-id (alist-get 'id thread)
                   :key
                   (my-files-agent-shell--codex-conversation-key thread)))
           codex-threads)
          (mapcar
           (lambda (entry)
             (list :kind 'saved
                   :value entry
                   :session-id (plist-get entry :session-id)
                   :key
                   (my-files-agent-shell--saved-conversation-key entry)))
           saved-chats)))
        (seen-session-ids (make-hash-table :test #'equal)))
    (seq-filter
     (lambda (record)
       (let ((session-id (plist-get record :session-id)))
         (or (null session-id)
             (unless (gethash session-id seen-session-ids)
               (puthash session-id t seen-session-ids)))))
     records)))

(defun my-files-agent-shell--records-for-section (section records)
  "Return RECORDS belonging to conversation SECTION."
  (seq-filter
   (lambda (record)
     (let* ((key (plist-get record :key))
            (deleted (my-files-agent-shell--conversation-deleted-p key))
            (archived (my-files-agent-shell--conversation-archived-p key)))
       (unless deleted
         (pcase section
           ('active (not archived))
           ('archived archived)
           (_ (and (not archived)
                   (eq (my-files-agent-shell--conversation-stage key)
                       section)))))))
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
    (let* ((selection-key
            (or my-files-agent-shell--pending-selection-key
                (my-files-agent-shell--selected-button-key)))
           (my-files-agent-shell--rendering-live-buffers
            (agent-shell-buffers))
           (main-buffer
            (and (window-live-p my-files-agent-shell--main-window)
                 (window-buffer my-files-agent-shell--main-window)))
           (my-files-agent-shell--rendering-main-chat
            (and (memq main-buffer
                       my-files-agent-shell--rendering-live-buffers)
                 main-buffer))
           (inhibit-read-only t))
      (setq my-files-agent-shell--pending-selection-key nil)
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
             (concat "SPC marks · U clears · m moves · a archives · "
                     "u restores · d deletes archived · i filters · "
                     "v navigation · ▶ current · ● open buffer"))
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
         (all-areas (my-files-agent-shell--discover-areas))
         (all-chat-buffers (agent-shell-buffers))
         (live-session-ids
          (delq nil
                (mapcar #'my-files-agent-shell--live-session-id
                        all-chat-buffers)))
         (area-projects
          (and my-files-agent-shell--in-progress-only
               (mapcar
                (lambda (area)
                  (cons area (my-files-agent-shell--discover-projects area)))
                all-areas)))
         (all-filter-directories
          (and my-files-agent-shell--in-progress-only
               (delete-dups
                (append
                 all-areas
                 (mapcan
                  (lambda (entry) (copy-sequence (cdr entry)))
                  area-projects)))))
         (all-saved-chats
          (and all-filter-directories
               (my-files-agent-shell--discover-saved-chats-in-directories
                all-filter-directories live-session-ids)))
         (areas
          (if my-files-agent-shell--in-progress-only
              (my-files-agent-shell--scopes-with-in-progress-chats
               all-areas all-chat-buffers all-saved-chats
               my-files-agent-shell--codex-threads)
            all-areas))
         (selected-area
          (and my-files-agent-shell--selected-area
               (seq-find
                (lambda (area)
                  (equal area my-files-agent-shell--selected-area))
                areas))))
    (setq my-files-agent-shell--selected-area
          (or selected-area (car areas)))
    (let* ((all-projects
            (and my-files-agent-shell--selected-area
                 (if my-files-agent-shell--in-progress-only
                     (alist-get my-files-agent-shell--selected-area
                                area-projects nil nil #'equal)
                   (my-files-agent-shell--discover-projects
                    my-files-agent-shell--selected-area))))
           (projects
            (if my-files-agent-shell--in-progress-only
                (my-files-agent-shell--scopes-with-in-progress-chats
                 all-projects all-chat-buffers all-saved-chats
                 my-files-agent-shell--codex-threads)
              all-projects))
           (selected-project
            (and my-files-agent-shell--selected-project
                 (seq-find
                  (lambda (project)
                    (equal project my-files-agent-shell--selected-project))
                  projects))))
      (setq my-files-agent-shell--selected-project selected-project)
      (let* ((scope (or my-files-agent-shell--selected-project
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
              (if my-files-agent-shell--in-progress-only
                  (and scope
                       (seq-filter
                        (lambda (entry)
                          (when-let* ((directory
                                      (plist-get entry :project)))
                            (my-files-agent-shell--directory-in-scope-p
                             directory scope)))
                        all-saved-chats))
                (and saved-chat-directories
                     (my-files-agent-shell--discover-saved-chats-in-directories
                      saved-chat-directories
                      (delq
                       nil
                       (mapcar #'my-files-agent-shell--live-session-id
                               chats))))))
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

(defun my-files-agent-shell--window-buffer-changed (&optional _frame)
  "Update row indicators after a browser window changes buffers."
  (when (my-files-agent-shell--visible-p)
    (my-files-agent-shell--update-chat-row-indicators)))

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
  "Schedule one Codex task refresh after Emacs becomes idle."
  (when (timerp my-files-agent-shell--codex-refresh-timer)
    (cancel-timer my-files-agent-shell--codex-refresh-timer))
  (setq my-files-agent-shell--codex-refresh-timer nil)
  (when (my-files-agent-shell--visible-p)
    (setq my-files-agent-shell--codex-refresh-timer
          (run-with-idle-timer
           my-files-agent-shell-codex-refresh-interval nil
           (lambda ()
             (setq my-files-agent-shell--codex-refresh-timer nil)
             (when (my-files-agent-shell--visible-p)
               (my-files-agent-shell--refresh-codex-threads t)))))))

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

(defun my-files-agent-shell--desired-chat-width ()
  "Return the preferred Chats width based on its visible text."
  (max my-files-agent-shell-chat-width
       (min my-files-agent-shell-chat-content-maximum-width
            (1+ (my-files-agent-shell--panel-content-width
                 (get-buffer my-files-agent-shell--chat-buffer-name))))))

(defun my-files-agent-shell--scaled-chat-width
    (total-width &optional requested-width)
  "Return a Chats width suitable for TOTAL-WIDTH.

REQUESTED-WIDTH defaults to the configured, content-aware width.  The result
never exceeds half of TOTAL-WIDTH and always reserves the configured minimum
for the main conversation window."
  (let ((minimum-total
         (+ my-files-agent-shell-minimum-panel-width
            my-files-agent-shell-minimum-main-width)))
    (when (< total-width minimum-total)
      (user-error "Frame is too narrow: need at least %d columns"
                  minimum-total))
    (max my-files-agent-shell-minimum-panel-width
         (min (max my-files-agent-shell-minimum-panel-width
                   (or requested-width
                       (my-files-agent-shell--desired-chat-width)))
              (floor total-width 2)
              (- total-width my-files-agent-shell-minimum-main-width)))))

(defun my-files-agent-shell--resize-panels-to-content ()
  "Resize the Chats column to fit text within half the workspace."
  (when (my-files-agent-shell--visible-p)
    (let* ((total-width
            (+ (window-total-width my-files-agent-shell--chat-window)
               (window-total-width my-files-agent-shell--main-window)))
           (width
            (my-files-agent-shell--scaled-chat-width
             total-width (my-files-agent-shell--desired-chat-width)))
           (delta
            (- width
               (window-total-width my-files-agent-shell--chat-window)))
           (ignore-window-parameters t))
      (unless (zerop delta)
        (window-resize my-files-agent-shell--chat-window delta t)))))

(defun my-files-agent-shell--prepare-panel-window (window buffer)
  "Display BUFFER in dedicated panel WINDOW."
  (set-window-buffer window buffer)
  (set-window-dedicated-p window t)
  (set-window-parameter window 'no-delete-other-windows t)
  (set-window-parameter window 'my-files-agent-shell-panel t))

(defun my-files-agent-shell--navigation-row-height ()
  "Return a shallow height that fits above both persistent windows."
  (let* ((available
          (min (window-total-height my-files-agent-shell--chat-window)
               (window-total-height my-files-agent-shell--main-window)))
         (minimum (max 2 window-min-height))
         (maximum (floor available 3)))
    (when (< available (* 2 minimum))
      (user-error "Frame is too short to show Areas and Projects"))
    (max minimum
         (min my-files-agent-shell-navigation-height maximum))))

(defun my-files-agent-shell--show-navigation-panels ()
  "Show Areas and Projects in a shallow row above the persistent windows."
  (unless (my-files-agent-shell--visible-p)
    (user-error "The My Files browser is not open"))
  (when (and (not (my-files-agent-shell--navigation-visible-p))
             (or (window-live-p my-files-agent-shell--area-window)
                 (window-live-p my-files-agent-shell--project-window)))
    (my-files-agent-shell--hide-navigation-panels))
  (unless (my-files-agent-shell--navigation-visible-p)
    (let ((height (my-files-agent-shell--navigation-row-height))
          area-window project-window)
      (condition-case error-data
          (let ((ignore-window-parameters t))
            (setq area-window
                  (split-window my-files-agent-shell--chat-window
                                (- height) 'above)
                  project-window
                  (split-window my-files-agent-shell--main-window
                                (- height) 'above)
                  my-files-agent-shell--area-window area-window
                  my-files-agent-shell--project-window project-window)
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
            (my-files-agent-shell--update-panel-focus-faces))
        (error
         (let ((ignore-window-parameters t))
           (when (window-live-p area-window)
             (delete-window area-window))
           (when (window-live-p project-window)
             (delete-window project-window)))
         (setq my-files-agent-shell--area-window nil
               my-files-agent-shell--project-window nil)
         (signal (car error-data) (cdr error-data)))))))

(defun my-files-agent-shell--hide-navigation-panels ()
  "Hide the optional Areas and Projects row."
  (when (or (window-live-p my-files-agent-shell--area-window)
            (window-live-p my-files-agent-shell--project-window))
    (let ((navigation-selected
           (memq (selected-window)
                 (list my-files-agent-shell--area-window
                       my-files-agent-shell--project-window)))
          (ignore-window-parameters t))
      (when navigation-selected
        (select-window my-files-agent-shell--chat-window))
      (when (window-live-p my-files-agent-shell--area-window)
        (delete-window my-files-agent-shell--area-window))
      (when (window-live-p my-files-agent-shell--project-window)
        (delete-window my-files-agent-shell--project-window))
      (setq my-files-agent-shell--area-window nil
            my-files-agent-shell--project-window nil)
      (when navigation-selected
        (my-files-agent-shell-focus-chats)))))

;;;###autoload
(defun my-files-agent-shell-toggle-navigation-panels ()
  "Toggle the shallow Areas and Projects row above the browser."
  (interactive)
  (unless (my-files-agent-shell--visible-p)
    (my-files-agent-shell-open))
  (if (my-files-agent-shell--navigation-visible-p)
      (my-files-agent-shell--hide-navigation-panels)
    (my-files-agent-shell--show-navigation-panels)))

;;;###autoload
(defun my-files-agent-shell-open ()
  "Open the Chats and main conversation workspace."
  (interactive)
  (if (my-files-agent-shell--visible-p)
      (my-files-agent-shell-focus-chats)
    (when my-files-agent-shell--saved-window-configuration
      (my-files-agent-shell-close))
    (let* ((main (selected-window))
           (configuration (current-window-configuration))
           chat-width chat-window)
      (condition-case error-data
          (progn
            (let ((ignore-window-parameters t))
              (delete-other-windows main))
            (setq chat-width
                  (my-files-agent-shell--scaled-chat-width
                   (window-total-width main))
                  chat-window
                  (split-window main (- chat-width) 'left))
            (setq my-files-agent-shell--saved-window-configuration configuration
                  my-files-agent-shell--area-window nil
                  my-files-agent-shell--project-window nil
                  my-files-agent-shell--chat-window chat-window
                  my-files-agent-shell--main-window main)
            (my-files-agent-shell--prepare-panel-window
             chat-window
             (my-files-agent-shell--panel-buffer
              my-files-agent-shell--chat-buffer-name
              #'my-files-agent-shell-chat-mode))
            (add-hook 'buffer-list-update-hook
                      #'my-files-agent-shell--buffer-list-updated)
            (add-hook 'window-selection-change-functions
                      #'my-files-agent-shell--update-panel-focus-faces)
            (add-hook 'window-buffer-change-functions
                      #'my-files-agent-shell--window-buffer-changed)
            (my-files-agent-shell-refresh)
            (my-files-agent-shell--start-codex-refresh-timer)
            (my-files-agent-shell-focus-chats))
        (error
         (remove-hook 'buffer-list-update-hook
                      #'my-files-agent-shell--buffer-list-updated)
         (remove-hook 'window-selection-change-functions
                      #'my-files-agent-shell--update-panel-focus-faces)
         (remove-hook 'window-buffer-change-functions
                      #'my-files-agent-shell--window-buffer-changed)
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
  (my-files-agent-shell--clear-conversation-echo)
  (remove-hook 'buffer-list-update-hook
               #'my-files-agent-shell--buffer-list-updated)
  (remove-hook 'window-selection-change-functions
               #'my-files-agent-shell--update-panel-focus-faces)
  (remove-hook 'window-buffer-change-functions
               #'my-files-agent-shell--window-buffer-changed)
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

(add-hook 'agent-shell-mode-hook
          #'my-files-agent-shell--maybe-enable-chat-style)

(unless (advice-member-p #'my-files-agent-shell--after-chat-relabel
                         'agent-shell-chat--relabel)
  (advice-add 'agent-shell-chat--relabel :after
              #'my-files-agent-shell--after-chat-relabel))

(unless
    (advice-member-p
     #'my-files-agent-shell--send-request-with-codex-resume-fallback
     'agent-shell--send-request)
  (advice-add
   'agent-shell--send-request :around
   #'my-files-agent-shell--send-request-with-codex-resume-fallback))

;; The package can be loaded after conversations already exist (for example,
;; by invoking the browser command for the first time mid-session).
(when my-files-agent-shell-chat-style-enabled
  (dolist (buffer (agent-shell-buffers))
    (with-current-buffer buffer
      (if my-files-agent-shell-chat-style-mode
          ;; Rebuild labels when upgrading a live buffer from an older style.
          ;; This removes any display properties the previous implementation
          ;; placed on `Me' before applying the current user-message gutter.
          (agent-shell-chat--relabel)
        (my-files-agent-shell-chat-style-mode 1)))))

(provide 'my-files-agent-shell)
;;; my-files-agent-shell.el ends here
