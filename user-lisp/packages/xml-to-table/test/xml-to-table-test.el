;;; xml-to-table-test.el --- Tests for xml-to-table -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'xml-to-table)

(ert-deftest xml-to-table-converts-repeated-elements ()
  (should
   (equal
    (xml-to-table-convert-string
     "<people><person><name>Ada</name><role>Engineer</role></person><person><name>Grace</name><role>Admiral</role></person></people>")
    (concat "| name  | role     |\n"
            "|-------+----------|\n"
            "| Ada   | Engineer |\n"
            "| Grace | Admiral  |\n"))))

(ert-deftest xml-to-table-flattens-attributes-and-nested-elements ()
  (should
   (equal
    (xml-to-table-convert-string
     (concat "<catalog>"
             "<book id='b1'><title>One</title><author><name>Ada</name></author></book>"
             "<book id='b2'><title>Two</title><author><name>Grace</name></author></book>"
             "</catalog>"))
    (concat "| @id | title | author/name |\n"
            "|-----+-------+-------------|\n"
            "| b1  | One   | Ada         |\n"
            "| b2  | Two   | Grace       |\n"))))

(ert-deftest xml-to-table-unions-columns-and-leaves-missing-values-empty ()
  (should
   (equal
    (xml-to-table-convert-string
     "<rows><row><a>1</a></row><row><b>2</b></row></rows>")
    (concat "| a | b |\n"
            "|---+---|\n"
            "| 1 |   |\n"
            "|   | 2 |\n"))))

(ert-deftest xml-to-table-joins-repeated-leaf-values ()
  (let ((xml-to-table-value-separator "; "))
    (should
     (string-match-p
      (regexp-quote "| red; blue |")
      (xml-to-table-convert-string
       "<items><item><tag>red</tag><tag>blue</tag></item></items>"
       "item")))))

(ert-deftest xml-to-table-normalizes-and-escapes-cell-text ()
  (should
   (string-match-p
    (regexp-quote "A \\vert{} B")
    (xml-to-table-convert-string
     "<rows><row><value>  A |\n B  </value></row></rows>"))))

(ert-deftest xml-to-table-allows-an-explicit-record-name ()
  (should
   (equal
    (xml-to-table-convert-string
     "<report><metadata><name>Example</name></metadata><items><item code='a'/><item code='b'/></items></report>"
     'item)
    (concat "| @code |\n"
            "|-------|\n"
            "| a     |\n"
            "| b     |\n"))))

(ert-deftest xml-to-table-converts-a-single-record ()
  (should
   (equal
    (xml-to-table-convert-string
     "<people><person id='1'><name>Ada</name></person></people>")
    (concat "| @id | name |\n"
            "|-----+------|\n"
            "|   1 | Ada  |\n"))))

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
    (concat "| @id | x:name |\n"
            "|-----+--------|\n"
            "|   1 | Ada    |\n"))))

(provide 'xml-to-table-test)
;;; xml-to-table-test.el ends here
