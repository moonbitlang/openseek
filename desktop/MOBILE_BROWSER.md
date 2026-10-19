# Mobile browser client

The browser console uses the same frontend as Desktop. Its responsive styles
live in `styles/responsive.css`; account/device entry and conversation UI do not
require Android classes, an APK, or an Android build.

On the console service, `/cloud` opens Cloud Chat independently of a connected
computer, and a page opened without a device lands there. A connected
computer's pages live under `/device/<id>/`. GitHub sign-in uses the normal
browser account flow and preserves the page-local return path.

## Local build and checks

From the repository root:

```sh
npm ci --prefix desktop/e2e
moon -C desktop run package/browser --target native
python3 -m http.server 53417 --bind 127.0.0.1 --directory desktop
```

The static preview is at `http://127.0.0.1:53417/dist/browser/index.html`; the
page then moves itself to `/cloud`. A static server only supplies frontend
assets, so reloading an application path such as `/cloud` or `/device/<id>/…`
needs the console service (or the browser tests' fixtures), as do real login,
Cloud and Connect. The browser tests use demo account,
Cloud and device responses against the real packaged web assets:

```sh
OPENSEEK_DESKTOP_BROWSER_BASE_URL=http://127.0.0.1:53417 \
  desktop/e2e/node_modules/.bin/playwright test \
    --config desktop/e2e/playwright.config.js \
    console_entry.spec.js console_disconnect.spec.js mobile_browser.spec.js \
    --project chromium --project webkit-mobile
```

The mobile layout suite runs in Chromium and WebKit. It checks 320, 360 and
393-pixel widths, landscape, reduced viewport height, the sidebar drawer,
Cloud without a device, send/stop/reconnection, retained drafts and bounded
long errors. It leaves file and terminal features available. Shared toolbar
controls keep their existing dimensions. On narrow screens, error notices sit
below the header so a failed send leaves its restored draft visible.

Reduced viewport height is a layout simulation, not proof of a real phone's
soft keyboard or browser toolbar behavior. Real GitHub credential entry and
native Android authentication are separate from fixture browser coverage.
