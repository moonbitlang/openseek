# Browser Tests

Playwright coverage for behavior that needs a real browser. The complete
harness split and commands live in `docs/harness.md`; this file contains only
browser-suite authoring contracts.

## Suites

```text
support/    Playwright fixtures, app helpers, logging, reporter
smoke/      user workflows against the workbench or embedded viewer
component/  Playwright drivers/assertions for direct MoonBit scenarios
moonbit/    js-target scenario libraries plus the single runner executable
```

`just test-browser-smoke` is the routine browser-correctness gate and runs both
the `smoke/` and `component/` directories.

- Smoke tests prefer real gestures and visible outcomes. Use helpers from
  `support/app.js`; do not call deterministic state-control globals when a
  user path exists. Workbench files are selected through the sidebar and
  remote protocol—the active document is not URL state.
- Component cases open the shared `/browser-tests/runner.html?scenario=<id>`
  page. The selected MoonBit scenario constructs the public Viewer or focused
  browser fixture and reports compact JSON through
  `__readonlyEditorBrowserTestReport`. Playwright validates the report,
  visible state, and feature-specific browser contracts and owns final
  pass/fail. The shared harness records console messages and fails a passing
  test if it observed a console error, uncaught page error, failed request, or
  HTTP response at status 400 or above.
- The `diff-editor-lifecycle` scenario exposes
  `__diffEditorLifecycleControls.set_scroll_left` for MultiDiff host writes.
  `horizontal-original`, `horizontal-modified`, and `horizontal-equal` select
  unwrapped model pairs. Run `playwright test
  tests/browser/component/diff_editor_lifecycle.spec.js --grep 'shared horizontal
  scroll'` to check asymmetric clamping and repeated/reversed host offsets.
- Every component case must state a browser-only contract. Headless Viewer
  tests own model, view-model, contribution, provider, cancellation, and
  event-order state. Component Playwright owns attachment, node ownership,
  frame scheduling, and behavior that requires Chromium layout, CSS, native
  input/focus, DOM Range, iframe ownership, or a native animation frame. Root
  Viewer integration tests do not install a fake DOM or create an intermediate
  mounted white-box layer.
- The `base-browser` runner scenario is the real-DOM owner for
  `editor/base/browser`: it covers iframe-owned focus, text-node event ancestry,
  native Selection endpoints, pointer capture, owning-window fallback, and
  monitor lifecycle. Keep deterministic animation-frame state in MoonBit unit
  tests; do not reintroduce object-literal DOMs or replace browser globals.
- The `browser-geometry` runner scenario is the fixed geometry oracle: it embeds
  tiny self-owned monospace and proportional TTF data URLs, awaits
  `document.fonts.ready`, and runs at deviceScaleFactor 1. Its Playwright suite
  compares public Viewer dimensions/positions with DOM Ranges and rendered
  line/widget boxes within the plan's 1 CSS px tolerance. A test-hosted JS
  probe receives package-private callbacks without adding MoonBit API, then
  exercises the real ContentWidgets renderer in a same-origin iframe whose
  scroll and viewport deliberately differ from the top window. Assertions
  cover owner-document mounting, overflowing page layout and its 15px/22px
  boundaries, plus focused-widget parking while its anchor is hidden.
- The `markdown-document` runner scenario mounts two public Viewers over shared
  services and an ordinary `.mbt.md` model. The suite uses real
  Range-derived `page.mouse` positions over semantic nested fence text; it
  never bypasses presentation routing or caret mapping through a test control.
  `__markdownDocumentControls` performs model replacement through public
  `Viewer::set_model`, releases deterministic async provider gates, mutates
  fixture inputs, and exposes readback. Assertions cover
  original model identity/URI/revision, 1-based provider positions, 0-based
  wire offsets, returned ranges, diagnostic projection, unsafe pointer zones,
  independent Viewer owners, and stale completion rejection across
  pointer/content/theme/model/disposal boundaries.
- Markdown-comment lifecycle, same-key reconciliation, delayed renderer
  invalidation, attachment counts, viewport behavior, and diagram rendering
  are covered by the five retained real-browser contracts. The browser fixture
  exposes only the source/theme/size/input controls those contracts need.
- The `markdown-feedback` scenario mounts a public `MarkdownViewer` with the
  host-owned feedback service. Native DOM selections inside emphasis, across
  paragraphs, and in lists/tables/code/images are checked against persisted
  source ranges and Markdown text. Real mouse release opens the composer
  directly without taking focus; keyboard shortcuts, draft retargeting,
  dismissal, selection-direction positioning, and first-display sizing follow
  the code feedback contract. It also verifies Add/Apply routing, keeps drafts
  anchored while scrolling, and discards drafts after content changes or
  same-URI model replacement. Controls only change fixture models and read host
  feedback; tests do not provide mappings.
- `smoke/viewer.spec.js` opens `README.md` and `src/literate.mbt.md` from the
  deterministic workspace fixture through the sidebar and native protocol.
  The host supplies unchanged URI-backed models; the Viewer alone selects
  Markdown, and the `.mbt.md` pointer reaches native `moon ide hover`.
  `smoke/embed.spec.js` proves the same selection through the in-memory
  standalone embed with no workbench, remote protocol, or WebSocket.
## Stable selectors and observability

- Shell: `.editor-shell` with `data-status`, `data-theme`, `data-line-count`,
  and `data-source-uri`.
- Tree rows: `.workspace-sidebar [data-workspace-id]` with
  `data-workspace-kind`, `aria-expanded`, and `aria-selected`.
- Viewer: `.monaco-editor.readonly-editor` and `.view-line[data-line]`.
- Markdown presentation:
  `.moonbit-viewer-markdown-document`,
  `.moonbit-viewer-markdown-document-viewport`,
  `.moonbit-viewer-markdown-document-article`, and
  `.moonbit-viewer-markdown-document-overlays`. Source-bearing semantic rows
  use `[data-markdown-code-line]` under a
  `[data-markdown-code-block][data-markdown-semantic="moonbit-check"]`.
  Diagnostics use `.moonbit-viewer-markdown-diagnostic`; the retained widget
  uses `.moonbit-viewer-markdown-hover-widget` and records accepted original
  model/source/wire/range facts in `data-markdown-hover-*` attributes.
- Definition navigation: a dedicated public-Viewer fixture drives plain clicks,
  Ctrl/Cmd definition links, goto, and Alt+F12 Peek with trusted browser input.
  Retained cases cover the HTML context menu, exact modifier-link gesture,
  F4/Shift+F4/Escape inside shared Peek, and semantic-Markdown navigation,
  overlay, focus, and replacement teardown. Request identity, query counts,
  leases, cancellation, controller isolation, empty results, and provider
  ordering live in the owning white-box suites.
- Product observability: `__readonlyEditorEvent`, `__readonlyEditorModel`,
  `__readonlyEditorDocument`, and `__readonlyEditorSource`. Copy assertions
  observe the real `ClipboardEvent.clipboardData` or browser clipboard.
- Reporter callback: `__readonlyEditorBrowserTestReport`; the Playwright
  reporter stores received payloads in `__readonlyEditorBrowserTestReports`.

MoonBit scenarios are ordinary libraries statically imported by
`tests/browser/moonbit/runner`, the suite's only executable. The staging script
writes exactly `runner.html`, `runner.mjs`, and `runner.mjs.map` under
`web/dist/browser-tests/`. Every Playwright `test()` still receives its own
fresh browser context and page; sharing the HTML and executable does not share
DOM, globals, storage, or scenario state between cases. A report has the shape
`{"suite":"viewer_api","status":"passed","failures":[],"metrics":{}}`.

Markdown diagnostic overlays assert the live resolved class/range/z-index
policy and `showUnused` underline. They intentionally do not claim Code's
`squiggly-inline-unnecessary` opacity or
`squiggly-inline-deprecated` strike-through: those effects mutate source
glyphs and are explicitly deferred for the readonly Markdown projection.

`support/test.js` writes `runner.log` and a failure screenshot. Its page
listeners make unexpected console/page/request/HTTP errors fail the current
test instead of leaving a green run with a noisy log. Playwright retains traces
and screenshots on failure, and component reporters attach compact JSON evidence under
`test-results/browser/**`. Set `READONLY_EDITOR_TEST_VERBOSE=1` or
`PW_VERBOSE=1` to mirror logs to the terminal.

The current monorepo
[editor workflow](../../../.github/workflows/editor.yml) runs
`just test-browser-smoke` but does not upload `test-results/**`. CI traces,
`runner.log`, attached reports, and failure screenshots are therefore not
downloadable after the job finishes.
