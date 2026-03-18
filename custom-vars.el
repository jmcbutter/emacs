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
 '(org-directory "~/Dropbox/Documents/")
 '(package-selected-packages
   '(anki-editor bbdb bookmark+ bookmarkplus bufferlo cape claude-code
                 consult corfu css csv-mode diff-hl diminish dmenu eat
                 exec-path-from-shell exwm gptel helpful hl-todo
                 indent-guide inheritenv jira ledger-mode leetcode
                 magit marginalia mason mcp monet
                 nerd-icons-completion nerd-icons-corfu
                 nerd-icons-dired nerd-icons-ibuffer orderless
                 pdf-tools prettier-js rainbow-delimiters snippy
                 treesit-langs undo-fu-session vertico vundo web-mode
                 ws-butler xclip yasnippet-capf yasnippet-snippets))
 '(package-vc-selected-packages '((monet :url "https://github.com/stevemolitor/monet")))
 '(safe-local-variable-values
   '((org-anki-default-note-type . "Cloze") (org-anki-inherit-tags))))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(web-mode-block-attr-name-face ((t (:foreground "dark green"))))
 '(web-mode-doctype-face ((t (:foreground "dim gray"))))
 '(web-mode-error-face ((t (:background "dark salmon"))))
 '(web-mode-html-attr-name-face ((t (:foreground "DarkOrchid4"))))
 '(web-mode-html-tag-face ((t (:foreground "medium blue")))))
