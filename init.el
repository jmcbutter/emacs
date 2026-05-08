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
  (package-quickstart t)
  (add-to-list 'load-path (expand-file-name "user-lisp/init/" user-emacs-directory)))

;; Customized Variables
(use-package emacs
  :custom
  (custom-file (locate-user-emacs-file "custom-vars.el"))
  :config
  (load custom-file 'noerror 'nomessage))

(use-package emacs
  :bind*
  ("M-o" . #'other-window))
;; Shell Vars
(use-package exec-path-from-shell
  :hook (after-init . exec-path-from-shell-initialize))

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

(use-package nerd-icons :defer)

(use-package nerd-icons-dired
  :hook (dired-mode . nerd-icons-dired-mode))

(use-package nerd-icons-ibuffer
  :hook (ibuffer-mode . nerd-icons-ibuffer-mode))

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
  (use-short-answers nil))

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
  (warning-minimum-level :error))

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
  :hook (after-init . undo-fu-session-global-mode)
  :custom (undo-fu-session-incompatible-files '("\\.gpg$" "/COMMIT_EDITMSG\\'" "/git-rebase-todo\\'"))
  :config
  (when (executable-find "zstd")
    ;; There are other algorithms available, but zstd is the fastest, and speed
    ;; is our priority within Emacs
    (setq undo-fu-session-compression 'zst)))

(use-package vundo
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
;; MINIBUFFER
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(use-package vertico
  :hook (after-init . vertico-mode)
  :custom
  (vertico-cycle t))

(use-package marginalia
  :after vertico
  :config
  (marginalia-mode))


(use-package nerd-icons-completion
  :after marginalia
  :config
  (nerd-icons-completion-mode)
  :hook
  (marginalia-mode . nerd-icons-completion-marginalia-setup))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ORG
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(require 'init-completion)
(require 'init-consult)
(require 'init-eglot)
(require 'init-magit)
(require 'init-org)
(require 'init-treesitter)

(use-package anki-editor
  :ensure t)


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; AI
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(use-package gptel
  :ensure t
  :config
  (require 'gptel-integrations))

(use-package mcp
  :ensure t
  :after gptel
  :custom (mcp-hub-servers
           `(("shopify" . (:command "npx"
                                    :args ("-y" "@shopify/dev-mcp@latest")))))
  :config (require 'mcp-hub)
  :hook (after-init . mcp-hub-start-all-server))

(use-package agent-shell
  :ensure t)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; BUFFERS
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(use-package bufferlo
  :ensure t
  :init (bufferlo-mode))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; BBDB
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(use-package bbdb
  :custom
  (bbdb-file "~/Dropbox/Documents/bbdb")
  (bbdb-allow-duplicates t)
  :ensure t)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; LEDGER
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(use-package ledger-mode
  :ensure t)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; CUSTOM ELISP
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(use-package emacs
  :config
  (add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; FRONTEND WEB DEV
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(use-package prettier-js
  :custom
  (prettier-js-command "prettierd")
  :hook
  ((js-mode
    web-mode
    scss-mode
    css-mode
    liquid-mode
    js-ts-mode
    web-mode
    css-ts-mode
    html-ts-mode
    mhtml-ts-mode
    tsx-ts-mode
    typescript-ts-mode
    ) . prettier-js-mode))

(use-package web-mode
  :custom
  (web-mode-markup-indent-offset 2)
  (web-mode-css-indent-offset 2)
  (web-mode-code-indent-offset 2)
  (web-mode-enable-css-colorization t)
  (web-mode-attr-indent-offset 2)
  (web-mode-attr-value-indent-offset 4)
  (web-mode-block-padding 2)
  (web-mode-part-padding 2)
  (web-mode-script-padding 2)
  (web-mode-style-padding 2)
  (web-mode-extra-keywords '(("django" . ("doc" "enddoc")))))

(define-derived-mode liquid-mode web-mode "Liquid"
  "Major mode for editing Shopify Liquid files, derived from web-mode.")

(add-to-list 'auto-mode-alist '("\\.liquid\\'" . liquid-mode))

(use-package css-mode
  :custom
  (css-indent-offset 2))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Jira
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(use-package jira
  :custom
  (jira-base-url "https://udundi.atlassian.net")
  (jira-token-is-personal-access-token nil)
  (jira-api-version 3))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; QOL
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(use-package eat
  :defer
  :hook ('eshell-load-hook #'eat-eshell-mode))

(use-package helpful
  :bind
  ;; Note that the built-in `describe-function' includes both functions
  ;; and macros. `helpful-function' is functions only, so we provide
  ;; `helpful-callable' as a drop-in replacement.
  ("C-h f" . helpful-callable)
  ("C-h v" . helpful-variable)
  ("C-h k" . helpful-key)
  ("C-h x" . helpful-command)
  )

(use-package diminish :defer)

(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

(use-package hl-todo
  :hook
  ((prog-mode yaml-ts-mode) . hl-todo-mode)
  :config
  ;; From doom emacs
  (setq hl-todo-highlight-punctuation ":"
        hl-todo-keyword-faces
        '(;; For reminders to change or add something at a later date.
          ("TODO" warning bold)
          ;; For code (or code paths) that are broken, unimplemented, or slow,
          ;; and may become bigger problems later.
          ("FIXME" error bold)
          ;; For code that needs to be revisited later, either to upstream it,
          ;; improve it, or address non-critical issues.
          ("REVIEW" font-lock-keyword-face bold)
          ;; For code smells where questionable practices are used
          ;; intentionally, and/or is likely to break in a future update.
          ("HACK" font-lock-constant-face bold)
          ;; For sections of code that just gotta go, and will be gone soon.
          ;; Specifically, this means the code is deprecated, not necessarily
          ;; the feature it enables.
          ("DEPRECATED" font-lock-doc-face bold)
          ;; Extra keywords commonly found in the wild, whose meaning may vary
          ;; from project to project.
          ("NOTE" success bold)
          ("BUG" error bold)
          ("XXX" font-lock-constant-face bold)))
  )

(use-package indent-guide
  :hook
  (prog-mode . indent-guide-mode)
  :config
  (setq indent-guide-char "│")) ;; Set the character used for the indent guide.

(use-package which-key
  :ensure nil ;; Don't install which-key because it's now built-in
  :hook (after-init . which-key-mode)
  :diminish
  :custom
  (which-key-side-window-location 'bottom)
  (which-key-sort-order #'which-key-key-order-alpha) ;; Same as default, except single characters are sorted alphabetically
  (which-key-sort-uppercase-first nil)
  (which-key-add-column-padding 1) ;; Number of spaces to add to the left of each column
  (which-key-min-display-lines 6)  ;; Increase the minimum lines to display because the default is only 1
  (which-key-idle-delay 0.8)       ;; Set the time delay (in seconds) for the which-key popup to appear
  (which-key-max-description-length 25)
  (which-key-allow-imprecise-window-fit nil)) ;; Fixes which-key window slipping out in Emacs Daemon

(use-package ws-butler
  :hook (after-init . ws-butler-global-mode))

(use-package emacs
  :custom
  (initial-scratch-message nil))

(use-package pdf-tools
  :ensure t
  :mode "\\.pdf\\'")


(with-eval-after-load 'project
  (defun project-find-regexp-with-unique-buffer (orig-fun &rest args)
    "An advice function that gives project-find-regexp a unique buffer name"
    (require 'xref)
    (let ((xref-buffer-name (format "%s %s" xref-buffer-name (car args))))
      (apply orig-fun args)))

  (advice-add 'project-find-regexp :around
              #'project-find-regexp-with-unique-buffer))


(use-package ediff
  :custom
  (ediff-split-window-function 'split-window-horizontally)
  (ediff-window-setup-function 'ediff-setup-windows-plain))
(put 'narrow-to-region 'disabled nil)


;; (when-let ((colorterm (getenv "COLORTERM")))
;;   (when (member colorterm '("truecolor" "24bit"))
;;     (unless (display-graphic-p)
;;       (set-terminal-parameter nil 'background-mode 'dark))))

(use-package xclip
  :ensure t
  :config
  (xclip-mode 1))

(use-package emacs-everywhere
  :ensure t)
