;;; autolisp-test.el --- Tests -*- lexical-binding: t -*-

;;; Commentary:

;; emacs -Q --batch -L . -l test/autolisp-test.el -f ert-run-tests-batch-and-exit
;; The dape tests are skipped unless dape is on the load path.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'imenu)
(eval-and-compile
  (add-to-list
   'load-path
   (expand-file-name
    ".." (file-name-directory
          (or load-file-name
              (and (boundp 'byte-compile-current-file)
                   byte-compile-current-file)
              buffer-file-name)))))

(require 'autolisp-mode)
(require 'autolisp-dcl-mode)
(require 'autolisp-project)
(require 'autolisp-dape)

(defvar dape-start-hook)
(defvar dape-configs)
(declare-function dape-breakpoint-toggle "dape")
(declare-function dape-breakpoint-remove-all "dape")
(declare-function dape-continue "dape")
(declare-function dape-quit "dape")
(declare-function dape--current-stack-frame "dape")
(declare-function dape--live-connection "dape")
(declare-function dape--live-connections "dape")
(declare-function dape--stopped-threads "dape")

(defconst autolisp-test-dir
  (file-name-directory (or load-file-name buffer-file-name)))

(defun autolisp-test-fixture (name)
  (expand-file-name (concat "fixtures/" name) autolisp-test-dir))

(defmacro autolisp-test-with (text &rest body)
  "Run BODY in an `autolisp-mode' buffer of TEXT, with point at ^."
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,text)
     (autolisp-mode)
     (goto-char (point-min))
     (when (search-forward "^" nil t) (delete-char -1))
     ,@body))

(defmacro autolisp-test-with-copies (&rest body)
  "Run BODY with DIR bound to a copy of the fixtures."
  (declare (indent 0))
  `(let* ((dir (file-name-as-directory (make-temp-file "autolisp" t)))
          (autolisp-search-project-root nil)
          (make-backup-files nil) (create-lockfiles nil))
     (unwind-protect
         (progn
           (dolist (f (directory-files (autolisp-test-fixture "") t "\\.\\(lsp\\|dcl\\)\\'"))
             (copy-file f dir))
           ,@body)
       (dolist (b (buffer-list))
         (when (and (buffer-file-name b)
                    (string-prefix-p (file-truename dir) (file-truename (buffer-file-name b))))
           (with-current-buffer b (set-buffer-modified-p nil))
           (kill-buffer b)))
       (delete-directory dir t))))

(defun autolisp-test-goto (text)
  (goto-char (point-min))
  (search-forward text)
  (goto-char (match-beginning 0)))

;;;; Data

(ert-deftest autolisp-data ()
  (should (> (length (autolisp-data-functions)) 2500))
  (should (autolisp-data-native-p "EntGet"))
  (should (member "DIMSCALE" (autolisp-data-commands)))
  (should (string-match-p "(entget" (autolisp-data-signature
                                     (car (autolisp-data-function-help "ENTGET")))))
  (should (= 2 (length (autolisp-data-function-help "vlax-3d-point"))))
  (let ((autolisp-help-year "2027"))
    (should (equal (autolisp-data-lisp-url "entget")
                   "https://help.autodesk.com/view/OARX/2027/ENU/?guid=GUID-12540DAE-C84B-4BDB-AEEC-DDFE5BE3C42A"))
    (should (string-match-p "4CEE5072" (autolisp-data-lisp-url "no-such-thing")))
    (should (string-match-p "B83960E6" (autolisp-data-dcl-url "button")))))

;;;; Syntax

(ert-deftest autolisp-block-comments ()
  (autolisp-test-with "a ;| one ( \" \n two |; (b)\n; line |; c\nd \";| str\" e ;|x|; f"
    (syntax-propertize (point-max))
    (cl-flet ((state (s) (autolisp-test-goto s) (syntax-ppss)))
      (should (nth 4 (state "one")))
      (should (nth 4 (state "two")))
      (should-not (nth 8 (state "b)")))
      (should (= 1 (car (syntax-ppss (point)))))
      (should (nth 4 (state "line")))
      (should-not (nth 8 (state "d \"")))
      (should (nth 3 (state "str")))
      (should-not (nth 8 (state "e ;")))
      (should-not (nth 8 (progn (goto-char (1- (point-max))) (syntax-ppss)))))))

(ert-deftest autolisp-block-comment-edits ()
  "Closing a block comment after the fact updates the code below it."
  (autolisp-test-with ";| open\n(defun f () 1)\n"
    (syntax-propertize (point-max))
    (goto-char (point-max))
    (should (nth 4 (syntax-ppss)))
    (goto-char 8) (insert " |;")
    (should-not (nth 4 (syntax-ppss (point-max))))))

(ert-deftest autolisp-font-lock ()
  (autolisp-test-with "(DEFUN c:Foo (a / b) (setq a (STRCAT \"x\" 'sym)) T)\n(myfun 1)\n"
    (font-lock-ensure)
    (cl-flet ((face (s) (autolisp-test-goto s) (get-text-property (point) 'face)))
      (should (eq (face "DEFUN") 'font-lock-keyword-face))
      (should (eq (face "c:Foo") 'font-lock-function-name-face))
      (should (eq (face "setq") 'font-lock-keyword-face))
      (should (eq (face "STRCAT") 'font-lock-builtin-face))
      (should (eq (face "sym") 'font-lock-constant-face))
      (should (eq (face "T)") 'font-lock-constant-face))
      (should-not (face "myfun")))))

(ert-deftest autolisp-font-lock-symbols ()
  "Constants and quotes inside longer symbols are left alone."
  (autolisp-test-with "(foo t-x nil? x:t)"
    (font-lock-ensure)
    (dolist (s '("t-x" "nil?" "x:t"))
      (autolisp-test-goto s)
      (should-not (get-text-property (point) 'face)))))

;;;; Indentation

(defun autolisp-test-indent (text)
  "Return TEXT reindented from scratch."
  (autolisp-test-with (replace-regexp-in-string "^[ \t]+" "" text)
    (let ((inhibit-message t)) (indent-region (point-min) (point-max)))
    (buffer-string)))

(ert-deftest autolisp-indentation ()
  (dolist (text '("(defun c:foo (a b / c)\n  (setq a 1)\n  (princ)\n)\n"
                  "(defun foo (a\n            b\n           )\n  a\n)\n"
                  "(setq a 1\n      b\n       2\n      c 3\n)\n"
                  "(if (= a b)\n  (foo)\n  (bar)\n)\n"
                  "(cond\n  ((= a b)\n   (foo)\n  )\n  (t nil)\n)\n"
                  "(strcat \"a\"\n        \"b\"\n)\n"
                  "(strcat\n  \"a\"\n  \"b\"\n)\n"
                  "(setq lst '((1 . 2)\n            (3 . 4)\n           )\n)\n"
                  "(mapcar '(lambda (x)\n           (* x x)\n         )\n        lst\n)\n"
                  "(foreach x lst\n  (print x)\n)\n"
                  "(vlax-for x lst\n  (print x)\n)\n"))
    (should (equal (autolisp-test-indent text) text))))

(ert-deftest autolisp-indentation-fixture ()
  "Autodesk's own consistently formatted sample keeps its indentation."
  (let ((before (with-temp-buffer
                  (insert-file-contents (autolisp-test-fixture "standards.lsp"))
                  (buffer-string))))
    (autolisp-test-with before
      (let ((inhibit-message t)) (indent-region (point-min) (point-max)))
      (should (equal (replace-regexp-in-string "[ \t]+$" "" (buffer-string))
                     (replace-regexp-in-string "[ \t]+$" "" before))))))

(ert-deftest autolisp-indent-leaves-strings-and-comments ()
  (let ((text "(princ \"one\n        two\")\n;|\n     block\n|;\n"))
    (autolisp-test-with text
      (let ((inhibit-message t)) (indent-region (point-min) (point-max)))
      (should (equal (buffer-string) text)))))

;;;; Completion and eldoc

(defun autolisp-test-complete ()
  "Return the completions at point."
  (pcase (autolisp-completion-at-point)
    (`(,beg ,_end ,table . ,_)
     (all-completions (buffer-substring-no-properties beg (point)) table))))

(ert-deftest autolisp-complete-code ()
  (autolisp-test-with "(defun my-helper (x) x)\n(vl-string-^"
    (should (member "vl-string-trim" (autolisp-test-complete))))
  (autolisp-test-with "(defun my-helper (x) x)\n(my-^"
    (should (member "my-helper" (autolisp-test-complete))))
  (autolisp-test-with "(VL-STRING-T^"
    (should (member "VL-STRING-TRIM" (autolisp-test-complete))))
  (autolisp-test-with "; (vl-str^"
    (should-not (autolisp-test-complete))))

(ert-deftest autolisp-complete-strings ()
  (autolisp-test-with "(getvar \"DIMSC^\")"
    (should (member "DIMSCALE" (autolisp-test-complete))))
  (autolisp-test-with "(setvar \"dimsc^\" 1)"
    (should (member "dimscale" (autolisp-test-complete))))
  (autolisp-test-with "(command \"_.dimlin^\")"
    (should (member "dimlinear" (autolisp-test-complete))))
  (autolisp-test-with "(princ \"dimsc^\")"
    (should-not (autolisp-test-complete))
    (let ((autolisp-complete-commands-in t))
      (should (autolisp-test-complete)))))

(defun autolisp-test-eldoc ()
  (let (out) (autolisp-eldoc-function (lambda (s &rest _) (setq out s))) out))

(ert-deftest autolisp-eldoc ()
  (autolisp-test-with "(entget ^)"
    (let ((s (autolisp-test-eldoc)))
      (should (string-match-p "entget" s))
      (should (eq (get-text-property (string-search "ename<" s) 'face s)
                  'eldoc-highlight-function-argument))))
  (autolisp-test-with "(defun f (aa bb / cc) 1)\n(f 1 ^2)"
    (let ((s (autolisp-test-eldoc)))
      (should (equal (substring-no-properties s) "(f aa bb)"))
      (should (eq (get-text-property (string-search "bb" s) 'face s)
                  'eldoc-highlight-function-argument)))))

;;;; Symbols

(ert-deftest autolisp-numbers-are-not-symbols ()
  (dolist (n '("1" "-1" "1.5" "1." ".5" "1e5" "1.5e-3" "+2"))
    (should-not (autolisp--user-symbol-p n)))
  (dolist (s '("1a" "a1" "foo" "*x*" "c:cmd"))
    (should (autolisp--user-symbol-p s))))

(ert-deftest autolisp-scopes ()
  (autolisp-test-with "(setq x 1)
(defun f (x / y) (setq y x) (foreach x y (g x)) (mapcar '(lambda (x) x) y))
(princ x)"
    (let* ((a (autolisp-analyze-buffer))
           (xs (gethash "x" (autolisp-analysis-table a)))
           (scopes (mapcar #'autolisp-ref-scope xs)))
      (should (= 8 (length xs)))
      ;; Global, the argument, the foreach variable and the lambda's.
      (should (= 4 (length (cl-remove-duplicates scopes :test #'eq))))
      (should (null (car scopes)))
      (should (null (car (last scopes))))
      (should (equal (autolisp-ref-args (car (gethash "f" (autolisp-analysis-table a))))
                     '("x"))))))

(ert-deftest autolisp-reader-tolerates-broken-code ()
  (dolist (text '("(defun f (a" ")))(foo)" "\"unclosed" ";| open" "(defun)" "(setq)"
                  "'" "(lambda)" "(foreach)" "(defun f nil 1)" "(a . b)" "\"a\\"))
    (autolisp-test-with text (should (autolisp-analyze-buffer)))))

(ert-deftest autolisp-global-flags ()
  (with-temp-buffer
    (insert-file-contents (autolisp-test-fixture "standards.lsp"))
    (autolisp-mode)
    (let ((globals (delete-dups
                    (mapcar #'autolisp-ref-name
                            (seq-filter #'autolisp-ref-global
                                        (autolisp-analysis-refs
                                         (autolisp-analyze-buffer)))))))
      (should (equal (sort globals #'string<)
                     '("globalsareloaded" "iscompliant" "loadglobalvariables"
                       "settextstyle" "sfc:style1" "sfc:style2" "sfc:style3"
                       "sfc:style4" "testresult"))))))

(ert-deftest autolisp-defun-docs ()
  (autolisp-test-with "(a) ; trailing\n(defun f () 1)\n; one\n; two  \n(defun g () 1)\n; far\n\n\n\n(defun h () 1)\n;|\n block\n|;\n\n(defun k () 1)"
    (cl-flet ((doc (n) (autolisp-ref-doc
                        (car (gethash n (autolisp-analysis-table
                                         (autolisp-analyze-buffer)))))))
      (should-not (doc "f"))
      (should (equal (doc "g") "; one\n; two"))
      (should-not (doc "h"))
      (should (string-match-p "block" (doc "k")))
      (should (equal (autolisp--clean-doc (doc "g")) "one\ntwo"))
      (should (equal (autolisp--clean-doc (doc "k")) "block")))))

(ert-deftest autolisp-definition-across-files ()
  (autolisp-test-with-copies
    (with-current-buffer (find-file-noselect (concat dir "paperspace utilities.lsp"))
      (autolisp-test-goto "settextstyle")
      (let ((defs (xref-backend-definitions
                   'autolisp (xref-backend-identifier-at-point 'autolisp))))
        (should (= 1 (length defs)))
        (should (string-suffix-p "standards.lsp"
                                 (xref-location-group (xref-item-location (car defs))))))
      (autolisp-test-goto "sfc:style2")
      (let ((defs (xref-backend-definitions
                   'autolisp (xref-backend-identifier-at-point 'autolisp))))
        (should (= 1 (length defs)))
        (should (string-match-p "setq\\|sfc:style2" (xref-item-summary (car defs))))))))

(ert-deftest autolisp-references-across-files ()
  (autolisp-test-with-copies
    (with-current-buffer (find-file-noselect (concat dir "standards.lsp"))
      (autolisp-test-goto "sfc:style1 \"SFC")
      (let ((files (mapcar (lambda (x) (file-name-nondirectory
                                        (xref-location-group (xref-item-location x))))
                           (xref-backend-references
                            'autolisp (xref-backend-identifier-at-point 'autolisp)))))
        ;; The localized uses inside SetTextStyle are a different symbol.
        (should (= 1 (cl-count "standards.lsp" files :test #'equal)))
        (should (member "paperspace utilities.lsp" files))))))

(ert-deftest autolisp-local-definition ()
  (autolisp-test-with "(setq v 0)\n(defun f (v)\n  (g ^v))"
    (let ((defs (autolisp-definitions-at-point)))
      (should (= 1 (length defs)))
      (should (eq 'local (autolisp-ref-kind (cdar defs)))))))

;;;; Rename

(ert-deftest autolisp-rename-local ()
  (autolisp-test-with "(setq v 0)
;|
  doc
  @Param v the value
|;
(defun f (v / w) (setq w V) (g ^v \"v\"))
(princ v)"
    (autolisp-rename-symbol "val")
    (should (equal (buffer-string) "(setq v 0)
;|
  doc
  @Param val the value
|;
(defun f (val / w) (setq w val) (g val \"v\"))
(princ v)"))))

(ert-deftest autolisp-rename-global-across-files ()
  (autolisp-test-with-copies
    (with-current-buffer (find-file-noselect (concat dir "standards.lsp"))
      (autolisp-test-goto "SetTextStyle")
      (autolisp-rename-symbol "ApplyTextStyle"))
    (dolist (f '("standards.lsp" "modelspace utilities.lsp" "paperspace utilities.lsp"))
      (with-current-buffer (find-file-noselect (concat dir f))
        (goto-char (point-min))
        (should (search-forward "ApplyTextStyle" nil t))
        (let ((case-fold-search t))
          (goto-char (point-min))
          (should-not (search-forward "settextstyle" nil t)))
        (should (buffer-modified-p))))))

(ert-deftest autolisp-rename-asks-when-not-global ()
  (autolisp-test-with-copies
    (with-current-buffer (find-file-noselect (concat dir "standards.lsp"))
      (autolisp-test-goto "SetDimStyle")
      (let (asked)
        (cl-letf (((symbol-function 'y-or-n-p) (lambda (p) (setq asked p) nil)))
          (autolisp-rename-symbol "ApplyDim"))
        (should (string-match-p "not @Global" asked)))
      (should-not (with-current-buffer
                      (find-file-noselect (concat dir "modelspace utilities.lsp"))
                    (buffer-modified-p))))))

(ert-deftest autolisp-rename-refuses-bad-names ()
  (autolisp-test-with "(setq ^foo 1 bar 2)"
    (dolist (n '("" "a b" "entget" "1" "x)" "nil"))
      (should-error (autolisp-rename-symbol n) :type 'user-error))
    (cl-letf (((symbol-function 'y-or-n-p) #'ignore))
      (should-error (autolisp-rename-symbol "bar") :type 'user-error))
    (should (equal (buffer-string) "(setq foo 1 bar 2)"))))

;;;; Editing commands

(ert-deftest autolisp-doc-comment ()
  (autolisp-test-with "(defun f (a b / c)\n  (g^ a)\n)\n"
    (autolisp-insert-doc-comment)
    (should (equal (buffer-string)
                   ";|\n  description\n  @Param a ?\n  @Param b ?\n  @Returns ?\n|;\n(defun f (a b / c)\n  (g a)\n)\n"))))

(ert-deftest autolisp-regions ()
  (autolisp-test-with "(a)\n(b)\n(c)\n"
    (autolisp-insert-region 5 9 "mid")
    (should (equal (buffer-string) "(a)\n;#region mid\n(b)\n;#endregion\n(c)\n"))
    (autolisp-test-goto "(b)")
    (should (equal (autolisp--region-bounds) '(17 . 33)))
    (autolisp-toggle-region)
    (should (invisible-p 19))
    (autolisp-toggle-region)
    (should-not (invisible-p 19))))

(ert-deftest autolisp-imenu ()
  (autolisp-test-with "(defun c:go () 1)\n(defun helper (x) x)\n;#region Stuff\n"
    (let ((index (funcall imenu-create-index-function)))
      (should (assoc "helper" index))
      (should (assoc "c:go" (cdr (assoc "Commands" index))))
      (should (assoc "Stuff" (cdr (assoc "Regions" index)))))))

(ert-deftest autolisp-mode-selection ()
  (dolist (f '("a.lsp" "A.LSP" "acad.mnl"))
    (should (eq 'autolisp-mode (assoc-default f auto-mode-alist #'string-match))))
  (should (eq 'autolisp-dcl-mode (assoc-default "x.dcl" auto-mode-alist #'string-match))))

;;;; DCL

(defmacro autolisp-test-dcl (text &rest body)
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,text)
     (autolisp-dcl-mode)
     (goto-char (point-min))
     (when (search-forward "^" nil t) (delete-char -1))
     ,@body))

(defun autolisp-test-dcl-complete ()
  (pcase (autolisp-dcl-completion-at-point)
    (`(,beg ,_ ,table . ,_)
     (all-completions (buffer-substring-no-properties beg (point)) table))))

(ert-deftest autolisp-dcl-completion ()
  (autolisp-test-dcl "d : dialog {\n  : but^"
    (should (member "button" (autolisp-test-dcl-complete)))
    (should-not (member "label" (autolisp-test-dcl-complete))))
  (autolisp-test-dcl "d : dialog {\n  : button { lab^ } }"
    (should (member "label" (autolisp-test-dcl-complete))))
  (autolisp-test-dcl "d : dialog {\n  : button { mult^ } }"
    (should-not (member "multiple_select" (autolisp-test-dcl-complete))))
  (autolisp-test-dcl "d : dialog { : button { is_default = t^ } }"
    (should (equal '("true") (autolisp-test-dcl-complete))))
  (autolisp-test-dcl "d : dialog { : button { key = \"lab^\"; } }"
    (should-not (autolisp-test-dcl-complete))))

(ert-deftest autolisp-dcl-indent-and-comments ()
  (let ((text "d : dialog {\n  // note }\n  label = \"}\";\n  : row {\n    : button {\n      key = \"a\";\n    }\n  }\n  ok_cancel;\n}\n"))
    (autolisp-test-dcl (replace-regexp-in-string "^[ ]+" "" text)
      (let ((inhibit-message t)) (indent-region (point-min) (point-max)))
      (should (equal (buffer-string) text)))))

;;;; Projects

(ert-deftest autolisp-projects ()
  (autolisp-test-with-copies
    (let ((autolisp-project-file nil) (inhibit-message t))
      (autolisp-create-project (concat dir "demo"))
      (should (string-suffix-p "demo.prj" autolisp-project-file))
      (should-not (autolisp-project-files))
      (autolisp-add-to-project (concat dir "standards.lsp"))
      (autolisp-add-to-project (concat dir "paperspace utilities.lsp"))
      (should (equal (mapcar #'file-name-nondirectory (autolisp-project-files))
                     '("standards.lsp" "paperspace utilities.lsp")))
      (should-error (autolisp-add-to-project (concat dir "standards.lsp")) :type 'user-error)
      (should-error (autolisp-add-to-project (concat dir "dialog.dcl")) :type 'user-error)
      (autolisp-remove-from-project "standards")
      (should (= 1 (length (autolisp-project-files))))
      (with-temp-buffer
        (insert-file-contents autolisp-project-file)
        (should (search-forward ":BUILD (:standard)" nil t)))
      (should-error (autolisp-create-project (concat dir "has space")) :type 'user-error))))

(ert-deftest autolisp-project-legacy-entries ()
  (autolisp-test-with-copies
    (let ((prj (concat dir "old.prj")))
      (with-temp-file prj
        (insert ";;; VLisp project file [V2.0] old saved to:[c:/x] at:[1/1/99]\n"
                "(VLISP-PROJECT-LIST :NAME old :OWN-LIST (\"standards\" \"sub\\\\other.lsp\" \"c:/abs/file\") :X (1 2))\n;;; EOF"))
      (should (equal (autolisp-project-files prj)
                     (list (concat dir "standards.lsp") (concat dir "sub/other.lsp")
                           "c:/abs/file.lsp"))))
    (let ((bad (concat dir "bad.prj")))
      (with-temp-file bad (insert "(foo)"))
      (should-error (autolisp-project-files bad) :type 'user-error))))

;;;; Debugging

(ert-deftest autolisp-dape-launch-config ()
  (let* ((dir (file-name-as-directory (make-temp-file "acad" t)))
         (autolisp-autocad-program (concat dir "acad.exe")))
    (unwind-protect
        (progn
          (with-temp-file autolisp-autocad-program)
          (should-error (autolisp-dape--launch-config nil) :type 'user-error)
          (with-temp-file (concat dir "AutoLispDebugAdapter.exe"))
          (let* ((autolisp-launch-parameters "/product C3D")
                 (c (autolisp-dape--launch-config (list :type "launchlisp"))))
            (should (string-suffix-p "AutoLispDebugAdapter.exe" (plist-get c 'command)))
            (should (equal (car (plist-get c 'command-args)) "--"))
            (should (equal (nth 2 (plist-get c 'command-args)) "/product C3D"))))
      (delete-directory dir t))))

(defun autolisp-test-wait (pred)
  "Wait up to ten seconds for PRED."
  (let ((end (+ (float-time) 10)) ok)
    (while (and (not (setq ok (funcall pred))) (< (float-time) end))
      (accept-process-output nil 0.05))
    ok))

(ert-deftest autolisp-dape-session ()
  "Attach, load a file, see its error and evaluate, through dape."
  (skip-unless (require 'dape nil t))
  (skip-unless (executable-find "python"))
  (autolisp-test-with-copies
    (let* ((log (concat dir "log.json"))
           (file (concat dir "err.lsp"))
           (dape-start-hook (remq 'dape-info dape-start-hook))
           (inhibit-message t)
           (requests (lambda ()
                       (when (file-exists-p log)
                         (with-temp-buffer
                           (insert-file-contents log)
                           (mapcar (lambda (l) (json-parse-string l :object-type 'plist))
                                   (split-string (buffer-string) "\n" t))))))
           (sent (lambda (name)
                   (seq-find (lambda (r) (equal (plist-get r :command) name))
                             (funcall requests)))))
      (with-temp-file file (insert "(setq a 1)\n  (car a)\n"))
      (with-current-buffer (find-file-noselect file)
        (cl-letf (((symbol-function 'autolisp-dape--choose-process)
                   (lambda () (list 4242 "c:/fake/acad.exe" "Drawing1.dwg")))
                  ((symbol-function 'autolisp-dape--adapter)
                   (lambda (_) (executable-find "python"))))
          (let ((dape-configs (copy-tree dape-configs)))
            (plist-put (alist-get 'autolisp-attach dape-configs)
                       'command-args
                       (list (expand-file-name "fake-adapter.py" autolisp-test-dir) log))
            (goto-char (point-min))
            (forward-line 1)
            (dape-breakpoint-toggle)
            (autolisp-debug-attach)))
        (should (autolisp-test-wait (lambda () (funcall sent "configurationDone"))))
        (should (autolisp-test-wait (lambda () (funcall sent "attach"))))
        (let ((args (plist-get (funcall sent "attach") :arguments)))
          (should (equal (plist-get args :type) "attachlisp"))
          (should (equal (plist-get args :processId) "4242"))
          (should (file-equal-p (plist-get args :program) file)))
        (should (equal "attachlisp"
                       (plist-get (plist-get (funcall sent "initialize") :arguments)
                                  :adapterID)))
        (let ((args (plist-get (funcall sent "setBreakpoints") :arguments)))
          (should (equal 2 (plist-get (aref (plist-get args :breakpoints) 0) :line)))
          (when (eq system-type 'windows-nt)
            (should (equal (plist-get (plist-get args :source) :path)
                           (string-replace "/" "\\" file)))))
        (autolisp-load-file)
        (should (autolisp-test-wait (lambda () autolisp-dape--error-overlays)))
        ;; As in AutoLispExt, the argument is the bare path.
        (should (file-equal-p (plist-get (funcall sent "customLoad") :arguments) file))
        (let ((ov (car autolisp-dape--error-overlays)))
          (should (equal "(car " (buffer-substring (overlay-start ov) (overlay-end ov))))
          (goto-char (overlay-start ov))
          (should (equal "bad argument type" (autolisp-test-eldoc))))
        ;; The user's frame is current, not AutoCAD's pseudo-frame.
        (should (autolisp-test-wait
                 (lambda ()
                   (eql 147 (plist-get (dape--current-stack-frame
                                        (dape--live-connection 'parent t))
                                       :id)))))
        (autolisp-eval-region (point-min) (line-end-position 0))
        (should (autolisp-test-wait (lambda () (funcall sent "evaluate"))))
        (should (equal "(setq a 1)"
                       (plist-get (plist-get (funcall sent "evaluate") :arguments)
                                  :expression)))
        (should (eql 147 (plist-get (plist-get (funcall sent "evaluate") :arguments)
                                    :frameId)))
        (dape-breakpoint-remove-all)
        ;; Reloading waits until AutoCAD runs, then reattaches to it.
        (should-error (autolisp-reload-file) :type 'user-error)
        (dape-continue (dape--live-connection 'parent))
        (should (autolisp-test-wait
                 (lambda () (null (dape--stopped-threads
                                   (dape--live-connection 'parent))))))
        (cl-letf (((symbol-function 'autolisp-dape--process-details)
                   (lambda (_) (list (list 4242 "c:/fake/acad.exe" ""))))
                  ((symbol-function 'autolisp-dape--adapter)
                   (lambda (_) (executable-find "python"))))
          (let ((dape-configs (copy-tree dape-configs)))
            (plist-put (alist-get 'autolisp-attach dape-configs)
                       'command-args
                       (list (expand-file-name "fake-adapter.py" autolisp-test-dir) log))
            (autolisp-reload-file)
            (should (autolisp-test-wait
                     (lambda ()
                       (= 2 (seq-count (lambda (r) (equal (plist-get r :command) "configurationDone"))
                                       (funcall requests))))))))
        (let ((attaches (seq-filter (lambda (r) (equal (plist-get r :command) "attach"))
                                    (funcall requests))))
          (should (equal '("4242" "4242")
                         (mapcar (lambda (r) (plist-get (plist-get r :arguments) :processId))
                                 attaches))))
        (dape-quit)
        (should (autolisp-test-wait (lambda () (funcall sent "disconnect"))))
        ;; Quitting must not ask for AutoCAD to be terminated.
        (should-not (plist-get (plist-get (funcall sent "disconnect") :arguments)
                               :terminateDebuggee))
        (should-not (funcall sent "terminate"))
        (should (autolisp-test-wait (lambda () (null (dape--live-connections)))))))))

(ert-deftest autolisp-load-needs-session ()
  (skip-unless (require 'dape nil t))
  (autolisp-test-with-copies
    (with-current-buffer (find-file-noselect (concat dir "standards.lsp"))
      (should-error (autolisp-load-file) :type 'user-error))))

(provide 'autolisp-test)
;;; autolisp-test.el ends here
