;;; lang-org.el --- Org Language Configuration -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(defvar org-plantuml-jar-path)
(defvar org-babel-load-languages)
(declare-function org-redisplay-inline-images "org" ())

(with-eval-after-load 'org
  (setq-default org-edit-src-content-indentation 4)
  (let ((scale 1.015))
    (set-face-attribute 'org-level-1 nil :height (expt scale 5) :weight 'medium :slant 'normal)
    (set-face-attribute 'org-level-2 nil :height (expt scale 4) :weight 'medium :slant 'normal)
    (set-face-attribute 'org-level-3 nil :height (expt scale 3) :weight 'medium :slant 'normal)
    (set-face-attribute 'org-level-4 nil :height (expt scale 2) :weight 'medium :slant 'normal)
    (set-face-attribute 'org-level-5 nil :height (expt scale 1) :weight 'medium :slant 'normal)
    (set-face-attribute 'org-level-6 nil :height (expt scale 0) :weight 'medium :slant 'normal)
    (set-face-attribute 'org-agenda-structure nil :height (expt scale 0) :weight 'bold :slant 'normal :background "#D1DCE1" :box '(:line-width (-1 . -1))))
  (add-hook 'org-mode-hook #'org-indent-mode)

  ;; Babel languages used by the spec templates: inline PlantUML
  ;; diagrams, curl checks, SQL DDL and Calc.  Results that are images
  ;; show inline right after C-c C-c.
  (setq org-plantuml-jar-path (expand-file-name "~/Src/plantuml.jar"))
  (org-babel-do-load-languages
   'org-babel-load-languages
   (append '((plantuml . t) (shell . t) (sql . t) (calc . t))
           (seq-remove (lambda (l) (memq (car l) '(plantuml shell sql calc)))
                       org-babel-load-languages)))
  (add-hook 'org-babel-after-execute-hook #'org-redisplay-inline-images))

(provide 'lang-org)
;;; lang-org.el ends here
