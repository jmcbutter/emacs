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
(define-derived-mode liquid-mode mhtml-mode "Liquid"
  "Major mode for Shopify Liquid templates.")
(add-to-list 'auto-mode-alist '("\\.liquid\\'" . liquid-mode))

(use-package lsp-mode
  :ensure t
  :init
  (add-hook 'liquid-mode-hook #'lsp-deferred)
  :config
  (add-to-list 'lsp-language-id-configuration '("\\.liquid\\'" . "liquid"))
  ;; (lsp-register-client
  ;;  (make-lsp-client
  ;;   :new-connection (lsp-stdio-connection '("shopify" "theme" "language-server"))
  ;;   :activation-fn (lsp-activate-on "liquid")
  ;;   :priority 1
  ;;   :add-on? t
  ;;   :initialization-options (list :themeCheck
  ;;                                 ;; The inner `list` creates the nested JSON object
  ;;                                 ;; that the server expects as the value.
  ;;                                 (list :checkOnOpen t
  ;;                                       :checkOnChange t
  ;;                                       :checkOnSave t
  ;;                                       :preloadOnBoot t))
  ;;   :server-id 'shopify-theme-ls))
  )


;; ;; 2. Manage it with rass AND force the languageId both servers expect
;; (with-eval-after-load 'eglot
;;   (add-to-list 'eglot-server-programs
;;                '((liquid-mode :language-id "liquid") . ("shopify" "theme" "language-server")))
;;   (add-hook 'liquid-mode-hook #'eglot-ensure))

(provide 'lang-liquid)
;;; lang-liquid.el ends here

