# Transcript Markdown

## Safety and compatibility constraints

- Raw HTML remains escaped, readable text. Unsafe link/image destinations do not
  become navigable or loadable DOM attributes.
- Numeric footnotes use the existing Sources presentation and source actions;
  nonnumeric footnotes do not become source citations.
- Local file links become application actions when a file opener is supplied.
  Local images use host-backed lazy loading instead of page-relative requests.
- A parser/rendering exception falls back to escaped source text so incomplete
  streaming input cannot terminate the transcript render loop.

Footnote fragment IDs are scoped to one rendering, not just the Markdown label:
several messages may contain the same label in one document. Footnote and
backlink anchors bypass Rabbita's application-navigation capture.
