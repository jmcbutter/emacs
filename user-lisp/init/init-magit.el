;;; init-magit.el ---  Magit Configuration -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(use-package magit
  :defer
  :custom (magit-diff-refine-hunk (quote all))
  :config
  (setopt magit-format-file-function #'magit-format-file-nerd-icons))

(use-package diff-hl
  :hook ((dired-mode         . diff-hl-dired-mode-unless-remote)
         (magit-post-refresh . diff-hl-magit-post-refresh)
         (after-init . global-diff-hl-mode)))

(provide 'init-magit)
;;; init-magit.el ends here
