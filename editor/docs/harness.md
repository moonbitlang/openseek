# Harness

Public Viewer integration behavior has two test layers. Headless MoonBit tests
own state that can be asserted without a browser; real Playwright tests own
DOM, pointer, browser-layout, animation-frame, and full-shell behavior. There
is no fake-DOM mounted Viewer layer between them.

## Commands

```sh
just test                    # MoonBit correctness
just test-browser-smoke      # browser correctness: smoke + component
```

`just test-browser` is an alias for `just test-browser-smoke`.

Focused build and development commands are:

```sh
just build                       # production assets + default Wasm server
just dist-front-end              # production browser assets only
just build-browser-tests         # single browser-correctness scenario runner
just                             # build and serve with repository defaults
just test-browser-component      # direct Viewer subset of browser correctness
just ROOT=. PORT=5173 dev        # build, serve, and print Local/Network URLs
just HOST=127.0.0.1 dev          # explicitly restrict access to loopback
just TARGET=native dev           # opt into the native server backend
just ROOT=~/git/other-repo dev   # browse another MoonBit repo with this viewer
just HOST=0.0.0.0 BROWSE_ROOT=~/git dev  # LAN access scoped to one subtree
just list                        # list every available recipe
```

Playwright owns `http://127.0.0.1:5174` by default and uses the deterministic
`tests/fixtures/workspace`. Set `READONLY_EDITOR_BASE_URL` to target an already
running server explicitly; only that opt-in path may reuse an existing server.
The direct Playwright CLI starts the default Wasm server without rebuilding
assets and assumes the browser bundles have already been staged; use the
`just test-browser-*` recipes when bundle freshness matters.

`just dev` defaults to `HOST=0.0.0.0`: it binds every IPv4 interface and prints
reachable Local and detected Network URLs. Set `HOST=127.0.0.1` (before the
recipe name: `just HOST=127.0.0.1 dev`) to restrict the listener and startup
output to the Local URL. The server target defaults to Wasm; set
`TARGET=native` explicitly when native-host behavior is the subject under test.

`ROOT` selects the repository served at startup. The workbench's **Open
Repository...** picker can re-root the running server without a restart. On a
loopback listener it may browse the host filesystem; on any other bind it is
disabled unless `BROWSE_ROOT` grants one realpathed directory and its
descendants. `ROOT` may be outside that scope, but the picker starts at
`BROWSE_ROOT` and cannot navigate above it. The reusable server API, direct CLI,
and lower-level `just serve` recipe remain loopback-only by default.

**Warning:** the reference server has no authentication and exposes workspace
source files. The default `just dev` launcher is intended only for trusted LANs.

## Test Layers

### MoonBit package tests

Use ordinary tests for DOM-free algorithms and `*_reference_test.mbt` /
`*_reference_wbtest.mbt` for traceable Monaco conformance ports. See
`docs/quality.md` for the reference-test contract.

### Headless Viewer tests

`viewer/test_viewer_harness_wbtest.mbt` provides the package-private fixture;
`viewer/test_viewer_wbtest.mbt` and the owning contribution `_wbtest.mbt`
files use it to construct a real, unattached `Viewer`, install a `TextModel`,
and exercise synchronous model/view-model/cursor/layout state. No browser
`View`, DOM measurement, or animation frame is created.

Useful white-box seams are:

- `with_test_viewer`
- `test_view_model` and `test_cursor`
- `test_window`
- `test_set_soft_wrap_column`
- `test_set_viewport`

Use this layer for positions, selections, wrapping, model/view conversion,
visible windows, scroll/reveal math, decoration inputs, and contribution state.

### Browser suites

```text
tests/browser/
  smoke/       real workbench/embed workflows and real pointer input
  component/   direct public-Viewer scenarios reported as compact JSON
  moonbit/     js-target scenario packages
  support/     Playwright fixtures, logging, and reporters
```

The browser-correctness gate runs both `smoke/` and `component/`. Their
directory names describe how they reach the browser surface, not separate
top-level quality gates. Playwright does not retry failed tests locally or in
GitHub Actions: a flaky first attempt is a failed gate, not a green run hidden
behind a fresh worker. Unexpected console errors, page errors, failed requests,
and HTTP responses at status 400 or above also fail the current test.

Every component case must justify why its contract needs Chromium. The retained
surface is limited to real font/Range/iframe geometry, native
keyboard/pointer/copy bridges, context menus and modifier links, folding
gestures, Markdown layout and diagram input, DOM convergence, ViewZone
ownership/geometry/mouse suppression, and small dedicated public-Viewer
contracts. Version and identity matrices, provider cancellation, transaction
ordering, and semantic no-op behavior belong to Headless MoonBit tests.
Attachment, node ownership, render scheduling, and browser-widget lifecycle
belong to Playwright.

Compilation is `moon build`'s job. Browser scenarios are JS-only library
packages statically imported by `tests/browser/moonbit/runner`, the only
browser-test executable, so shared editor dependencies are linked once.
`scripts/build-web.mbtx` assembles the production reference app and embed page,
then owner-adjacent CSS and codicons, under `web/dist`;
`scripts/stage_mermaid` adds the pinned, SHA-256-verified local Mermaid ESM
tree. `scripts/build-browser-tests.mbtx` stages the MoonBit scenarios used by
browser correctness as one `runner.html`/`runner.mjs` pair under
`web/dist/browser-tests`. Before staging, the assembler requires the runner and
source map to exist in exactly one of the module-qualified or unqualified
layouts; it rejects ambiguous layouts rather than risking a stale artifact from
a different `moon.work` context. Staging replaces that generated directory, so
obsolete per-scenario pages cannot remain reachable.

Both assemblers stage `editor-code-worker.js` beside the HTML entry. The
production shell and browser-test static routes serve their respective copies;
the worker client resolves its URL against `document.baseURI`. Desktop browser
and macOS package assemblers publish the same artifact beside their frontend
entry. Real Worker timeout/cancellation and prepared default folding scenarios
exercise this deployment contract, as well as model/version freshness.

### Browser scenario ownership

A browser-visible contract normally has two adjacent owners:

- A MoonBit scenario under `tests/browser/moonbit/` constructs the product
  through the appropriate public surface, owns deterministic setup or manual
  provider completion, reports fixture-initialization failures, and emits a
  compact JSON report. It must not reimplement a state machine solely so
  Playwright can inspect it. Keep DOM-free policy and synchronous state-machine
  assertions in ordinary or headless MoonBit tests instead.
- A Playwright spec under `tests/browser/component/` or
  `tests/browser/smoke/` supplies the browser-only evidence: real input, DOM and
  layout observations, host integration, and the final assertions. Use a
  component test for a direct public Viewer and a smoke test when the workbench,
  sidebar, remote protocol, file watching, or host tool adapter is part of the
  behavior.

When adding a scenario package, declare its JS target, export one focused entry
function, then import and dispatch it from `tests/browser/moonbit/runner` under
a stable scenario id. Playwright opens that id through
`gotoBrowserScenario`; its default fixture creates a fresh context and page for
every case. Keep scenario ids, selectors, globals, and focused-run instructions
in `tests/browser/README.md` or the owning package README. Keep feature behavior
in the owning package docs and focused tests; do not grow a feature-by-feature
catalog in this cross-cutting harness guide.

## Browser Rules

- Smoke tests use the sidebar and remote protocol when testing the workbench;
  the active file is application state, not a URL query/hash.
- Prefer real gestures and visible outcomes. Use deterministic test globals only
  when no user path exists.
- Markdown semantic hover tests derive a point from the rendered text range and
  move `page.mouse` there. Test globals may hold an async provider completion
  or expose readback, but must not bypass caret hit testing, coordinate
  conversion, or presentation routing.
- Use Playwright for caret-API hit testing, measured selection/widget geometry,
  browser event wiring, server/file-watch integration, and screenshots/traces.
- Monaco parity comes from an explicit behavior mapping plus focused
  conformance evidence, not from copying TypeScript representation or relying
  on browser DOM snapshots against Monaco. Source-shaped control flow is
  required only for algorithm-fidelity slices where ordering or arithmetic is
  part of the contract.
- The MoonBit reporter only emits data; Playwright validates the report and
  owns pass/fail.

## Failure Evidence

`tests/browser/support/test.js` writes `runner.log` and a failure screenshot;
the Playwright configuration retains failure traces and screenshots under
`test-results/browser/**`. Component suites also attach their JSON
reports. Shared listeners record console messages, uncaught page errors, failed
requests, and HTTP responses at status 400 or above for diagnosis. If the test
body otherwise passes, any of those events still fails the test at fixture
teardown so a green result cannot hide a browser or network failure. Set
`READONLY_EDITOR_TEST_VERBOSE=1` or `PW_VERBOSE=1` to mirror logs to the terminal.

The current monorepo [editor workflow](../../.github/workflows/editor.yml) runs
the browser gate but does not upload `test-results/**` as CI artifacts. Traces,
`runner.log`, attached reports, and failure screenshots are therefore local to
the CI job rather than downloadable after it finishes.

Package globals, selectors, and scenario-authoring details live in
`tests/browser/README.md`.
