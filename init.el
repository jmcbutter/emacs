;; -*- lexical-binding: t; -*-
;; Package Setup
(use-package emacs
  :custom
  (use-package-always-ensure t)
  (package-archives '(("melpa" . "https://melpa.org/packages/")
                      ("elpa" . "https://elpa.gnu.org/packages/")
                      ("nongnu" . "https://elpa.nongnu.org/nongnu/")))
  (use-package-always-defer t)
  (use-package-enable-imenu-support t)
  (package-quickstart t))

(use-package org-edna
  :ensure t
  :config
  (org-edna-mode))

;; Customized Variables
(use-package emacs
  :custom
  (custom-file (locate-user-emacs-file "custom-vars.el"))
  :config
  (load custom-file 'noerror 'nomessage))

(use-package emacs
  :config
  (load-theme 'modus-operandi-deuteranopia)
  (fido-vertical-mode)
  (set-frame-font "-*-JetBrainsMono Nerd Font-regular-normal-normal-*-16-*-*-*-m-0-iso10646-1")
  ;; (custom-set-faces '(variable-pitch ((t (:family "iMWritingMono Nerd Font")))))
  ;; (custom-set-faces '(variable-pitch ((t (:family "GoMono Nerd Font")))))
  (custom-set-faces '(variable-pitch ((t (:family "GoMono Nerd Font")))))
  ;; (custom-set-faces '(variable-pitch ((t (:family "AnonymousPro Nerd Font")))))
  ;; (custom-set-faces '(variable-pitch ((t (:family "LiterationSerif Nerd Font")))))
  (add-hook 'org-mode-hook 'variable-pitch-mode))



(use-package emacs
  :bind*
  ("M-o" . #'other-window))
;; Shell Vars
;; (use-package exec-path-from-shell
;;   :hook (after-init . exec-path-from-shell-initialize))

;; UI
(use-package emacs
  :hook
  ((prog-mode text-mode help-mode org-agenda-mode).  #'hl-line-mode)
  ((prog-mode text-mode help-mode org-agenda-mode).  #'visual-line-mode)
  :custom
  (menu-bar-mode nil)
  (scroll-bar-mode nil)
  (tool-bar-mode nil)
  (blink-cursor-mode nil)
  (global-hl-line-mode nil)
  (display-fill-column-indicator-column 80)
  (whitespace-style '(face tabs tab-mark trailing)))

;; Editing
(use-package emacs
  :custom
  (delete-selection-mode t)
  (indent-tabs-mode nil)
  (tab-width 8))

;; QOL
(use-package emacs
  :custom
  (global-auto-revert-mode t)
  (recentf-mode t)
  (use-short-answers nil)
  (ring-bell-function 'ignore))

;; Keybindings in Terminal Emacs
(use-package emacs
  :bind  (("M-%" . #'query-replace-regexp)
          ;; C-S-<backspace> . #'kill-whole-line
          ;; C-x C-+ #'text-scale-adjust
          ;; C-x C-- #'text-scale-adjust
          ;; C-x C-0 #'text-scale-adjust
          ;; C-x C-; #'comment-line
          ;; C-x C-= #'text-scale-adjust
          ;; C-M-S-l #'recenter-other-window
          ;; C-M-S-v #'scroll-other-window-down
          ;; C-M-% #'query-replace-regexp
          ;; C-h C-\ #'describe-input-method
          ;; C-\ #'toggle-input-method
          ;; C-? undo-redo
          ;; C-M-_ undo-redo
          ;; C-x RET C-\ #'set-input-method
          ;; C-x C-M-+ #'global-text-scale-adjust
          ;; C-x C-M-- #'global-text-scale-adjust
          ;; C-x C-M-0 #'global-text-scale-adjust
          ;; C-x C-M-= #'global-text-scale-adjust
          ))

;; Scrolling
(use-package emacs
  :custom
  (scroll-conservatively 0)
  (scroll-margin 0)
  (mouse-wheel-progressive-speed nil))

;; Warnings
(use-package emacs
  :custom
  (native-comp-async-report-warnings-errors 'silent)
  ;; (warning-minimum-level :error)
  )

;; Recovery
(defun my-shorten-auto-save-file-name (&rest args)
  ;; Hash file saves to prevent the "file name too long" issue
  (let ((buffer-file-name
         (when buffer-file-name (sha1 buffer-file-name))))
    (apply args)))

(advice-add 'make-auto-save-file-name :around
            #'my-shorten-auto-save-file-name)

(use-package emacs
  :custom
  (backup-by-copying t)
  (backup-directory-alist '(("." . "~/.emacs_backups/")))
  (make-backup-files t)
  (auto-save-default t)
  (auto-save-list-file-prefix "~/.emacs_autosave/")
  (auto-save-file-name-transforms
  `((".*" "~/.emacs_autosave/" t)))
  (lock-file-name-transforms
      '(("\\`/.*/\\([^/]+\\)\\'" "~/.emacs_lockfiles/\\1" t)))
  (delete-by-moving-to-trash t)
  (savehist-mode))

(use-package undo-fu-session
  :ensure t
  :hook (after-init . undo-fu-session-global-mode)
  :custom (undo-fu-session-incompatible-files '("\\.gpg$" "/COMMIT_EDITMSG\\'" "/git-rebase-todo\\'"))
  :config
  (when (executable-find "zstd")
    ;; There are other algorithms available, but zstd is the fastest, and speed
    ;; is our priority within Emacs
    (setq undo-fu-session-compression 'zst)))

(use-package vundo
  :ensure t
  :defer
  :custom
  (vundo-glyph-alist vundo-unicode-symbols)
  (vundo-compact-display t))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; PROGRAMMING
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Prog Mode
(use-package emacs
  :hook
  (prog-mode . hs-minor-mode)
  (prog-mode . display-fill-column-indicator-mode)
  (prog-mode . whitespace-mode))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ORG
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(require 'config-org)
(require 'config-completion)
(require 'config-eglot)
(require 'config-web-mode)

(require 'lang-liquid)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; BBDB
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(use-package bbdb
  :custom
  (bbdb-file "~/Dropbox/Documents/bbdb")
  (bbdb-allow-duplicates t)
  :ensure t)

(use-package emacs
  :custom
  (initial-scratch-message nil))
