;;; autolisp-symbols.el --- AutoLISP symbol analysis, xref, rename -*- lexical-binding: t -*-

;; SPDX-License-Identifier: Apache-2.0

;;; Commentary:

;; A small reader that records every user symbol in a file with the form
;; that localizes it.  The scoping rules follow AutoLispExt: `defun',
;; `defun-q' and `lambda' localize their argument list (arguments and
;; locals alike); `foreach' and `vlax-for' localize their variable; an
;; @Global comment marks a definition as visible across files.
;;
;; The reader works on plain text rather than on syntax tables, so it can
;; analyze files that are not being visited.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'xref)
(require 'project)
(eval-and-compile
  (add-to-list
   'load-path
   (file-name-directory
    (or load-file-name
        (and (boundp 'byte-compile-current-file)
             byte-compile-current-file)
        buffer-file-name))))

(require 'autolisp-data)

(declare-function autolisp-project-files "autolisp-project")

(defcustom autolisp-search-project-root t
  "Whether cross-file commands search all .lsp/.mnl files in the project.
When nil, only open buffers and the active .prj file are searched."
  :type 'boolean
  :group 'autolisp)

(defcustom autolisp-search-file-limit 2000
  "Largest number of project files to analyze."
  :type 'integer
  :group 'autolisp)

;;;; Reader

(cl-defstruct (autolisp-node (:constructor autolisp-node--make))
  type                        ; atom, string or list
  name                        ; downcased symbol text, for atoms
  beg end
  quoted                      ; preceded by '
  children closed)

(cl-defstruct (autolisp-scope (:constructor autolisp-scope--make))
  beg end names parent
  defun-ref)                  ; the defun's own ref, if it has a name

(cl-defstruct (autolisp-ref (:constructor autolisp-ref--make))
  name beg end scope
  kind                        ; nil, defun, setq or local
  head                        ; non-nil in function position
  quoted
  global                      ; flagged by @Global
  args                        ; for defuns: the argument names
  doc)                        ; for defuns: preceding comment text

(cl-defstruct (autolisp-analysis (:constructor autolisp-analysis--make))
  refs                        ; list in buffer order
  table)                      ; name -> refs in buffer order

(defvar autolisp--comments nil "Comments read so far: list of (BEG . END).")

(defun autolisp--skip-blank ()
  "Skip whitespace and comments, recording comments."
  (let (go)
    (while (progn
             (skip-chars-forward " \t\n\r\f")
             (setq go (eq (char-after) ?\;)))
      (let ((beg (point)))
        (if (eq (char-after (1+ beg)) ?|)
            (progn (forward-char 2)
                   (unless (search-forward "|;" nil t) (goto-char (point-max))))
          (end-of-line))
        (push (cons beg (point)) autolisp--comments)))
    go))

(defun autolisp--read ()
  "Read one form at point and return a node, or nil at end or on `)'."
  (autolisp--skip-blank)
  (let ((quoted nil))
    (while (eq (char-after) ?\')
      (setq quoted t)
      (forward-char 1)
      (autolisp--skip-blank))
    (let ((beg (point)) (c (char-after)))
      (cond
       ((or (null c) (eq c ?\))) nil)
       ((eq c ?\()
        (forward-char 1)
        (let (children child)
          (while (setq child (autolisp--read)) (push child children))
          (autolisp--skip-blank)
          (let ((closed (eq (char-after) ?\))))
            (when closed (forward-char 1))
            (autolisp-node--make :type 'list :beg beg :end (point)
                                 :quoted quoted :closed closed
                                 :children (nreverse children)))))
       ((eq c ?\")
        (forward-char 1)
        (while (progn (skip-chars-forward "^\"\\\\")
                      (eq (char-after) ?\\))
          (forward-char (min 2 (- (point-max) (point)))))
        (unless (eobp) (forward-char 1))
        (autolisp-node--make :type 'string :beg beg :end (point)))
       (t
        (skip-chars-forward "^ \t\n\r\f()\"';")
        (autolisp-node--make :type 'atom :beg beg :end (point) :quoted quoted
                             :name (downcase (buffer-substring-no-properties
                                              beg (point)))))))))

(defun autolisp--read-all ()
  "Read every form in the buffer, skipping stray closing parens."
  (goto-char (point-min))
  (let (forms form)
    (while (progn (setq form (autolisp--read)) (or form (not (eobp))))
      (if form (push form forms)
        (forward-char 1)))
    (nreverse forms)))

(defun autolisp--user-symbol-p (name)
  "Return non-nil if NAME is a symbol the user could define."
  (not (or (string-match-p "\\`[-+]?\\(?:[0-9]+\\.?[0-9]*\\|\\.[0-9]+\\)\\(?:e[-+]?[0-9]+\\)?\\'"
                           name)
           (member name '("/" "." "t" "nil" "pi"))
           (and (not (equal name "*error*")) (autolisp-data-native-p name)))))

;;;; Analysis

(defvar autolisp--refs nil)

(defun autolisp--head-name (node)
  "Return the operator name of list NODE, or nil."
  (let ((first (car (autolisp-node-children node))))
    (and first (eq (autolisp-node-type first) 'atom)
         (autolisp-node-name first))))

(defun autolisp--add-ref (node scope &rest props)
  "Record atom NODE in SCOPE with PROPS, and return the ref.
SCOPE is the innermost scope; the ref gets the one that binds it."
  (when (autolisp--user-symbol-p (autolisp-node-name node))
    (let ((s scope) (name (autolisp-node-name node)))
      (while (and s (not (member name (autolisp-scope-names s))))
        (setq s (autolisp-scope-parent s)))
      (let ((ref (apply #'autolisp-ref--make :name name
                        :beg (autolisp-node-beg node) :end (autolisp-node-end node)
                        :quoted (autolisp-node-quoted node) :scope s props)))
        (push ref autolisp--refs)
        ref))))

(defun autolisp--atoms (node)
  "Return the atom children of list NODE, or NODE itself if an atom."
  (cond ((null node) nil)
        ((eq (autolisp-node-type node) 'atom) (list node))
        (t (seq-filter (lambda (n) (eq (autolisp-node-type n) 'atom))
                       (autolisp-node-children node)))))

(defun autolisp--arg-names (header)
  "Return the argument names in HEADER, without the locals."
  (when (and header (eq (autolisp-node-type header) 'list))
    (mapcar #'autolisp-node-name
            (seq-take-while (lambda (n) (not (equal (autolisp-node-name n) "/")))
                            (autolisp--atoms header)))))

(defun autolisp--make-scope (node header parent)
  "Return a scope for NODE binding the atoms of HEADER inside PARENT."
  (autolisp-scope--make
   :beg (autolisp-node-beg node) :end (autolisp-node-end node) :parent parent
   :names (seq-filter #'autolisp--user-symbol-p
                      (mapcar #'autolisp-node-name (autolisp--atoms header)))))

(defun autolisp--walk-all (nodes scope)
  "Walk NODES in SCOPE."
  (dolist (n nodes) (autolisp--walk n scope)))

(defun autolisp--walk (node scope)
  "Record the symbols in NODE, which appears in SCOPE."
  (pcase (autolisp-node-type node)
    ('atom (autolisp--add-ref node scope))
    ('list
     (let* ((kids (autolisp-node-children node))
            (op (autolisp--head-name node)))
       (cond
        ((and (member op '("defun" "defun-q"))
              (cadr kids) (eq (autolisp-node-type (cadr kids)) 'atom))
         (let* ((header (nth 2 kids))
                (inner (autolisp--make-scope node header scope))
                (ref (autolisp--add-ref (cadr kids) scope :kind 'defun
                                        :args (autolisp--arg-names header))))
           (setf (autolisp-scope-defun-ref inner) ref)
           (dolist (a (autolisp--atoms header))
             (autolisp--add-ref a inner :kind 'local))
           (autolisp--walk-all (nthcdr 3 kids) inner)))
        ((equal op "lambda")
         (let ((inner (autolisp--make-scope node (cadr kids) scope)))
           (dolist (a (autolisp--atoms (cadr kids)))
             (autolisp--add-ref a inner :kind 'local))
           (autolisp--walk-all (nthcdr 2 kids) inner)))
        ((and (member op '("foreach" "vlax-for"))
              (cadr kids) (eq (autolisp-node-type (cadr kids)) 'atom))
         (let ((inner (autolisp--make-scope node (cadr kids) scope)))
           (autolisp--add-ref (cadr kids) inner :kind 'local)
           (autolisp--walk-all (nthcdr 2 kids) inner)))
        ((equal op "setq")
         (let ((target t))
           (dolist (k (cdr kids))
             (if (and target (eq (autolisp-node-type k) 'atom))
                 (autolisp--add-ref k scope :kind 'setq)
               (autolisp--walk k scope))
             (setq target (not target)))))
        (t
         (when (and kids (eq (autolisp-node-type (car kids)) 'atom))
           (autolisp--add-ref (car kids) scope
                              :head (not (autolisp-node-quoted node))))
         (autolisp--walk-all (if (and kids (eq (autolisp-node-type (car kids)) 'atom))
                                 (cdr kids)
                               kids)
                             scope)))))))

(defun autolisp--setq-targets (node)
  "Return the positions of the variables set by `setq' list NODE."
  (let ((target t) out)
    (dolist (k (cdr (autolisp-node-children node)) (nreverse out))
      (when (and target (eq (autolisp-node-type k) 'atom))
        (push (autolisp-node-beg k) out))
      (setq target (not target)))))

(defun autolisp--definition-positions (node)
  "Return positions of the names NODE directly defines."
  (when (eq (autolisp-node-type node) 'list)
    (pcase (autolisp--head-name node)
      ((or "defun" "defun-q")
       (when-let* ((n (cadr (autolisp-node-children node))))
         (list (autolisp-node-beg n))))
      ("setq" (autolisp--setq-targets node)))))

(defun autolisp--flatten (nodes)
  "Return all list nodes in NODES, outermost first, in buffer order."
  (let (out)
    (cl-labels ((visit (n)
                  (when (eq (autolisp-node-type n) 'list)
                    (push n out)
                    (mapc #'visit (autolisp-node-children n)))))
      (mapc #'visit nodes))
    (nreverse out)))

(defun autolisp--global-positions (lists)
  "Return positions of definitions in LISTS flagged by an @Global comment."
  (let (positions (case-fold-search t))
    (dolist (c autolisp--comments positions)
      (when (save-excursion
              (goto-char (car c))
              (re-search-forward "@global\\_>" (cdr c) t))
        (goto-char (car c))
        (let* ((bol (line-beginning-position)) (cbeg (car c))
               (inline (progn (skip-chars-backward " \t" bol) (> (point) bol))))
          (if inline
              ;; Trailing comment: whatever this line defines or finishes.
              (dolist (l lists)
                (let ((defs (autolisp--definition-positions l))
                      (end (autolisp-node-end l)))
                  (if (and (>= end bol) (<= end cbeg))
                      (setq positions (append defs positions))
                    (dolist (p defs)
                      (when (and (>= p bol) (< p cbeg)) (push p positions))))))
            ;; Comment on its own: the next form.
            (when-let* ((next (seq-find (lambda (l) (> (autolisp-node-beg l) cbeg))
                                        lists)))
              (setq positions
                    (append (autolisp--definition-positions next) positions)))))))))

(defun autolisp--comment-index ()
  "Return a table from the last character of a comment to its start.
Only comments on lines of their own are included; a trailing comment
documents the code before it."
  (let ((index (make-hash-table)))
    (dolist (c autolisp--comments index)
      (goto-char (car c))
      (skip-chars-backward " \t")
      (when (bolp)
        (goto-char (cdr c))
        (skip-chars-backward " \t\r\n")
        (puthash (point) (car c) index)))))

(defun autolisp--comment-before (pos index)
  "Return the text of the comments just before POS, or nil.
INDEX is the result of `autolisp--comment-index'."
  (let ((start nil) (here pos) beg)
    (while (progn
             (goto-char here)
             (skip-chars-backward " \t\r\n")
             (and (setq beg (gethash (point) index))
                  ;; At most one blank line may come between.
                  (<= (count-lines (point) here) 2)))
      (setq start beg here beg))
    (when start
      (string-trim (buffer-substring-no-properties start pos)))))

(defun autolisp-analyze-buffer ()
  "Analyze the current buffer and return an `autolisp-analysis'."
  (save-excursion
    (save-restriction
      (widen)
      (let* ((autolisp--comments nil) (autolisp--refs nil)
             (forms (autolisp--read-all))
             (lists (autolisp--flatten forms))
             (table (make-hash-table :test #'equal)))
        (autolisp--walk-all forms nil)
        (let ((refs (sort (nreverse autolisp--refs)
                          (lambda (a b) (< (autolisp-ref-beg a)
                                           (autolisp-ref-beg b)))))
              (globals (autolisp--global-positions lists))
              (comments (autolisp--comment-index))
              (starts (make-hash-table)))
          (dolist (l lists)
            (dolist (p (autolisp--definition-positions l))
              (puthash p (autolisp-node-beg l) starts)))
          (dolist (r refs)
            ;; Localized symbols cannot be global.
            (when (and (null (autolisp-ref-scope r))
                       (memq (autolisp-ref-beg r) globals))
              (setf (autolisp-ref-global r) t))
            (when (eq (autolisp-ref-kind r) 'defun)
              (setf (autolisp-ref-doc r)
                    (autolisp--comment-before
                     (gethash (autolisp-ref-beg r) starts) comments)))
            (push r (gethash (autolisp-ref-name r) table)))
          (maphash (lambda (k v) (puthash k (nreverse v) table)) table)
          (autolisp-analysis--make :refs refs :table table))))))

;;;; Caching

(defvar-local autolisp--buffer-analysis nil
  "Cons (TICK . ANALYSIS) for this buffer.")

(defconst autolisp--cache-seconds 5
  "How long to trust file listings and modification times.")

(defvar autolisp--file-cache (make-hash-table :test #'equal)
  "File name -> (CHECKED MODTIME . ANALYSIS) for files not being visited.")

(defvar autolisp--listing-cache (make-hash-table :test #'equal)
  "Directory -> (CHECKED . FILES).")

(defun autolisp-buffer-analysis (&optional buffer)
  "Return the analysis of BUFFER, reusing it while the text is unchanged."
  (with-current-buffer (or buffer (current-buffer))
    (let ((tick (buffer-chars-modified-tick)))
      (unless (eql (car autolisp--buffer-analysis) tick)
        (setq autolisp--buffer-analysis (cons tick (autolisp-analyze-buffer))))
      (cdr autolisp--buffer-analysis))))

(defun autolisp-file-analysis (file)
  "Return the analysis of FILE, using its buffer if it is being visited."
  (if-let* ((buf (get-file-buffer file)))
      (autolisp-buffer-analysis buf)
    (let ((cached (gethash file autolisp--file-cache))
          (now (float-time)))
      (if (and cached (< (- now (car cached)) autolisp--cache-seconds))
          (cddr cached)
        (let* ((mtime (file-attribute-modification-time (file-attributes file)))
               (analysis (if (and cached (equal (cadr cached) mtime))
                             (cddr cached)
                           (with-temp-buffer
                             ;; The file may have gone since it was listed.
                             (ignore-error file-error
                               (insert-file-contents file))
                             (autolisp-analyze-buffer)))))
          (puthash file (cons now (cons mtime analysis)) autolisp--file-cache)
          analysis)))))

;;;; Which files

(defconst autolisp-file-regexp "\\.\\(?:lsp\\|mnl\\)\\'")

(defun autolisp--directory-files ()
  "Return the AutoLISP files that belong with the current buffer."
  (let* ((key (cons default-directory autolisp-search-project-root))
         (cached (gethash key autolisp--listing-cache))
         (now (float-time)))
    (if (and cached (< (- now (car cached)) autolisp--cache-seconds))
        (cdr cached)
      (let ((files (seq-filter #'file-readable-p (autolisp--list-directory-files))))
        (puthash key (cons now files) autolisp--listing-cache)
        files))))

(defun autolisp--list-directory-files ()
  "List the AutoLISP files that belong with the current buffer."
  (let ((case-fold-search t))
    (if-let* ((project (and autolisp-search-project-root
                            buffer-file-name
                            (project-current nil))))
        (seq-filter (lambda (f) (string-match-p autolisp-file-regexp f))
                    (project-files project))
      (when buffer-file-name
        (directory-files (file-name-directory buffer-file-name) t
                         autolisp-file-regexp t)))))

(defun autolisp-related-files ()
  "Return files to search from the current buffer, without duplicates.
That is the open AutoLISP buffers, the active .prj file and the files of
the project or directory."
  (let* ((open (delq nil (mapcar (lambda (b)
                                   (and (provided-mode-derived-p
                                         (buffer-local-value 'major-mode b)
                                         'autolisp-mode)
                                        (buffer-file-name b)))
                                 (buffer-list))))
         (prj (and (fboundp 'autolisp-project-files)
                   (seq-filter #'file-readable-p (autolisp-project-files))))
         (all (delete-dups
               (mapcar #'expand-file-name
                       (append (and buffer-file-name (list buffer-file-name))
                               open prj (autolisp--directory-files))))))
    (seq-take all autolisp-search-file-limit)))

(defun autolisp--map-analyses (function)
  "Call FUNCTION with the file and analysis of every related file.
The file is the current buffer when that visits none."
  (unless buffer-file-name
    (funcall function (current-buffer) (autolisp-buffer-analysis)))
  (dolist (file (autolisp-related-files))
    (funcall function file (autolisp-file-analysis file))))

(defmacro autolisp--do-analyses (spec &rest body)
  "Run BODY for every related analysis.
SPEC is (FILE ANALYSIS); FILE is a file name, or the current buffer when
it visits no file."
  (declare (indent 1))
  (let ((file (car spec)) (analysis (cadr spec)))
    `(autolisp--map-analyses (lambda (,file ,analysis) ,@body))))

;;;; Queries

(defun autolisp-symbol-bounds ()
  "Return the bounds of the AutoLISP symbol at point, or nil."
  (unless (nth 8 (syntax-ppss))
    (bounds-of-thing-at-point 'symbol)))

(defun autolisp-symbol-at-point ()
  "Return the AutoLISP symbol at point as a string, or nil."
  (when-let* ((b (autolisp-symbol-bounds)))
    (buffer-substring-no-properties (car b) (cdr b))))

(defun autolisp-ref-at-point ()
  "Return the `autolisp-ref' at point, or nil."
  (when-let* ((b (autolisp-symbol-bounds))
              (a (autolisp-buffer-analysis)))
    (seq-find (lambda (r) (= (autolisp-ref-beg r) (car b)))
              (gethash (downcase (buffer-substring-no-properties (car b) (cdr b)))
                       (autolisp-analysis-table a)))))

(defun autolisp-global-refs (analysis name)
  "Return the refs to NAME in ANALYSIS that no form localizes."
  (seq-filter (lambda (r) (null (autolisp-ref-scope r)))
              (gethash name (autolisp-analysis-table analysis))))

(defun autolisp-find-defuns (name)
  "Return (FILE . REF) for every global defun of NAME."
  (let ((key (downcase name)) out)
    (autolisp--do-analyses (file a)
      (dolist (r (autolisp-global-refs a key))
        (when (eq (autolisp-ref-kind r) 'defun) (push (cons file r) out))))
    (nreverse out)))

(defun autolisp-all-defun-names ()
  "Return the names of all user functions, as written."
  (let (out)
    (autolisp--do-analyses (_file a)
      (dolist (r (autolisp-analysis-refs a))
        (when (eq (autolisp-ref-kind r) 'defun) (push (autolisp-ref-name r) out))))
    (delete-dups out)))

(defun autolisp-definitions-at-point ()
  "Return (FILE . REF) definitions for the symbol at point."
  (when-let* ((ref (autolisp-ref-at-point)))
    (let ((here (or buffer-file-name (current-buffer)))
          (name (autolisp-ref-name ref))
          (scope (autolisp-ref-scope ref)))
      (if scope
          ;; A local: go to where it is localized.
          (list (cons here
                      (seq-find (lambda (r) (and (eq (autolisp-ref-scope r) scope)
                                                 (eq (autolisp-ref-kind r) 'local)))
                                (gethash name (autolisp-analysis-table
                                               (autolisp-buffer-analysis))))))
        (or
         ;; Definitions flagged @Global win.
         (let (out)
           (autolisp--do-analyses (file a)
             (dolist (r (autolisp-global-refs a name))
               (when (autolisp-ref-global r) (push (cons file r) out))))
           (nreverse out))
         ;; AutoLISP has one namespace, so a defun is the definition.
         (autolisp-find-defuns name)
         ;; A global variable: the nearest earlier setq in this file.
         (let ((earlier
                (seq-filter (lambda (r) (and (eq (autolisp-ref-kind r) 'setq)
                                             (<= (autolisp-ref-beg r)
                                                 (autolisp-ref-beg ref))))
                            (autolisp-global-refs (autolisp-buffer-analysis) name))))
           (when earlier
             (list (cons here
                         (or (car (last (remq ref earlier))) ref)))))
         (let (out)
           (autolisp--do-analyses (file a)
             (dolist (r (autolisp-global-refs a name))
               (when (eq (autolisp-ref-kind r) 'setq) (push (cons file r) out))))
           (nreverse out)))))))

(defun autolisp-references (ref)
  "Return (FILE . REF) for everything that refers to the same symbol as REF."
  (let ((name (autolisp-ref-name ref)) (scope (autolisp-ref-scope ref)) out)
    (if scope
        (let ((here (or buffer-file-name (current-buffer))))
          (dolist (r (gethash name (autolisp-analysis-table
                                    (autolisp-buffer-analysis))))
            (when (eq (autolisp-ref-scope r) scope) (push (cons here r) out))))
      (autolisp--do-analyses (file a)
        (dolist (r (autolisp-global-refs a name)) (push (cons file r) out))))
    (nreverse out)))

;;;; Xref

(defun autolisp--xref-item (entry)
  "Return an xref item for ENTRY, a (FILE . REF) pair."
  (let ((file (car entry)) (beg (autolisp-ref-beg (cdr entry)))
        (end (autolisp-ref-end (cdr entry))))
    (cl-flet ((build (make)
                (save-excursion
                  (save-restriction
                    (widen)
                    (goto-char beg)
                    (let* ((bol (line-beginning-position))
                           (line (buffer-substring-no-properties
                                  bol (line-end-position)))
                           (col (- beg bol)))
                      (add-face-text-property
                       col (min (length line) (+ col (- end beg)))
                       'xref-match nil line)
                      (xref-make-match line (funcall make (line-number-at-pos) col)
                                       (- end beg)))))))
      (if (bufferp file)
          (with-current-buffer file
            (build (lambda (_l _c) (xref-make-buffer-location file beg))))
        (let ((make (lambda (line col) (xref-make-file-location file line col))))
          (if-let* ((buf (get-file-buffer file)))
              (with-current-buffer buf (build make))
            (with-temp-buffer
              (insert-file-contents file)
              (build make))))))))

(defun autolisp-xref-backend ()
  "Xref backend for AutoLISP buffers."
  'autolisp)

(cl-defmethod xref-backend-identifier-at-point ((_ (eql 'autolisp)))
  "Return the symbol at point, tagged with its position."
  (when-let* ((b (autolisp-symbol-bounds)))
    (propertize (buffer-substring-no-properties (car b) (cdr b))
                'autolisp-marker (copy-marker (car b)))))

(defun autolisp--ref-for-identifier (identifier)
  "Return the ref IDENTIFIER was taken from, if it carries a position."
  (when-let* ((m (get-text-property 0 'autolisp-marker identifier))
              ((eq (marker-buffer m) (current-buffer))))
    (save-excursion (goto-char m) (autolisp-ref-at-point))))

(cl-defmethod xref-backend-definitions ((_ (eql 'autolisp)) identifier)
  "Return the definitions of IDENTIFIER."
  (mapcar #'autolisp--xref-item
          (if-let* ((m (get-text-property 0 'autolisp-marker identifier))
                    ((autolisp--ref-for-identifier identifier)))
              (save-excursion (goto-char m) (autolisp-definitions-at-point))
            (autolisp-find-defuns identifier))))

(cl-defmethod xref-backend-references ((_ (eql 'autolisp)) identifier)
  "Return the references to IDENTIFIER."
  (mapcar #'autolisp--xref-item
          (autolisp-references
           (or (autolisp--ref-for-identifier identifier)
               (autolisp-ref--make :name (downcase identifier))))))

(cl-defmethod xref-backend-apropos ((_ (eql 'autolisp)) pattern)
  "Return the user functions matching PATTERN."
  (let ((re (xref-apropos-regexp pattern)) (case-fold-search t) out)
    (autolisp--do-analyses (file a)
      (dolist (r (autolisp-analysis-refs a))
        (when (and (eq (autolisp-ref-kind r) 'defun)
                   (string-match-p re (autolisp-ref-name r)))
          (push (autolisp--xref-item (cons file r)) out))))
    (nreverse out)))

(cl-defmethod xref-backend-identifier-completion-table ((_ (eql 'autolisp)))
  "Return the names that can be looked up."
  (autolisp-all-defun-names))

(cl-defmethod xref-backend-identifier-completion-ignore-case ((_ (eql 'autolisp)))
  "AutoLISP symbols are case-insensitive."
  t)

;;;; Rename

(defun autolisp--valid-symbol-name-p (name)
  "Return non-nil if NAME can name a user symbol."
  (and (not (string-empty-p name))
       (not (string-match-p "[][ \t\r\n()\"';]" name))
       (autolisp--user-symbol-p (downcase name))))

(defun autolisp--param-tag-positions (scope name)
  "Return (BEG . END) of @Param tags for NAME documenting SCOPE's defun."
  (when-let* ((ref (autolisp-scope-defun-ref scope))
              (doc (autolisp-ref-doc ref)))
    (save-excursion
      (goto-char (autolisp-scope-beg scope))
      (when (search-backward doc nil t)
        (let ((limit (autolisp-scope-beg scope)) (case-fold-search t) out)
          (while (re-search-forward
                  (concat "@param[ \t]+\\(" (regexp-quote name) "\\)\\(?:[ \t\r\n]\\|$\\)")
                  limit t)
            (push (cons (match-beginning 1) (match-end 1)) out))
          out)))))

(defun autolisp--rename-targets (ref)
  "Return an alist of (FILE (BEG . END)...) to rename for REF."
  (let* ((here (or buffer-file-name (current-buffer)))
         (entries (autolisp-references ref))
         (others (seq-remove (lambda (e) (equal (car e) here)) entries))
         (global (seq-some (lambda (e) (autolisp-ref-global (cdr e))) entries))
         (by-file nil))
    ;; Without @Global the symbol may only share its name with the others.
    (when (and others (not global)
               (not (y-or-n-p
                     (format "`%s' is not @Global; also rename %d use%s in %d other file%s? "
                             (autolisp-ref-name ref) (length others)
                             (if (cdr others) "s" "")
                             (length (seq-uniq (mapcar #'car others)))
                             (if (cdr (seq-uniq (mapcar #'car others))) "s" "")))))
      (setq entries (seq-filter (lambda (e) (equal (car e) here)) entries)))
    (dolist (e entries)
      (push (cons (autolisp-ref-beg (cdr e)) (autolisp-ref-end (cdr e)))
            (alist-get (car e) by-file nil nil #'equal)))
    (when (autolisp-ref-scope ref)
      (dolist (p (autolisp--param-tag-positions (autolisp-ref-scope ref)
                                                (autolisp-ref-name ref)))
        (push p (alist-get here by-file nil nil #'equal))))
    by-file))

(defun autolisp--rename-collision (ref new)
  "Return non-nil if naming REF NEW would merge it with another symbol."
  (let ((key (downcase new)) (scope (autolisp-ref-scope ref)))
    (unless (equal key (autolisp-ref-name ref))
      (if scope
          (seq-some (lambda (r) (and (>= (autolisp-ref-beg r) (autolisp-scope-beg scope))
                                     (< (autolisp-ref-beg r) (autolisp-scope-end scope))))
                    (gethash key (autolisp-analysis-table (autolisp-buffer-analysis))))
        (catch 'hit
          (autolisp--do-analyses (_file a)
            (when (gethash key (autolisp-analysis-table a)) (throw 'hit t))))))))

(defun autolisp-rename-symbol (new)
  "Rename the symbol at point to NEW, respecting AutoLISP scoping.
Edited files are left unsaved so that the change can be reviewed."
  (interactive
   (let ((ref (autolisp-ref-at-point)))
     (unless ref
       (user-error "No user-defined symbol at point"))
     (list (read-string (format "Rename `%s' to: " (autolisp-symbol-at-point))
                        (autolisp-symbol-at-point)))))
  (let ((ref (autolisp-ref-at-point)))
    (unless ref (user-error "No user-defined symbol at point"))
    (unless (autolisp--valid-symbol-name-p new)
      (user-error "`%s' is not usable as a symbol name" new))
    (when (and (autolisp--rename-collision ref new)
               (not (y-or-n-p (format "`%s' is already in use here; rename anyway? " new))))
      (user-error "Rename cancelled"))
    (let ((count 0) (targets (autolisp--rename-targets ref)))
      (dolist (file-targets targets)
        (with-current-buffer (if (bufferp (car file-targets)) (car file-targets)
                               (find-file-noselect (car file-targets)))
          (save-excursion
            (save-restriction
              (widen)
              (atomic-change-group
                ;; Last first, so that earlier positions stay valid.
                (dolist (p (sort (copy-sequence (cdr file-targets))
                                 (lambda (a b) (> (car a) (car b)))))
                  (goto-char (car p))
                  (delete-region (car p) (cdr p))
                  (insert new)
                  (setq count (1+ count))))))))
      (message "Renamed %d occurrence%s in %d file%s (not saved)"
               count (if (= count 1) "" "s")
               (length targets) (if (cdr targets) "s" ""))
      count)))

(provide 'autolisp-symbols)
;;; autolisp-symbols.el ends here
