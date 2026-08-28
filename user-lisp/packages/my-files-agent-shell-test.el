;;; my-files-agent-shell-test.el --- Tests for My Files agent browser -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'my-files-agent-shell)

(defmacro my-files-agent-shell-test--with-tree (bindings &rest body)
  "Create a temporary My Files tree, bind BINDINGS, then evaluate BODY."
  (declare (indent 1))
  `(let ((root (make-temp-file "my-files-agent-shell-test-" t)))
     (unwind-protect
         (let ((my-files-agent-shell-root-directory root)
               ,@bindings)
           ,@body)
       (delete-directory root t))))

(defun my-files-agent-shell-test--button-with-property (property value)
  "Return the next button whose PROPERTY equals VALUE in the current buffer."
  (let ((button (next-button (point-min))))
    (while (and button (not (equal (button-get button property) value)))
      (setq button (next-button (button-end button))))
    button))

(ert-deftest my-files-agent-shell-discovers-only-marked-top-level-areas ()
  (my-files-agent-shell-test--with-tree ()
    (dolist (name '("Zulu" "alpha" "Unmarked"))
      (make-directory (expand-file-name name root)))
    (write-region "" nil (expand-file-name "Zulu/.area.toml" root) nil 'silent)
    (write-region "" nil (expand-file-name "alpha/.area.toml" root) nil 'silent)
    (should
     (equal (mapcar #'my-files-agent-shell--path-name
                    (my-files-agent-shell--discover-areas))
            '("alpha" "Zulu")))))

(ert-deftest my-files-agent-shell-discovers-projects-and-prunes-hidden-trees ()
  (my-files-agent-shell-test--with-tree ()
    (let ((area (expand-file-name "Work" root)))
      (dolist (path '("Client One" "Group/Client Two" ".codex/template"))
        (make-directory (expand-file-name path area) t)
        (write-region
         "" nil (expand-file-name ".project.toml" (expand-file-name path area))
         nil 'silent))
      (make-directory (expand-file-name "Client One/Nested" area) t)
      (write-region
       "" nil (expand-file-name "Client One/Nested/.project.toml" area)
       nil 'silent)
      (should
       (equal (mapcar
               (lambda (project)
                 (directory-file-name (file-relative-name project area)))
               (my-files-agent-shell--discover-projects area))
              '("Client One" "Group/Client Two"))))))

(ert-deftest my-files-agent-shell-filters-chats-by-selected-project ()
  (my-files-agent-shell-test--with-tree ()
    (let* ((project (expand-file-name "Work/Project" root))
           (other (expand-file-name "Work/Other" root))
           (project-buffer (generate-new-buffer " project-chat"))
           (nested-buffer (generate-new-buffer " worktree-chat"))
           (other-buffer (generate-new-buffer " other-chat")))
      (make-directory (expand-file-name "worktrees/feature" project) t)
      (make-directory other t)
      (unwind-protect
          (progn
            (with-current-buffer project-buffer
              (setq default-directory (file-name-as-directory project)))
            (with-current-buffer nested-buffer
              (setq default-directory
                    (file-name-as-directory
                     (expand-file-name "worktrees/feature" project))))
            (with-current-buffer other-buffer
              (setq default-directory (file-name-as-directory other)))
            (should
             (equal
              (my-files-agent-shell--project-chat-buffers
               project (list project-buffer other-buffer nested-buffer))
              (list project-buffer nested-buffer))))
        (mapc #'kill-buffer
              (list project-buffer nested-buffer other-buffer))))))

(ert-deftest my-files-agent-shell-discovers-resumable-transcript-history ()
  (my-files-agent-shell-test--with-tree ()
    (let* ((project (expand-file-name "Work/Project" root))
           (transcripts (expand-file-name ".agent-shell/transcripts" project))
           (saved-file (expand-file-name "saved.md" transcripts))
           (live-file (expand-file-name "live.md" transcripts)))
      (make-directory transcripts t)
      (write-region
       (concat "# Agent Shell Transcript\n\n"
               "**Agent:** Codex\n"
               "**Started:** 2026-08-24 16:18:34\n"
               "**Working Directory:** " project "/\n"
               "**Session ID:** saved-session\n\n---\n\n"
               "## User (2026-08-24 16:18:34)\n\n"
               "Build the area and project browser.\n")
       nil saved-file nil 'silent)
      (write-region
       (concat "# Agent Shell Transcript\n\n"
               "**Agent:** Codex\n"
               "**Session ID:** live-session\n\n---\n\n"
               "## User\n\nAlready open.\n")
       nil live-file nil 'silent)
      (let ((entries
             (my-files-agent-shell--discover-saved-chats
              project '("live-session"))))
        (should (= (length entries) 1))
        (should (equal (plist-get (car entries) :session-id)
                       "saved-session"))
        (should (equal (plist-get (car entries) :agent) "Codex"))
        (should (equal (plist-get (car entries) :title)
                       "Build the area and project browser."))))))

(ert-deftest my-files-agent-shell-centralizes-agent-data-at-workspace-root ()
  (my-files-agent-shell-test--with-tree ()
    (let* ((project (expand-file-name "Work/Project" root))
           (worktree (expand-file-name "worktrees/feature" project))
           (fallback (expand-file-name "Standard Project" root)))
      (make-directory worktree t)
      (make-directory fallback t)
      (write-region "" nil (expand-file-name ".project.toml" project)
                    nil 'silent)
      (cl-letf (((symbol-function 'agent-shell-cwd)
                 (lambda () worktree)))
        (should
         (equal (my-files-agent-shell-agent-data-directory "transcripts")
                (expand-file-name ".agent-shell/transcripts" project))))
      (cl-letf (((symbol-function 'agent-shell-cwd)
                 (lambda () fallback)))
        (should
         (equal (my-files-agent-shell-agent-data-directory "screenshots")
                (expand-file-name ".agent-shell/screenshots" fallback)))))))

(ert-deftest my-files-agent-shell-renders-codex-project-tasks ()
  (my-files-agent-shell-test--with-tree ()
    (let* ((project (expand-file-name "Work/Eaveside Migrator" root))
           (worktree (expand-file-name "worktrees/preview" project))
           (other (expand-file-name "Work/Other" root))
           (active `((id . "active-thread")
                     (cwd . ,worktree)
                     (name . "Improve preview record formatting")
                     (status . ((type . "active")))))
           (saved `((id . "saved-thread")
                    (cwd . ,project)
                    (name . "Fix activity import and sign-in")
                    (status . ((type . "notLoaded")))))
           (unrelated `((id . "other-thread")
                        (cwd . ,other)
                        (name . "Unrelated task")
                        (status . ((type . "active")))))
           (my-files-agent-shell--selected-project project)
           (my-files-agent-shell-chat-width 80))
      (make-directory worktree t)
      (make-directory other t)
      (let ((threads
             (my-files-agent-shell--project-codex-threads
              project (list unrelated active saved))))
        (should (equal threads (list active saved)))
        (my-files-agent-shell--render-chat-lists nil nil threads)
        (with-current-buffer my-files-agent-shell--chat-buffer-name
          (let ((text (buffer-string)))
            (should (string-match-p "In Progress (1)" text))
            (should (string-match-p "Staged (1)" text))
            (should (string-match-p "Improve preview record formatting" text))
            (should (string-match-p "Fix activity import and sign-in" text))
            (should-not (string-match-p "Unrelated task" text))))))))

(ert-deftest my-files-agent-shell-archives-codex-task-from-the-pane ()
  (let* ((thread '((id . "thread-to-archive")
                   (cwd . "/tmp/project")
                   (name . "Archive this task")
                   (status . ((type . "notLoaded")))))
         (my-files-agent-shell--selected-project "/tmp/project")
         archived)
    (cl-letf (((symbol-function 'yes-or-no-p) (lambda (_prompt) t))
              ((symbol-function 'my-files-agent-shell--request-codex-archive)
               (lambda (value) (setq archived value))))
      (my-files-agent-shell--render-chat-lists nil nil (list thread))
      (with-current-buffer my-files-agent-shell--chat-buffer-name
        (let ((archive-button
               (my-files-agent-shell-test--button-with-property
                'my-files-agent-shell-codex-thread thread)))
          (should archive-button)
          (button-activate archive-button)))
      (should (equal archived thread)))))

(ert-deftest my-files-agent-shell-persists-codex-archive-through-app-server ()
  (let* ((thread '((id . "thread-to-archive")
                   (name . "Archive this task")))
         (my-files-agent-shell--codex-session 'query-session)
         (my-files-agent-shell--codex-session-initialized t)
         (my-files-agent-shell--codex-threads (list thread))
         request)
    (cl-letf (((symbol-function 'my-files-agent-shell--codex-session-live-p)
               (lambda () t))
              ((symbol-function 'my-files-agent-shell--schedule-refresh)
               #'ignore)
              ((symbol-function 'codex-ide--request-async)
               (lambda (session method params callback)
                 (setq request (list session method params))
                 (funcall callback nil nil))))
      (my-files-agent-shell--request-codex-archive thread)
      (should
       (equal request
              '(query-session "thread/archive"
                              ((threadId . "thread-to-archive")))))
      (should-not my-files-agent-shell--codex-threads))))

(ert-deftest my-files-agent-shell-categorizes-live-chat-state ()
  (let ((buffer (generate-new-buffer " chat-category")))
    (unwind-protect
        (dolist (case '((busy . in-progress)
                        (blocked . in-progress)
                        (ready . staged)
                        (starting . in-progress)))
          (cl-letf (((symbol-function 'agent-shell-status)
                     (lambda (&rest _arguments) (car case))))
            (should (eq (my-files-agent-shell--chat-category buffer)
                        (cdr case)))))
      (kill-buffer buffer))))

(ert-deftest my-files-agent-shell-recategorizes-chat-when-its-state-changes ()
  (let ((chat (generate-new-buffer " recategorized chat"))
        (status 'ready)
        subscriptions
        (my-files-agent-shell--selected-project default-directory))
    (unwind-protect
        (cl-letf (((symbol-function 'agent-shell-subscribe-to)
                   (lambda (&rest arguments)
                     (push (cons (plist-get arguments :event)
                                 (plist-get arguments :on-event))
                           subscriptions)))
                  ((symbol-function
                    'my-files-agent-shell--chat-status-symbol)
                   (lambda (_buffer) status))
                  ((symbol-function 'my-files-agent-shell--chat-title)
                   #'buffer-name)
                  ((symbol-function
                    'my-files-agent-shell--schedule-refresh)
                   (lambda (&rest _arguments)
                     (my-files-agent-shell--render-chat-lists
                      (list chat) nil))))
          (my-files-agent-shell--render-chat-lists (list chat) nil)
          (with-current-buffer my-files-agent-shell--chat-buffer-name
            (should (string-match-p "In Progress (0)" (buffer-string)))
            (should (string-match-p "Staged (1)" (buffer-string))))
          (setq status 'busy)
          (let ((on-input-submitted
                 (alist-get 'input-submitted subscriptions)))
            (should on-input-submitted)
            (funcall on-input-submitted '((:event . input-submitted))))
          (with-current-buffer my-files-agent-shell--chat-buffer-name
            (should (string-match-p "In Progress (1)" (buffer-string)))
            (should (string-match-p "Staged (0)" (buffer-string))))
          (setq status 'ready)
          (let ((on-turn-complete
                 (alist-get 'turn-complete subscriptions)))
            (should on-turn-complete)
            (funcall on-turn-complete '((:event . turn-complete))))
          (with-current-buffer my-files-agent-shell--chat-buffer-name
            (should (string-match-p "In Progress (0)" (buffer-string)))
            (should (string-match-p "Staged (1)" (buffer-string)))))
      (kill-buffer chat))))

(ert-deftest my-files-agent-shell-renders-collapsible-chat-categories ()
  (let ((working (generate-new-buffer "working chat"))
        (ready (generate-new-buffer "ready chat"))
        (my-files-agent-shell--selected-project default-directory)
        (saved (list (list :session-id "completed-session"
                           :agent "Codex"
                           :title "Completed chat"
                           :project default-directory))))
    (unwind-protect
        (cl-letf (((symbol-function
                    'my-files-agent-shell--chat-status-symbol)
                   (lambda (buffer)
                     (if (eq buffer ready) 'ready 'busy)))
                  ((symbol-function 'my-files-agent-shell--chat-title)
                   #'buffer-name)
                  ((symbol-function 'my-files-agent-shell--subscribe-chat)
                   #'ignore))
          (my-files-agent-shell--render-chat-lists
           (list working ready) saved)
          (with-current-buffer my-files-agent-shell--chat-buffer-name
            (let* ((text (buffer-string))
                   (in-progress-position
                    (string-match "In Progress (1)" text))
                   (staged-position (string-match "Staged (1)" text))
                   (completed-position (string-match "Completed (1)" text))
                   (in-progress-button
                    (my-files-agent-shell-test--button-with-property
                     'my-files-agent-shell-category 'in-progress))
                   (body (button-get
                          in-progress-button
                          'my-files-agent-shell-body-overlay)))
              (should (< in-progress-position
                         staged-position
                         completed-position))
              (should in-progress-button)
              (should-not (overlay-get body 'invisible))
              (button-activate in-progress-button)
              (should (memq 'in-progress
                            my-files-agent-shell--collapsed-chat-sections))
              (should (overlay-get body 'invisible))
              (should (equal
                       (get-text-property
                        (button-start in-progress-button) 'display)
                       "▸"))
              (goto-char (button-start in-progress-button))
              (my-files-agent-shell-next-item)
              (should
               (eq (button-get (button-at (point))
                               'my-files-agent-shell-category)
                   'staged))
              (button-activate in-progress-button)
              (should-not (memq
                           'in-progress
                           my-files-agent-shell--collapsed-chat-sections))
              (should-not (overlay-get body 'invisible)))))
      (mapc #'kill-buffer (list working ready)))))

(ert-deftest my-files-agent-shell-archives-staged-chat-from-the-pane ()
  (let ((chat (generate-new-buffer " staged chat to archive"))
        (my-files-agent-shell--selected-project default-directory)
        refresh-scheduled)
    (cl-letf (((symbol-function 'my-files-agent-shell--chat-status-symbol)
               (lambda (_buffer) 'ready))
              ((symbol-function 'my-files-agent-shell--chat-title)
               #'buffer-name)
              ((symbol-function 'my-files-agent-shell--subscribe-chat)
               #'ignore)
              ((symbol-function 'yes-or-no-p)
               (lambda (_prompt) t))
              ((symbol-function 'my-files-agent-shell--schedule-refresh)
               (lambda (&rest _arguments)
                 (setq refresh-scheduled t))))
      (my-files-agent-shell--render-chat-lists (list chat) nil)
      (with-current-buffer my-files-agent-shell--chat-buffer-name
        (let ((archive-button
               (my-files-agent-shell-test--button-with-property
                'my-files-agent-shell-action 'archive)))
          (should archive-button)
          (button-activate archive-button)))
      (should-not (buffer-live-p chat))
      (should refresh-scheduled))))

(ert-deftest my-files-agent-shell-does-not-archive-in-progress-chat ()
  (let ((chat (generate-new-buffer " busy chat not archived"))
        (my-files-agent-shell--selected-project default-directory))
    (unwind-protect
        (cl-letf (((symbol-function
                    'my-files-agent-shell--chat-status-symbol)
                   (lambda (_buffer) 'busy))
                  ((symbol-function 'my-files-agent-shell--chat-title)
                   #'buffer-name)
                  ((symbol-function 'my-files-agent-shell--subscribe-chat)
                   #'ignore))
          (my-files-agent-shell--render-chat-lists (list chat) nil)
          (with-current-buffer my-files-agent-shell--chat-buffer-name
            (let ((archive-button
                   (my-files-agent-shell-test--button-with-property
                    'my-files-agent-shell-action 'archive)))
              (should archive-button)
              (should-error (button-activate archive-button)
                            :type 'user-error)))
          (should (buffer-live-p chat)))
      (when (buffer-live-p chat)
        (kill-buffer chat)))))

(ert-deftest my-files-agent-shell-scales-panels-to-preserve-main-window ()
  (let ((my-files-agent-shell-area-width 20)
        (my-files-agent-shell-project-width 30)
        (my-files-agent-shell-chat-width 40)
        (my-files-agent-shell-minimum-panel-width 10)
        (my-files-agent-shell-minimum-main-width 40))
    (should (equal (my-files-agent-shell--scaled-panel-widths 150)
                   '(20 30 40)))
    (let ((scaled (my-files-agent-shell--scaled-panel-widths 100)))
      (should (= (apply #'+ scaled) 60))
      (should (seq-every-p (lambda (width) (>= width 10)) scaled)))))

(ert-deftest my-files-agent-shell-requires-compatible-shell-maker ()
  (should (fboundp 'shell-maker-start-v2)))

(ert-deftest my-files-agent-shell-uses-emacs-navigation-bindings ()
  (dolist (binding '(("C-n" . my-files-agent-shell-next-item)
                     ("C-p" . my-files-agent-shell-previous-item)
                     ("C-f" . my-files-agent-shell-next-panel)
                     ("C-b" . my-files-agent-shell-previous-panel)))
    (should (eq (keymap-lookup my-files-agent-shell-mode-map (car binding))
                (cdr binding))))
  (dolist (key '("h" "j" "k" "l"))
    (should-not
     (memq (keymap-lookup my-files-agent-shell-mode-map key)
           '(my-files-agent-shell-next-item
             my-files-agent-shell-previous-item
             my-files-agent-shell-next-panel
             my-files-agent-shell-previous-panel)))))

(ert-deftest my-files-agent-shell-highlights-the-keyboard-focus-row ()
  (with-temp-buffer
    (my-files-agent-shell-mode)
    (should hl-line-mode)
    (should (local-variable-p 'hl-line-sticky-flag))
    (should-not hl-line-sticky-flag)))

(ert-deftest my-files-agent-shell-panels-remain-resizable ()
  (with-temp-buffer
    (my-files-agent-shell-mode)
    (should-not window-size-fixed)))

(ert-deftest my-files-agent-shell-keyboard-navigation-crosses-columns ()
  (my-files-agent-shell-test--with-tree ()
    (let* ((area (expand-file-name "Work" root))
           (project (expand-file-name "Project" area))
           (configuration (current-window-configuration)))
      (make-directory project t)
      (write-region "" nil (expand-file-name ".area.toml" area) nil 'silent)
      (write-region "" nil (expand-file-name ".project.toml" project) nil 'silent)
      (unwind-protect
          (progn
            (let ((ignore-window-parameters t))
              (delete-other-windows))
            (setq my-files-agent-shell--selected-area nil
                  my-files-agent-shell--selected-project nil)
            (my-files-agent-shell-open)
            (should (eq (selected-window)
                        my-files-agent-shell--area-window))
            (my-files-agent-shell-next-panel)
            (should (eq (selected-window)
                        my-files-agent-shell--project-window))
            (my-files-agent-shell-next-panel)
            (should (eq (selected-window)
                        my-files-agent-shell--chat-window))
            (my-files-agent-shell-next-panel)
            (should (eq (selected-window)
                        my-files-agent-shell--main-window))
            (my-files-agent-shell-previous-panel)
            (should (eq (selected-window)
                        my-files-agent-shell--chat-window)))
        (when (my-files-agent-shell--visible-p)
          (my-files-agent-shell-close))
        (set-window-configuration configuration)))))

(provide 'my-files-agent-shell-test)
;;; my-files-agent-shell-test.el ends here
