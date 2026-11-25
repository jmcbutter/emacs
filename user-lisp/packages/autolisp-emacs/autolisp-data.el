;;; autolisp-data.el --- AutoLISP and DCL reference data -*- lexical-binding: t -*-

;; SPDX-License-Identifier: Apache-2.0

;;; Commentary:

;; Lazy access to the word lists and help index that ship with Autodesk's
;; AutoLispExt (Apache-2.0).  They live in the data/ directory unmodified.
;; Nothing is read until it is first needed.

;;; Code:

(require 'json)
(require 'subr-x)

(defgroup autolisp nil
  "Editing and debugging AutoLISP."
  :group 'languages
  :prefix "autolisp-")

(defcustom autolisp-help-year nil
  "AutoCAD release year whose online help is opened.
When nil, use the newest AutoCAD found on this machine, or 2026."
  :type '(choice (const :tag "Detect" nil) (string :tag "Year")))

(defcustom autolisp-help-language "ENU"
  "Language code used in Autodesk help URLs."
  :type 'string)

(defvar autolisp-data-directory
  (expand-file-name "data/" (file-name-directory
                             (or load-file-name buffer-file-name
                                 default-directory)))
  "Directory holding the AutoLispExt data files.")

(defvar autolisp-data--cache (make-hash-table :test #'eq)
  "Loaded data, keyed by symbol.")

(defmacro autolisp-data--once (key &rest body)
  "Return the cached value for KEY, computing it with BODY the first time."
  (declare (indent 1))
  (let ((v (make-symbol "v")))
    `(let ((,v (gethash ,key autolisp-data--cache 'missing)))
       (if (eq ,v 'missing)
           (puthash ,key (progn ,@body) autolisp-data--cache)
         ,v))))

(defun autolisp-data--lines (file)
  "Return the non-empty lines of data FILE."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8-auto))
      (insert-file-contents (expand-file-name file autolisp-data-directory)))
    (mapcar #'string-trim (split-string (buffer-string) "[\r\n]+" t "[ \t]+"))))

(defun autolisp-data-functions ()
  "Return all built-in AutoLISP and Visual LISP symbol names, lower case."
  (autolisp-data--once 'functions
    (delete-dups (mapcar #'downcase
                         (autolisp-data--lines "alllispkeys.txt")))))

(defun autolisp-data--function-set ()
  "Return a hash set of built-in names."
  (autolisp-data--once 'function-set
    (let ((h (make-hash-table :test #'equal :size 4096)))
      (dolist (n (autolisp-data-functions) h) (puthash n t h)))))

(defun autolisp-data-native-p (name)
  "Return non-nil if NAME is a built-in AutoLISP symbol."
  (gethash (downcase name) (autolisp-data--function-set)))

(defun autolisp-data-commands ()
  "Return AutoCAD command and system variable names, upper case."
  (autolisp-data--once 'commands
    (delete-dups (mapcar #'upcase (autolisp-data--lines "cmdAndVarsList.txt")))))

(defun autolisp-data-dcl-words ()
  "Return all DCL keywords."
  (autolisp-data--once 'dcl-words
    (delete-dups (autolisp-data--lines "alldclkeys.txt"))))

(defun autolisp-data--help ()
  "Return the parsed help index, a hash table."
  (autolisp-data--once 'help
    (with-temp-buffer
      (let ((coding-system-for-read 'utf-8-auto))
        (insert-file-contents
         (expand-file-name "webHelpAbstraction.json" autolisp-data-directory)))
      (goto-char (point-min))
      (json-parse-buffer :object-type 'hash-table :array-type 'list
                         :null-object nil :false-object nil))))

(defun autolisp-data--section (name)
  "Return section NAME of the help index."
  (gethash name (autolisp-data--help)))

(defun autolisp-data-function-help (name)
  "Return a list of help entries for function NAME, or nil.
Some functions have several documented signatures."
  (let ((key (downcase name)))
    (if-let* ((one (gethash key (autolisp-data--section "functions"))))
        (list one)
      (gethash key (autolisp-data--section "ambiguousFunctions")))))

(defun autolisp-data-dcl-tile (name)
  "Return the help entry for DCL tile NAME, or nil."
  (gethash (downcase name) (autolisp-data--section "dclTiles")))

(defun autolisp-data-dcl-attribute (name)
  "Return the help entry for DCL attribute NAME, or nil."
  (gethash (downcase name) (autolisp-data--section "dclAttributes")))

(defun autolisp-data-dcl-tiles ()
  "Return the names of all documented DCL tiles."
  (hash-table-keys (autolisp-data--section "dclTiles")))

(defun autolisp-data-dcl-attributes ()
  "Return the names of all documented DCL attributes."
  (hash-table-keys (autolisp-data--section "dclAttributes")))

(defun autolisp-data-signature (entry)
  "Return the display signature of help ENTRY."
  (gethash "signature" entry))

(defun autolisp-data-description (entry)
  "Return the description of help ENTRY."
  (gethash "description" entry))

(defun autolisp-data--format-type (type)
  "Format value TYPE from the help index."
  (let ((id (gethash "id" type))
        (names (gethash "typeNames" type))
        (enums (gethash "enums" type)))
    (concat (or id "") (if names (concat " — " names) "")
            (if enums (concat "\n      one of: " (string-join enums ", ")) ""))))

(defun autolisp-data-format-entry (entry)
  "Format help ENTRY as plain text."
  (let ((args (gethash "arguments" entry))
        (ret (gethash "returnType" entry))
        (value (gethash "valueType" entry))
        (objects (gethash "validObjects" entry))
        (attributes (gethash "attributes" entry)))
    (string-join
     (delq nil
           (list (autolisp-data-signature entry)
                 (when-let* ((d (autolisp-data-description entry))) (concat "\n" d))
                 (when args
                   (concat "\nArguments:\n"
                           (mapconcat (lambda (a)
                                        (concat "  " (autolisp-data--format-type a)))
                                      args "\n")))
                 (when ret
                   (concat "\nReturns: "
                           (or (gethash "typeNames" ret) "")))
                 (when value
                   (concat "\nValue: " (autolisp-data--format-type value)))
                 (when attributes
                   (concat "\nAttributes: " (string-join attributes ", ")))
                 (when objects
                   (concat "\nValid objects: "
                           (mapconcat #'string-trim objects ", ")))
                 (when-let* ((p (gethash "platforms" entry)))
                   (concat "\nPlatforms: " (string-replace "|" ", " p)))))
     "\n")))

;;;; AutoCAD installation

(defun autolisp-data-autocad-programs ()
  "Return installed acad.exe paths, newest release first."
  (when (eq system-type 'windows-nt)
    (sort (file-expand-wildcards
           (expand-file-name "Autodesk/AutoCAD */acad.exe"
                             (or (getenv "ProgramFiles") "C:/Program Files")))
          (lambda (a b) (string> a b)))))

(defun autolisp-data-help-year ()
  "Return the release year to use in help URLs."
  (or autolisp-help-year
      (autolisp-data--once 'year
        (let ((p (car (autolisp-data-autocad-programs))))
          (if (and p (string-match "AutoCAD \\([0-9]\\{4\\}\\)/" p))
              (match-string 1 p)
            "2026")))))

(defun autolisp-data-url (guid)
  "Return the help URL for GUID."
  (format "https://help.autodesk.com/view/OARX/%s/%s/?guid=GUID-%s"
          (autolisp-data-help-year) autolisp-help-language guid))

(defun autolisp-data-lisp-url (name)
  "Return the help URL for AutoLISP symbol NAME, or the landing page."
  (let* ((key (downcase (string-trim name)))
         (entry (or (gethash key (autolisp-data--section "objects"))
                    (car (autolisp-data-function-help key))))
         (owner (gethash key (autolisp-data--section "enumerators"))))
    (cond (entry (autolisp-data-url (gethash "guid" entry)))
          ((and owner (not (equal (downcase owner) key)))
           (autolisp-data-lisp-url owner))
          (t (autolisp-data-url "4CEE5072-8817-4920-8A2D-7060F5E16547")))))

(defun autolisp-data-dcl-url (name)
  "Return the help URL for DCL word NAME, or the landing page."
  (let ((entry (or (autolisp-data-dcl-tile name)
                   (autolisp-data-dcl-attribute name))))
    (autolisp-data-url (if entry (gethash "guid" entry)
                         "F8F5A79B-9A05-4E25-A6FC-9720216BA3E7"))))

(provide 'autolisp-data)
;;; autolisp-data.el ends here
