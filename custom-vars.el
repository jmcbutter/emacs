;;; -*- lexical-binding: t -*-
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(agent-shell-clipboard-image-handlers
   '(((:command . "xclip")
      (:save
       . #[257
           "\300 \301=\205\13\0\302\303\304\"\211\205\22\0\305\1!\211\205\33\0\306\2\307\"?\211\203#\0\310\311!\210\266\3\312\313\314\"r\211q\210\315\316\2\"\216\317\320!\210\321\322\320\314\320\323\324\325\326\327&\11\211\330U\204M\0\310\331\2\"\210\332ed\5\320\333%*\207"
           [window-system x gui-get-selection CLIPBOARD TARGETS
                          vectorp seq-contains-p image/png error
                          "No image/png in clipboard"
                          generate-new-buffer " *temp*" t make-closure
                          #[0 "\301\300!\205\11\0\302\300!\207"
                              [V0 buffer-name kill-buffer] 2]
                          set-buffer-multibyte nil call-process
                          "xclip" "-selection" "clipboard" "-t"
                          "image/png" "-o" 0
                          "Command xclip failed with exit code %d"
                          write-region silent]
           12 "\12\12(fn FILE-PATH)"]))
     ((:command . "powershell")
      (:save
       . #[257
           "\300\301\302\211\211\303\304\305\306\6\11!\"&\6\211\307U?\205\32\0\310\311\2\"\207"
           [call-process "powershell" nil "-Command" format
                         "& {(Get-Clipboard -Format image).Save(%s)}"
                         shell-quote-argument 0 error
                         "Command powershell failed with exit code %d"]
           11 "\12\12(fn FILE-PATH)"]))))
 '(custom-safe-themes
   '("b5fd9c7429d52190235f2383e47d340d7ff769f141cd8f9e7a4629a81abc6b19"
     "4990532659bb6a285fee01ede3dfa1b1bdf302c5c3c8de9fad9b6bc63a9252f7"
     "df6dfd55673f40364b1970440f0b0cb8ba7149282cf415b81aaad2d98b0f0290"
     "4b88b7ca61eb48bb22e2a4b589be66ba31ba805860db9ed51b4c484f3ef612a7"
     "4594d6b9753691142f02e67b8eb0fda7d12f6cc9f1299a49b819312d6addad1d"
     "13096a9a6e75c7330c1bc500f30a8f4407bd618431c94aeab55c9855731a95e1"
     default))
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
   '(agent-shell agent-shell-knockknock agent-shell-sidebar apptrack bbdb
                 bufferlo calibredb clipetty codex-ide corfu diminish
                 dired-preview dockerfile-mode doom-themes eat
                 eaveside-agent-manager eca eglot-java
                 exec-path-from-shell feature-mode forge ghostel gptel
                 lsp-mode magit marginalia md-ts-mode
                 nerd-icons-completion nerd-icons-dired
                 nerd-icons-ibuffer nov org-edna pdf-tools
                 plantuml-mode rainbow-delimiters sqlite3 texfrag
                 undo-fu-session vertico vundo web-mode ws-butler
                 xclip))
 '(package-vc-selected-packages
   '((eaveside-agent-manager :url
                             "git@github.com:jmcbutter/eaveside-agentic-workflow.git"
                             :lisp-dir "eaveside-agent-manager")
     (reader :url "https://codeberg.org/divyaranjan/emacs-reader"
             :make "all")
     (codex-ide :url "https://github.com/dgillis/emacs-codex-ide")
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
