;;; xml-to-table.el --- Convert XML records to Org tables -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jordan

;; Author: Jordan Butterfield
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1") (org "9.5"))
;; Keywords: convenience, data, xml, org

;; This file is not part of GNU Emacs.

;;; Commentary:

;; `xml-to-table' replaces XML in the active region, or in the whole buffer,
;; with an Org table.  Repeated sibling elements are inferred as records.
;; With a prefix argument, the command prompts for the record element instead.
;;
;; Record attributes become columns prefixed with "@".  Nested elements use
;; slash-separated column names, and repeated values are joined with
;; `xml-to-table-value-separator'.  The non-interactive entry point
;; `xml-to-table-convert-string' returns a table without modifying a buffer.

;;; Code:

(require 'cl-lib)
(require 'org-table)
(require 'seq)
(require 'subr-x)
(require 'xml)

(defgroup xml-to-table nil
  "Convert XML records to Org tables."
  :group 'org
  :prefix "xml-to-table-")

(defcustom xml-to-table-value-separator ", "
  "String used to join repeated values in one table cell."
  :type 'string
  :group 'xml-to-table)

(define-error 'xml-to-table-error "Could not convert XML to a table")
(define-error 'xml-to-table-parse-error "Could not parse XML"
  'xml-to-table-error)

(defun xml-to-table--element-p (node)
  "Return non-nil when NODE is an XML element."
  (and (consp node) (symbolp (car node))))

(defun xml-to-table--element-children (node)
  "Return the element children of XML NODE."
  (seq-filter #'xml-to-table--element-p (xml-node-children node)))

(defun xml-to-table--name (node)
  "Return the qualified element name of XML NODE as a string."
  (symbol-name (xml-node-name node)))

(defun xml-to-table--qualified-name (name)
  "Return XML attribute or element NAME as a string."
  (cond
   ((symbolp name) (symbol-name name))
   ((consp name) (concat (car name) (cdr name)))
   (t (format "%s" name))))

(defun xml-to-table--parse-region (begin end &optional buffer)
  "Parse XML between BEGIN and END in BUFFER and return its root element."
  (with-current-buffer (or buffer (current-buffer))
    (save-restriction
      (narrow-to-region begin end)
      (goto-char (point-min))
      (let ((case-fold-search t))
        (when (re-search-forward "<!DOCTYPE\\(?:[[:space:]]\\|>\\)" nil t)
          (signal 'xml-to-table-parse-error
                  '("DTD declarations are not supported"))))
      (condition-case error-data
          (let ((roots
                 (seq-filter
                  #'xml-to-table--element-p
                  (xml-parse-region
                   (point-min) (point-max)))))
            (unless (= (length roots) 1)
              (signal 'xml-to-table-parse-error
                      '("XML must contain exactly one root element")))
            (car roots))
        (xml-to-table-error
         (signal (car error-data) (cdr error-data)))
        (error
         (signal 'xml-to-table-parse-error
                 (list (error-message-string error-data))))))))

(defun xml-to-table--parse-string (xml)
  "Parse XML string and return its root element."
  (with-temp-buffer
    (insert xml)
    (xml-to-table--parse-region (point-min) (point-max))))

(defun xml-to-table--walk-elements (node function)
  "Call FUNCTION for NODE and each of its descendant elements."
  (funcall function node)
  (dolist (child (xml-to-table--element-children node))
    (xml-to-table--walk-elements child function)))

(defun xml-to-table--record-candidates (root)
  "Return unique element names below ROOT."
  (let (names)
    (xml-to-table--walk-elements
     root
     (lambda (node)
       (let ((name (xml-to-table--name node)))
         (unless (member name names)
           (push name names)))))
    (nreverse names)))

(defun xml-to-table--infer-record-name (root)
  "Infer the repeated record element name below ROOT."
  (let ((best-name nil)
        (best-count 1))
    (xml-to-table--walk-elements
     root
     (lambda (parent)
       (let ((counts (make-hash-table :test #'equal))
             order)
         (dolist (child (xml-to-table--element-children parent))
           (let ((name (xml-to-table--name child)))
             (unless (gethash name counts)
               (push name order))
             (puthash name (1+ (gethash name counts 0)) counts)))
         (dolist (name (nreverse order))
           (let ((count (gethash name counts)))
             (when (> count best-count)
               (setq best-name name
                     best-count count)))))))
    (or best-name
        (let ((children (xml-to-table--element-children root)))
          (if (and (= (length children) 1)
                   (or (xml-node-attributes (car children))
                       (xml-to-table--element-children (car children))))
              (xml-to-table--name (car children))
            (xml-to-table--name root))))))

(defun xml-to-table--records (root record-name)
  "Return elements named RECORD-NAME in ROOT, in document order."
  (let (records)
    (xml-to-table--walk-elements
     root
     (lambda (node)
       (when (equal (xml-to-table--name node) record-name)
         (push node records))))
    (nreverse records)))

(defun xml-to-table--normalize-cell (value)
  "Normalize XML scalar VALUE for use in an Org table cell."
  (let ((text (string-trim
               (replace-regexp-in-string
                "[[:space:]]+" " " (substring-no-properties value)))))
    (replace-regexp-in-string "|" "\\vert{}" text t t)))

(defun xml-to-table--row (record)
  "Flatten XML RECORD into an ordered alist representing one row."
  (let ((values (make-hash-table :test #'equal))
        keys)
    (cl-labels
        ((add-value
          (key value)
          (unless (gethash key values)
            (setq keys (append keys (list key))))
          (puthash key
                   (append (gethash key values)
                           (list (xml-to-table--normalize-cell value)))
                   values))
         (visit
          (node path)
          (dolist (attribute (xml-node-attributes node))
            (add-value
             (concat (unless (string-empty-p path) (concat path "/"))
                     "@" (xml-to-table--qualified-name (car attribute)))
             (cdr attribute)))
          (let* ((children (xml-node-children node))
                 (elements (seq-filter #'xml-to-table--element-p children))
                 (direct-text
                  (xml-to-table--normalize-cell
                   (mapconcat #'identity (seq-filter #'stringp children) " "))))
            (when (or (not (string-empty-p direct-text))
                      (and (null elements)
                           (or (not (string-empty-p path))
                               (null (xml-node-attributes node)))))
              (add-value
               (cond
                ((and (string-empty-p path) elements) "#text")
                ((string-empty-p path) "value")
                (elements (concat path "/#text"))
                (t path))
               direct-text))
            (dolist (child elements)
              (visit child
                     (concat (unless (string-empty-p path) (concat path "/"))
                             (xml-to-table--name child)))))))
      (visit record ""))
    (mapcar
     (lambda (key)
       (let* ((all-values (gethash key values))
              (nonempty (seq-remove #'string-empty-p all-values)))
         (cons key
               (string-join (or nonempty (list ""))
                            xml-to-table-value-separator))))
     keys)))

(defun xml-to-table--columns (rows)
  "Return the ordered union of column names in ROWS."
  (let ((seen (make-hash-table :test #'equal))
        columns)
    (dolist (row rows)
      (dolist (cell row)
        (unless (gethash (car cell) seen)
          (puthash (car cell) t seen)
          (setq columns (append columns (list (car cell)))))))
    columns))

(defun xml-to-table--insert-org-row (cells)
  "Insert CELLS as one unaligned Org table row."
  (insert "| " (string-join cells " | ") " |\n"))

(defun xml-to-table--render (rows)
  "Render flattened XML ROWS as an aligned Org table string."
  (let ((columns (xml-to-table--columns rows)))
    (unless columns
      (signal 'xml-to-table-error '("The selected records contain no values")))
    (with-temp-buffer
      (delay-mode-hooks (org-mode))
      (xml-to-table--insert-org-row columns)
      (insert "|-|\n")
      (dolist (row rows)
        (xml-to-table--insert-org-row
         (mapcar (lambda (column) (or (alist-get column row nil nil #'equal) ""))
                 columns)))
      (goto-char (point-min))
      (org-table-align)
      (buffer-substring-no-properties (point-min) (point-max)))))

;;;###autoload
(defun xml-to-table-convert-string (xml &optional record-name)
  "Convert XML to an Org table string.

RECORD-NAME is a string or symbol naming the element represented by each row.
When it is nil, infer the record element from repeated sibling elements."
  (let* ((root (xml-to-table--parse-string xml))
         (name (if record-name
                   (xml-to-table--qualified-name record-name)
                 (xml-to-table--infer-record-name root)))
         (records (xml-to-table--records root name)))
    (unless records
      (signal 'xml-to-table-error
              (list (format "No <%s> records were found" name))))
    (xml-to-table--render (mapcar #'xml-to-table--row records))))

(defun xml-to-table--bounds ()
  "Return the active region bounds, or the accessible buffer bounds."
  (if (use-region-p)
      (cons (region-beginning) (region-end))
    (cons (point-min) (point-max))))

(defun xml-to-table--read-record-name (begin end)
  "Read a record element name for XML between BEGIN and END."
  (let* ((root (xml-to-table--parse-region begin end))
         (default (xml-to-table--infer-record-name root))
         (candidates (xml-to-table--record-candidates root)))
    (completing-read
     (format "Record element (default %s): " default)
     candidates nil t nil nil default)))

(defun xml-to-table--interactive-arguments ()
  "Return interactive arguments for `xml-to-table'."
  (let* ((bounds (xml-to-table--bounds))
         (begin (car bounds))
         (end (cdr bounds)))
    (list begin end
          (when current-prefix-arg
            (xml-to-table--read-record-name begin end)))))

;;;###autoload
(defun xml-to-table (begin end &optional record-name)
  "Replace XML between BEGIN and END with an Org table.

Interactively, use the active region or the whole accessible buffer.  Infer
the repeated record element by default.  With a prefix argument, prompt for
RECORD-NAME before converting."
  (interactive (xml-to-table--interactive-arguments))
  (let ((table (xml-to-table-convert-string
                (buffer-substring-no-properties begin end)
                record-name)))
    (atomic-change-group
      (delete-region begin end)
      (goto-char begin)
      (insert table))))

(provide 'xml-to-table)
;;; xml-to-table.el ends here
