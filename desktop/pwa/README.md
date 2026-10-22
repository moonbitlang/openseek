# Installable web app

These files make the browser console installable as a standalone app (Chrome
and Edge "Install", Android "Add to Home screen", iOS "Add to Home Screen")
and let it receive Web Push. `package/build.mjs` copies the manifest and icons
next to `frontend.js` under `/assets/`, and `index.html` links them by
root-absolute path. `sw.js` goes to the bundle root instead, beside
`index.html`.

The manifest pins the app's identity to origin-absolute locations: `id` and
`scope` are `/`, so every page route stays inside the installed app, and
`start_url` is `/cloud`, the application route that needs no device. Icon `src`
values are relative to the manifest.

## Service worker

`sw.js` only shows pushes and opens the conversation a notification names; it
has no fetch handler and caches nothing. Installing never needed it: current
Chrome installs without one, and iOS Add to Home Screen never did. It is
served at `/sw.js` because a worker's default scope is its own directory, and
`/` covers `/cloud/...` and `/device/...` without a `Service-Worker-Allowed`
header. The local console and the console proxy already serve root bundle
files; openseek-api has its own `/sw.js` route.

The page registers it only in a browser, never in the window. The payload it
reads is the relay's contract in `docs/plans/web-push.md`, and its strings
mirror `frontend/system_notification.mbt`. `sw.test.mjs` runs it against a
fake worker scope:

```bash
node --test sw.test.mjs
```

## Icons

`icon-192.png` and `icon-512.png` render `package/macos/appicon.svg`, the
rounded tile with a transparent margin that desktop launchers show as is.
`icon-maskable-512.png` and `apple-touch-icon.png` render
`icon-full-bleed.svg`, the same glyph on a square edge-to-edge tile. Android
and iOS cut their own shape from it, and the glyph stays inside the maskable
safe zone. After changing either SVG, regenerate the PNGs:

```bash
rsvg-convert -w 192 -h 192 ../package/macos/appicon.svg -o icon-192.png
rsvg-convert -w 512 -h 512 ../package/macos/appicon.svg -o icon-512.png
rsvg-convert -w 512 -h 512 icon-full-bleed.svg -o icon-maskable-512.png
rsvg-convert -w 180 -h 180 icon-full-bleed.svg -o apple-touch-icon.png
```
