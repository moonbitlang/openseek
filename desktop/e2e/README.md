# Desktop end-to-end tests

This Playwright suite builds and mounts the real Desktop browser-console bundle
in Chromium. It replaces only its HTTP and WebSocket data sources; Rabbita
rendering, DOM patching, focus, keyboard, layout, and event handling run in the
browser. The stateful transport fixture also exercises composer send/stop,
conversation creation/archive/restore, host settings, skill installation, and
Codex account login plus first-turn start/stop through their real JSON-RPC
client paths. Its repository snapshot also covers changed-file review,
review progress and navigation, Git Graph keyboard interaction, commit
expansion, and immutable historical diffs.

Two question-card layout flows also run in WebKit to cover Safari's grid
sizing, clipping, and narrow-viewport interaction. Shared question state and
protocol cases run in Chromium and model tests.

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

CI builds with `node package/build.mjs browser --release` from `desktop/` so
each fresh page loads the smaller production bundle. Local `just test-browser`
keeps the debug bundle for diagnosis. Both use the same static-server script
compiled for native release to avoid Wasm transfer overhead.

Prefer accessible roles, labels, and visible text. Use classes only for
product DOM whose presentation contract is itself under test. Mock network
traffic with Playwright routes and use retrying assertions instead of fixed
sleeps.

## Suite scope

Keep E2E cases for browser integration: event wiring, focus, selection, real
rendering, transport ownership, and complete user workflows. Exercise state
transition permutations in the existing model tests. Before adding a browser
case, identify the integration failure that existing model and E2E tests miss.

Use representative combinations when theme, viewport, renderer, or error
variants share the same implementation. Keep extra variants when they exercise
a distinct integration path or reproduce a browser-specific regression.

Avoid checks that only memorialize a removed control or feature, or pin icon
paths, decorative pixel dimensions, alignment, and theme colors. Keep layout
checks tied to observable behavior such as clipping, reachability, or scrolling.
