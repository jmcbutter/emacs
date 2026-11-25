;;; lang-autolisp.el --- AutoLISP Language Configuration -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(use-package dape
  :ensure t
  :defer t
  :custom
  (dape-buffer-window-arrangement 'right))

(use-package autolisp-mode
  :ensure nil
  :load-path "user-lisp/packages/autolisp-emacs"
  :mode (("\\.\\(?:lsp\\|LSP\\|mnl\\|MNL\\)\\'" . autolisp-mode)
         ("\\.\\(?:dcl\\|DCL\\)\\'" . autolisp-dcl-mode)))

(provide 'lang-autolisp)
;;; lang-autolisp.el ends here
