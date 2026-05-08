;;; init-completion.el --- Emacs Completion Configuration -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

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


(provide 'init-completion)
;;; init-completion.el ends here
