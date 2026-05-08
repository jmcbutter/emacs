;;; init-treesitter.el --- Treesitter Configuration -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(use-package treesit
  :ensure nil
  :config
  (setq treesit-language-source-alist
        '((css . ("https://github.com/tree-sitter/tree-sitter-css" "v0.23.2"))
          (go . ("https://github.com/tree-sitter/tree-sitter-go" "v0.20.0"))
          (html . ("https://github.com/tree-sitter/tree-sitter-html" "v0.20.1"))
          (javascript . ("https://github.com/tree-sitter/tree-sitter-javascript" "v0.20.1" "src"))
          (json . ("https://github.com/tree-sitter/tree-sitter-json" "v0.20.2"))
          (markdown . ("https://github.com/ikatyang/tree-sitter-markdown" "v0.7.1"))
          (python . ("https://github.com/tree-sitter/tree-sitter-python" "v0.23.6"))
          (rust . ("https://github.com/tree-sitter/tree-sitter-rust" "v0.21.2"))
          (toml . ("https://github.com/tree-sitter/tree-sitter-toml" "v0.5.1"))
          (tsx . ("https://github.com/tree-sitter/tree-sitter-typescript" "v0.20.3" "tsx/src"))
          (typescript . ("https://github.com/tree-sitter/tree-sitter-typescript" "v0.20.3" "typescript/src"))
          (yaml . ("https://github.com/ikatyang/tree-sitter-yaml" "v0.5.0"))
          (gdscript . ("https://github.com/PrestonKnopp/tree-sitter-gdscript"))
          (make . ("https://github.com/alemuller/tree-sitter-make"))
          (markdown . ("https://github.com/ikatyang/tree-sitter-markdown"))
          (vue . ("https://github.com/ikatyang/tree-sitter-vue"))))

  (defun start/install-treesit-grammars ()
    "Install missing treesitter grammars"
    (interactive)
    (dolist (grammar treesit-language-source-alist)
      (let ((lang (car grammar)))
        (unless (treesit-language-available-p lang)
          (treesit-install-language-grammar lang)))))

  ;; Call this function to install missing grammars
  (add-hook 'after-init-hook #'start/install-treesit-grammars)

  ;; Optionally, add any additional mode remappings not covered by defaults
  (setq major-mode-remap-alist
        '((yaml-mode . yaml-ts-mode)
          (sh-mode . bash-ts-mode)
          (c-mode . c-ts-mode)
          (c++-mode . c++-ts-mode)
          (css-mode . css-ts-mode)
          (python-mode . python-ts-mode)
          ; (mhtml-mode . html-ts-mode)
          (javascript-mode . js-ts-mode)
          (js-json-mode . json-ts-mode)
          (typescript-mode . typescript-ts-mode)
          (conf-toml-mode . toml-ts-mode)
          (gdscript-mode . gdscript-ts-mode)
          ))
  (setq treesit-font-lock-level 3)

  ;; Or if there is no built in mode
  (use-package cmake-ts-mode :ensure nil :mode ("CMakeLists\\.txt\\'" "\\.cmake\\'"))
  (use-package go-mod-ts-mode :ensure nil :mode "\\.mod\\'")
  (use-package lua-ts-mode :ensure nil :mode "\\.lua\\'")
  (use-package rust-ts-mode :ensure nil :mode "\\.rs\\'")
  (use-package typescript-ts-mode :ensure nil :mode "\\.ts\\'")
  (use-package tsx-ts-mode :ensure nil :mode "\\.tsx\\'")
  (use-package yaml-ts-mode :ensure nil :mode ("\\.yaml\\'" "\\.yml\\'")))


(provide 'init-treesitter)
;;; init-treesitter.el ends here
