;;; -*- lexical-binding: t -*-
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(ediff-merge-split-window-function 'split-window-horizontally)
 '(ediff-split-window-function 'split-window-horizontally)
 '(ediff-window-setup-function 'ediff-setup-windows-plain)
 '(ledger-reports
   '(("bal"
      "ledger [[ledger-mode-flags]] -f /home/jmcbutter/Dropbox/Documents/Support/Environment/301\\ 11th\\ St/profit-loss.ledger bal")
     ("reg" "%(binary) -f %(ledger-file) reg")
     ("payee" "%(binary) -f %(ledger-file) reg @%(payee)")
     ("account" "%(binary) -f %(ledger-file) reg %(account)")))
 '(org-agenda-files nil)
 '(org-directory "~/Dropbox/Documents/")
 '(package-selected-packages
   '(agent-shell-sidebar bbdb clipetty codex-ide corfu eglot-java
                         exec-path-from-shell forge ghostel gptel
                         magit markdown-mode org-edna plantuml-mode
                         vundo web-mode xclip))
 '(package-vc-selected-packages
   '((codex-ide :url "https://github.com/dgillis/emacs-codex-ide")
     (agent-shell-knockknock :url
                             "https://github.com/xenodium/agent-shell-knockknock")))
 '(plantuml-executable-path "\"plantuml\"")
 '(safe-local-variable-values
   '((org-anki-default-note-type . "Cloze") (org-anki-inherit-tags)))
 '(treesit-font-lock-level 4))
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
