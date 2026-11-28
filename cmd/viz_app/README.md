# viz_app — the session visualizer frontend

The browser half of the OpenSeek session visualizer: a
[rabbita](https://github.com/moonbit-community/rabbita) (Elm-architecture)
single-page app, compiled to JavaScript and served by the `inspect` server at
`GET /viz_app.js`. `web/index.html` is the shell that loads the bundle and
provides the `#app` mount point. See `viz/README.mbt.md` for the whole-picture
tour of the three viz pieces and the full run recipe.

## A separate module on purpose

This directory is its own module (`moonbitlang/openseek-viz-app`, a `moon.work`
member), not a package of `moonbitlang/openseek`:

- it keeps the `moonbit-community/rabbita` DOM framework out of the main
  module's dependency set;
- it is js-only (`supported_targets = "js"`), unlike the rest of the
  workspace;
- nothing imports it — the only contract with the rest of the repo is the
  compiled bundle.

The consequence: a plain `moon build` does **not** produce the bundle. Build it
explicitly:

```bash
moon build cmd/viz_app --target js
```

The `inspect` server auto-locates the output under
`_build/js/{release,debug}/build/cmd/viz_app/viz_app.js` (or takes an explicit
`--bundle` path); if the bundle is missing it serves a 404 telling you to run
the command above.

## Structure

The app's files:

- `main.mbt` — mounts the app and issues the initial commands: fetch the
  session listing, install the keyboard shortcuts, the hash-navigation
  listener, and the scroll-position tracker.
- `app.mbt` — the TEA loop (`Model` / `Msg` / `update` / `view`) plus the
  `extern "js"` DOM glue.
- `trajectory_view.mbt` — the run waterfall: the header totals, the kind
  legend, and the rows drawn from `@trajectory.layout_trajectory`. It renders
  positions in percent and nothing else; deciding which span hangs under which
  happens server-side in the `trajectory` package. A row that names a
  background job also carries the way into that job's own `.out` file.
- `job_log.mbt` — the job log a row opens in place: the
  `/api/sessions/<key>/jobs/<job>` reply it reads, what a follow-up page does
  to it, and the words the block draws. The output never comes from the
  session log — the log names the job, the job's file holds the text — so a
  forty-minute job reads without loading its transcript.

Everything is private. The parse + render logic (session text → typed events →
`@html.Html`) lives in the `viz` package. Its parsing and projection rules are
tested headlessly; this package is the browser shell that mounts the resulting
HTML and owns state, fetching, and DOM wiring. Run `just test-browser` from
this directory to build the bundle and use Playwright to verify the mounted
cards, mode and argument toggles, filters, dropped files, URL/scroll restore,
keyboard shortcuts, standalone embedded data, and theme behavior in Chromium.
The repository root exposes the same command as `just viz-test-browser`.

## Data sources

The same `Model` is fed from three places:

1. **Live server** — the read-only JSON API (`/api/sessions` listing,
   `/api/sessions/<key>` envelope, `/api/trajectory/<root>` waterfall, and
   `/api/sessions/<key>/jobs/<job>` for one job's output). Fetch results carry
   the session id they were issued for, so a slow response for a session the
   user already left is discarded instead of clobbering the pane.
2. **Standalone export** — `inspect --export` bakes API responses into
   `window.__OPENSEEK_DATA__`; `fetch_text` consults that embedded map first,
   so an exported page answers its own requests with no server behind it. An
   export carries session logs and run waterflows, not job outputs, so the
   waterfall of an archive offers no `.out` button rather than one that would
   fail on click.
3. **Drag and drop** — a session `.jsonl` dropped anywhere in the window is
   read and rendered entirely client-side; nothing is uploaded.

## URL hash as restorable state

- `s=` — the selected session. Subrun chips are plain `#s=<child id>` anchors;
  a `hashchange` listener turns them into selections. App-initiated hash
  writes use `replaceState`, which never fires `hashchange`, so navigation
  cannot loop.
- `t=` — the run whose waterfall is open (a session id, usually the run's
  root). The page replaces the session pane rather than nesting in it, so it
  survives a selection change; `Back to log` clears the value.
- `v=` — the view mode (`raw` | `model`). An explicit value wins over the
  defaults: a standalone export opens on the raw log, the live viewer on the
  model view.
- `seq=` — the scroll position, maintained by a rAF-throttled scrollspy and
  restored on refresh; scrubber segments jump to their step.

## Keyboard shortcuts

`n` / `p` jump to the next / previous failure, `u` unfolds the current card.
Text-entry targets and modified keys are left alone.

## Theme

Light / Dark / System, applied by setting `data-theme` on `<html>`. `System`
defers to the OS through the stylesheet's `prefers-color-scheme` query, so it
tracks live OS changes without a listener.
