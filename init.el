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

;; Language Server
(use-package eglot
  :ensure nil
  :hook ((c-mode c++-mode)
         . eglot-ensure)
  :custom
  (eglot-events-buffer-size 0)
  (eglot-autoshutdown t)
  (eglot-report-progress nil))
  ;; :config
  ;; (add-to-list 'eglot-server-programs
  ;;              `(typescript-ts-mode . ("PATH_TO_THE_LSP_FOLDER/bin/lua-language-server" "-lsp"))))

(use-package mason
  :hook (after-init . mason-ensure))

;; Autocompletion
;; (use-package yasnippet
;;   :hook (prog-mode . yas-minor-mode))

;; (use-package yasnippet-snippets :defer)

;; (defun start/corfu-yas-tab-handler ()
;;   "Prioritize corfu over yasnippet when yasnippet is active"
;;   (interactive)
;;   (if (> corfu--index -1)
;;       (corfu-complete)
;;     (yas-next-field-or-maybe-expand)
;;     ))

;; (use-package snippy
;;   :vc (:url "https://github.com/MiniApollo/snippy.git"
;;             :branch "main"
;;             :rev :newest)
;;   :hook (after-init . global-snippy-minor-mode)
;;   :custom
;;   (snippy-global-languages '("global")) ;; Recomended
;;   ;; Optional
;;   ;; (snippy-install-dir (expand-file-name <Your location>))
;;   ;; Use different snippet collections
;;   ;; (snippy-source '("Your git repo" . "my-snippets-dir"))
;;   :config
;;   (snippy-install-or-update-snippets))

;; (use-package emacs
;;   :after (yasnippet corfu)
;;   :bind
;;   (:map yas-keymap
;;         ("TAB" . start/corfu-yas-tab-handler)))

(use-package corfu
  ;; Optional customizations
  :custom
  (corfu-cycle t)                ;; Enable cycling for `corfu-next/previous'
  (corfu-auto nil)                 ;; Enable auto completion
  (corfu-auto-prefix 2)          ;; Minimum length of prefix for auto completion.
  (corfu-popupinfo-mode t)       ;; Enable popup information
  (corfu-popupinfo-delay 0.5)    ;; Lower popup info delay to 0.5 seconds from 2 seconds
  (corfu-separator ?\s)          ;; Orderless field separator, Use M-SPC to enter separator
  ;; (corfu-quit-at-boundary nil)   ;; Never quit at completion boundary
  ;; (corfu-quit-no-match nil)      ;; Never quit, even if there is no match
  ;; (corfu-preview-current nil)    ;; Disable current candidate preview
  ;; (corfu-preselect 'prompt)      ;; Preselect the prompt
  ;; (corfu-on-exact-match nil)     ;; Configure handling of exact matches
  ;; (corfu-scroll-margin 5)        ;; Use scroll margin
  (completion-ignore-case t)

  ;; Emacs 30 and newer: Disable Ispell completion function.
  ;; Try `cape-dict' as an alternative.
  (text-mode-ispell-word-completion nil)

  ;; Enable indentation+completion using the TAB key.
  ;; `completion-at-point' is often bound to M-TAB.
  (tab-always-indent 'complete)

  (corfu-preview-current nil) ;; Don't insert completion without confirmation
  ;; Recommended: Enable Corfu globally.  This is recommended since Dabbrev can
  ;; be used globally (M-/).  See also the customization variable
  ;; `global-corfu-modes' to exclude certain modes.
  :init
  (global-corfu-mode))

;; (use-package nerd-icons-corfu
;;   :after corfu
;;   :init (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter))

;; (use-package yasnippet-capf :defer)

;; (defun start/setup-capfs ()
;;   "Configure completion backends"
;;   ;; Take care when adding Capfs to the list since each of the Capfs adds a small runtime cost.
;;   (let ((merge-backends (list
;;                          #'cape-keyword      ;; Keyword completion
;;                          ;; #'cape-abbrev       ;; Complete abbreviation
;;                          #'cape-dabbrev      ;; Complete word from current buffers
;;                          ;; #'cape-line         ;; Complete entire line from current buffer
;;                          ;; #'cape-history      ;; Complete from Eshell, Comint or minibuffer history
;;                          ;; #'cape-dict         ;; Dictionary completion (Needs Dictionary file installed)
;;                          ;; #'cape-tex          ;; Complete Unicode char from TeX command, e.g. \hbar
;;                          ;; #'cape-sgml         ;; Complete Unicode char from SGML entity, e.g., &alpha
;;                          ;; #'cape-rfc1345      ;; Complete Unicode char using RFC 1345 mnemonics
;;                          ;; #'snippy-capf       ;; Vscode Snippets (Snippy needs to be installed)
;;                          #'yasnippet-capf    ;; Yasnippet snippets
;;                          ))
;;         (seperate-backends (list
;;                             #'cape-file ;; Path completion
;;                             #'cape-elisp-block ;; Complete elisp in Org or Markdown mode
;;                             )))
;;     ;; Remove keyword completion in git commits
;;     (when (derived-mode-p 'git-commit-mode)
;;       (setq merge-backends (remq #'cape-keyword merge-backends)))

;;     ;; Add Elisp symbols only in Elisp modes
;;     (when (derived-mode-p 'emacs-lisp-mode 'ielm-mode)
;;       (setq merge-backends (cons #'cape-elisp-symbol merge-backends))) ;; Emacs Lisp code (functions, variables)

;;     ;; Add Eglot to the front of the list if it's active
;;     (when (bound-and-true-p eglot--managed-mode)
;;       (setq merge-backends (cons #'eglot-completion-at-point merge-backends)))

;;     ;; Create the super-capf and set it buffer-locally
;;     (setq-local completion-at-point-functions
;;                 (append
;;                  seperate-backends
;;                  (list (apply #'cape-capf-super merge-backends)))
;;                 )))

;; (use-package cape
;;   :after (corfu)
;;   :init
;;   ;; Add to the global default value of `completion-at-point-functions' which is
;;   ;; used by `completion-at-point'.  The order of the functions matters, the
;;   ;; first function returning a result wins.  Note that the list of buffer-local
;;   ;; completion functions takes precedence over the global list.

;;   ;; Seperate function needed, because we use setq-local (everything is replaced)
;;   (add-hook 'eglot-managed-mode-hook #'start/setup-capfs)
;;   (add-hook 'prog-mode-hook #'start/setup-capfs)
;;   (add-hook 'text-mode-hook #'start/setup-capfs))

;; (use-package orderless
;;   :defer
;;   :custom
;;   (completion-styles '(orderless basic))
;;   (completion-category-overrides '((file (styles basic partial-completion)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; TREESITTER
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(use-package treesit
  :ensure nil
  :config
  (setq treesit-language-source-alist
        '((css . ("https://github.com/tree-sitter/tree-sitter-css" "v0.23.2"))
          (go . ("https://github.com/tree-sitter/tree-sitter-go" "v0.20.0"))
          (html . ("https://github.com/tree-sitter/tree-sitter-html" "v0.20.1"))
          (javascript . ("https://github.com/tree-sitter/tree-sitter-javascript" "v0.20.1" "src"))
          (json . ("https://github.com/tree-sitter/tree-sitter-json" "v0.20.2"))
          (markdown . ("https://github.com/ikatyang/tree-sitter-markdown" "v0.7.1"))
          (python . ("https://github.com/tree-sitter/tree-sitter-python" "v0.23.6"))
          (rust . ("https://github.com/tree-sitter/tree-sitter-rust" "v0.21.2"))
          (toml . ("https://github.com/tree-sitter/tree-sitter-toml" "v0.5.1"))
          (tsx . ("https://github.com/tree-sitter/tree-sitter-typescript" "v0.20.3" "tsx/src"))
          (typescript . ("https://github.com/tree-sitter/tree-sitter-typescript" "v0.20.3" "typescript/src"))
          (yaml . ("https://github.com/ikatyang/tree-sitter-yaml" "v0.5.0"))
          (gdscript . ("https://github.com/PrestonKnopp/tree-sitter-gdscript"))
          (make . ("https://github.com/alemuller/tree-sitter-make"))
          (markdown . ("https://github.com/ikatyang/tree-sitter-markdown"))
          (vue . ("https://github.com/ikatyang/tree-sitter-vue"))))

  (defun start/install-treesit-grammars ()
    "Install missing treesitter grammars"
    (interactive)
    (dolist (grammar treesit-language-source-alist)
      (let ((lang (car grammar)))
        (unless (treesit-language-available-p lang)
          (treesit-install-language-grammar lang)))))

  ;; Call this function to install missing grammars
  (add-hook 'after-init-hook #'start/install-treesit-grammars)

  ;; Optionally, add any additional mode remappings not covered by defaults
  (setq major-mode-remap-alist
        '((yaml-mode . yaml-ts-mode)
          (sh-mode . bash-ts-mode)
          (c-mode . c-ts-mode)
          (c++-mode . c++-ts-mode)
          (css-mode . css-ts-mode)
          (python-mode . python-ts-mode)
          (mhtml-mode . html-ts-mode)
          (javascript-mode . js-ts-mode)
          (js-json-mode . json-ts-mode)
          (typescript-mode . typescript-ts-mode)
          (conf-toml-mode . toml-ts-mode)
          (gdscript-mode . gdscript-ts-mode)
          ))
  (setq treesit-font-lock-level 3)

  ;; Or if there is no built in mode
  (use-package cmake-ts-mode :ensure nil :mode ("CMakeLists\\.txt\\'" "\\.cmake\\'"))
  (use-package go-mod-ts-mode :ensure nil :mode "\\.mod\\'")
  (use-package lua-ts-mode :ensure nil :mode "\\.lua\\'")
  (use-package rust-ts-mode :ensure nil :mode "\\.rs\\'")
  (use-package typescript-ts-mode :ensure nil :mode "\\.ts\\'")
  (use-package tsx-ts-mode :ensure nil :mode "\\.tsx\\'")
  (use-package yaml-ts-mode :ensure nil :mode ("\\.yaml\\'" "\\.yml\\'")))



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
(require 'init-org)
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
  ((js-mode web-mode scss-mode css-mode) . prettier-js-mode))

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
;; EGLOT
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(use-package eglot
  :ensure t
  :hook (liquid-mode . eglot-ensure)
  :config
  (setq-default eglot-workspace-configuration
              '((:tailwindCSS . (:includeLanguages (:liquid-mode "html")
                                                   :userLanguages (:liquid-mode "html")))))
  (setq eglot-stay-out-of '(completion-styles))
  (add-to-list 'eglot-server-programs
               '(liquid-mode . ("rass" "liquidtailwind"))))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Jira
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(use-package jira
  :custom
  (jira-base-url "https://udundi.atlassian.net")
  (jira-token-is-personal-access-token nil)
  (jira-api-version 3))




;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Slack
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Leetcode
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; QOL
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(use-package eat
  :defer
  :hook ('eshell-load-hook #'eat-eshell-mode))

(use-package magit
  :defer
  :custom (magit-diff-refine-hunk (quote all))
  :config
  (setopt magit-format-file-function #'magit-format-file-nerd-icons))

(use-package diff-hl
  :hook ((dired-mode         . diff-hl-dired-mode-unless-remote)
         (magit-post-refresh . diff-hl-magit-post-refresh)
         (after-init . global-diff-hl-mode)))

;; (use-package consult
;;   ;; Enable automatic preview at point in the *Completions* buffer. This is
;;   ;; relevant when you use the default completion UI.
;;   :hook (completion-list-mode . consult-preview-at-point-mode)
;;   :init
;;   ;; Optionally configure the register formatting. This improves the register
;;   ;; preview for `consult-register', `consult-register-load',
;;   ;; `consult-register-store' and the Emacs built-ins.
;;   (setq register-preview-delay 0.5
;;         register-preview-function #'consult-register-format)

;;   ;; Optionally tweak the register preview window.
;;   ;; This adds thin lines, sorting and hides the mode line of the window.
;;   (advice-add #'register-preview :override #'consult-register-window)

;;   ;; Use Consult to select xref locations with preview
;;   (setq xref-show-xrefs-function #'consult-xref
;;         xref-show-definitions-function #'consult-xref)
;;   :config
;;   ;; Optionally configure preview. The default value
;;   ;; is 'any, such that any key triggers the preview.
;;   ;; (setq consult-preview-key 'any)
;;   ;; (setq consult-preview-key "M-.")
;;   ;; (setq consult-preview-key '("S-<down>" "S-<up>"))

;;   ;; For some commands and buffer sources it is useful to configure the
;;   ;; :preview-key on a per-command basis using the `consult-customize' macro.
;;   ;; (consult-customize
;;   ;; consult-theme :preview-key '(:debounce 0.2 any)
;;   ;; consult-ripgrep consult-git-grep consult-grep
;;   ;; consult-bookmark consult-recent-file consult-xref
;;   ;; consult--source-bookmark consult--source-file-register
;;   ;; consult--source-recent-file consult--source-project-recent-file
;;   ;; :preview-key "M-."
;;   ;; :preview-key '(:debounce 0.4 any))

;;   ;; By default `consult-project-function' uses `project-root' from project.el.
;;   ;; Optionally configure a different project root function.
;;    ;;;; 1. project.el (the default)
;;   (setq consult-project-function #'consult--default-project--function)
;;    ;;;; 2. vc.el (vc-root-dir)
;;   ;; (setq consult-project-function (lambda (_) (vc-root-dir)))
;;    ;;;; 3. locate-dominating-file
;;   ;; (setq consult-project-function (lambda (_) (locate-dominating-file "." ".git")))
;;    ;;;; 4. projectile.el (projectile-project-root)
;;   ;;;; (autoload 'projectile-project-root "projectile")
;;   ;;;; (setq consult-project-function (lambda (_) (projectile-project-root)))
;;    ;;;; 5. No project support
;;   ;; (setq consult-project-function nil)
;;   )

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
