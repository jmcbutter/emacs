;;; config-eglot.el --- Eglot Configuration -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(use-package eglot
  :ensure t
  :custom
  (eglot-ignored-server-capabilities '(:documentOnTypeFormattingProvider :documentHighlightProvider))
  (eglot-send-changes-idle-time 1.0)
  (eglot-events-buffer-config '(:size 0)))

(provide 'config-eglot)
;;; config-eglot.el ends here

