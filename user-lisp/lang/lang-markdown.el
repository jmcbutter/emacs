;;; lang-markdown.el --- Markdown Language Configuration -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(use-package markdown-mode
  :config
  (let ((scale 1.15))
    (set-face-attribute 'markdown-header-face-1 nil :height (expt scale 3) :weight 'medium :slant 'normal)
    (set-face-attribute 'markdown-header-face-2 nil :height (expt scale 3) :weight 'medium :slant 'oblique)
    (set-face-attribute 'markdown-header-face-3 nil :height (expt scale 2) :weight 'medium :slant 'normal)
    (set-face-attribute 'markdown-header-face-4 nil :height (expt scale 2) :weight 'medium :slant 'oblique)
    (set-face-attribute 'markdown-header-face-5 nil :height (expt scale 1) :weight 'medium :slant 'normal)
    (set-face-attribute 'markdown-header-face-6 nil :height (expt scale 1) :weight 'medium :slant 'oblique)))

(provide 'lang-markdown)
;;; lang-markdown.el ends here
