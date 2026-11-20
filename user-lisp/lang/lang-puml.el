;;; lang-puml.el --- Puml Language Configuration -*- lexical-binding: t -*-
;;; Commentary:

;; C-c C-c previews the diagram in the window you're in, replacing the
;; source; q in the preview goes back.  C-u C-c C-c previews it in a
;; split, and C-u C-u C-c C-c in a new frame, as plantuml-mode does by
;; default.  In dired, C-c C-c on a .puml file renders it straight away
;; without visiting the file.

;;; Code:

(declare-function plantuml-preview-string "plantuml-mode" (prefix string))
(declare-function dired-get-file-for-visit "dired" ())
(defvar dired-mode-map)

(use-package plantuml-mode
  :ensure t
  :mode "\\.puml\\'"
  :custom
  (plantuml-jar-path "~/Src/plantuml.jar")
  (plantuml-default-exec-mode 'jar)
  :config
  (advice-add 'plantuml-update-preview-buffer :before
              #'jmb/plantuml--preview-in-same-window))

(defun jmb/plantuml--preview-in-same-window (prefix buf)
  "Show preview BUF in the selected window when there's no PREFIX.
plantuml-mode calls `display-buffer' when there's no prefix argument,
which puts the preview in another window.  Showing BUF here first lets
that call reuse this window instead."
  (when (= prefix 1)
    (switch-to-buffer buf)))

(defun jmb/dired-plantuml-preview (prefix)
  "Render the PlantUML file at point without visiting it.
The preview replaces dired in this window; q goes back.  PREFIX works as
it does for `plantuml-preview': \\[universal-argument] previews in a split, \\[universal-argument] \\[universal-argument] in a
new frame."
  (interactive "p")
  (let ((file (dired-get-file-for-visit)))
    (unless (string-match-p "\\.p\\(lant\\)?uml\\'" file)
      (user-error "Not a PlantUML file: %s" (file-name-nondirectory file)))
    (require 'plantuml-mode)
    ;; Run from the file's folder so relative !include paths resolve.
    (let ((default-directory (file-name-directory file)))
      (plantuml-preview-string
       prefix
       (with-temp-buffer
         (insert-file-contents file)
         (buffer-string))))))

(with-eval-after-load 'dired
  (keymap-set dired-mode-map "C-c C-c" #'jmb/dired-plantuml-preview))

(provide 'lang-puml)
;;; lang-puml.el ends here
