# Transcript Markdown

`markdown_nodes` parses CommonMark and cmark's non-strict extensions, then maps
that AST to Rabbita nodes. It does not use `cmark_html` or insert input HTML.
The renderer owns the semantic mapping; transcript CSS owns presentation.

## Semantic mapping

The mapping covers cmark's current `Block` and `Inline` variants. It preserves
rendered document semantics, not a round-trip representation of Markdown source.
Source locations, whitespace layout, bullet/fence spelling, separator dash counts,
and definition placement are not DOM semantics and are not retained.

| AST content | Rabbita representation |
| --- | --- |
| Paragraphs, headings, quotes, thematic breaks | Corresponding HTML elements; heading levels and supplied IDs are retained. |
| Lists | Ordered/unordered kind, ordered start, item order, nesting, and tight/loose paragraph structure are retained. |
| Task items | Disabled checkboxes retain checked state and the original marker in `data-task-marker`; cancelled content uses `del`. Unknown task markers follow cmark's checked-state policy. |
| Tables | Header/data cells, source row order, `col_count` (including empty trailing cells), and separator-defined alignment are retained. A separator governs the preceding header and subsequent data rows. Alignment is emitted as both a class and `text-align`, independent of a stylesheet. |
| Code | Code text and explicit fence language are retained; the complete supplied info string is available as `data-code-info`. |
| Text, emphasis, strong emphasis, strikethrough, code spans | Text and nested inline structure are retained. Hard breaks use `br`; soft breaks use collapsible whitespace. |
| Links and images | Resolved inline/reference destinations and titles are retained. Image alternate text preserves hard line breaks. An empty link destination remains a link, not a missing definition. |
| Mathematics | TeX text, line breaks, and inline/display intent are retained using math containers, `data-math-display`, and `\(...\)` / `\[...\]` delimiters. Mathematics is not reclassified as code; this package does not install a TeX typesetter. |
| Footnotes | References retain their full custom labels when supplied. Ordinary notes are numbered in first-use order and retain bodies, repeated references, and backlinks. Nested notes share the same reference registry. Unused definitions are not rendered. |
| Definition-only nodes and blank lines | Definitions are resolved through `Doc.defs`; they and blank lines do not create visible blocks. |

Block and inline dispatch are exhaustive matches rather than wildcard fallbacks.
When cmark changes its AST, update this mapping at the same time as the renderer.

## Product and safety policy

These transformations are intentional rather than missing AST support:

- Raw HTML remains escaped, readable text. Unsafe link/image destinations do not
  become navigable or loadable DOM attributes.
- Numeric footnotes use the existing Sources presentation and source actions;
  nonnumeric footnotes do not become source citations. A footnote referenced from
  a note body links to an existing source entry when one is already registered.
- Local file links become application actions when a file opener is supplied.
  Local images use host-backed lazy loading instead of page-relative requests.
- Plain prose additionally recognizes web URLs and positioned file references.
  Link labels and inline code do not undergo that linkification.
- Code fences retain existing syntax highlighting, diagram rendering, copy
  controls, and explicit workspace-file/artifact presentations. Unlabelled code
  keeps the product's default MoonBit highlighting policy.
- A parser/rendering exception falls back to escaped source text so incomplete
  streaming input cannot terminate the transcript render loop.

Footnote fragment IDs are scoped to one rendering, not just the Markdown label:
several messages may contain the same label in one document. Footnote and
backlink anchors bypass Rabbita's application-navigation capture.

## Verification

From the repository root:

```sh
moon check desktop/frontend/markdown --target js --deny-warn
moon test desktop/frontend/markdown --target js
moon info desktop/frontend/markdown
moon fmt desktop/frontend/markdown
```

The package tests do not launch a browser. Actual layout and fragment-navigation
interaction require a focused Desktop browser preview; see
[`desktop/e2e/README.md`](../../e2e/README.md).
