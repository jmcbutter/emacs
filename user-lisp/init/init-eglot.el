;;; init-eglot.el --- Eglot Configuration -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(use-package mason
  :hook (after-init . mason-ensure))

(use-package eglot
  :ensure t
  :hook ((c-mode
          c++-mode
          liquid-mode
          js-ts-mode
          web-mode
          scss-mode
          css-ts-mode
          html-ts-mode
          mhtml-ts-mode
          go-ts-mode
          php-ts-mode
          tsx-ts-mode
          java-ts-mode
          rust-ts-mode
          typescript-ts-mode
          python-ts-mode
          go-mod-ts-mode
          go-work-ts-mode)
         . eglot-ensure)

  :custom
  (eglot-events-buffer-size 0)
  (eglot-autoshutdown t)
  (eglot-report-progress nil))

  ;; :config
  ;; (setq-default eglot-workspace-configuration
  ;;             '((:tailwindCSS . (:includeLanguages (:liquid-mode "html")
  ;;                                                  :userLanguages (:liquid-mode "html")))))
  ;; (setq eglot-stay-out-of '(completion-styles))
  ;; (add-to-list 'eglot-server-programs
  ;;              '(liquid-mode . ("rass" "liquidtailwind"))))


(use-package eldoc-box
  :ensure t)


(provide 'init-eglot)
;;; init-eglot.el ends here
