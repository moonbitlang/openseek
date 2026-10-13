`two-pages.pdf` is an original two-page OpenSeek test document with selectable
Helvetica text. `encrypted.pdf` contains the same content and uses the test
password `open-seek`. It was generated with Ghostscript:

```sh
gs -sDEVICE=pdfwrite -dBATCH -dNOPAUSE -dQUIET -dCompatibilityLevel=1.7 \
  -sUserPassword=open-seek -sOwnerPassword=test-owner -dEncryptionR=3 \
  -dKeyLength=128 -sOutputFile=encrypted.pdf two-pages.pdf
```

`single-paragraph.docx` and `book1.xlsx` come from the Office Viewer test fixtures.

`review-comments.docx` is a fictional two-page Chinese review document with
three real comments, headers, footers and a table. It covers comment placement
and readable sidebar styles when the body source map is only partially available.

`quarter-sales.xlsx` is the actual fictional quarterly sales demonstration
workbook reported in the XLSX crash. Its two Chinese worksheets contain merged
headings, number formats, and 20 formulas, including cross-sheet references.
