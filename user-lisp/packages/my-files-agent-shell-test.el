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
               (my-files-agent-shell-state-file
                (expand-file-name "conversation-state.json" root))
               (my-files-agent-shell--conversation-states
                (make-hash-table :test #'equal))
               (my-files-agent-shell--conversation-states-loaded t)
               (my-files-agent-shell--conversation-state-load-error nil)
               ,@bindings)
           ,@body)
       (delete-directory root t))))

(defmacro my-files-agent-shell-test--with-state (bindings &rest body)
  "Evaluate BODY with isolated conversation state and BINDINGS."
  (declare (indent 1))
  `(let ((state-root (make-temp-file "my-files-agent-shell-state-test-" t)))
     (unwind-protect
         (let ((my-files-agent-shell-state-file
                (expand-file-name "conversation-state.json" state-root))
               (my-files-agent-shell--conversation-states
                (make-hash-table :test #'equal))
               (my-files-agent-shell--conversation-states-loaded t)
               (my-files-agent-shell--conversation-state-load-error nil)
               ,@bindings)
           ,@body)
       (delete-directory state-root t))))

(defun my-files-agent-shell-test--set-session-id (buffer session-id)
  "Give Agent Shell BUFFER the stable SESSION-ID used by the browser."
  (with-current-buffer buffer
    (setq-local agent-shell--state
                `(:session (:id ,session-id)))))

(defun my-files-agent-shell-test--button-with-property (property value)
  "Return the next button whose PROPERTY equals VALUE in the current buffer."
  (let ((button (next-button (point-min))))
    (while (and button (not (equal (button-get button property) value)))
      (setq button (next-button (button-end button))))
    button))

(defun my-files-agent-shell-test--button-prefix (button)
  "Return the text on BUTTON's line before BUTTON."
  (save-excursion
    (goto-char (button-start button))
    (buffer-substring-no-properties (line-beginning-position) (point))))

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

(ert-deftest my-files-agent-shell-filters-scope-options-to-in-progress-chats ()
  (my-files-agent-shell-test--with-tree
      ((my-files-agent-shell--in-progress-only nil)
       (my-files-agent-shell--selected-area nil)
       (my-files-agent-shell--selected-project nil)
       (my-files-agent-shell--available-areas nil)
       (my-files-agent-shell--available-projects nil)
       (my-files-agent-shell--codex-threads nil))
    (let* ((work (expand-file-name "Work" root))
           (personal (expand-file-name "Personal" root))
           (empty (expand-file-name "Empty" root))
           (active (expand-file-name "Active" work))
           (review (expand-file-name "Review" work))
           (archived (expand-file-name "Archived" work))
           (codex-project (expand-file-name "Codex" personal))
           (review-transcript
            (expand-file-name ".agent-shell/transcripts/review.md" review))
           (archived-transcript
            (expand-file-name ".agent-shell/transcripts/archived.md"
                              archived))
           (live-chat (generate-new-buffer " in-progress filter chat"))
           (codex-thread
            `((id . "codex-in-progress")
              (cwd . ,codex-project)
              (name . "Codex in progress")
              (status . ((type . "notLoaded"))))))
      (unwind-protect
          (progn
            (dolist (area (list work personal empty))
              (make-directory area t)
              (write-region "" nil
                            (expand-file-name ".area.toml" area)
                            nil 'silent))
            (dolist (project (list active review archived codex-project))
              (make-directory project t)
              (write-region "" nil
                            (expand-file-name ".project.toml" project)
                            nil 'silent))
            (dolist (spec `((,review-transcript . "review-session")
                            (,archived-transcript . "archived-session")))
              (make-directory (file-name-directory (car spec)) t)
              (write-region
               (concat "# Agent Shell Transcript\n\n"
                       "**Agent:** Codex\n"
                       "**Session ID:** " (cdr spec) "\n\n---\n\n"
                       "## User\n\nFilter this conversation.\n")
               nil (car spec) nil 'silent))
            (my-files-agent-shell-test--set-session-id
             live-chat "live-in-progress")
            (with-current-buffer live-chat
              (setq default-directory (file-name-as-directory active)))
            (my-files-agent-shell--set-conversation-stage
             "agent:review-session" 'review)
            (my-files-agent-shell--set-conversation-archived
             "agent:archived-session" t)
            (setq my-files-agent-shell--selected-area
                  (my-files-agent-shell--canonical-directory work)
                  my-files-agent-shell--selected-project
                  (my-files-agent-shell--canonical-directory review)
                  my-files-agent-shell--codex-threads (list codex-thread))
            (cl-letf (((symbol-function 'agent-shell-buffers)
                       (lambda () (list live-chat)))
                      ((symbol-function
                        'my-files-agent-shell--subscribe-chat)
                       #'ignore)
                      ((symbol-function
                        'my-files-agent-shell--refresh-codex-threads)
                       #'ignore))
              (my-files-agent-shell-toggle-in-progress-filter)
              (should my-files-agent-shell--in-progress-only)
              (should-not my-files-agent-shell--selected-project)
              (should
               (member (my-files-agent-shell--canonical-directory work)
                       my-files-agent-shell--available-areas))
              (should
               (member (my-files-agent-shell--canonical-directory personal)
                       my-files-agent-shell--available-areas))
              (should-not
               (member (my-files-agent-shell--canonical-directory empty)
                       my-files-agent-shell--available-areas))
              (should
               (equal my-files-agent-shell--available-projects
                      (list
                       (my-files-agent-shell--canonical-directory active))))
              (my-files-agent-shell-toggle-in-progress-filter)
              (should-not my-files-agent-shell--in-progress-only)
              (should
               (member (my-files-agent-shell--canonical-directory empty)
                       my-files-agent-shell--available-areas))
              (dolist (project (list active review archived))
                (should
                 (member
                  (my-files-agent-shell--canonical-directory project)
                  my-files-agent-shell--available-projects)))))
        (kill-buffer live-chat)))))

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

(ert-deftest my-files-agent-shell-preserves-complete-saved-title-for-hover ()
  (my-files-agent-shell-test--with-tree ()
    (let* ((project (expand-file-name "Work/Project" root))
           (file (expand-file-name ".agent-shell/transcripts/long.md"
                                   project))
           (title (concat "Review this complete conversation title: "
                          (make-string 100 ?x))))
      (make-directory (file-name-directory file) t)
      (write-region
       (concat "# Agent Shell Transcript\n\n"
               "**Agent:** Codex\n"
               "**Session ID:** long-title-session\n\n---\n\n"
               "## User\n\n" title "\n")
       nil file nil 'silent)
      (let ((entry (my-files-agent-shell--read-transcript file project)))
        (should (equal (plist-get entry :full-title) title))
        (should (< (length (plist-get entry :title)) (length title)))
        (should (string-suffix-p "…" (plist-get entry :title)))))))

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
        (my-files-agent-shell--set-conversation-stage
         "codex:saved-thread" 'staged)
        (my-files-agent-shell--render-chat-lists nil nil threads)
        (with-current-buffer my-files-agent-shell--chat-buffer-name
          (let ((text (buffer-string)))
            (should (string-match-p "Active Conversations (2)" text))
            (should (string-match-p "In Progress (1)" text))
            (should (string-match-p "Staged (1)" text))
            (should (string-match-p "Review (0)" text))
            (should (string-match-p "Completed (0)" text))
            (should (string-match-p "Archived (0)" text))
            (should (string-match-p "Improve preview record formatting" text))
            (should (string-match-p "Fix activity import and sign-in" text))
            (should-not (string-match-p "Unrelated task" text))))))))

(ert-deftest my-files-agent-shell-coalesces-codex-task-with-live-session ()
  (my-files-agent-shell-test--with-state
      ((my-files-agent-shell--selected-project default-directory))
    (let* ((thread
            `((id . "shared-session")
              (cwd . ,default-directory)
              (name . "Shared conversation")
              (status . ((type . "notLoaded")))))
           (chat (generate-new-buffer " shared conversation"))
           (my-files-agent-shell--codex-threads (list thread)))
      (unwind-protect
          (progn
            (my-files-agent-shell--set-conversation-stage
             "codex:shared-session" 'review)
            (my-files-agent-shell--render-chat-lists nil nil (list thread))
            (my-files-agent-shell-test--set-session-id chat "shared-session")
            (cl-letf (((symbol-function 'agent-shell-buffers)
                       (lambda () (list chat)))
                      ((symbol-function
                        'my-files-agent-shell--chat-status-symbol)
                       (lambda (_buffer) 'ready))
                      ((symbol-function 'my-files-agent-shell--chat-title)
                       (lambda (_buffer) "Shared conversation"))
                      ((symbol-function
                        'my-files-agent-shell--subscribe-chat)
                       #'ignore))
              (my-files-agent-shell--render-chat-lists
               (list chat) nil (list thread)))
            (with-current-buffer my-files-agent-shell--chat-buffer-name
              (let ((button (next-button (point-min)))
                    rows)
                (while button
                  (when (or
                         (eq (button-get button
                                         'my-files-agent-shell-buffer)
                             chat)
                         (equal
                          (alist-get
                           'id
                           (button-get
                            button 'my-files-agent-shell-codex-entry))
                          "shared-session"))
                    (push button rows))
                  (setq button (next-button (button-end button))))
                (should (= (length rows) 2))
                (should
                 (equal
                  (sort
                   (mapcar
                    (lambda (row)
                      (button-get row 'my-files-agent-shell-section))
                    rows)
                   (lambda (left right)
                     (string< (symbol-name left) (symbol-name right))))
                  '(active review)))
                (dolist (row rows)
                  (should (eq (button-get row
                                          'my-files-agent-shell-buffer)
                              chat))
                  (should (string-prefix-p "[ready] "
                                           (button-label row)))))))
        (kill-buffer chat)))))

(ert-deftest my-files-agent-shell-archives-codex-task-from-the-pane ()
  (my-files-agent-shell-test--with-state
      ((my-files-agent-shell--selected-project "/tmp/project")
       refresh-scheduled)
    (let ((thread '((id . "thread-to-archive")
                    (cwd . "/tmp/project")
                    (name . "Archive this task")
                    (status . ((type . "notLoaded"))))))
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (_prompt) t))
                ((symbol-function 'my-files-agent-shell--schedule-refresh)
                 (lambda (&rest _arguments)
                   (setq refresh-scheduled t))))
        (my-files-agent-shell--render-chat-lists nil nil (list thread))
        (with-current-buffer my-files-agent-shell--chat-buffer-name
          (goto-char
           (button-start
            (my-files-agent-shell-test--button-with-property
             'my-files-agent-shell-conversation-key
             "codex:thread-to-archive")))
          (my-files-agent-shell-archive-at-point))
        (should refresh-scheduled)
        (should
         (my-files-agent-shell--conversation-archived-p
          "codex:thread-to-archive"))
        (my-files-agent-shell--render-chat-lists nil nil (list thread))
        (with-current-buffer my-files-agent-shell--chat-buffer-name
          (let ((text (buffer-string)))
            (should (string-match-p "Active Conversations (0)" text))
            (should (string-match-p "In Progress (0)" text))
            (should (string-match-p "Archived (1)" text))))))))

(ert-deftest my-files-agent-shell-deletes-archived-task-from-manager ()
  (my-files-agent-shell-test--with-state
      ((my-files-agent-shell--selected-project "/tmp/project"))
    (let ((thread '((id . "thread-to-delete")
                    (cwd . "/tmp/project")
                    (name . "Never show this task again")
                    (status . ((type . "notLoaded"))))))
      (my-files-agent-shell--set-conversation-archived
       "codex:thread-to-delete" t)
      (cl-letf (((symbol-function 'yes-or-no-p) (lambda (_prompt) t))
                ((symbol-function 'my-files-agent-shell--schedule-refresh)
                 #'ignore))
        (my-files-agent-shell--render-chat-lists nil nil (list thread))
        (with-current-buffer my-files-agent-shell--chat-buffer-name
          (goto-char
           (button-start
            (my-files-agent-shell-test--button-with-property
             'my-files-agent-shell-conversation-key
             "codex:thread-to-delete")))
          (my-files-agent-shell-delete-at-point))
        (should
         (my-files-agent-shell--conversation-deleted-p
          "codex:thread-to-delete"))
        (my-files-agent-shell--render-chat-lists nil nil (list thread))
        (with-current-buffer my-files-agent-shell--chat-buffer-name
          (should-not
           (string-match-p "Never show this task again" (buffer-string))))))))

(ert-deftest my-files-agent-shell-persists-workflow-state-as-json ()
  (my-files-agent-shell-test--with-state ()
    (my-files-agent-shell--set-conversation-stage
     "codex:persistent-thread" 'review)
    (my-files-agent-shell--set-conversation-archived
     "codex:persistent-thread" t)
    (my-files-agent-shell--set-conversation-deleted
     "codex:persistent-thread" t)
    (should (= (file-modes my-files-agent-shell-state-file) #o600))
    (setq my-files-agent-shell--conversation-states
          (make-hash-table :test #'equal)
          my-files-agent-shell--conversation-states-loaded nil)
    (should
     (eq (my-files-agent-shell--conversation-stage
          "codex:persistent-thread")
         'review))
    (should
     (my-files-agent-shell--conversation-archived-p
      "codex:persistent-thread"))
    (should
     (my-files-agent-shell--conversation-deleted-p
      "codex:persistent-thread"))))

(ert-deftest my-files-agent-shell-loads-state-without-deletion-field ()
  (my-files-agent-shell-test--with-state ()
    (write-region
     (concat "{\"version\":1,\"conversations\":[{"
             "\"key\":\"codex:legacy-thread\","
             "\"stage\":\"review\",\"archived\":false}]}\n")
     nil my-files-agent-shell-state-file nil 'silent)
    (setq my-files-agent-shell--conversation-states-loaded nil)
    (should
     (eq (my-files-agent-shell--conversation-stage "codex:legacy-thread")
         'review))
    (should-not
     (my-files-agent-shell--conversation-deleted-p
      "codex:legacy-thread"))))

(ert-deftest my-files-agent-shell-starts-new-chat-in-empty-marker-project ()
  (let* ((project (make-temp-file "agent-shell-project-" t))
         (other (make-temp-file "agent-shell-other-" t))
         (caller (generate-new-buffer " agent-chat-panel-caller"))
         (main-buffer (generate-new-buffer " agent-chat-main"))
         (launched-chat (generate-new-buffer " launched-agent-chat"))
         (config '((:identifier . codex)))
         (main-window (selected-window))
         (original-buffer (window-buffer main-window))
         (my-files-agent-shell--selected-project project)
         (my-files-agent-shell--main-window main-window)
         started-in)
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (write-region "" nil (expand-file-name ".project.toml" project)
                        nil 'silent)
          (with-current-buffer main-buffer
            (setq default-directory (file-name-as-directory other)))
          (set-window-buffer main-window main-buffer)
          (cl-letf (((symbol-function 'agent-shell-start)
                     (lambda (&rest _arguments)
                       (setq started-in
                             (if agent-shell-cwd-function
                                 (funcall agent-shell-cwd-function)
                               other))
                       (display-buffer
                        launched-chat '(display-buffer-pop-up-window))
                       launched-chat))
                    ((symbol-function 'agent-shell-select-config)
                     (lambda (&rest _arguments) config))
                    ((symbol-function 'my-files-agent-shell--schedule-refresh)
                     #'ignore))
            (with-current-buffer caller
              (my-files-agent-shell--new-chat nil)))
          (should (= (length (window-list)) 1))
          (should (eq (window-buffer main-window) launched-chat))
          (should
           (equal (file-name-as-directory (file-truename started-in))
                  (file-name-as-directory (file-truename project))))
          (should
           (equal (buffer-local-value
                   'my-files-agent-shell--assigned-project launched-chat)
                  (my-files-agent-shell--canonical-directory project)))
          (should
           (equal
            (funcall
             (buffer-local-value 'agent-shell-cwd-function launched-chat))
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

(ert-deftest my-files-agent-shell-defaults-to-in-progress-regardless-of-runtime ()
  (my-files-agent-shell-test--with-state
      ((my-files-agent-shell--selected-project default-directory))
    (let ((chat (generate-new-buffer " manually categorized chat")))
      (unwind-protect
          (progn
            (my-files-agent-shell-test--set-session-id chat "manual-default")
            (dolist (status '(busy blocked ready starting))
              (cl-letf (((symbol-function
                          'my-files-agent-shell--chat-status-symbol)
                         (lambda (_buffer) status))
                        ((symbol-function 'my-files-agent-shell--chat-title)
                         #'buffer-name)
                        ((symbol-function
                          'my-files-agent-shell--subscribe-chat)
                         #'ignore))
                (my-files-agent-shell--render-chat-lists (list chat) nil)
                (with-current-buffer my-files-agent-shell--chat-buffer-name
                  (let ((text (buffer-string)))
                    (should (string-match-p
                             "Active Conversations (1)" text))
                    (should (string-match-p "In Progress (1)" text))
                    (should (string-match-p "Review (0)" text))
                    (should (string-match-p "Staged (0)" text)))))))
        (kill-buffer chat)))))

(ert-deftest my-files-agent-shell-moves-stage-manually-and-keeps-it ()
  (my-files-agent-shell-test--with-state
      ((my-files-agent-shell--selected-project default-directory))
    (let ((chat (generate-new-buffer " manually moved chat"))
          (status 'ready)
          subscriptions)
      (unwind-protect
          (progn
            (my-files-agent-shell-test--set-session-id chat "manual-move")
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
                      ((symbol-function 'completing-read)
                       (lambda (&rest _arguments) "Review"))
                      ((symbol-function
                        'my-files-agent-shell--schedule-refresh)
                       (lambda (&rest _arguments)
                         (my-files-agent-shell--render-chat-lists
                          (list chat) nil))))
              (my-files-agent-shell--render-chat-lists (list chat) nil)
              (with-current-buffer my-files-agent-shell--chat-buffer-name
                (goto-char
                 (button-start
                  (my-files-agent-shell-test--button-with-property
                   'my-files-agent-shell-conversation-key
                   "agent:manual-move")))
                (my-files-agent-shell-move-at-point))
              (should
               (eq (my-files-agent-shell--conversation-stage
                    "agent:manual-move")
                   'review))
              (setq status 'busy)
              (let ((on-input-submitted
                     (alist-get 'input-submitted subscriptions)))
                (should on-input-submitted)
                (funcall on-input-submitted '((:event . input-submitted))))
              (with-current-buffer my-files-agent-shell--chat-buffer-name
                (let ((text (buffer-string)))
                  (should (string-match-p "Active Conversations (1)" text))
                  (should (string-match-p "In Progress (0)" text))
                  (should (string-match-p "Review (1)" text))
                  (should (string-match-p "Staged (0)" text))))))
        (kill-buffer chat)))))

(ert-deftest my-files-agent-shell-renders-collapsible-chat-categories ()
  (my-files-agent-shell-test--with-state
      ((my-files-agent-shell--selected-project default-directory))
    (let ((working (generate-new-buffer "working chat"))
          (ready (generate-new-buffer "ready chat"))
          (saved (list (list :session-id "completed-session"
                             :agent "Codex"
                             :title "Completed chat"
                             :project default-directory))))
      (unwind-protect
          (progn
            (my-files-agent-shell-test--set-session-id working "working")
            (my-files-agent-shell-test--set-session-id ready "ready")
            (my-files-agent-shell--set-conversation-stage
             "agent:ready" 'staged)
            (my-files-agent-shell--set-conversation-stage
             "agent:completed-session" 'completed)
            (cl-letf (((symbol-function
                        'my-files-agent-shell--chat-status-symbol)
                       (lambda (buffer)
                         (if (eq buffer ready) 'ready 'busy)))
                      ((symbol-function 'my-files-agent-shell--chat-title)
                       #'buffer-name)
                      ((symbol-function
                        'my-files-agent-shell--subscribe-chat)
                       #'ignore))
              (my-files-agent-shell--render-chat-lists
               (list working ready) saved)
              (with-current-buffer my-files-agent-shell--chat-buffer-name
                (let* ((text (buffer-string))
                       (active-position
                        (string-match "Active Conversations (3)" text))
                       (in-progress-position
                        (string-match "In Progress (1)" text))
                       (review-position (string-match "Review (0)" text))
                       (staged-position (string-match "Staged (1)" text))
                       (completed-position
                        (string-match "Completed (1)" text))
                       (archived-position (string-match "Archived (0)" text))
                       (in-progress-button
                        (my-files-agent-shell-test--button-with-property
                         'my-files-agent-shell-category 'in-progress))
                       (body (button-get
                              in-progress-button
                              'my-files-agent-shell-body-overlay)))
                  (should (< in-progress-position
                             review-position
                             staged-position
                             completed-position
                             active-position
                             archived-position))
                  (should in-progress-button)
                  (should-not (overlay-get body 'invisible))
                  (button-activate in-progress-button)
                  (should (memq
                           'in-progress
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
                       'review))
                  (button-activate in-progress-button)
                  (should-not (memq
                               'in-progress
                               my-files-agent-shell--collapsed-chat-sections))
                  (should-not (overlay-get body 'invisible))))))
        (mapc #'kill-buffer (list working ready))))))

(ert-deftest my-files-agent-shell-archives-live-chat-nondestructively ()
  (my-files-agent-shell-test--with-state
      ((my-files-agent-shell--selected-project default-directory)
       refresh-scheduled)
    (let ((chat (generate-new-buffer " busy chat to archive")))
      (unwind-protect
          (progn
            (my-files-agent-shell-test--set-session-id chat "busy-archive")
            (cl-letf (((symbol-function
                        'my-files-agent-shell--chat-status-symbol)
                       (lambda (_buffer) 'busy))
                      ((symbol-function 'my-files-agent-shell--chat-title)
                       #'buffer-name)
                      ((symbol-function
                        'my-files-agent-shell--subscribe-chat)
                       #'ignore)
                      ((symbol-function 'yes-or-no-p)
                       (lambda (_prompt) t))
                      ((symbol-function
                        'my-files-agent-shell--schedule-refresh)
                       (lambda (&rest _arguments)
                         (setq refresh-scheduled t))))
              (my-files-agent-shell--render-chat-lists (list chat) nil)
              (with-current-buffer my-files-agent-shell--chat-buffer-name
                (goto-char
                 (button-start
                  (my-files-agent-shell-test--button-with-property
                   'my-files-agent-shell-conversation-key
                   "agent:busy-archive")))
                (my-files-agent-shell-archive-at-point))
              (should (buffer-live-p chat))
              (should refresh-scheduled)
              (should
               (my-files-agent-shell--conversation-archived-p
                "agent:busy-archive"))))
        (when (buffer-live-p chat)
          (kill-buffer chat))))))

(ert-deftest my-files-agent-shell-scales-chat-list-to-preserve-main-window ()
  (let ((my-files-agent-shell-chat-width 400)
        (my-files-agent-shell-minimum-panel-width 10)
        (my-files-agent-shell-minimum-main-width 40))
    (should (= (my-files-agent-shell--scaled-chat-width 150 16) 16))
    (should (= (my-files-agent-shell--scaled-chat-width 150) 75))
    (should (= (my-files-agent-shell--scaled-chat-width 100) 50))
    (should-error (my-files-agent-shell--scaled-chat-width 49)
                  :type 'user-error)))

(ert-deftest my-files-agent-shell-sizes-chat-list-from-visible-text ()
  (let* ((chat-name " *My Files Width Test Chats*")
         (my-files-agent-shell--chat-buffer-name chat-name)
         (my-files-agent-shell-chat-width 5)
         (my-files-agent-shell-chat-content-maximum-width 48))
    (unwind-protect
        (progn
          (with-current-buffer (get-buffer-create chat-name)
            (insert "12345678901234567890"))
          (should (= (my-files-agent-shell--desired-chat-width) 21))
          (with-current-buffer chat-name
            (erase-buffer)
            (insert (make-string 100 ?x)))
          (should (= (my-files-agent-shell--desired-chat-width) 48)))
      (kill-buffer chat-name))))

(ert-deftest my-files-agent-shell-requires-compatible-shell-maker ()
  (should (fboundp 'shell-maker-start-v2)))

(ert-deftest my-files-agent-shell-uses-emacs-navigation-bindings ()
  (dolist (binding '(("C-n" . my-files-agent-shell-next-item)
                     ("C-p" . my-files-agent-shell-previous-item)
                     ("C-f" . my-files-agent-shell-next-panel)
                     ("C-b" . my-files-agent-shell-previous-panel)
                     ("1" . my-files-agent-shell-select-area)
                     ("2" . my-files-agent-shell-select-project)
                     ("v" . my-files-agent-shell-select-scope)
                     ("SPC" . my-files-agent-shell-toggle-mark-at-point)
                     ("i" . my-files-agent-shell-toggle-in-progress-filter)
                     ("a" . my-files-agent-shell-archive-at-point)
                     ("d" . my-files-agent-shell-delete-at-point)
                     ("m" . my-files-agent-shell-move-at-point)
                     ("u" . my-files-agent-shell-restore-at-point)
                     ("U" . my-files-agent-shell-unmark-all)))
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

(ert-deftest my-files-agent-shell-chat-panel-has-modeline-and-scope-toolbar ()
  (let ((my-files-agent-shell--selected-area "/tmp/Work/")
        (my-files-agent-shell--selected-project "/tmp/Work/Client/"))
    (with-temp-buffer
      (my-files-agent-shell-chat-mode)
      (should (equal mode-name "Agent Chats"))
      (should (equal mode-line-format '(" " mode-name " ")))
      (should (equal header-line-format
                     '(:eval (my-files-agent-shell--scope-toolbar))))
      (let* ((toolbar (my-files-agent-shell--scope-toolbar))
             (area-button (nth 1 toolbar))
             (project-button (nth 3 toolbar))
             (filter-button (nth 5 toolbar)))
        (should (string-match-p "Area: Work" area-button))
        (should (string-match-p "Project: Client" project-button))
        (should (string-match-p "In Progress: All" filter-button))
        (should
         (eq (keymap-lookup
              (get-text-property 0 'local-map area-button)
              "<header-line> <mouse-1>")
             #'my-files-agent-shell-select-area))
        (should
         (eq (keymap-lookup
              (get-text-property 0 'local-map project-button)
              "<header-line> <mouse-1>")
             #'my-files-agent-shell-select-project))
        (should
         (eq (keymap-lookup
              (get-text-property 0 'local-map filter-button)
              "<header-line> <mouse-1>")
             #'my-files-agent-shell-toggle-in-progress-filter))))))

(ert-deftest my-files-agent-shell-restores-highlighted-chat-with-u ()
  (my-files-agent-shell-test--with-state
      ((my-files-agent-shell--selected-project default-directory)
       refresh-scheduled)
    (let ((chat (generate-new-buffer " highlighted chat to restore")))
      (unwind-protect
          (progn
            (my-files-agent-shell-test--set-session-id chat "restore-me")
            (my-files-agent-shell--set-conversation-archived
             "agent:restore-me" t)
            (cl-letf (((symbol-function
                        'my-files-agent-shell--chat-status-symbol)
                       (lambda (_buffer) 'ready))
                      ((symbol-function 'my-files-agent-shell--chat-title)
                       #'buffer-name)
                      ((symbol-function
                        'my-files-agent-shell--subscribe-chat)
                       #'ignore)
                      ((symbol-function
                        'my-files-agent-shell--schedule-refresh)
                       (lambda (&rest _arguments)
                         (setq refresh-scheduled t))))
              (my-files-agent-shell--render-chat-lists (list chat) nil)
              (with-current-buffer my-files-agent-shell--chat-buffer-name
                (goto-char
                 (button-start
                  (my-files-agent-shell-test--button-with-property
                   'my-files-agent-shell-conversation-key
                   "agent:restore-me")))
                (my-files-agent-shell-restore-at-point))
              (should refresh-scheduled)
              (should-not
               (my-files-agent-shell--conversation-archived-p
                "agent:restore-me"))))
        (when (buffer-live-p chat)
          (kill-buffer chat))))))

(ert-deftest my-files-agent-shell-panels-remain-resizable ()
  (with-temp-buffer
    (my-files-agent-shell-mode)
    (should-not window-size-fixed)))

(ert-deftest my-files-agent-shell-selects-scopes-without-extra-windows ()
  (my-files-agent-shell-test--with-tree ()
    (let* ((area (expand-file-name "Work" root))
           (project (file-name-as-directory
                     (expand-file-name "Project" area)))
           (configuration (current-window-configuration))
           (selections '("Work" "Project" "All area chats"))
           (my-files-agent-shell--available-areas nil)
           (my-files-agent-shell--available-projects nil)
           prompts)
      (make-directory project t)
      (write-region "" nil (expand-file-name ".area.toml" area) nil 'silent)
      (write-region "" nil (expand-file-name ".project.toml" project) nil 'silent)
      (unwind-protect
          (cl-letf (((symbol-function 'agent-shell-buffers) #'ignore)
                    ((symbol-function
                      'my-files-agent-shell--refresh-codex-threads)
                     #'ignore)
                    ((symbol-function 'completing-read)
                     (lambda (prompt &rest _arguments)
                       (push prompt prompts)
                       (pop selections))))
            (let ((ignore-window-parameters t))
              (delete-other-windows))
            (setq my-files-agent-shell--selected-area nil
                  my-files-agent-shell--selected-project nil)
            (my-files-agent-shell-open)
            (should (= (length (window-list)) 2))
            (my-files-agent-shell-select-area)
            (should
             (equal my-files-agent-shell--selected-area
                    (my-files-agent-shell--canonical-directory area)))
            (should-not my-files-agent-shell--selected-project)
            (should (= (length (window-list)) 2))
            (my-files-agent-shell-select-project)
            (should
             (equal my-files-agent-shell--selected-project
                    (my-files-agent-shell--canonical-directory project)))
            (should (= (length (window-list)) 2))
            (my-files-agent-shell-select-project)
            (should-not my-files-agent-shell--selected-project)
            (should (equal (nreverse prompts)
                           '("Area: " "Project in Work: "
                             "Project in Work: "))))
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
         (resumed-chat (generate-new-buffer " resumed codex task"))
         (placeholder (generate-new-buffer " resume placeholder"))
         (config '((:identifier . codex)))
         (my-files-agent-shell--selected-project project)
         (my-files-agent-shell--main-window (selected-window))
         resumed-id
         resumed-directory
         restore-verbosity)
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (set-window-buffer my-files-agent-shell--main-window placeholder)
          (with-temp-buffer
            (insert-text-button
             "Open"
             'my-files-agent-shell-codex-entry thread)
            (let ((button (button-at (point-min))))
              (cl-letf (((symbol-function 'agent-shell-buffers) #'ignore)
                        ((symbol-function
                          'my-files-agent-shell--agent-config)
                         #'ignore)
                        ((symbol-function 'agent-shell-select-config)
                         (lambda (&rest _arguments) config))
                        ((symbol-function 'agent-shell-start)
                         (lambda (&rest arguments)
                           (setq resumed-id (plist-get arguments :session-id)
                                 resumed-directory default-directory
                                 restore-verbosity
                                 agent-shell-session-restore-verbosity)
                           (display-buffer
                            resumed-chat '(display-buffer-pop-up-window))
                           resumed-chat)))
                (my-files-agent-shell--open-codex-chat button))))
          (should (= (length (window-list)) 1))
          (should
           (eq (window-buffer my-files-agent-shell--main-window)
               resumed-chat))
          (should (equal (buffer-name resumed-chat)
                         "Resume in Agent Shell")))
      (mapc #'kill-buffer (list resumed-chat placeholder))
      (delete-directory project t))
    (should (equal resumed-id "codex-session-id"))
    (should (equal (my-files-agent-shell--canonical-directory
                    resumed-directory)
                   (my-files-agent-shell--canonical-directory project)))
    (should (eq restore-verbosity 'first-last))))

(ert-deftest my-files-agent-shell-retries-codex-history-load-with-resume ()
  (let* ((buffer (generate-new-buffer " codex history fallback"))
         (state '((:agent-config . ((:identifier . codex)))
                  (:supports-session-resume . t)
                  (:pending-restore . ((:prompt-turns . (nil))))))
         (load-request
          (acp-make-session-load-request
           :session-id "paginated-session"
           :cwd default-directory
           :mcp-servers '(((name . "example")))))
         methods
         fallback-text
         response
         resume-request
         failure)
    (unwind-protect
        (cl-letf (((symbol-function
                    'agent-shell--update-bootstrapping-fragment)
                   (lambda (&rest arguments)
                     (setq fallback-text (plist-get arguments :body))))
                  ((symbol-function 'agent-shell--make-boxed-message)
                   (lambda (&rest arguments)
                     (plist-get arguments :text))))
          (my-files-agent-shell--send-request-with-codex-resume-fallback
           (lambda (&rest arguments)
             (let* ((request (plist-get arguments :request))
                    (method (map-elt request :method)))
               (setq methods (append methods (list method)))
               (if (equal method "session/load")
                   (funcall
                    (plist-get arguments :on-failure)
                    '((code . -32603) (message . "Internal error"))
                    '((details . "paginated threads do not support thread/read(includeTurns=true)")))
                 (setq resume-request request)
                 (funcall (plist-get arguments :on-success)
                          '((models . []))))))
           :state state
           :client 'client
           :request load-request
           :buffer buffer
           :on-success (lambda (result) (setq response result))
           :on-failure (lambda (error-data raw-message)
                         (setq failure (list error-data raw-message)))))
      (kill-buffer buffer))
    (should (equal methods '("session/load" "session/resume")))
    (should
     (equal (map-nested-elt resume-request '(:params sessionId))
            "paginated-session"))
    (should
     (equal (map-nested-elt resume-request '(:params cwd))
            (directory-file-name (expand-file-name default-directory))))
    (should
     (equal (map-nested-elt resume-request '(:params mcpServers))
            '(((name . "example")))))
    (should (equal (map-elt response 'models) []))
    (should-not failure)
    (should-not (map-elt state :pending-restore))
    (should (string-match-p "without history" fallback-text))))

(ert-deftest my-files-agent-shell-keeps-codex-load-error-when-resume-fails ()
  (let* ((buffer (generate-new-buffer " codex failed fallback"))
         (state '((:agent-config . ((:identifier . codex)))
                  (:supports-session-resume . t)
                  (:pending-restore . nil)))
         (load-request
          (acp-make-session-load-request
           :session-id "unavailable-session"
           :cwd default-directory))
         methods
         failure)
    (unwind-protect
        (cl-letf (((symbol-function
                    'agent-shell--update-bootstrapping-fragment)
                   #'ignore)
                  ((symbol-function 'agent-shell--make-boxed-message)
                   (lambda (&rest arguments)
                     (plist-get arguments :text))))
          (my-files-agent-shell--send-request-with-codex-resume-fallback
           (lambda (&rest arguments)
             (let ((method
                    (map-elt (plist-get arguments :request) :method)))
               (setq methods (append methods (list method)))
               (funcall
                (plist-get arguments :on-failure)
                `((code . -32603) (message . ,method))
                `((method . ,method)))))
           :state state
           :client 'client
           :request load-request
           :buffer buffer
           :on-success #'ignore
           :on-failure (lambda (error-data raw-message)
                         (setq failure (list error-data raw-message)))))
      (kill-buffer buffer))
    (should (equal methods '("session/load" "session/resume")))
    (should (equal (map-elt (car failure) 'message) "session/resume"))
    (should (equal (map-elt (cadr failure) 'method) "session/resume"))))

(ert-deftest my-files-agent-shell-does-not-retry-non-codex-history-load ()
  (let* ((buffer (generate-new-buffer " non-codex history load"))
         (state '((:agent-config . ((:identifier . other-agent)))
                  (:supports-session-resume . t)))
         (load-request
          (acp-make-session-load-request
           :session-id "other-session"
           :cwd default-directory))
         methods
         failure)
    (unwind-protect
        (my-files-agent-shell--send-request-with-codex-resume-fallback
         (lambda (&rest arguments)
           (setq methods
                 (append methods
                         (list
                          (map-elt (plist-get arguments :request)
                                   :method))))
           (funcall (plist-get arguments :on-failure)
                    '((code . -32603)) '((details . "load failed"))))
         :state state
         :client 'client
         :request load-request
         :buffer buffer
         :on-success #'ignore
         :on-failure (lambda (error-data raw-message)
                       (setq failure (list error-data raw-message))))
      (kill-buffer buffer))
    (should (equal methods '("session/load")))
    (should (equal (map-elt (cadr failure) 'details) "load failed"))))

(ert-deftest my-files-agent-shell-resumes-chat-from-stale-live-row ()
  (my-files-agent-shell-test--with-state
      ((my-files-agent-shell--selected-project default-directory))
    (let* ((chat (generate-new-buffer " stale live row"))
           (replacement (generate-new-buffer " replacement live row"))
           (config '((:identifier . codex)))
           resumed)
      (unwind-protect
          (progn
            (my-files-agent-shell-test--set-session-id chat "stale-session")
            (with-current-buffer chat
              (setq default-directory
                    (file-name-as-directory default-directory))
              (map-put! agent-shell--state :agent-config config))
            (cl-letf (((symbol-function
                        'my-files-agent-shell--chat-status-symbol)
                       (lambda (_buffer) 'ready))
                      ((symbol-function 'my-files-agent-shell--chat-title)
                       (lambda (_buffer) "Stale conversation"))
                      ((symbol-function
                        'my-files-agent-shell--subscribe-chat)
                       #'ignore))
              (my-files-agent-shell--render-chat-lists (list chat) nil))
            (with-current-buffer my-files-agent-shell--chat-buffer-name
              (let ((button
                     (my-files-agent-shell-test--button-with-property
                      'my-files-agent-shell-conversation-key
                      "agent:stale-session")))
                (kill-buffer chat)
                (cl-letf (((symbol-function
                            'my-files-agent-shell--start-resumed-chat)
                           (lambda (session-id agent-name directory
                                    &optional agent-config)
                             (setq resumed
                                   (list session-id agent-name directory
                                         agent-config))
                             replacement)))
                  (my-files-agent-shell--open-chat button))))
            (should (equal (nth 0 resumed) "stale-session"))
            (should
             (equal (my-files-agent-shell--canonical-directory
                     (nth 2 resumed))
                    (my-files-agent-shell--canonical-directory
                     default-directory)))
            (should (eq (nth 3 resumed) config)))
        (mapc (lambda (buffer)
                (when (buffer-live-p buffer) (kill-buffer buffer)))
              (list chat replacement))))))

(ert-deftest my-files-agent-shell-opens-existing-buffer-instead-of-resuming ()
  (let* ((project (make-temp-file "agent-shell-open-existing-" t))
         (chat (generate-new-buffer " existing tool-created chat"))
         (other (generate-new-buffer " existing chat placeholder"))
         (thread `((id . "already-open-session")
                   (cwd . ,project)
                   (name . "Already open from browser")))
         (my-files-agent-shell--main-window (selected-window)))
    (unwind-protect
        (save-window-excursion
          (set-window-buffer my-files-agent-shell--main-window other)
          (my-files-agent-shell-test--set-session-id
           chat "already-open-session")
          (with-temp-buffer
            (insert-text-button
             "Open"
             'my-files-agent-shell-codex-entry thread)
            (let ((button (button-at (point-min))))
              (cl-letf (((symbol-function 'agent-shell-buffers)
                         (lambda () (list chat)))
                        ((symbol-function 'agent-shell-start)
                         (lambda (&rest _arguments)
                           (user-error "Couldn't resume session")))
                        ((symbol-function
                          'my-files-agent-shell--schedule-refresh)
                         #'ignore))
                (my-files-agent-shell--open-codex-chat button))))
          (should
           (eq (window-buffer my-files-agent-shell--main-window) chat)))
      (mapc #'kill-buffer (list chat other))
      (delete-directory project t))))

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
           (my-files-agent-shell--available-areas nil)
           (my-files-agent-shell--available-projects nil)
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
      (should
       (equal my-files-agent-shell--available-projects
              (list (my-files-agent-shell--canonical-directory project))))
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

(ert-deftest my-files-agent-shell-shows-complete-titles-on-hover ()
  (my-files-agent-shell-test--with-state
      ((my-files-agent-shell--selected-project default-directory))
    (let* ((chat (generate-new-buffer " hover live chat"))
           (live-title "Complete live conversation title")
           (saved-title "Saved conversation title…")
           (saved-full-title "Complete saved conversation title")
           (saved (list :session-id "hover-saved"
                        :agent "Codex"
                        :started "2026-08-29"
                        :title saved-title
                        :full-title saved-full-title))
           (codex-title "Complete Codex conversation title")
           (thread `((id . "hover-codex")
                     (name . ,codex-title)
                     (status . ((type . "notLoaded"))))))
      (unwind-protect
          (progn
            (my-files-agent-shell-test--set-session-id chat "hover-live")
            (cl-letf (((symbol-function 'my-files-agent-shell--chat-title)
                       (lambda (_buffer) live-title))
                      ((symbol-function
                        'my-files-agent-shell--chat-status-symbol)
                       (lambda (_buffer) 'ready))
                      ((symbol-function
                        'my-files-agent-shell--subscribe-chat)
                       #'ignore))
              (my-files-agent-shell--render-chat-lists
               (list chat) (list saved) (list thread)))
            (with-current-buffer my-files-agent-shell--chat-buffer-name
              (let ((live-button
                     (my-files-agent-shell-test--button-with-property
                      'my-files-agent-shell-conversation-key
                      "agent:hover-live"))
                    (saved-button
                     (my-files-agent-shell-test--button-with-property
                      'my-files-agent-shell-conversation-key
                      "agent:hover-saved"))
                    (codex-button
                     (my-files-agent-shell-test--button-with-property
                      'my-files-agent-shell-conversation-key
                      "codex:hover-codex")))
                (should (equal (button-get live-button 'help-echo)
                               (concat live-title
                                       "\nOpen this live conversation")))
                (should
                 (equal
                  (button-get
                   live-button 'my-files-agent-shell-conversation-title)
                  live-title))
                (should (equal (button-get saved-button 'help-echo)
                               (concat saved-full-title
                                       "\nResume Codex session from "
                                       "2026-08-29")))
                (should
                 (equal
                  (button-get
                   saved-button 'my-files-agent-shell-conversation-title)
                  saved-full-title))
                (should (equal (button-get codex-button 'help-echo)
                               (concat codex-title
                                       "\nResume this Codex task in "
                                       "Agent Shell")))
                (should
                 (equal
                  (button-get
                   codex-button 'my-files-agent-shell-conversation-title)
                  codex-title)))))
        (kill-buffer chat)))))

(ert-deftest my-files-agent-shell-echoes-keyboard-highlighted-title ()
  (let ((panel (generate-new-buffer " keyboard title panel"))
        (other (generate-new-buffer " keyboard title other"))
        (title "Complete keyboard-highlighted conversation title")
        (my-files-agent-shell--echoed-conversation-title nil)
        current-message-text)
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (let ((window (selected-window))
                button-position)
            (set-window-buffer window panel)
            (with-current-buffer panel
              (my-files-agent-shell-chat-mode)
              (let ((inhibit-read-only t))
                (insert-text-button
                 "Clipped title"
                 'my-files-agent-shell-conversation-title title))
              (setq button-position
                    (button-start (button-at (point-min))))
              (should
               (memq #'my-files-agent-shell--update-conversation-echo
                     post-command-hook)))
            (set-window-point window button-position)
            (cl-letf (((symbol-function 'current-message)
                       (lambda () current-message-text))
                      ((symbol-function 'message)
                       (lambda (format-string &rest arguments)
                         (setq current-message-text
                               (and format-string
                                    (apply #'format format-string
                                           arguments))))))
              (my-files-agent-shell--update-conversation-echo)
              (should (equal current-message-text title))
              (should
               (equal my-files-agent-shell--echoed-conversation-title
                      title))
              (set-window-buffer window other)
              (my-files-agent-shell--update-conversation-echo)
              (should-not current-message-text)
              (should-not
               my-files-agent-shell--echoed-conversation-title))))
      (mapc #'kill-buffer (list panel other)))))

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

(ert-deftest my-files-agent-shell-updates-busy-status-without-rerendering ()
  (my-files-agent-shell-test--with-state
      ((my-files-agent-shell--selected-project default-directory))
    (let ((chat (generate-new-buffer " status-only chat"))
          (status 'ready)
          subscriptions
          (refresh-count 0))
      (unwind-protect
          (progn
            (my-files-agent-shell-test--set-session-id chat "status-only")
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
                         (cl-incf refresh-count))))
              (my-files-agent-shell--render-chat-lists (list chat) nil)
              (with-current-buffer my-files-agent-shell--chat-buffer-name
                (let* ((button
                        (my-files-agent-shell-test--button-with-property
                         'my-files-agent-shell-conversation-key
                         "agent:status-only"))
                       (before (buffer-string)))
                  (goto-char (button-start button))
                  (setq status 'busy)
                  (funcall (alist-get 'input-submitted subscriptions)
                           '((:event . input-submitted)))
                  (should (= refresh-count 0))
                  (should
                   (equal (buffer-string)
                          (replace-regexp-in-string
                           "\\[ready\\]" "[busy]" before t t)))
                  (should
                   (equal
                    (button-get (button-at (point))
                                'my-files-agent-shell-conversation-key)
                    "agent:status-only"))))))
        (kill-buffer chat)))))

(ert-deftest my-files-agent-shell-renames-live-buffer-from-codex-title ()
  (let ((chat (generate-new-buffer "Codex Agent @ Project"))
        subscriptions
        (refresh-count 0))
    (unwind-protect
        (progn
          (with-current-buffer chat
            (setq-local agent-shell--state
                        '(:session (:id "named-session"
                                    :title "Codex generated title"))))
          (cl-letf (((symbol-function 'agent-shell-subscribe-to)
                     (lambda (&rest arguments)
                       (push (cons (plist-get arguments :event)
                                   (plist-get arguments :on-event))
                             subscriptions)))
                    ((symbol-function 'shell-maker-set-buffer-name)
                     (lambda (buffer title)
                       (with-current-buffer buffer
                         (rename-buffer title t))))
                    ((symbol-function
                      'my-files-agent-shell--schedule-refresh)
                     (lambda (&rest _arguments)
                       (cl-incf refresh-count))))
            (my-files-agent-shell--subscribe-chat chat)
            (should (equal (buffer-name chat) "Codex generated title"))
            (with-current-buffer chat
              (map-put! (map-elt agent-shell--state :session)
                        :title "Refined Codex title"))
            (funcall (alist-get 'session-title-changed subscriptions)
                     '((:event . session-title-changed)))
            (should (equal (buffer-name chat) "Refined Codex title"))
            (should (= refresh-count 1))))
      (when (buffer-live-p chat)
        (kill-buffer chat)))))

(ert-deftest my-files-agent-shell-codex-status-labels-use-local-runtime-state ()
  (dolist (case
           '(("active" . "[busy]")
             ("completed" . "[ready]")
             ("interrupted" . "[ready]")
             ("failed" . "[error]")))
    (should
     (equal
      (my-files-agent-shell--codex-thread-status-label
       `((status . ((type . "notLoaded")))
         (my-files-agent-shell-local-runtime-status . ,(car case))))
      (cdr case))))
  (should
   (equal
    (my-files-agent-shell--codex-thread-status-label
     '((status . ((type . "notLoaded")))))
    "[unknown]"))
  (should
   (equal
    (my-files-agent-shell--codex-thread-status-label
     '((status . ((type . "active")))
       (my-files-agent-shell-local-runtime-status . "completed")))
    "[busy]")))

(ert-deftest my-files-agent-shell-codex-local-status-requires-live-writer-lock ()
  (let* ((turn-statuses
          (my-files-agent-shell--parse-codex-turn-statuses
           (concat "running\tinProgress\n"
                   "stale\tinProgress\n"
                   "done\tcompleted\n"
                   "broken\tfailed\n")))
         (locked-threads
          (my-files-agent-shell--parse-codex-writer-locks
           (concat "/tmp/thread-writer-locks/running.lock\n"
                   "/tmp/thread-writer-locks/done.lock\n")))
         (threads
          '(((id . "running") (status . ((type . "notLoaded"))))
            ((id . "stale") (status . ((type . "notLoaded"))))
            ((id . "done") (status . ((type . "notLoaded"))))
            ((id . "broken") (status . ((type . "notLoaded"))))))
         (enriched
          (my-files-agent-shell--apply-codex-local-statuses
           threads turn-statuses locked-threads)))
    (should
     (equal (mapcar #'my-files-agent-shell--codex-thread-status-label enriched)
            '("[busy]" "[unknown]" "[ready]" "[error]")))))

(ert-deftest my-files-agent-shell-codex-poll-updates-only-status-brackets ()
  (my-files-agent-shell-test--with-state
      ((my-files-agent-shell--selected-project default-directory))
    (let* ((first
            '((id . "first-codex-status")
              (cwd . "/tmp/first")
              (name . "First Codex status")
              (status . ((type . "notLoaded")))))
           (second
            '((id . "second-codex-status")
              (cwd . "/tmp/second")
              (name . "Second Codex status")
              (status . ((type . "notLoaded")))))
           (active-first
            '((id . "first-codex-status")
              (cwd . "/tmp/first")
              (name . "First Codex status")
              (status . ((type . "active")))))
           (my-files-agent-shell--codex-threads (list first second))
           (my-files-agent-shell--codex-error nil)
           (my-files-agent-shell--codex-refreshing t)
           (my-files-agent-shell--codex-last-refresh-time nil)
           (refresh-count 0))
      (cl-letf (((symbol-function 'agent-shell-buffers) #'ignore)
                ((symbol-function 'codex-ide--request-async)
                 (lambda (_session _method _params callback)
                   (funcall callback
                            `((data . ,(list second active-first)))
                            nil)))
                ((symbol-function
                  'my-files-agent-shell--enrich-codex-runtime-statuses)
                 (lambda (threads callback)
                   (funcall callback threads)))
                ((symbol-function 'my-files-agent-shell--schedule-refresh)
                 (lambda (&rest _arguments)
                   (cl-incf refresh-count))))
        (my-files-agent-shell--render-chat-lists
         nil nil my-files-agent-shell--codex-threads)
        (my-files-agent-shell--codex-list-page 'session nil nil)
        (should (= refresh-count 0))
        (with-current-buffer my-files-agent-shell--chat-buffer-name
          (let ((text (buffer-string)))
            (should (string-match-p
                     "\\[busy\\] First Codex status" text))
            (should (string-match-p
                     "\\[unknown\\] Second Codex status" text))
            (should (< (string-match "First Codex status" text)
                       (string-match "Second Codex status" text)))))))))

(ert-deftest my-files-agent-shell-polls-codex-only-after-emacs-is-idle ()
  (let ((my-files-agent-shell--codex-refresh-timer nil)
        idle-arguments
        regular-arguments
        refresh-force)
    (cl-letf (((symbol-function 'my-files-agent-shell--visible-p)
               (lambda () t))
              ((symbol-function 'run-at-time)
               (lambda (&rest arguments)
                 (setq regular-arguments arguments)
                 'regular-timer))
              ((symbol-function 'run-with-idle-timer)
               (lambda (&rest arguments)
                 (setq idle-arguments arguments)
                 'idle-timer))
              ((symbol-function 'my-files-agent-shell--refresh-codex-threads)
               (lambda (&optional force)
                 (setq refresh-force force))))
      (my-files-agent-shell--start-codex-refresh-timer)
      (should-not regular-arguments)
      (should (= (nth 0 idle-arguments)
                 my-files-agent-shell-codex-refresh-interval))
      (should-not (nth 1 idle-arguments))
      (funcall (nth 2 idle-arguments))
      (should refresh-force)
      (should-not my-files-agent-shell--codex-refresh-timer))))

(ert-deftest my-files-agent-shell-marks-current-and-open-conversations ()
  (my-files-agent-shell-test--with-state
      ((my-files-agent-shell--selected-project default-directory))
    (let ((current (generate-new-buffer " current chat"))
          (open (generate-new-buffer " open chat"))
          (other (generate-new-buffer " main window placeholder")))
      (unwind-protect
          (save-window-excursion
            (delete-other-windows)
            (let ((my-files-agent-shell--main-window (selected-window)))
              (my-files-agent-shell-test--set-session-id current "current")
              (my-files-agent-shell-test--set-session-id open "open")
              (set-window-buffer my-files-agent-shell--main-window current)
              (cl-letf (((symbol-function 'agent-shell-buffers)
                         (lambda () (list current open)))
                        ((symbol-function
                          'my-files-agent-shell--chat-status-symbol)
                         (lambda (_buffer) 'ready))
                        ((symbol-function 'my-files-agent-shell--chat-title)
                         #'buffer-name)
                        ((symbol-function
                          'my-files-agent-shell--subscribe-chat)
                         #'ignore))
                (my-files-agent-shell--render-chat-lists
                 (list current open) nil
                 '(((id . "open")
                    (name . "Open Codex task")
                    (status . ((type . "notLoaded"))))))
                (with-current-buffer my-files-agent-shell--chat-buffer-name
                  (let ((current-button
                         (my-files-agent-shell-test--button-with-property
                          'my-files-agent-shell-conversation-key
                          "agent:current"))
                        (open-button
                         (my-files-agent-shell-test--button-with-property
                          'my-files-agent-shell-conversation-key
                          "agent:open")))
                    (should (string-match-p
                             "▶"
                             (my-files-agent-shell-test--button-prefix
                              current-button)))
                    (should (string-match-p
                             "●"
                             (my-files-agent-shell-test--button-prefix
                              open-button)))))
                (set-window-buffer my-files-agent-shell--main-window open)
                (my-files-agent-shell--update-chat-row-indicators)
                (with-current-buffer my-files-agent-shell--chat-buffer-name
                  (let ((current-button
                         (my-files-agent-shell-test--button-with-property
                          'my-files-agent-shell-conversation-key
                          "agent:current"))
                        (open-button
                         (my-files-agent-shell-test--button-with-property
                          'my-files-agent-shell-conversation-key
                          "agent:open")))
                    (should (string-match-p
                             "●"
                             (my-files-agent-shell-test--button-prefix
                              current-button)))
                    (should (string-match-p
                             "▶"
                             (my-files-agent-shell-test--button-prefix
                              open-button))))))
              (set-window-buffer my-files-agent-shell--main-window other)))
        (mapc #'kill-buffer (list current open other))))))

(ert-deftest my-files-agent-shell-keeps-inactive-chat-highlight-after-render ()
  (let ((first (generate-new-buffer " first highlighted chat"))
        (second (generate-new-buffer " second highlighted chat"))
        (other (generate-new-buffer " selected main buffer"))
        (my-files-agent-shell--selected-project default-directory))
    (unwind-protect
        (save-window-excursion
          (delete-other-windows)
          (let ((main-window (selected-window))
                (chat-window (split-window-right)))
            (set-window-buffer main-window other)
            (my-files-agent-shell-test--set-session-id first "first-highlight")
            (my-files-agent-shell-test--set-session-id
             second "second-highlight")
            (cl-letf (((symbol-function
                        'my-files-agent-shell--chat-status-symbol)
                       (lambda (_buffer) 'ready))
                      ((symbol-function 'my-files-agent-shell--chat-title)
                       #'buffer-name)
                      ((symbol-function
                        'my-files-agent-shell--subscribe-chat)
                       #'ignore))
              (my-files-agent-shell--render-chat-lists
               (list first second) nil)
              (set-window-buffer chat-window
                                 my-files-agent-shell--chat-buffer-name)
              (with-selected-window chat-window
                (goto-char
                 (button-start
                  (my-files-agent-shell-test--button-with-property
                   'my-files-agent-shell-conversation-key
                   "agent:second-highlight")))
                (my-files-agent-shell--remember-panel-selection)
                (hl-line-highlight))
              (select-window main-window)
              (my-files-agent-shell--render-chat-lists
               (list first second) nil)
              (with-current-buffer my-files-agent-shell--chat-buffer-name
                (let ((button (button-at (window-point chat-window))))
                  (should
                   (equal
                    (button-get button
                                'my-files-agent-shell-conversation-key)
                    "agent:second-highlight"))
                  (should (overlayp hl-line-overlay))
                  (should
                   (= (line-number-at-pos (overlay-start hl-line-overlay))
                      (line-number-at-pos (button-start button)))))))))
      (mapc #'kill-buffer (list first second other)))))

(ert-deftest my-files-agent-shell-batch-moves-and-archives-marked-chats ()
  (my-files-agent-shell-test--with-state
      ((my-files-agent-shell--selected-project default-directory))
    (let ((first (generate-new-buffer " first marked chat"))
          (second (generate-new-buffer " second marked chat")))
      (unwind-protect
          (progn
            (my-files-agent-shell-test--set-session-id first "first-marked")
            (my-files-agent-shell-test--set-session-id second "second-marked")
            (cl-letf (((symbol-function
                        'my-files-agent-shell--chat-status-symbol)
                       (lambda (_buffer) 'ready))
                      ((symbol-function 'my-files-agent-shell--chat-title)
                       #'buffer-name)
                      ((symbol-function
                        'my-files-agent-shell--subscribe-chat)
                       #'ignore)
                      ((symbol-function 'completing-read)
                       (lambda (&rest _arguments) "Review"))
                      ((symbol-function 'yes-or-no-p)
                       (lambda (_prompt) t))
                      ((symbol-function
                        'my-files-agent-shell--schedule-refresh)
                       (lambda (&rest _arguments)
                         (my-files-agent-shell--render-chat-lists
                          (list first second) nil))))
              (my-files-agent-shell--render-chat-lists
               (list first second) nil)
              (with-current-buffer my-files-agent-shell--chat-buffer-name
                (dolist (key '("agent:first-marked"
                               "agent:second-marked"))
                  (goto-char
                   (button-start
                    (my-files-agent-shell-test--button-with-property
                     'my-files-agent-shell-conversation-key key)))
                  (my-files-agent-shell-toggle-mark-at-point))
                (goto-char
                 (button-start
                  (my-files-agent-shell-test--button-with-property
                   'my-files-agent-shell-conversation-key
                   "agent:first-marked")))
                (my-files-agent-shell-move-at-point))
              (dolist (key '("agent:first-marked"
                             "agent:second-marked"))
                (should (eq (my-files-agent-shell--conversation-stage key)
                            'review)))
              (with-current-buffer my-files-agent-shell--chat-buffer-name
                (should-not my-files-agent-shell--marked-conversation-keys)
                (dolist (key '("agent:first-marked"
                               "agent:second-marked"))
                  (goto-char
                   (button-start
                    (my-files-agent-shell-test--button-with-property
                     'my-files-agent-shell-conversation-key key)))
                  (my-files-agent-shell-toggle-mark-at-point))
                (goto-char
                 (button-start
                  (my-files-agent-shell-test--button-with-property
                   'my-files-agent-shell-conversation-key
                   "agent:first-marked")))
                (my-files-agent-shell-archive-at-point))
              (dolist (key '("agent:first-marked"
                             "agent:second-marked"))
                (should
                 (my-files-agent-shell--conversation-archived-p key)))
              (with-current-buffer my-files-agent-shell--chat-buffer-name
                (should-not
                 my-files-agent-shell--marked-conversation-keys))))
        (mapc #'kill-buffer (list first second))))))

(ert-deftest my-files-agent-shell-move-keeps-selection-at-original-list ()
  (my-files-agent-shell-test--with-state
      ((my-files-agent-shell--selected-project default-directory))
    (let ((first (generate-new-buffer " first stationary chat"))
          (moved (generate-new-buffer " moved stationary chat"))
          (next (generate-new-buffer " next stationary chat")))
      (unwind-protect
          (progn
            (my-files-agent-shell-test--set-session-id first
                                                       "first-stationary")
            (my-files-agent-shell-test--set-session-id moved
                                                       "moved-stationary")
            (my-files-agent-shell-test--set-session-id next
                                                       "next-stationary")
            (cl-letf (((symbol-function
                        'my-files-agent-shell--chat-status-symbol)
                       (lambda (_buffer) 'ready))
                      ((symbol-function 'my-files-agent-shell--chat-title)
                       #'buffer-name)
                      ((symbol-function
                        'my-files-agent-shell--subscribe-chat)
                       #'ignore)
                      ((symbol-function 'completing-read)
                       (lambda (&rest _arguments) "Completed"))
                      ((symbol-function
                        'my-files-agent-shell--schedule-refresh)
                       (lambda (&rest _arguments)
                         (my-files-agent-shell--render-chat-lists
                          (list first moved next) nil))))
              (my-files-agent-shell--render-chat-lists
               (list first moved next) nil)
              (with-current-buffer my-files-agent-shell--chat-buffer-name
                (goto-char
                 (button-start
                  (my-files-agent-shell-test--button-with-property
                   'my-files-agent-shell-conversation-key
                   "agent:moved-stationary")))
                (my-files-agent-shell-move-at-point)
                (let ((button (button-at (point))))
                  (should
                   (equal
                    (button-get button
                                'my-files-agent-shell-conversation-key)
                    "agent:next-stationary"))
                  (should
                   (eq (button-get button 'my-files-agent-shell-section)
                       'in-progress))))))
        (mapc #'kill-buffer (list first moved next))))))

(ert-deftest my-files-agent-shell-chat-style-centers-the-message-column ()
  (let ((my-files-agent-shell-chat-message-width 80))
    (should
     (equal (my-files-agent-shell--chat-column-margins 120)
            '(20 . 20)))
    (should
     (equal (my-files-agent-shell--chat-column-margins 121)
            '(20 . 21)))
    (should
     (equal (my-files-agent-shell--chat-column-margins 72)
            '(0 . 0)))))

(ert-deftest my-files-agent-shell-chat-style-restores-window-margins ()
  (save-window-excursion
    (delete-other-windows)
    (let* ((window (selected-window))
           (buffer (generate-new-buffer " chat style window"))
           (original (window-margins window)))
      (unwind-protect
          (progn
            (set-window-buffer window buffer)
            (with-current-buffer buffer
              (setq-local my-files-agent-shell-chat-style-mode t)
              (setq-local my-files-agent-shell-chat-message-width 40))
            (my-files-agent-shell--update-chat-window-column window)
            (should (= (window-body-width window) 40))
            (should (window-parameter
                     window 'my-files-agent-shell-chat-column))
            (with-current-buffer buffer
              (setq-local my-files-agent-shell-chat-style-mode nil))
            (my-files-agent-shell--update-chat-window-column window)
            (should (equal (window-margins window) original))
            (should-not (window-parameter
                         window 'my-files-agent-shell-chat-column)))
        (kill-buffer buffer)))))

(ert-deftest my-files-agent-shell-chat-style-left-aligns-and-distinguishes-user-turns ()
  (with-temp-buffer
    (insert "Short message")
    (let* ((input (make-overlay (point-min) (point-max)))
           (label (make-overlay (point-min) (point-min)))
           (label-text
            (propertize " Me " 'face 'agent-shell-chat-me-label)))
      (overlay-put input 'category 'agent-shell-chat-me-input)
      (overlay-put input 'line-prefix agent-shell-chat--body-indent)
      (overlay-put input 'wrap-prefix agent-shell-chat--body-indent)
      (overlay-put label 'category 'agent-shell-chat-me-label)
      (overlay-put label 'before-string (concat "\n" label-text "\n"))
      (setq-local my-files-agent-shell-chat-style-mode t)
      (my-files-agent-shell--style-chat-overlays)
      (let* ((prefix (overlay-get input 'line-prefix))
             (styled-label (overlay-get label 'before-string))
             (label-start (text-property-any
                           0 (length styled-label)
                           'face 'agent-shell-chat-me-label
                           styled-label)))
        (should (eq (overlay-get input 'face)
                    'my-files-agent-shell-user-message))
        (should (equal (substring-no-properties prefix) "│ "))
        (should-not (get-text-property 0 'display prefix))
        (should label-start)
        (should-not
         (get-text-property
          label-start 'line-prefix styled-label))))))

(ert-deftest my-files-agent-shell-chat-style-collapses-and-separates-activity ()
  (with-temp-buffer
    (agent-shell-ui-update-fragment
     (agent-shell-ui-make-group-model
      :namespace-id "turn" :block-id "activity-1"
      :label-left "Thought" :expanded t)
     :expanded t)
    (agent-shell-ui-update-fragment
     (agent-shell-ui-make-fragment-model
      :namespace-id "turn" :block-id "edit-1"
      :label-left "Edit" :body "Changed a file"
      :group-id "activity-1")
     :expanded t)
    (setq-local my-files-agent-shell-chat-style-mode t)
    (my-files-agent-shell--collapse-existing-activity-groups)
    (my-files-agent-shell--style-existing-activity-fragments)
    (goto-char (point-min))
    (let* ((group-match
            (text-property-search-forward
             'agent-shell-ui-state nil
             (lambda (_value state)
               (eq (map-elt state :kind) 'group))))
           (state (and group-match (prop-match-value group-match)))
           (separator
            (seq-find
             (lambda (overlay)
               (eq (overlay-get overlay 'category)
                   'my-files-agent-shell-activity-separator))
             (overlays-in (point-min) (point-max)))))
      (should group-match)
      (should (map-elt state :collapsed))
      (should separator)
      (should
       (eq (overlay-get separator 'face)
           'my-files-agent-shell-activity-separator))
      (should
       (equal
        (get-text-property
         0 'display (overlay-get separator 'after-string))
        '(space :align-to right-fringe))))))

(provide 'my-files-agent-shell-test)
;;; my-files-agent-shell-test.el ends here
