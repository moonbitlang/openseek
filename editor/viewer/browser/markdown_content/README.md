# Markdown content styles

`markdown_content.css` owns host-neutral content presentation for roots carrying
`moonbit-viewer-markdown-content`. Both the Viewer document's cmark HTML and
OpenSeek's AST-to-Rabbita Markdown use it. It does not change either renderer,
URL/HTML policy, source attributes, or event handling.

The shared rules cover headings, paragraphs, lists, quotes, inline/fenced code,
tables, links, images, tasks, and footnotes. Table alignment consumes cmark's
`left` / `center` / `right` cell classes. A `[role="region"]` with a direct table
child owns horizontal overflow and outer spacing, including inside lists and
quotes. Tables prefer the region width and use automatic, content-dependent
column sizing rather than equal-width columns. Long text and URLs wrap; cells
retain a minimum width of `8ch`, so dense tables can still
overflow and scroll instead of squeezing every column into unreadable slivers.

Hosts retain root typography, reading/figure measures, document/stream viewports,
folding, overlays, code-copy controls, diagrams, file actions, and Sources cards.
They supply `--markdown-*` tokens on the content root for palette and density:

- `paragraph-margin`, `block-margin`, `heading-margin`, `list-margin`,
  `list-item-margin`, and `rule-margin` control spacing.
- `heading-size` / `heading-line-height` optionally flatten the default document
  hierarchy for compact surfaces.
- `quote-*`, `code-*`, `inline-code-*`, `border`, `cell-padding`, `cell-min-width`,
  `link-color`, and `note-*` adapt presentation to the host. Every name has the
  `--markdown-` prefix; stylesheet fallbacks use Viewer `--vscode-*` and editor
  font tokens, never OpenSeek tokens.

Document-level outer cadence remains in `markdown_document.css`. Desktop binds
its compact palette/density in `styles/transcript.css`; Skills and GitHub keep
their existing surface-specific overrides. Plain transcript text is not enrolled.

The reference shell's `scripts/build-web.mbtx` and Desktop's
`frontend/build/viewer.css` both include this stylesheet before host rules.
CSS bundling checks syntax and import resolution only; layout, themes, horizontal
scrolling, and fragment navigation still require a focused browser preview.
