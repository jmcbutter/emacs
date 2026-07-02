;;; lang-liquid.el --- Liquid Language Configuration -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(use-package web-mode
  :ensure t
  :config
  (add-to-list 'web-mode-extra-snippets '("django" . (("doc" . "{% doc %}\n|\n{% enddoc %}"))))
  (add-to-list 'web-mode-extra-control-blocks '("django" . ("doc" "enddoc"
                                                            "style" "endstyle"
                                                            "case" "endcase"))))
;; 1. Real major mode for .liquid
(define-derived-mode liquid-mode web-mode "Liquid"
  "Major mode for Shopify Liquid templates.")
(add-to-list 'auto-mode-alist '("\\.liquid\\'" . liquid-mode))

;; (defun jmb/liquid-eglot-contact (&optional _interactive _project)
;;   "Contact spec for `liquid-mode': eglot -> rass -> {Shopify theme LS, Tailwind}.

;; eglot speaks to a single LSP server per buffer, so we put João Távora's
;; `rass' multiplexer (https://github.com/joaotavora/rassumfrassum) in front
;; of it: eglot talks to one `rass' process, which fans out to the Shopify
;; theme language server and the Tailwind CSS language server.

;; The backend server list, the per-server themeCheck options, and a longer
;; completion-aggregation timeout (rass's stock 3000ms cap truncates the
;; theme server's slower completion replies) all live in the `liquidtail'
;; preset at ~/.config/rassumfrassum/liquidtail.py."
;;   (list (or (executable-find "rass")
;;             (expand-file-name "~/.local/bin/rass"))
;;         "liquidtail"))

;; (use-package eglot
;;   :ensure t
;;   :init
;;   (add-hook 'liquid-mode-hook 'eglot-ensure)
;;   :config
;;   (add-to-list 'eglot-server-programs '(liquid-mode . jmb/liquid-eglot-contact))
;;   ;; The theme-language-server's documentOnTypeFormattingProvider fires on every
;;   ;; space, {, %, etc. — disabling it prevents 20-30s freezes while typing.
;;   (add-to-list 'eglot-ignored-server-capabilities :documentOnTypeFormattingProvider))

(provide 'lang-liquid)
;;; lang-liquid.el ends here
