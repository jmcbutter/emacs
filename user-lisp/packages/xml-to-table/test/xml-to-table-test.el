;;; xml-to-table-test.el --- Tests for xml-to-table -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'xml-to-table)

(ert-deftest xml-to-table-converts-repeated-elements ()
  (should
   (equal
    (xml-to-table-convert-string
     "<people><person><name>Ada</name><role>Engineer</role></person><person><name>Grace</name><role>Admiral</role></person></people>")
    '(("name" "role")
      ("Ada" "Engineer")
      ("Grace" "Admiral")))))

(ert-deftest xml-to-table-flattens-attributes-and-nested-elements ()
  (should
   (equal
    (xml-to-table-convert-string
     (concat "<catalog>"
             "<book id='b1'><title>One</title><author><name>Ada</name></author></book>"
             "<book id='b2'><title>Two</title><author><name>Grace</name></author></book>"
             "</catalog>"))
    '(("@id" "title" "author/name")
      ("b1" "One" "Ada")
      ("b2" "Two" "Grace")))))

(ert-deftest xml-to-table-unions-columns-and-leaves-missing-values-empty ()
  (should
   (equal
    (xml-to-table-convert-string
     "<rows><row><a>1</a></row><row><b>2</b></row></rows>")
    '(("a" "b")
      ("1" "")
      ("" "2")))))

(ert-deftest xml-to-table-joins-repeated-leaf-values ()
  (let ((xml-to-table-value-separator "; "))
    (should
     (equal
      (xml-to-table-convert-string
       "<items><item><tag>red</tag><tag>blue</tag></item></items>"
       "item")
      '(("tag") ("red; blue"))))))

(ert-deftest xml-to-table-normalizes-cell-text-and-preserves-pipes ()
  (should
   (equal
    (xml-to-table-convert-string
     "<rows><row><value>  A |\n B  </value></row></rows>")
    '(("value") ("A | B")))))

(ert-deftest xml-to-table-allows-an-explicit-record-name ()
  (should
   (equal
    (xml-to-table-convert-string
     "<report><metadata><name>Example</name></metadata><items><item code='a'/><item code='b'/></items></report>"
     'item)
    '(("@code") ("a") ("b")))))

(ert-deftest xml-to-table-converts-a-single-record ()
  (should
   (equal
    (xml-to-table-convert-string
     "<people><person id='1'><name>Ada</name></person></people>")
    '(("@id" "name") ("1" "Ada")))))

(ert-deftest xml-to-table-rejects-an-unknown-record-name ()
  (should-error
   (xml-to-table-convert-string "<rows><row><a>1</a></row></rows>" "missing")
   :type 'xml-to-table-error))

(ert-deftest xml-to-table-rejects-malformed-xml ()
  (should-error
   (xml-to-table-convert-string "<rows><row></rows>")
   :type 'xml-to-table-parse-error))

(ert-deftest xml-to-table-rejects-dtd-input ()
  (should-error
   (xml-to-table-convert-string
    "<!DOCTYPE rows [<!ENTITY example 'value'>]><rows><row>&example;</row></rows>")
   :type 'xml-to-table-parse-error))

(ert-deftest xml-to-table-command-preserves-input-after-parse-errors ()
  (with-temp-buffer
    (insert "<rows><row></rows>")
    (let ((original (buffer-string)))
      (should-error
       (xml-to-table (point-min) (point-max))
       :type 'xml-to-table-parse-error)
      (should (equal (buffer-string) original)))))

(ert-deftest xml-to-table-offers-scalar-record-elements ()
  (let ((root
         (xml-to-table--parse-string
          "<items><item>a</item><item>b</item></items>")))
    (should (member "item" (xml-to-table--record-candidates root)))
    (should (equal (xml-to-table--infer-record-name root) "item"))))

(ert-deftest xml-to-table-preserves-namespace-prefixes ()
  (should
   (equal
    (xml-to-table-convert-string
     "<x:rows xmlns:x='urn:test'><x:row id='1'><x:name>Ada</x:name></x:row></x:rows>"
     "x:row")
    '(("@id" "x:name") ("1" "Ada")))))

(ert-deftest xml-to-table-creates-an-editable-ses-spreadsheet ()
  (let ((spreadsheet
         (xml-to-table--make-spreadsheet
          '(("name" "age") ("Ada" "36")) "test.xml")))
    (unwind-protect
        (with-current-buffer spreadsheet
          (should (eq major-mode 'ses-mode))
          (should xml-to-table--spreadsheet-p)
          (should (= ses--header-row 1))
          (should (equal (ses-cell-value 0 0) "name"))
          (should (equal (ses-cell-value 1 1) "36"))
          (should (eq (key-binding (kbd "C-c C-e"))
                      #'xml-to-table-export-csv))
          (should
           (equal (xml-to-table--spreadsheet-table)
                  '(("name" "age") ("Ada" "36"))))
          (should-not (buffer-modified-p)))
      (when (buffer-live-p spreadsheet)
        (kill-buffer spreadsheet)))))

(ert-deftest xml-to-table-command-leaves-source-and-opens-spreadsheet ()
  (let (displayed)
    (cl-letf (((symbol-function 'pop-to-buffer)
               (lambda (buffer &rest _arguments)
                 (setq displayed buffer))))
      (with-temp-buffer
        (insert "<rows><row><name>Ada</name></row></rows>")
        (let ((original (buffer-string)))
          (xml-to-table (point-min) (point-max))
          (should (equal (buffer-string) original)))))
    (unwind-protect
        (with-current-buffer displayed
          (should (equal (ses-cell-value 0 0) "name"))
          (should (equal (ses-cell-value 1 0) "Ada")))
      (when (buffer-live-p displayed)
        (kill-buffer displayed)))))

(ert-deftest xml-to-table-serializes-csv-special-characters ()
  (should
   (equal
    (xml-to-table--csv-string
     '(("name" "note") ("Ada" "A, \"quoted\" value")))
    (concat "name,note\n"
            "Ada,\"A, \"\"quoted\"\" value\"\n"))))

(provide 'xml-to-table-test)
;;; xml-to-table-test.el ends here
