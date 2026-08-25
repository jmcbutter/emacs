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

(provide 'my-files-agent-shell-test)
;;; my-files-agent-shell-test.el ends here
