;;; config-web-mode.el --- Web Mode Configuration -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(use-package web-mode
  :ensure t
  :custom
  (web-mode-attr-indent-offset nil)
  (web-mode-attr-value-indent-offset 2)
  (web-mode-block-padding 2)
  (web-mode-code-indent-offset 2)
  (web-mode-css-indent-offset 2)
  (web-mode-enable-auto-indentation nil)
  (web-mode-enable-comment-annotation t)
  (web-mode-enable-comment-interpolation t)
  (web-mode-enable-current-column-highlight t)
  (web-mode-enable-css-colorization t)
  (web-mode-enable-element-content-fontification t)
  (web-mode-enable-sql-detection t)
  (web-mode-markup-comment-indent-offset 2)
  (web-mode-markup-indent-offset 2)
  (web-mode-part-padding 2)
  (web-mode-script-padding 2)
  (web-mode-sql-indent-offset 2)
  (web-mode-style-padding 2))

(provide 'config-web-mode)
;;; config-web-mode.el ends here

