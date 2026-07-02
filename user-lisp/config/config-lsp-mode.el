;;; config-lsp-mode.el --- Lsp-Mode Configuration -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

;; (use-package lsp-mode
;;   :ensure t
;;   :custom
;;   (lsp-eldoc-render-all t)
;;   (lsp-keymap-prefix "C-c l")
;;   (lsp-log-io nil)
;;   (lsp-idle-delay 0.5)
;;   :config
;;   (defun lsp-booster--advice-json-parse (old-fn &rest args)
;;     "Try to parse bytecode instead of json."
;;     (or
;;      (when (equal (following-char) ?#)
;;        (let ((bytecode (read (current-buffer))))
;;          (when (byte-code-function-p bytecode)
;;            (funcall bytecode))))
;;      (apply old-fn args)))
;;   (advice-add (if (progn (require 'json)
;;                          (fboundp 'json-parse-buffer))
;;                   'json-parse-buffer
;;                 'json-read)
;;               :around
;;               #'lsp-booster--advice-json-parse)

;;   (defun lsp-booster--advice-final-command (old-fn cmd &optional test?)
;;     "Prepend emacs-lsp-booster command to lsp CMD."
;;     (let ((orig-result (funcall old-fn cmd test?)))
;;       (if (and (not test?)                             ;; for check lsp-server-present?
;;                (not (file-remote-p default-directory)) ;; see lsp-resolve-final-command, it would add extra shell wrapper
;;                lsp-use-plists
;;                (not (functionp 'json-rpc-connection))  ;; native json-rpc
;;                (executable-find "emacs-lsp-booster"))
;;           (progn
;;             (when-let ((command-from-exec-path (executable-find (car orig-result))))  ;; resolve command from exec-path (in case not found in $PATH)
;;               (setcar orig-result command-from-exec-path))
;;             (message "Using emacs-lsp-booster for %s!" orig-result)
;;             (cons "emacs-lsp-booster" orig-result))
;;         orig-result)))
;;   (advice-add 'lsp-resolve-final-command :around #'lsp-booster--advice-final-command)

;;   ;; custom-vars.el may contain a stale server path from a different machine.
;;   ;; Find the binary in the NVM global bin; fall back to managed install if absent.
;;   (with-eval-after-load 'lsp-tailwindcss
;;     (unless (and (stringp lsp-tailwindcss-server-path)
;;                  (not (string-empty-p lsp-tailwindcss-server-path))
;;                  (file-executable-p lsp-tailwindcss-server-path))
;;       (let ((nvm-server (expand-file-name "~/.nvm/versions/node/v24.16.0/bin/tailwindcss-language-server")))
;;         (setq lsp-tailwindcss-server-path
;;               (if (file-executable-p nvm-server) nvm-server ""))))))


(provide 'config-lsp-mode)
;;; config-lsp-mode.el ends here

