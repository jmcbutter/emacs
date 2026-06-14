;;; -*- lexical-binding: t -*-
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(ledger-reports
   '(("bal"
      "ledger [[ledger-mode-flags]] -f /home/jmcbutter/Dropbox/Documents/Support/Environment/301\\ 11th\\ St/profit-loss.ledger bal")
     ("reg" "%(binary) -f %(ledger-file) reg")
     ("payee" "%(binary) -f %(ledger-file) reg @%(payee)")
     ("account" "%(binary) -f %(ledger-file) reg %(account)")))
 '(lsp-tailwindcss-add-on-mode t)
 '(lsp-tailwindcss-class-functions [])
 '(lsp-tailwindcss-server-path
   "/home/jmcbutter/.config/nvm/versions/node/v24.16.0/bin/tailwindcss-language-server")
 '(lsp-tailwindcss-server-version "0.14.7")
 '(org-directory "~/Dropbox/Documents/")
 '(package-selected-packages nil)
 '(package-vc-selected-packages '((monet :url "https://github.com/stevemolitor/monet")))
 '(plantuml-default-exec-mode 'jar)
 '(plantuml-executable-path "\"plantuml\"")
 '(plantuml-jar-path "~/bin/plantuml-gplv2-1.2026.2.jar")
 '(safe-local-variable-values
   '((org-anki-default-note-type . "Cloze") (org-anki-inherit-tags))))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(variable-pitch ((t (:family "LiterationSerif Nerd Font"))))
 '(web-mode-block-attr-name-face ((t (:foreground "dark green"))))
 '(web-mode-doctype-face ((t (:foreground "dim gray"))))
 '(web-mode-error-face ((t (:background "dark salmon"))))
 '(web-mode-html-attr-name-face ((t (:foreground "DarkOrchid4"))))
 '(web-mode-html-tag-face ((t (:foreground "medium blue")))))
