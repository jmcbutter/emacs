# xml-to-table

`xml-to-table` converts repeated XML records into an aligned Org table without
external programs or third-party Elisp dependencies.

## Usage

Select XML and run `M-x xml-to-table`. If no region is active, the command uses
the whole accessible buffer. The package normally infers the row element from
repeated siblings:

```xml
<people>
  <person id="1"><name>Ada</name><role>Engineer</role></person>
  <person id="2"><name>Grace</name><role>Admiral</role></person>
</people>
```

becomes:

```org
| @id | name  | role     |
|-----+-------+----------|
|   1 | Ada   | Engineer |
|   2 | Grace | Admiral  |
```

Use `C-u M-x xml-to-table` to choose the element represented by each row. This
is useful for documents containing several repeated structures.

From Elisp, use:

```elisp
(xml-to-table-convert-string xml "person")
```

The optional record name may be a string or symbol. If omitted, it is inferred.

## Mapping rules

- Record attributes use `@attribute` columns.
- Nested leaves use slash-separated columns such as `address/city`.
- Attributes on nested elements use names such as `price/@currency`.
- Repeated leaves share a cell and use `xml-to-table-value-separator`, which
  defaults to `", "`.
- Missing values produce empty cells.
- Whitespace is collapsed, and literal pipes are escaped for Org tables.
- DTD declarations are rejected; the converter is intended for ordinary data
  documents, not DTD processing.

## Development

Run the tests from this directory:

```sh
emacs -Q --batch -L . -L test \
  -l test/xml-to-table-test.el \
  -f ert-run-tests-batch-and-exit
```

Byte-compile with warnings treated as errors:

```sh
emacs -Q --batch -L . \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile xml-to-table.el
```
