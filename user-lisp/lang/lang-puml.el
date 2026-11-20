;;; lang-puml.el --- Puml Language Configuration -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(use-package plantuml-mode
  :ensure t
  :mode "\\.puml\\'"
  :custom
  (plantuml-jar-path "~/Src/plantuml.jar")
  (plantuml-default-exec-mode 'jar))

(provide 'lang-puml)
;;; lang-puml.el ends here
