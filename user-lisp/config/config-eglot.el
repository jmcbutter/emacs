;;; config-eglot.el --- Eglot Configuration -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(use-package eglot
  :ensure t
  :custom
  (eglot-code-action-indications nil)
  :config
  (add-hook 'eglot-managed-mode-hook (lambda () (eldoc-mode -1)))
  (add-to-list 'eglot-ignored-server-capabilities :documentHighlightProvider))

(provide 'config-eglot)
;;; config-eglot.el ends here


