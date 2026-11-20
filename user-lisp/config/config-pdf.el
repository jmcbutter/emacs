;;; config-pdf.el --- PDF Configuration -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(use-package pdf-tools
  :ensure t
  :demand t
  :custom
  (pdf-view-display-size 'fit-page)
  :config
  (pdf-tools-install))


(provide 'config-pdf)
;;; config-pdf.el ends here
