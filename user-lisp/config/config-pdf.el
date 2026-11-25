;;; config-pdf.el --- PDF Configuration -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(use-package pdf-tools
  ;; Its epdfinfo program isn't available on Windows without MSYS2.
  :unless (eq system-type 'windows-nt)
  :ensure t
  :demand t
  :custom
  (pdf-view-display-size 'fit-page)
  :config
  (pdf-tools-install))


(provide 'config-pdf)
;;; config-pdf.el ends here
