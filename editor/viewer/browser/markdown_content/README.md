# Markdown content styles

`markdown_content.css` supplies shared content presentation for roots carrying
`moonbit-viewer-markdown-content`. Both the Viewer document's cmark HTML and
OpenSeek's AST-to-Rabbita Markdown use it. Renderers retain ownership of semantic
mapping, URL/HTML policy, source attributes, and event handling.

Hosts own root typography, reading measures, viewports, and interaction controls.
They bind `--markdown-*` tokens for host-specific presentation; shared defaults use
Viewer/editor tokens, never OpenSeek tokens. Table overflow belongs to the
renderer-provided table region, not the document or transcript viewport.

Load the shared stylesheet before host overrides. The reference shell includes
it through `scripts/build-web.mbtx`; Desktop uses `frontend/build/viewer.css`.
