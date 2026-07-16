;;; lang-typescript.el --- TypeScript Language Configuration -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(use-package typescript-ts-mode
  :init
  (add-to-list 'auto-mode-alist '("\\.ts\\'" . typescript-ts-mode)))


(provide 'lang-typescript)
;;; lang-typescript.el ends here
