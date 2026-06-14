;;; dumb-indent-mode.el --- A minor mode to handle indentation in buffers without an indentation engine  -*- lexical-binding: t; -*-

;;; Commentary:

;;; Code:
(defun dumb-indent ()
  "Indent line or region right to tab stop."
  (interactive)
  (cond
   ((use-region-p)
    (indent-rigidly-right-to-tab-stop (region-beginning) (region-end))
    (setq deactivate-mark nil))
   (t (back-to-indentation)
      (tab-to-tab-stop))))

(defun dumb-outdent ()
  "Outdent line or region right to tab stop."
  (interactive)
  (cond
   ((use-region-p)
    (indent-rigidly-left-to-tab-stop (region-beginning) (region-end))
    (setq deactivate-mark nil))
   (t (back-to-indentation)
      (indent-line-to (indent-next-tab-stop (current-column) 'prev)))))

(defun dumb-newline ()
  "Create a newline indented to the previous line's indent."
  (interactive)
  (newline)
  (let ((prev (save-excursion
                (forward-line -1)
                (back-to-indentation)
                (current-column))))
    (indent-line-to prev)))

(defvar-keymap dumb-indent-minor-mode-map
  :doc "Keymap for dumb indent minor mode"
  "TAB" #'dumb-indent
  "<backtab>" #'dumb-outdent
  "RET" #'dumb-newline)

(define-minor-mode dumb-indent-mode
  "Simple minor mode to handle indentation in buffers lacking good indentation.

`dumb-indent'  and `dumb-outdent' shift the line or region
according to `dumb-indent-offset'. Newlines automatically
indent to the indentation level of the previous line."
  :group 'dumb-indent
  :lighter " di"
  :keymap dumb-indent-minor-mode-map
  (setq-local indent-line-function 'indent-relative-first-indent-point))

(provide 'dumb-indent-mode)

;;; dumb-indent-mode.el ends here
