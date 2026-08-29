;;; my-files-agent-shell-test.el --- Tests for My Files agent browser -*- lexical-binding: t; -*-

;;; Code:

(eval-and-compile
  (add-to-list
   'load-path
   (file-name-directory
    (or load-file-name
        (and (boundp 'byte-compile-current-file)
             byte-compile-current-file)
        buffer-file-name))))

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

(ert-deftest my-files-agent-shell-starts-new-chat-in-selected-project ()
  (let* ((project (make-temp-file "agent-shell-project-" t))
         (other (make-temp-file "agent-shell-other-" t))
         (caller (generate-new-buffer " agent-chat-panel-caller"))
         (main-buffer (generate-new-buffer " agent-chat-main"))
         (launched-chat (generate-new-buffer " launched-agent-chat"))
         (main-window (selected-window))
         (original-buffer (window-buffer main-window))
         (my-files-agent-shell--selected-project project)
         (my-files-agent-shell--main-window main-window)
         started-in)
    (unwind-protect
        (progn
          (with-current-buffer main-buffer
            (setq default-directory (file-name-as-directory other)))
          (set-window-buffer main-window main-buffer)
          (cl-letf (((symbol-function 'agent-shell)
                     (lambda (&optional _argument)
                       (setq started-in default-directory)
                       launched-chat))
                    ((symbol-function 'my-files-agent-shell--schedule-refresh)
                     #'ignore))
            (with-current-buffer caller
              (my-files-agent-shell--new-chat nil)))
          (should
           (equal (file-name-as-directory (file-truename started-in))
                  (file-name-as-directory (file-truename project))))
          (should
           (equal (buffer-local-value
                   'my-files-agent-shell--assigned-project launched-chat)
                  (my-files-agent-shell--canonical-directory project))))
      (set-window-buffer main-window original-buffer)
      (mapc #'kill-buffer (list caller main-buffer launched-chat))
      (delete-directory project t)
      (delete-directory other t))))

(ert-deftest my-files-agent-shell-assigns-running-main-chat-to-project ()
  (let* ((project (make-temp-file "agent-shell-project-" t))
         (other (make-temp-file "agent-shell-other-" t))
         (chat (generate-new-buffer " running-main-agent-chat"))
         (main-window (selected-window))
         (original-buffer (window-buffer main-window))
         (my-files-agent-shell--selected-project project)
         (my-files-agent-shell--main-window main-window))
    (unwind-protect
        (progn
          (with-current-buffer chat
            (setq default-directory (file-name-as-directory other)
                  major-mode 'agent-shell-mode))
          (set-window-buffer main-window chat)
          (cl-letf (((symbol-function 'agent-shell-buffers)
                     (lambda () (list chat)))
                    ((symbol-function 'my-files-agent-shell--schedule-refresh)
                     #'ignore))
            (my-files-agent-shell--render-chat-lists nil nil nil)
            (with-current-buffer my-files-agent-shell--chat-buffer-name
              (should
               (string-match-p "+ Assign current chat here"
                               (buffer-string))))
            (my-files-agent-shell--assign-main-chat-to-project nil))
          (should
           (equal (buffer-local-value
                   'my-files-agent-shell--assigned-project chat)
                  (my-files-agent-shell--canonical-directory project)))
          (should
           (equal (my-files-agent-shell--project-chat-buffers
                   project (list chat))
                  (list chat))))
      (set-window-buffer main-window original-buffer)
      (kill-buffer chat)
      (delete-directory project t)
      (delete-directory other t))))

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
    (should
     (equal (my-files-agent-shell--scaled-panel-widths
             150 '(12 14 16))
            '(12 14 16)))
    (let ((scaled (my-files-agent-shell--scaled-panel-widths 150)))
      (should (= (apply #'+ scaled) 75))
      (should (seq-every-p (lambda (width) (>= width 10)) scaled)))
    (let ((scaled (my-files-agent-shell--scaled-panel-widths 100)))
      (should (= (apply #'+ scaled) 50))
      (should (seq-every-p (lambda (width) (>= width 10)) scaled)))))

(ert-deftest my-files-agent-shell-sizes-panels-from-visible-text ()
  (let* ((area-name " *My Files Width Test Areas*")
         (project-name " *My Files Width Test Projects*")
         (chat-name " *My Files Width Test Chats*")
         (my-files-agent-shell--area-buffer-name area-name)
         (my-files-agent-shell--project-buffer-name project-name)
         (my-files-agent-shell--chat-buffer-name chat-name)
         (my-files-agent-shell-area-width 5)
         (my-files-agent-shell-project-width 5)
         (my-files-agent-shell-chat-width 5))
    (unwind-protect
        (progn
          (with-current-buffer (get-buffer-create area-name)
            (insert "1234567890"))
          (with-current-buffer (get-buffer-create project-name)
            (insert "123456789012345"))
          (with-current-buffer (get-buffer-create chat-name)
            (insert "12345678901234567890"))
          (should (equal (my-files-agent-shell--desired-panel-widths)
                         '(11 16 21))))
      (mapc #'kill-buffer (list area-name project-name chat-name)))))

(ert-deftest my-files-agent-shell-requires-compatible-shell-maker ()
  (should (fboundp 'shell-maker-start-v2)))

(ert-deftest my-files-agent-shell-uses-emacs-navigation-bindings ()
  (dolist (binding '(("C-n" . my-files-agent-shell-next-item)
                     ("C-p" . my-files-agent-shell-previous-item)
                     ("C-f" . my-files-agent-shell-next-panel)
                     ("C-b" . my-files-agent-shell-previous-panel)
                     ("a" . my-files-agent-shell-archive-at-point)))
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
    (should hl-line-sticky-flag)
    (should (eq hl-line-face 'my-files-agent-shell-cursor-inactive))))

(ert-deftest my-files-agent-shell-archives-highlighted-chat-with-a ()
  (let ((chat (generate-new-buffer " highlighted chat to archive"))
        (my-files-agent-shell--selected-project default-directory)
        archived)
    (unwind-protect
        (cl-letf (((symbol-function
                    'my-files-agent-shell--chat-status-symbol)
                   (lambda (_buffer) 'ready))
                  ((symbol-function 'my-files-agent-shell--chat-title)
                   #'buffer-name)
                  ((symbol-function 'my-files-agent-shell--subscribe-chat)
                   #'ignore)
                  ((symbol-function 'my-files-agent-shell--archive-chat)
                   (lambda (button)
                     (setq archived
                           (button-get
                            button 'my-files-agent-shell-buffer)))))
          (my-files-agent-shell--render-chat-lists (list chat) nil)
          (with-current-buffer my-files-agent-shell--chat-buffer-name
            (goto-char
             (button-start
              (my-files-agent-shell-test--button-with-property
               'my-files-agent-shell-buffer chat)))
            (my-files-agent-shell-archive-at-point))
          (should (eq archived chat)))
      (when (buffer-live-p chat)
        (kill-buffer chat)))))

(ert-deftest my-files-agent-shell-panels-remain-resizable ()
  (with-temp-buffer
    (my-files-agent-shell-mode)
    (should-not window-size-fixed)))

(ert-deftest my-files-agent-shell-keyboard-navigation-crosses-columns ()
  (my-files-agent-shell-test--with-tree ()
    (let* ((area (expand-file-name "Work" root))
           (project (file-name-as-directory
                     (expand-file-name "Project" area)))
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
            (let* ((windows (list my-files-agent-shell--area-window
                                  my-files-agent-shell--project-window
                                  my-files-agent-shell--chat-window
                                  my-files-agent-shell--main-window))
                   (total (apply #'+ (mapcar #'window-total-width windows)))
                   (panels (apply #'+
                                  (mapcar #'window-total-width
                                          (butlast windows)))))
              (should (<= panels (floor total 2))))
            (with-current-buffer my-files-agent-shell--area-buffer-name
              (should
               (eq (button-get
                    (my-files-agent-shell-test--button-with-property
                     'my-files-agent-shell-selected t)
                    'face)
                   'my-files-agent-shell-selected)))
            (my-files-agent-shell-next-panel)
            (should (eq (selected-window)
                        my-files-agent-shell--project-window))
            (with-current-buffer my-files-agent-shell--area-buffer-name
              (should
               (eq (button-get
                    (my-files-agent-shell-test--button-with-property
                     'my-files-agent-shell-selected t)
                    'face)
                   'my-files-agent-shell-selected-inactive)))
            (my-files-agent-shell-next-item)
            (should
             (equal (button-get (button-at (point))
                                'my-files-agent-shell-path)
                    project))
            (my-files-agent-shell-next-panel)
            (should (eq (selected-window)
                        my-files-agent-shell--chat-window))
            (set-window-point my-files-agent-shell--project-window
                              (point-min))
            (my-files-agent-shell-previous-panel)
            (should (eq (selected-window)
                        my-files-agent-shell--project-window))
            (should
             (equal (button-get (button-at (point))
                                'my-files-agent-shell-path)
                    project))
            (my-files-agent-shell-next-panel)
            (my-files-agent-shell-next-panel)
            (should (eq (selected-window)
                        my-files-agent-shell--main-window))
            (my-files-agent-shell-previous-panel)
            (should (eq (selected-window)
                        my-files-agent-shell--chat-window)))
        (when (my-files-agent-shell--visible-p)
          (my-files-agent-shell-close))
        (set-window-configuration configuration)))))

(ert-deftest my-files-agent-shell-reads-only-saved-chat-metadata ()
  (my-files-agent-shell-test--with-tree ()
    (let* ((project (expand-file-name "Work/Project" root))
           (file (expand-file-name ".agent-shell/transcripts/large.md" project))
           (original-insert-file-contents
            (symbol-function 'insert-file-contents))
           reads)
      (make-directory (file-name-directory file) t)
      (write-region
       (concat "# Agent Shell Transcript\n\n"
               "**Agent:** Codex\n"
               "**Session ID:** large-session\n\n---\n\n"
               "## User\n\nKeep this title cheap to discover.\n\n"
               (make-string (* 2 1024 1024) ?x))
       nil file nil 'silent)
      (cl-letf (((symbol-function 'insert-file-contents)
                 (lambda (filename &optional visit beg end replace)
                   (push (list beg end) reads)
                   (funcall original-insert-file-contents
                            filename visit beg end replace))))
        (let ((entry (my-files-agent-shell--read-transcript file project)))
          (should (equal (plist-get entry :session-id) "large-session"))
          (should (equal (plist-get entry :title)
                         "Keep this title cheap to discover."))))
      (should reads)
      (dolist (read reads)
        (should (numberp (cadr read)))
        (should (<= (- (cadr read) (or (car read) 0)) (* 64 1024)))))))

(ert-deftest my-files-agent-shell-lists-codex-metadata-without-scanning-rollouts ()
  (let (request)
    (cl-letf (((symbol-function 'codex-ide--request-async)
               (lambda (session method params _callback)
                 (setq request (list session method params)))))
      (my-files-agent-shell--codex-list-page 'query-session nil nil))
    (should (equal (nth 0 request) 'query-session))
    (should (equal (nth 1 request) "thread/list"))
    (should (eq (alist-get 'useStateDbOnly (nth 2 request)) t))))

(ert-deftest my-files-agent-shell-opens-codex-task-in-agent-shell-with-history ()
  (let* ((project (make-temp-file "agent-shell-codex-project-" t))
         (thread `((id . "codex-session-id")
                   (cwd . ,project)
                   (name . "Resume in Agent Shell")))
         (my-files-agent-shell--selected-project project)
         (my-files-agent-shell--main-window (selected-window))
         resumed-id
         resumed-directory
         restore-verbosity)
    (unwind-protect
        (with-temp-buffer
          (insert-text-button
           "Open"
           'my-files-agent-shell-codex-entry thread)
          (let ((button (button-at (point-min))))
            (cl-letf (((symbol-function 'my-files-agent-shell--agent-config)
                       #'ignore)
                      ((symbol-function 'agent-shell-resume-session)
                       (lambda (session-id)
                         (setq resumed-id session-id
                               resumed-directory default-directory
                               restore-verbosity
                               agent-shell-session-restore-verbosity))))
              (my-files-agent-shell--open-codex-chat button))))
      (delete-directory project t))
    (should (equal resumed-id "codex-session-id"))
    (should (equal (my-files-agent-shell--canonical-directory
                    resumed-directory)
                   (my-files-agent-shell--canonical-directory project)))
    (should (eq restore-verbosity 'first-last))))

(ert-deftest my-files-agent-shell-filters-chats-by-selected-area ()
  (my-files-agent-shell-test--with-tree ()
    (let* ((area (expand-file-name "Work" root))
           (project (expand-file-name "Project" area))
           (other-area (expand-file-name "Personal" root))
           (area-buffer (generate-new-buffer " area-chat"))
           (project-buffer (generate-new-buffer " project-chat"))
           (other-buffer (generate-new-buffer " other-area-chat")))
      (make-directory project t)
      (make-directory other-area t)
      (unwind-protect
          (progn
            (with-current-buffer area-buffer
              (setq default-directory (file-name-as-directory area)))
            (with-current-buffer project-buffer
              (setq default-directory (file-name-as-directory project)))
            (with-current-buffer other-buffer
              (setq default-directory (file-name-as-directory other-area)))
            (should
             (equal
              (my-files-agent-shell--area-chat-buffers
               area (list other-buffer project-buffer area-buffer))
              (list project-buffer area-buffer))))
        (mapc #'kill-buffer
              (list area-buffer project-buffer other-buffer))))))

(ert-deftest my-files-agent-shell-keeps-area-wide-scope-without-a-project ()
  (my-files-agent-shell-test--with-tree ()
    (let* ((area (expand-file-name "Work" root))
           (project (expand-file-name "Project" area))
           (my-files-agent-shell--selected-area
            (file-name-as-directory area))
           (my-files-agent-shell--selected-project nil)
           (my-files-agent-shell--codex-threads nil))
      (make-directory project t)
      (write-region "" nil (expand-file-name ".area.toml" area) nil 'silent)
      (write-region "" nil (expand-file-name ".project.toml" project)
                    nil 'silent)
      (cl-letf (((symbol-function 'agent-shell-buffers) #'ignore)
                ((symbol-function
                  'my-files-agent-shell--refresh-codex-threads)
                 #'ignore))
        (my-files-agent-shell-refresh))
      (should-not my-files-agent-shell--selected-project)
      (with-current-buffer my-files-agent-shell--project-buffer-name
        (should (string-match-p "All area chats" (buffer-string))))
      (with-current-buffer my-files-agent-shell--chat-buffer-name
        (should-not (string-match-p "Select a project" (buffer-string)))))))

(ert-deftest my-files-agent-shell-navigation-moves-between-rows ()
  (let ((first (generate-new-buffer "first chat"))
        (second (generate-new-buffer "second chat"))
        (my-files-agent-shell--selected-project default-directory))
    (unwind-protect
        (cl-letf (((symbol-function
                    'my-files-agent-shell--chat-status-symbol)
                   (lambda (_buffer) 'ready))
                  ((symbol-function 'my-files-agent-shell--chat-title)
                   #'buffer-name)
                  ((symbol-function 'my-files-agent-shell--subscribe-chat)
                   #'ignore))
          (my-files-agent-shell--render-chat-lists (list first second) nil)
          (with-current-buffer my-files-agent-shell--chat-buffer-name
            (let ((first-row
                   (my-files-agent-shell-test--button-with-property
                    'my-files-agent-shell-action 'open)))
              (goto-char (button-start first-row))
              (my-files-agent-shell-next-item)
              (let ((next-row (button-at (point))))
                (should (eq (button-get next-row 'my-files-agent-shell-action)
                            'open))
                (should (equal (button-label next-row)
                               "[ready] second chat"))))))
      (mapc #'kill-buffer (list first second)))))

(ert-deftest my-files-agent-shell-caches-saved-chat-metadata ()
  (my-files-agent-shell-test--with-tree
      ((my-files-agent-shell--transcript-metadata-cache
        (make-hash-table :test #'equal)))
    (let* ((project (expand-file-name "Work/Project" root))
           (file (expand-file-name ".agent-shell/transcripts/saved.md" project))
           (original-insert-file-contents
            (symbol-function 'insert-file-contents))
           (read-count 0))
      (make-directory (file-name-directory file) t)
      (write-region
       (concat "# Agent Shell Transcript\n\n"
               "**Agent:** Codex\n"
               "**Session ID:** cached-session\n\n---\n\n"
               "## User\n\nCache this title.\n")
       nil file nil 'silent)
      (cl-letf (((symbol-function 'insert-file-contents)
                 (lambda (&rest arguments)
                   (cl-incf read-count)
                   (apply original-insert-file-contents arguments))))
        (should (my-files-agent-shell--read-transcript file project))
        (should (my-files-agent-shell--read-transcript file project)))
      (should (= read-count 1)))))

(ert-deftest my-files-agent-shell-render-preserves-selected-chat-row ()
  (let ((first (generate-new-buffer "first preserved chat"))
        (second (generate-new-buffer "second preserved chat"))
        (my-files-agent-shell--selected-project default-directory))
    (unwind-protect
        (cl-letf (((symbol-function
                    'my-files-agent-shell--chat-status-symbol)
                   (lambda (_buffer) 'ready))
                  ((symbol-function 'my-files-agent-shell--chat-title)
                   #'buffer-name)
                  ((symbol-function 'my-files-agent-shell--subscribe-chat)
                   #'ignore))
          (my-files-agent-shell--render-chat-lists (list first second) nil)
          (with-current-buffer my-files-agent-shell--chat-buffer-name
            (goto-char
             (button-start
              (my-files-agent-shell-test--button-with-property
               'my-files-agent-shell-buffer second))))
          (my-files-agent-shell--render-chat-lists (list first second) nil)
          (with-current-buffer my-files-agent-shell--chat-buffer-name
            (let ((button (button-at (point))))
              (should (eq (button-get button 'my-files-agent-shell-buffer)
                          second)))))
      (mapc #'kill-buffer (list first second)))))

(ert-deftest my-files-agent-shell-ignores-unrelated-buffer-list-updates ()
  (let ((chat (generate-new-buffer "known agent chat"))
        (other (generate-new-buffer "unrelated buffer"))
        (my-files-agent-shell--known-chat-buffers nil)
        (refresh-count 0))
    (unwind-protect
        (cl-letf (((symbol-function 'agent-shell-buffers)
                   (lambda () (list chat)))
                  ((symbol-function 'my-files-agent-shell--schedule-refresh)
                   (lambda (&rest _arguments)
                     (cl-incf refresh-count))))
          (setq my-files-agent-shell--known-chat-buffers (list chat))
          (my-files-agent-shell--buffer-list-updated)
          (should (= refresh-count 0))
          (cl-letf (((symbol-function 'agent-shell-buffers)
                     (lambda () (list other chat))))
            (my-files-agent-shell--buffer-list-updated))
          (should (= refresh-count 1)))
      (mapc #'kill-buffer (list chat other)))))

(provide 'my-files-agent-shell-test)
;;; my-files-agent-shell-test.el ends here
