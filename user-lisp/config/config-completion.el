;;; config-completion.el --- In-buffer completion -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(use-package corfu
  :ensure t
  :custom
  (corfu-cycle t)
  (corfu-auto t)
  (corfu-auto-prefix 2)
  (corfu-auto-delay 1.5)
  (corfu-popupinfo-mode t)
  (corfu-popupinfo-delay 0.5)
  (corfu-separator ?\s)
  (corfu-preview-current nil)
  (completion-ignore-case t)
  (tab-always-indent 'complete)
  :init
  (global-corfu-mode))

(provide 'config-completion)
;;; config-completion.el ends here
