;;; config-llm.el --- LLM configuration -*- lexical-binding: t -*-
;;; Commentary:
;;; Code:

(declare-function agent-shell-openai-make-authentication "agent-shell-openai")

(defun my-agent-shell--codex-acp-auth-method-compat (args)
  "Translate old Codex ACP auth method ids to codex-acp 1.1 ids."
  (let ((method-id (plist-get args :method-id)))
    (pcase method-id
      ((or "openai-api-key" "codex-api-key")
       (plist-put args :method-id "api-key"))
      ("chatgpt"
       (plist-put args :method-id "chat-gpt"))
      (_ args))))

(use-package agent-shell
  :ensure t
  :config
  (with-eval-after-load 'acp
    (unless (advice-member-p #'my-agent-shell--codex-acp-auth-method-compat
                             'acp-make-authenticate-request)
      (advice-add 'acp-make-authenticate-request
                  :filter-args
                  #'my-agent-shell--codex-acp-auth-method-compat)))

  (setq agent-shell-openai-authentication
        (agent-shell-openai-make-authentication :login t)))

(use-package agent-shell-sidebar
  :after agent-shell
  :vc (:url "https://github.com/cmacrae/agent-shell-sidebar")
  :custom
  (agent-shell-sidebar-position 'right)
  (agent-shell-sidebar-locked t)
  (agent-shell-sidebar-default-config
   (agent-shell-openai-make-codex-config)))

(use-package gptel
  :ensure t
  :config
  (with-eval-after-load 'gptel-openai-oauth
    (defun my/gptel-openai-oauth-authorization-url-fixed
        (redirect-uri verifier state)
      "Return a fixed OpenAI OAuth authorization URL.

Do not pre-encode REDIRECT-URI here. `url-build-query-string'
will encode it exactly once."
      (concat
       gptel--openai-oauth-url "/oauth/authorize?"
       (url-build-query-string
        `(("response_type" "code")
          ("client_id" ,gptel--openai-oauth-client-id)
          ("redirect_uri" ,redirect-uri)
          ("scope" "openid profile email offline_access")
          ("code_challenge" ,(gptel-oauth--generate-code-challenge verifier))
          ("code_challenge_method" "S256")
          ("id_token_add_organizations" "true")
          ("prompt" "login")
          ("codex_cli_simplified_flow" "true")
          ("state" ,state)
          ("originator" "gptel")))))

    (advice-add
     'gptel--openai-oauth-authorization-url
     :override
     #'my/gptel-openai-oauth-authorization-url-fixed)

    (defun my/gptel-openai-oauth-login-with-authorization-code-fixed
        (backend)
      "Authenticate BACKEND using fixed OpenAI OAuth PKCE flow."
      (let* ((redirect-uri
              (format "http://localhost:%d%s"
                      gptel--openai-oauth-redirect-port
                      gptel--openai-oauth-redirect-path))
             (verifier (gptel-oauth--generate-code-verifier))
             (state (secure-hash 'sha256
                                 (format "%s%s" (float-time) (random))))
             (authorization-url
              (gptel--openai-oauth-authorization-url
               redirect-uri verifier state))
             (code
              (gptel--openai-oauth-read-code authorization-url state))
             (token-plist
              (gptel--url-retrieve
                  (concat gptel--openai-oauth-url "/oauth/token")
                :method 'post
                :data
                (url-build-query-string
                 `(("grant_type" "authorization_code")
                   ("client_id" ,gptel--openai-oauth-client-id)
                   ("code" ,code)
                   ("code_verifier" ,verifier)
                   ("redirect_uri" ,redirect-uri)))
                :content-type "application/x-www-form-urlencoded")))
        (gptel--openai-oauth-persist backend token-plist)))

    (advice-add
     'gptel--openai-oauth-login-with-authorization-code
     :override
     #'my/gptel-openai-oauth-login-with-authorization-code-fixed))

  (setq gptel-model 'gpt-5.5
        gptel-backend (gptel-make-openai-oauth "OpenAI-sub")))

(use-package codex-ide
  :ensure t
  :vc (:url "https://github.com/dgillis/emacs-codex-ide" :rev :newest)
  :bind ("C-c C-;" . codex-ide-menu))


(defvar jmb/llm-global-prefix-map (make-sparse-keymap)
  "A keymap for handy global access to org helpers, particularly clocking.")
(define-key jmb/llm-global-prefix-map (kbd "c") 'agent-shell-sidebar-toggle-focus)
(define-key jmb/llm-global-prefix-map (kbd "f") 'agent-shell-sidebar-toggle-focus)
(define-key jmb/llm-global-prefix-map (kbd "s") 'agent-shell-sidebar-toggle)

(define-key global-map (kbd "C-c a") jmb/llm-global-prefix-map)

(provide 'config-llm)
;;; config-llm.el ends here
