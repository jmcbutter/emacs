;;; config-ghostel.el --- Ghostel Configuration -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:


(use-package ghostel
  :ensure t
  :bind (:map ghostel-semi-char-mode-map
              ("C-\\" . ghostel-send-C-backslash)))

(provide 'config-ghostel)
;;; config-ghostel.el ends here


