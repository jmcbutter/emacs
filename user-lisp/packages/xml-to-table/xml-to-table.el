;;; xml-to-table.el --- View XML records as a spreadsheet -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Jordan

;; Author: Jordan Butterfield
;; Version: 0.2.0
;; Package-Requires: ((emacs "28.1"))
;; Keywords: convenience, data, spreadsheet, xml

;; This file is not part of GNU Emacs.

;;; Commentary:

;; `xml-to-table' reads XML from the active region, or from the whole buffer,
;; and opens the records in an editable Simple Emacs Spreadsheet (SES) buffer.
;; The source XML is not changed.  With a prefix argument, the command prompts
;; for the element that should become each spreadsheet row.
;;
;; Record attributes become columns prefixed with "@".  Nested elements use
;; slash-separated column names, and repeated values are joined with
;; `xml-to-table-value-separator'.  Use `xml-to-table-export-csv' from a
;; generated spreadsheet to save its current values as CSV.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'ses)
(require 'subr-x)
(require 'xml)

;; SES defines these buffer-local variables dynamically.
(defvar ses--cells)
(defvar ses--numcols)
(defvar ses--numrows)

(defgroup xml-to-table nil
  "View XML records in an Emacs spreadsheet."
  :group 'data
  :prefix "xml-to-table-")

(defcustom xml-to-table-value-separator ", "
  "String used to join repeated values in one spreadsheet cell."
  :type 'string
  :group 'xml-to-table)

(defcustom xml-to-table-minimum-column-width 8
  "Minimum initial width of generated spreadsheet columns."
  :type 'integer
  :group 'xml-to-table)

(defcustom xml-to-table-maximum-column-width 40
  "Maximum initial width of generated spreadsheet columns.

Longer values remain intact and can be viewed by widening the column in SES."
  :type 'integer
  :group 'xml-to-table)

(define-error 'xml-to-table-error "Could not convert XML to a table")
(define-error 'xml-to-table-parse-error "Could not parse XML"
  'xml-to-table-error)

(defvar-local xml-to-table--spreadsheet-p nil
  "Non-nil in spreadsheet buffers created by `xml-to-table'.")

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
  (if (symbolp name) (symbol-name name) (format "%s" name)))

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
                  (xml-parse-region (point-min) (point-max)))))
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
  "Normalize XML scalar VALUE for use in a spreadsheet cell."
  (string-trim
   (replace-regexp-in-string
    "[[:space:]]+" " " (substring-no-properties value))))

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

;;;###autoload
(defun xml-to-table-convert-string (xml &optional record-name)
  "Convert XML into a matrix suitable for a spreadsheet.

The return value is a list of rows.  The first row contains column names and
the remaining rows contain string values.  RECORD-NAME is a string or symbol
naming the element represented by each row.  When it is nil, infer the record
element from repeated sibling elements."
  (let* ((root (xml-to-table--parse-string xml))
         (name (if record-name
                   (xml-to-table--qualified-name record-name)
                 (xml-to-table--infer-record-name root)))
         (records (xml-to-table--records root name)))
    (unless records
      (signal 'xml-to-table-error
              (list (format "No <%s> records were found" name))))
    (let* ((rows (mapcar #'xml-to-table--row records))
           (columns (xml-to-table--columns rows)))
      (unless columns
        (signal 'xml-to-table-error
                '("The selected records contain no values")))
      (cons columns
            (mapcar
             (lambda (row)
               (mapcar
                (lambda (column)
                  (or (alist-get column row nil nil #'equal) ""))
                columns))
             rows)))))

(defun xml-to-table--column-width (table column)
  "Return an initial SES width for COLUMN in TABLE."
  (let* ((content-width
          (apply #'max
                 (mapcar
                  (lambda (row) (string-width (nth column row)))
                  table)))
         (minimum (max 1 xml-to-table-minimum-column-width))
         (maximum (max minimum xml-to-table-maximum-column-width)))
    (min maximum (max minimum (+ content-width 2)))))

(defun xml-to-table--install-spreadsheet-keys ()
  "Install XML spreadsheet commands in the current SES buffer."
  (use-local-map (copy-keymap (current-local-map)))
  (local-set-key (kbd "C-c C-e") #'xml-to-table-export-csv)
  (setq-local ses-mode-print-map (copy-keymap ses-mode-print-map))
  (define-key ses-mode-print-map (kbd "C-c C-e")
              #'xml-to-table-export-csv))

(defun xml-to-table--make-spreadsheet (table source-name)
  "Create and return an SES buffer containing TABLE from SOURCE-NAME."
  (let* ((row-count (length table))
         (column-count (length (car table)))
         (buffer
          (generate-new-buffer
           (generate-new-buffer-name
            (format "*XML Spreadsheet: %s*" source-name)))))
    (condition-case error-data
        (with-current-buffer buffer
          (let ((ses-initial-size (cons row-count column-count))
                (ses-initial-default-printer "%s")
                (inhibit-message t))
            (ses-mode)
            (setq-local xml-to-table--spreadsheet-p t)
            (cl-loop
             for row-values in table
             for row from 0
             do (cl-loop
                 for value in row-values
                 for column from 0
                 do (ses-cell-set-formula row column value)))
            (ses-recalculate-all)
            (dotimes (column column-count)
              (ses-set-column-width
               column (xml-to-table--column-width table column)))
            (ses-set-header-row 1)
            (ses-command-hook))
          (xml-to-table--install-spreadsheet-keys)
          (set-buffer-modified-p nil)
          (goto-char (point-min))
          buffer)
      (error
       (when (buffer-live-p buffer)
         (kill-buffer buffer))
       (signal (car error-data) (cdr error-data))))))

(defun xml-to-table--cell-string (value)
  "Return SES cell VALUE as text for export."
  (cond
   ((or (null value) (eq value '*skip*)) "")
   ((stringp value) value)
   (t (format "%s" value))))

(defun xml-to-table--spreadsheet-table ()
  "Return the current generated SES spreadsheet as a matrix of strings."
  (unless (and xml-to-table--spreadsheet-p (eq major-mode 'ses-mode))
    (user-error "This is not an XML spreadsheet buffer"))
  (cl-loop
   for row below ses--numrows
   collect
   (cl-loop
    for column below ses--numcols
    collect (xml-to-table--cell-string (ses-cell-value row column)))))

(defun xml-to-table--csv-cell (value)
  "Quote string VALUE when required by CSV syntax."
  (if (string-match-p "[\",\n\r]" value)
      (concat "\"" (string-replace "\"" "\"\"" value) "\"")
    value))

(defun xml-to-table--csv-string (table)
  "Serialize string matrix TABLE as CSV."
  (concat
   (mapconcat
    (lambda (row)
      (mapconcat #'xml-to-table--csv-cell row ","))
    table "\n")
   "\n"))

;;;###autoload
(defun xml-to-table-export-csv (file)
  "Export the current XML spreadsheet values to CSV FILE."
  (interactive
   (list (read-file-name "Export CSV to: " nil nil nil "xml-table.csv")))
  (let ((table (xml-to-table--spreadsheet-table)))
    (when (and (file-exists-p file)
               (not (yes-or-no-p (format "Overwrite %s? " file))))
      (user-error "CSV export cancelled"))
    (let ((coding-system-for-write 'utf-8-unix))
      (write-region
       (xml-to-table--csv-string table)
       nil file nil 'silent)))
  (message "Exported XML spreadsheet to %s" file)
  file)

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
  "Open XML between BEGIN and END as an editable SES spreadsheet.

Interactively, use the active region or the whole accessible buffer.  Infer
the repeated record element by default.  With a prefix argument, prompt for
RECORD-NAME before converting.  The source buffer is never modified."
  (interactive (xml-to-table--interactive-arguments))
  (let* ((source-name
          (if (buffer-file-name)
              (file-name-nondirectory (buffer-file-name))
            (buffer-name)))
         (table
          (xml-to-table-convert-string
           (buffer-substring-no-properties begin end)
           record-name))
         (spreadsheet
          (xml-to-table--make-spreadsheet table source-name)))
    (pop-to-buffer spreadsheet)
    spreadsheet))

(provide 'xml-to-table)
;;; xml-to-table.el ends here
