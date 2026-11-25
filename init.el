;; -*- lexical-binding: t; -*-
;; Package Setup
(add-to-list 'load-path (locate-user-emacs-file "user-lisp/config"))
(add-to-list 'load-path (locate-user-emacs-file "user-lisp/lang"))
(add-to-list 'load-path (locate-user-emacs-file "user-lisp/minor-modes"))
(add-to-list 'load-path (locate-user-emacs-file "user-lisp/packages"))

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
  (load custom-file 'noerror 'nomessage)
  (setq auth-sources '("~/.authinfo.gpg"))
  (setq epa-pinentry-mode 'loopback))

(use-package emacs
  :config
  (load-theme 'modus-operandi-tinted)
  ;; Windows registers the same font under its short family name.
  (set-frame-font (if (eq system-type 'windows-nt)
                      "-*-JetBrainsMono NF-regular-normal-normal-*-16-*-*-*-*-0-iso10646-1"
                    "-*-JetBrainsMono Nerd Font-regular-normal-normal-*-16-*-*-*-m-0-iso10646-1"))
  (custom-set-faces '(variable-pitch ((t (:family "GoMono Nerd Font")))))
  (add-hook 'org-mode-hook 'variable-pitch-mode)
  (add-hook 'markdown-mode-hook 'variable-pitch-mode))



(use-package emacs
  :bind*
  ("M-o" . #'other-window))
;; Shell Vars
(use-package exec-path-from-shell
  :unless (eq system-type 'windows-nt)
  :ensure t
  :hook (after-init . exec-path-from-shell-initialize))

;; UI
(use-package emacs
  :hook
  ((prog-mode text-mode help-mode org-agenda-mode) .  #'hl-line-mode)
  ((prog-mode text-mode help-mode org-agenda-mode) .  #'visual-line-mode)
  ((prog-mode) .  #'display-line-numbers-mode)
  ;; Precision scrolling runs off the end of a single tall image and
  ;; snaps back to the top, and the plain wheel scrolls past it into
  ;; blank space, so route the wheel to image-mode's own commands,
  ;; which stop at the image's edges.
  ((image-mode) . (lambda ()
                    (setq-local scroll-margin 0)
                    (setq-local pixel-scroll-precision-mode nil)
                    (setq-local mwheel-scroll-up-function #'image-scroll-up)
                    (setq-local mwheel-scroll-down-function #'image-scroll-down)))
  :custom
  (menu-bar-mode nil)
  (scroll-bar-mode nil)
  (tool-bar-mode nil)
  (blink-cursor-mode nil)
  (global-hl-line-mode nil)
  (display-fill-column-indicator-column 80)
  (whitespace-style '(face tabs tab-mark trailing))
  (inhibit-startup-screen t)
  (mouse-wheel-tilt-scroll t)
  (mouse-wheel-scroll-amount-horizontal 5)
  (mwheel-scroll-left-function
        (lambda (&optional _arg _set-minimum)
          (scroll-left mouse-wheel-scroll-amount-horizontal)))

  (mwheel-scroll-right-function
        (lambda (&optional _arg _set-minimum)
          (scroll-right mouse-wheel-scroll-amount-horizontal)))
  (pixel-scroll-precision-mode t)
  (auto-window-vscroll t))

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
  :config
  ;; (w32-register-hot-key [M-tab])
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
  (warning-minimum-level :error)
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

;; (use-package undo-fu-session
;;   :ensure t
;;   :hook (after-init . undo-fu-session-global-mode)
;;   :custom (undo-fu-session-incompatible-files '("\\.gpg$" "/COMMIT_EDITMSG\\'" "/git-rebase-todo\\'"))
;;   :config
;;   (when (executable-find "zstd")
;;     ;; There are other algorithms available, but zstd is the fastest, and speed
;;     ;; is our priority within Emacs
;;     (setq undo-fu-session-compression 'zst)))

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


(defun cc/markdown-to-org-region (start end)
  "Convert Markdown formatted text in region (START, END) to Org.

This command requires that pandoc (man page `pandoc(1)') be
installed."
  (interactive "r")
  (shell-command-on-region
   start end
   "pandoc -f markdown -t org --wrap=preserve" t t))

(use-package xclip
  :unless (eq system-type 'windows-nt)
  :ensure t
  :demand t
  :config
  (xclip-mode))

(use-package clipetty
  :ensure t
  :config
  (global-clipetty-mode 1))

(use-package eca
  :ensure t)




;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Light/Dark Mode
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(unless (eq system-type 'windows-nt)
  (require 'dbus))

(defvar my-light-theme 'modus-operandi-tinted)
(defvar my-dark-theme 'modus-vivendi)

(defun my-system-dark-p ()
  (if (eq system-type 'windows-nt)
      (eql 0 (w32-read-registry
              'HKCU
              "Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"
              "AppsUseLightTheme"))
    (string-match-p
     "prefer-dark"
     (car (process-lines
           "gsettings"
           "get"
           "org.gnome.desktop.interface"
           "color-scheme")))))

(defun my-apply-system-theme (&rest _)
  (mapc #'disable-theme custom-enabled-themes)
  (load-theme
   (if (my-system-dark-p)
       my-dark-theme
     my-light-theme)
   t))

;; Apply current theme at startup.
(my-apply-system-theme)

;; React to changes from Windows, or from the desktop portal.
(if (eq system-type 'windows-nt)
    (add-hook 'toolkit-theme-set-functions #'my-apply-system-theme)
  (dbus-register-signal
   :session
   nil
   "/org/freedesktop/portal/desktop"
   "org.freedesktop.portal.Settings"
   "SettingChanged"
   (lambda (namespace key _value)
     (when (and (equal namespace "org.freedesktop.appearance")
                (equal key "color-scheme"))
       (my-apply-system-theme)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; User Lisp
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(require 'config-agenda)
(require 'config-completion)
(require 'config-eglot)
(require 'config-web-mode)
(require 'config-llm)
(require 'config-magit)
(require 'config-pdf)
(require 'config-treesit)
(require 'config-which-key)

(require 'lang-liquid)
(require 'lang-markdown)
(require 'lang-org)
(require 'lang-puml)
(put 'scroll-left 'disabled nil)
(put 'dired-find-alternate-file 'disabled nil)
