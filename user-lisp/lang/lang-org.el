;;; lang-org.el --- Org Language Configuration -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(with-eval-after-load 'org
  (setq-default org-edit-src-content-indentation 4)
  (let ((scale 1.15))
    (set-face-attribute 'org-level-1 nil :height (expt scale 3) :weight 'medium :slant 'normal)
    (set-face-attribute 'org-level-2 nil :height (expt scale 3) :weight 'medium :slant 'oblique)
    (set-face-attribute 'org-level-3 nil :height (expt scale 2) :weight 'medium :slant 'normal)
    (set-face-attribute 'org-level-4 nil :height (expt scale 2) :weight 'medium :slant 'oblique)
    (set-face-attribute 'org-level-5 nil :height (expt scale 1) :weight 'medium :slant 'normal)
    (set-face-attribute 'org-level-6 nil :height (expt scale 1) :weight 'medium :slant 'oblique)
    (set-face-attribute 'org-level-7 nil :height (expt scale 0) :weight 'medium :slant 'normal)
    (set-face-attribute 'org-level-8 nil :height (expt scale 0) :weight 'medium :slant 'oblique))
  (add-hook 'org-mode-hook #'org-indent-mode))

(provide 'lang-org)
;;; lang-org.el ends here
