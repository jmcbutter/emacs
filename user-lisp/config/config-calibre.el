;;; config-calibre.el --- Calibre -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(use-package calibredb
  :ensure t
  :defer t
  :config
  (setq calibredb-root-dir "~/Dropbox/Library/books")
  ;; for folder driver metadata: it should be .metadata.calibre
  (setq calibredb-db-dir (expand-file-name "metadata.db" calibredb-root-dir))
  (setq calibredb-library-alist '(("~/Dropbox/Library/books" (name . "Calibre")))))

(provide 'config-calibre)
;;; config-calibre.el ends here
