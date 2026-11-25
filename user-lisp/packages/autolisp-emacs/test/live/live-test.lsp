; Used by live-test.el.  Arithmetic only: draws nothing, changes no settings.
(defun emacs:live-test (n / a b)
  (setq a (* n 2))
  (setq b (+ a 1))
  b
)
(emacs:live-test 20)
