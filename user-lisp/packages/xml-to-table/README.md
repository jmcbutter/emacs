# xml-to-table

`xml-to-table` opens repeated XML records as an editable Emacs spreadsheet. It
uses the built-in Simple Emacs Spreadsheet (SES), so it does not require Org,
an external converter, or another Elisp package.

## Usage

Select XML and run `M-x xml-to-table`. If no region is active, the command uses
the whole accessible buffer. The source XML remains unchanged, and the data
opens in a new `*XML Spreadsheet: …*` buffer.

The package normally infers the row element from repeated siblings:

```xml
<people>
  <person id="1"><name>Ada</name><role>Engineer</role></person>
  <person id="2"><name>Grace</name><role>Admiral</role></person>
</people>
```

This opens a spreadsheet with `@id`, `name`, and `role` columns. Cells are
editable with normal SES commands: press `RET` to edit a cell, use the arrow
keys to move, and enter formulas such as `(+ A2 A3)` where useful.

Use `C-u M-x xml-to-table` to choose the element represented by each row. This
is useful for documents containing several repeated structures.

## Saving and export

- Use `C-x C-w` to keep an editable `.ses` file.
- Press `C-c C-e` in a generated spreadsheet to export its current values as
  CSV for Excel, LibreOffice, or another spreadsheet application.
- SES also provides its standard sorting, row, column, formula, and TSV export
  commands; run `C-h m` in the spreadsheet for the complete key map.

From Elisp, `xml-to-table-convert-string` returns a matrix whose first row is
the column header:

```elisp
(xml-to-table-convert-string xml "person")
;; => (("@id" "name" "role")
;;     ("1" "Ada" "Engineer")
;;     ("2" "Grace" "Admiral"))
```

## Mapping rules

- Record attributes use `@attribute` columns.
- Nested leaves use slash-separated columns such as `address/city`.
- Attributes on nested elements use names such as `price/@currency`.
- Repeated leaves share a cell and use `xml-to-table-value-separator`, which
  defaults to `", "`.
- Missing values produce empty cells.
- Whitespace is collapsed while literal punctuation is preserved.
- DTD declarations are rejected; the converter is intended for ordinary data
  documents, not DTD processing.

## Development

Run the tests from this directory:

```sh
emacs -Q --batch -L . -L test \
  --eval '(setq load-prefer-newer t)' \
  -l test/xml-to-table-test.el \
  -f ert-run-tests-batch-and-exit
```

Byte-compile with warnings treated as errors:

```sh
emacs -Q --batch -L . \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile xml-to-table.el
```
