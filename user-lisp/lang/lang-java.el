;;; lang-java.el --- Java Language Configuration -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:
(use-package eglot-java
  :ensure t
  :mode ("\\.java\\'" . eglot-java-mode)
  :interpreter ("java" . eglot-java-mode))


(provide 'lang-java)
;;; lang-java.el ends here
