# Desktop end-to-end tests

This Playwright suite builds and mounts the real Desktop browser-console bundle
in Chromium. It replaces only its HTTP and WebSocket data sources; Rabbita
rendering, DOM patching, focus, keyboard, layout, and event handling run in the
browser. The stateful transport fixture also exercises composer send/stop,
conversation creation/archive/restore, host settings, skill installation, and
Codex account login plus first-turn start/stop through their real JSON-RPC
client paths.

## Setup

From this directory:

```sh
npm ci
npx playwright install chromium
```

## Run

From `desktop/` or this directory (Just finds the parent `justfile`):

```sh
just test-browser
```

The repository root keeps `just desktop-test-browser` as an alias. After the
bundle has been built, `npm test` in this directory runs Playwright alone.

Prefer accessible roles, labels, and visible text. Use classes only for
product DOM whose presentation contract is itself under test. Mock network
traffic with Playwright routes and use retrying assertions instead of fixed
sleeps.
