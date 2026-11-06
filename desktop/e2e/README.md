# Desktop end-to-end tests

This Playwright suite builds and mounts the real Desktop browser-console bundle
in Chromium. It replaces only its HTTP and WebSocket data sources; Rabbita
rendering, DOM patching, focus, keyboard, and event handling run in the
browser. The stateful transport fixture also exercises composer send/stop,
conversation creation/archive/restore, host settings, skill installation, and
Codex account login plus first-turn start/stop through their real JSON-RPC
client paths. Its repository snapshot also covers changed-file review,
review progress and navigation, Git Graph keyboard interaction, commit
expansion, and immutable historical diffs.

`mobile_browser.spec.js` runs in Chromium and WebKit to exercise mobile user
workflows and the browser integration shared with the Android client. It needs
no Android build and does not simulate a real phone's soft keyboard or toolbar.

## Setup

From this directory:

```sh
npm ci
npx playwright install chromium webkit
```

## Run

From `desktop/` or this directory (Just finds the parent `justfile`):

```sh
just test-browser
```

The repository root keeps `just desktop-test-browser` as an alias. After the
bundle has been built, `npm test` in this directory runs Playwright alone.

CI and local `just test-browser` build with
`node package/build.mjs browser --release` from `desktop/`. The smaller bundle
keeps mocked resource responses below Chromium's 100 MiB DevTools pipe limit;
large debug bundles can exceed it after base64 encoding. Both use the same
static-server script compiled for native release to avoid Wasm transfer overhead.

CI runs the browser tests in the official Playwright image, which includes
Chromium, WebKit, and their system dependencies. Keep `PLAYWRIGHT_IMAGE` in
`.github/workflows/desktop.yml` at the same version as `@playwright/test` in
`package.json` and `package-lock.json`. The frontend build and native static
server stay on the Ubuntu runner; the container reuses that server through
the host network, so it needs no MoonBit or C toolchain installation.

Locate controls by stable IDs, action keys, or domain identity. Scope role
locators to the owning component without matching translated names. Add a small
stable data attribute when the component has no suitable identity; avoid menu
positions and wording that includes descriptions, counts, or shortcuts.

Check visibility independently of content. When a scenario tests rendered
content, translations, or an accessible name, locate the target first and
assert that content explicitly. Keep fixture values such as paths and session
IDs separate from product copy. Mock
network traffic with Playwright routes and use retrying assertions instead of
fixed sleeps.

Import `test` and `expect` from `tests/support/test.js`. Its pages run with CSS
transitions and animations disabled, so clicks do not wait for moving targets.
Use `{ tag: '@motion' }` only when a workflow needs animations enabled.

## Suite scope

Keep E2E cases for browser integration: event wiring, focus, selection, real
rendering, transport ownership, and complete user workflows. Exercise state
transition permutations in the existing model tests. Before adding a browser
case, identify the integration failure that existing model and E2E tests miss.

Use representative combinations when theme, viewport, renderer, or error
variants share the same implementation. Keep extra variants when they exercise
a distinct integration path or reproduce a browser-specific regression.

Do not add layout E2E cases or layout assertions: alignment, spacing, dimensions,
overflow, responsive breakpoints, and theme styling are outside this suite.
Do not test RUI's generic menu, popover, keyboard wrapping, dismissal, or focus
return behavior here. Keep application workflows and their observable results.
Coordinates needed to perform dragging or text selection are interaction inputs;
scroll-position preservation and selected content remain workflow behavior.
Avoid assertions that only memorialize a removed control or feature.

## Offline interactive answers

The artifact runner compiles the Rabbita starter and runs four standalone
component cases plus five state/composer flows. Six file-preview cases use a
self-contained HTML fixture. Run `npm run test:artifact-offline` or
`just desktop-test-artifacts`.

For explicit live-model acceptance, see `tests/integration/README.md`. Given its generated page, `OPENSEEK_LIVE_COMPONENT_HTML=... node --test desktop/e2e/artifact-generation-live.test.mjs` independently tests the retained source and browser behavior. Set `OPENSEEK_LIVE_SELECTION_OUT` to capture a selected state for the live follow-up check. Live calls stay outside offline CI.

## Offline file artifacts

Run `npm run test:artifact-offline` to build the production frontend and exercise
self-contained HTML previews with fixture transport in a headless browser.
Set `OPENSEEK_UI_CAPTURE_DIR` for local captures. From the repository root, run
`node desktop/e2e/run-artifact-offline.mjs`.
