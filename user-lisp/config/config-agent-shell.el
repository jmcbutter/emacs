;;; config-completion.el --- In-buffer completion -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(use-package agent-shell
  :ensure t
  :config
  (setq agent-shell-openai-authentication
      (agent-shell-openai-make-authentication :login t)))

(provide 'config-completion)
;;; config-completion.el ends here
