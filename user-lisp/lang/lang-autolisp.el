;;; lang-autolisp.el --- AutoLISP Language Configuration -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(use-package dape
  :ensure t
  :defer t
  :custom
  (dape-buffer-window-arrangement 'right))

;; Completion is ranked well enough here to show sooner than elsewhere.
(defvar corfu-auto-delay)
(defvar corfu-auto-prefix)

(defun jmb/autolisp-corfu-setup ()
  "Make corfu pop up quickly in this buffer."
  (setq-local corfu-auto-delay 0.2
              corfu-auto-prefix 2))

(use-package autolisp-mode
  :ensure nil
  :load-path "user-lisp/packages/autolisp-emacs"
  :hook ((autolisp-mode autolisp-dcl-mode) . jmb/autolisp-corfu-setup)
  :mode (("\\.\\(?:lsp\\|LSP\\|mnl\\|MNL\\)\\'" . autolisp-mode)
         ("\\.\\(?:dcl\\|DCL\\)\\'" . autolisp-dcl-mode)))

(provide 'lang-autolisp)
;;; lang-autolisp.el ends here
