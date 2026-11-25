;;; autolisp-complete.el --- Completion for AutoLISP -*- lexical-binding: t -*-

;; SPDX-License-Identifier: Apache-2.0

;;; Commentary:

;; Completion that knows where point is: operators after a paren, variables
;; first among arguments, and the values an argument accepts.  Matches are
;; ranked by how well they match, then by scope, then by how often AutoLISP
;; code uses them (data/usage.txt).

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(eval-and-compile
  (add-to-list
   'load-path
   (file-name-directory
    (or load-file-name
        (and (boundp 'byte-compile-current-file)
             byte-compile-current-file)
        buffer-file-name))))

(require 'autolisp-data)
(require 'autolisp-symbols)

(declare-function autolisp--operands "autolisp-mode")
(declare-function autolisp--in-arg-list-p "autolisp-mode")
(declare-function autolisp--short-signature "autolisp-mode")
(declare-function autolisp--doc-buffer "autolisp-mode")

(defcustom autolisp-complete-commands-in
  '("command" "command-s" "vl-cmdf" "getcname" "vla-sendcommand"
    "vla-postcommand")
  "Functions whose string arguments complete command names.
If t, complete commands and variables in every string, as AutoLispExt does."
  :type '(choice (const :tag "Every string" t) (repeat string))
  :group 'autolisp)

;; Prefix matches are ranked first by `autolisp-complete--sort', so a style
;; that also finds the middle of a word costs nothing.
(add-to-list 'completion-category-defaults
             '(autolisp (styles substring partial-completion flex)))

;;;; Usage counts

(defun autolisp-complete--usage (section)
  "Return the usage counts of SECTION as a hash table."
  (gethash section
           (autolisp-data--once 'usage
             (let ((all (make-hash-table :test #'equal)) table)
               (dolist (line (autolisp-data--lines "usage.txt") all)
                 (if (string-match "\\`\\[\\(.+\\)\\]\\'" line)
                     (setq table (puthash (match-string 1 line)
                                          (make-hash-table :test #'equal) all))
                   (pcase-let ((`(,name ,n) (split-string line " ")))
                     (puthash name (string-to-number n) table))))))))

(defun autolisp-complete--count (section name)
  "Return how often NAME of SECTION is used."
  (gethash name (autolisp-complete--usage section) 0))

;;;; Candidates
;;
;; A candidate is a string with the text properties `autolisp-score', higher
;; being better, and `autolisp-note', its annotation.

(defun autolisp-complete--make (text score note &optional kind)
  "Return candidate TEXT with SCORE, annotation NOTE and KIND."
  (propertize text 'autolisp-score score 'autolisp-note note
              'autolisp-kind kind))

(defun autolisp-complete--get (candidate property)
  "Return PROPERTY of CANDIDATE, which may have been faced since."
  (and (> (length candidate) 0) (get-text-property 0 property candidate)))

(defun autolisp-complete--spread (candidate input)
  "Return how far apart the characters of INPUT are in CANDIDATE."
  (let ((from 0) first at)
    (catch 'none
      (mapc (lambda (c)
              (setq at (or (cl-position c candidate :start from)
                           (throw 'none 1000)))
              (unless first (setq first at))
              (setq from (1+ at)))
            input)
      (+ first (- from first (length input))))))

(defun autolisp-complete--match-rank (candidate input)
  "Return how well CANDIDATE matches INPUT; 0 is best."
  (let* ((c (downcase candidate))
         (at (and (not (string-empty-p input)) (string-search input c))))
    (cond ((string-empty-p input) 0)
          ((equal c input) 0)
          ((eql at 0) 1)
          ((null at) (+ 4 (autolisp-complete--spread c input)))
          ((memq (aref c (1- at)) '(?- ?_ ?: ?*)) 2)
          (t 3))))

(defun autolisp-complete--sort (candidates input)
  "Sort CANDIDATES for INPUT."
  (let ((input (downcase input)))
    (mapcar
     #'cdr
     (sort (mapcar (lambda (c)
                     (cons (list (autolisp-complete--match-rank c input)
                                 (or (autolisp-complete--get c 'autolisp-score) 0))
                           c))
                   candidates)
           (lambda (a b)
             (let ((ra (caar a)) (rb (caar b))
                   (sa (cadar a)) (sb (cadar b))
                   (ca (cdr a)) (cb (cdr b)))
               (cond ((/= ra rb) (< ra rb))
                     ((/= sa sb) (> sa sb))
                     ((/= (length ca) (length cb)) (< (length ca) (length cb)))
                     (t (string< ca cb)))))))))

(defun autolisp-complete-table (candidates beg)
  "Return a completion table of CANDIDATES for input that starts at BEG.
CANDIDATES may be a function, which is called when they are first needed."
  (let* ((start (copy-marker beg))
         (here (current-buffer))
         (list (if (functionp candidates) 'unknown candidates))
         (sort (lambda (cands)
                 (autolisp-complete--sort
                  cands
                  (if-let* ((buffer (marker-buffer start)))
                      (with-current-buffer buffer
                        (if (<= start (point))
                            (buffer-substring-no-properties start (point))
                          ""))
                    "")))))
    (lambda (string pred action)
      (if (eq action 'metadata)
          `(metadata (category . autolisp)
                     (display-sort-function . ,sort)
                     (cycle-sort-function . ,sort))
        (when (eq list 'unknown)
          (setq list (if (buffer-live-p here)
                         (with-current-buffer here (funcall candidates)))))
        (let ((completion-ignore-case t))
          (complete-with-action action list string pred))))))

(defun autolisp-complete--annotation (candidate)
  "Return the annotation of CANDIDATE."
  (if-let* ((note (autolisp-complete--get candidate 'autolisp-note)))
      (concat "  " note)
    ""))

(defun autolisp-complete--result (beg end candidates)
  "Return completion data for CANDIDATES between BEG and END.
CANDIDATES is a list, or a function that returns one."
  (when candidates
    (list beg end
          (autolisp-complete-table
           (if (functionp candidates)
               (lambda () (autolisp-complete--unique (funcall candidates)))
             (autolisp-complete--unique candidates))
           beg)
          :annotation-function #'autolisp-complete--annotation
          :company-kind (lambda (c) (autolisp-complete--get c 'autolisp-kind))
          :company-docsig #'autolisp--short-signature
          :company-doc-buffer #'autolisp--doc-buffer)))

(defun autolisp-complete--unique (candidates)
  "Return CANDIDATES without repeats, ignoring case and keeping the first."
  (let ((seen (make-hash-table :test #'equal :size 4096)) out)
    (dolist (c candidates (nreverse out))
      (let ((key (downcase c)))
        (unless (gethash key seen)
          (puthash key t seen)
          (push c out))))))

;;;; Built-in functions

(defun autolisp-complete--arguments (signature)
  "Return the arguments in SIGNATURE, without their types."
  (if (string-match "\\`([^ )]+ *\\(.*\\))\\'" signature)
      (replace-regexp-in-string "<[^>]*>" "" (match-string 1 signature))
    ""))

(defun autolisp-complete--family-score (name)
  "Return a score for an unused NAME, by the kind of function it is."
  (cond ((string-prefix-p "vla-" name) 0)
        ((string-prefix-p "acet-" name) 0)
        ((string-prefix-p "vlax-" name) 2)
        ((string-prefix-p "vl-" name) 3)
        ((autolisp-data-function-help name) 2)
        (t 1)))

(defun autolisp-complete--builtins ()
  "Return candidates for the built-in functions, in lower case."
  (autolisp-data--once 'builtin-candidates
    (mapcar (lambda (name)
              (let ((help (car (autolisp-data-function-help name))))
                (autolisp-complete--make
                 name
                 (+ (* 10 (autolisp-complete--count "functions" name))
                    (autolisp-complete--family-score name))
                 (and help
                      (autolisp-complete--arguments
                       (autolisp-data-signature help)))
                 'function)))
            (autolisp-data-functions))))

(defun autolisp-complete--case (candidates prefix)
  "Return CANDIDATES in upper case if PREFIX is typed that way."
  (if (and (not (equal prefix (downcase prefix)))
           (equal prefix (upcase prefix)))
      (mapcar (lambda (c)
                (apply #'propertize (upcase (substring-no-properties c))
                       (text-properties-at 0 c)))
              candidates)
    candidates))

;;;; User symbols

(defconst autolisp-complete--local-score 10000000)
(defconst autolisp-complete--buffer-score 5000000)
(defconst autolisp-complete--project-score 2000000)

(defun autolisp-complete--raise (candidate bonus)
  "Return CANDIDATE with BONUS added to its score."
  (propertize candidate 'autolisp-score
              (+ bonus (or (autolisp-complete--get candidate 'autolisp-score) 0))))

(defun autolisp-complete--visible-locals (analysis pos)
  "Return the names of ANALYSIS that are localized around POS."
  (let (scopes)
    (dolist (r (autolisp-analysis-refs analysis))
      (when-let* ((s (autolisp-ref-scope r)))
        (when (and (not (memq s scopes))
                   (<= (autolisp-scope-beg s) pos) (<= pos (autolisp-scope-end s)))
          (push s scopes))))
    (delete-dups (mapcan (lambda (s) (copy-sequence (autolisp-scope-names s)))
                         scopes))))

(defun autolisp-complete--user (pos &optional place)
  "Return candidates for the user's symbols, except one only at POS.
PLACE is `operator' if only a function makes sense, `quoted' if anything
does, and otherwise variables come first."
  (let* ((analysis (autolisp-buffer-analysis))
         (locals (autolisp-complete--visible-locals analysis pos))
         (functions (make-hash-table :test #'equal))
         out)
    (autolisp--do-analyses (_file a)
      (dolist (r (autolisp-analysis-refs a))
        (when (and (eq (autolisp-ref-kind r) 'defun)
                   (/= (autolisp-ref-beg r) pos)
                   (not (gethash (autolisp-ref-name r) functions)))
          (puthash (autolisp-ref-name r) r functions))))
    (maphash
     (lambda (name refs)
       (let* ((others (seq-remove (lambda (r) (= (autolisp-ref-beg r) pos)) refs))
              (function (gethash name functions))
              (local (member name locals))
              ;; A local of some other function is of little use here.
              (reachable (seq-some (lambda (r) (null (autolisp-ref-scope r))) others))
              (spelled (or (seq-find #'autolisp-ref-kind others) (car others))))
         (when (and others (or function (not (eq place 'operator))))
           (push (autolisp-complete--make
                  (autolisp-ref-text spelled)
                  (+ (length others)
                     (cond ((and function place) autolisp-complete--buffer-score)
                           (function 0)
                           (local autolisp-complete--local-score)
                           (reachable autolisp-complete--buffer-score)
                           (t 0)))
                  (cond (function (string-join (autolisp-ref-args function) " "))
                        (local "local")
                        (reachable "variable")
                        (t "elsewhere"))
                  (if function 'function 'variable))
                 out))))
     (autolisp-analysis-table analysis))
    (maphash
     (lambda (_name ref)
       (push (autolisp-complete--make
              (autolisp-ref-text ref)
              (if place autolisp-complete--project-score 0)
              (string-join (autolisp-ref-args ref) " ")
              'function)
             out))
     functions)
    ;; Both loops pushed, so put the buffer's own entries first.
    (nreverse out)))

;;;; Arguments

(defun autolisp-complete--call (pos)
  "Return (NAME INDEX) for the argument that starts at POS, or nil."
  (save-excursion
    (goto-char pos)
    (when-let* ((open (nth 1 (syntax-ppss))))
      (let* ((items (autolisp--operands open))
             (op (car items)))
        (when (and (cdr op) (< (car op) pos))
          (list (downcase (cdr op)) (length (cdr items))))))))

(defun autolisp-complete--enums (name index)
  "Return the documented values of argument INDEX of function NAME."
  (seq-uniq
   (mapcan (lambda (entry)
             (when-let* ((arg (nth index (gethash "arguments" entry))))
               (copy-sequence (gethash "enums" arg))))
           (autolisp-data-function-help name))))

(defconst autolisp-complete--tables
  '("LAYER" "BLOCK" "STYLE" "LTYPE" "DIMSTYLE" "VIEW" "UCS" "VPORT" "APPID"))

(defun autolisp-complete--member-names (prefix)
  "Return the ActiveX member names of the functions starting with PREFIX."
  (autolisp-data--once (intern (concat "members-" prefix))
    (let (out)
      (maphash (lambda (key entry)
                 (when (string-prefix-p prefix key)
                   (push (substring (gethash "id" entry) (length prefix)) out)))
               (autolisp-data--section "functions"))
      (delete-dups out))))

(defun autolisp-complete--methods ()
  "Return the ActiveX method names."
  (autolisp-data--once 'methods
    (let (out)
      (maphash (lambda (_k object)
                 (dolist (m (gethash "methods" object))
                   (push (string-remove-prefix "vla-" m) out)))
               (autolisp-data--section "objects"))
      (delete-dups out))))

(defun autolisp-complete--dcl-matches (regexp)
  "Return what group 1 of REGEXP matches in the related DCL files."
  (let (out)
    (dolist (file (autolisp--nearby-files "\\.dcl\\'") (nreverse (delete-dups out)))
      (with-temp-buffer
        (if-let* ((buffer (get-file-buffer file)))
            (insert-buffer-substring buffer)
          (ignore-error file-error (insert-file-contents file)))
        (goto-char (point-min))
        (while (re-search-forward regexp nil t)
          (push (match-string-no-properties 1) out))))))

(defun autolisp-complete--unordered (names note kind)
  "Return candidates for NAMES, with annotation NOTE and KIND."
  (mapcar (lambda (n) (autolisp-complete--make n 0 note kind)) names))

(defun autolisp-complete--simple (names note &optional kind)
  "Return candidates for NAMES, in order, with annotation NOTE and KIND."
  (let ((score (length names)))
    (mapcar (lambda (n) (prog1 (autolisp-complete--make n score note kind)
                          (setq score (1- score))))
            names)))

(defun autolisp-complete--names (section note other other-note)
  "Return command and variable candidates, those used as SECTION first.
Annotate them with NOTE; those only used as OTHER come last, with OTHER-NOTE."
  (mapcar (lambda (name)
            (let ((n (autolisp-complete--count section name)))
              (cond ((> n 0) (autolisp-complete--make name (+ 10 n) note 'constant))
                    ((> (autolisp-complete--count other name) 0)
                     (autolisp-complete--make name 0 other-note 'constant))
                    (t (autolisp-complete--make name 5 "command/variable" 'constant)))))
          (autolisp-data-commands)))

(defun autolisp-complete--values (name index)
  "Return candidates for argument INDEX of NAME given as a string or symbol."
  (let ((first (eql index 0)) (second (eql index 1)))
    (cond
     ((and first (member name '("getvar" "setvar")))
      (autolisp-complete--names "variables" "variable" "commands" "command"))
     ((and second (member name '("vla-getvariable" "vla-setvariable")))
      (autolisp-complete--names "variables" "variable" "commands" "command"))
     ((and first (member name '("tblsearch" "tblnext" "tblobjname")))
      (autolisp-complete--simple autolisp-complete--tables "table" 'constant))
     ((and second (member name '("vlax-get-property" "vlax-get" "vlax-property-available-p")))
      (autolisp-complete--unordered (autolisp-complete--member-names "vla-get-")
                                    "property" 'property))
     ((and second (member name '("vlax-put-property" "vlax-put")))
      (autolisp-complete--unordered (autolisp-complete--member-names "vla-put-")
                                    "property" 'property))
     ((and second (member name '("vlax-invoke-method" "vlax-invoke"
                                 "vlax-method-applicable-p")))
      (autolisp-complete--unordered (autolisp-complete--methods) "method" 'method))
     ((and first (member name '("action_tile" "get_tile" "set_tile" "mode_tile"
                                "start_list" "start_image" "get_attr"
                                "client_data_tile" "dimx_tile" "dimy_tile")))
      (autolisp-complete--simple
       (autolisp-complete--dcl-matches "\\_<key\\s-*=\\s-*\"\\([^\"]+\\)\"")
       "tile" 'property))
     ((and first (equal name "new_dialog"))
      (autolisp-complete--simple
       (autolisp-complete--dcl-matches
        "^\\s-*\\([A-Za-z_][A-Za-z_0-9]*\\)\\s-*:\\s-*dialog\\_>")
       "dialog" 'class))
     ((and first (equal name "load_dialog"))
      (autolisp-complete--simple
       (mapcar #'file-name-nondirectory (autolisp--nearby-files "\\.dcl\\'"))
       "file" 'file))
     ((and first (member name '("load" "autoload")))
      (autolisp-complete--simple
       (mapcar #'file-name-nondirectory (autolisp-related-files)) "file" 'file))
     (t
      (autolisp-complete--simple
       (seq-filter (lambda (e) (string-match-p "\\`[A-Za-z][A-Za-z0-9_]*\\'" e))
                   (autolisp-complete--enums name (or index -1)))
       "value" 'enum-member)))))

;;;; In strings

(defun autolisp-complete--string (start)
  "Complete in the string that starts at START."
  (pcase-let ((`(,name ,index) (or (autolisp-complete--call start) '("" nil))))
    (let ((command (or (eq autolisp-complete-commands-in t)
                       (member name autolisp-complete-commands-in)))
          (end (point)))
      (if (not command)
          (let ((beg (1+ start)))
            (autolisp-complete--result
             beg (save-excursion (skip-chars-forward "^\"\n") (point))
             (autolisp-complete--values name index)))
        ;; _ asks for the English name and . for the original command.
        (let ((beg (save-excursion
                     (skip-chars-backward "A-Za-z0-9-" (1+ start)) (point))))
          (when (and (save-excursion
                       (goto-char beg)
                       (skip-chars-backward "._'" (1+ start))
                       (or (= (point) (1+ start)) (memq (char-before) '(?\s ?\n))))
                     ;; The first string names the command; the later ones may
                     ;; be anything, so wait to be asked.
                     (or (eql index 0) (< beg end)))
            (autolisp-complete--result
             beg (save-excursion (skip-chars-forward "A-Za-z0-9-") (point))
             (let ((prefix (buffer-substring-no-properties beg end))
                   (names (autolisp-complete--names "commands" "command"
                                                    "variables" "variable")))
               (if (equal prefix (upcase prefix))
                   names
                 (mapcar (lambda (c)
                           (apply #'propertize (downcase (substring-no-properties c))
                                  (text-properties-at 0 c)))
                         names))))))))))

;;;; In code

(defun autolisp-complete--code ()
  "Complete the symbol at point."
  (let* ((end (point))
         (beg (save-excursion (skip-syntax-backward "w_") (point)))
         (prefix (buffer-substring-no-properties beg end))
         (before (char-before beg))
         (quoted (eq before ?\'))
         (open (save-excursion (nth 1 (syntax-ppss beg))))
         (operator (and open (not quoted)
                        (= beg (save-excursion
                                 (goto-char (1+ open))
                                 (skip-chars-forward " \t\n")
                                 (point)))))
         (header (and open (save-excursion (autolisp--in-arg-list-p open))))
         (call (and (not operator) (autolisp-complete--call
                                    (if quoted (1- beg) beg)))))
    (when (and (not (string-match-p "\\`[-+]?[0-9.]" prefix))
               (or (< beg end) operator quoted))
      (unless (and (member (car call) '("defun" "defun-q"))
                   ;; Only the name of a new function, and once begun.
                   (not header)
                   (or (not (eql (cadr call) 0)) (= beg end)))
        (autolisp-complete--result
         beg (save-excursion (skip-syntax-forward "w_") (point))
         (lambda ()
           (cond
            (header
             (seq-remove (lambda (c) (eq (autolisp-complete--get c 'autolisp-kind)
                                         'function))
                         (autolisp-complete--user beg)))
            ((member (car call) '("defun" "defun-q"))
             (autolisp-complete--user beg 'quoted))
            (t
             (append
              (and call (autolisp-complete--argument call quoted))
              (autolisp-complete--user beg (cond (operator 'operator)
                                                 (quoted 'quoted)))
              (autolisp-complete--case (autolisp-complete--builtins) prefix))))))))))

(defun autolisp-complete--argument (call quoted)
  "Return the values that the argument of CALL accepts, ranked first.
QUOTED is non-nil after a quote."
  (pcase-let ((`(,name ,index) call))
    (mapcar
     (lambda (c)
       (autolisp-complete--raise c (* 2 autolisp-complete--local-score)))
     (cond
      ((not quoted)
       (autolisp-complete--simple
        (seq-filter (lambda (e) (string-match-p "\\`:?[A-Za-z]" e))
                    (autolisp-complete--enums name index))
        "value" 'enum-member))
      ((string-prefix-p "vlax-" name)
       (autolisp-complete--values name index))
      ((member name '("getvar" "setvar"))
       (mapcar (lambda (c)
                 (apply #'propertize (downcase (substring-no-properties c))
                        (text-properties-at 0 c)))
               (autolisp-complete--values name index)))))))

(defun autolisp-completion-at-point ()
  "Complete the AutoLISP symbol, or the string, at point."
  (let ((state (syntax-ppss)))
    (cond ((nth 3 state) (autolisp-complete--string (nth 8 state)))
          ((nth 4 state) nil)
          (t (autolisp-complete--code)))))

(provide 'autolisp-complete)
;;; autolisp-complete.el ends here
