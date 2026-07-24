;;; lang-org.el --- Org Language Configuration -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(with-eval-after-load 'org
  (setq-default org-edit-src-content-indentation 4)
  (let ((scale 1.1))
    (set-face-attribute 'org-level-1 nil :height (expt scale 5) :weight 'medium :slant 'normal)
    (set-face-attribute 'org-level-2 nil :height (expt scale 4) :weight 'medium :slant 'normal)
    (set-face-attribute 'org-level-3 nil :height (expt scale 3) :weight 'medium :slant 'normal)
    (set-face-attribute 'org-level-4 nil :height (expt scale 2) :weight 'medium :slant 'normal)
    (set-face-attribute 'org-level-5 nil :height (expt scale 1) :weight 'medium :slant 'normal)
    (set-face-attribute 'org-level-6 nil :height (expt scale 0) :weight 'medium :slant 'normal)
    (set-face-attribute 'org-agenda-structure nil :height (expt scale 0) :weight 'bold :slant 'normal :background "#D1DCE1" :box '(:line-width (-1 . -1))))
  (add-hook 'org-mode-hook #'org-indent-mode))

(provide 'lang-org)
;;; lang-org.el ends here
