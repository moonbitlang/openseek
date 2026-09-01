# Session viewer end-to-end tests

This Playwright suite builds and mounts the real `cmd/viz_app` bundle in
Chromium. It replaces only the viewer's HTTP data source; Rabbita rendering,
DOM patching, filters, theme, layout, and event handling run in the browser.
It covers served and dropped logs, URL/view/scroll restoration, keyboard
navigation, embedded standalone exports, and Light/Dark/System palettes.

## Setup

From this directory:

```sh
npm ci
npx playwright install chromium
```

## Run

From `cmd/viz_app/` or this directory (Just finds the parent `justfile`):

```sh
just test-browser
```

The repository root keeps `just viz-test-browser` as an alias. After the
bundle has been built, `npm test` in this directory runs Playwright alone.

Prefer accessible roles, labels, and visible text. Use classes only for
product DOM whose presentation contract is itself under test. Mock network
traffic with Playwright routes and use retrying assertions instead of fixed
sleeps.
