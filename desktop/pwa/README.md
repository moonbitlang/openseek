# Installable web app

These files make the browser console installable as a standalone app (Chrome
and Edge "Install", Android "Add to Home screen", iOS "Add to Home Screen").
`package/build.mjs` copies them next to `frontend.js` under `/assets/`, and
`index.html` links them by root-absolute path. Every host already serves that
prefix, so no server route is involved.

The manifest pins the app's identity to origin-absolute locations: `id` and
`scope` are `/`, so every page route stays inside the installed app, and
`start_url` is `/cloud`, the application route that needs no device. Icon `src`
values are relative to the manifest.

There is no service worker yet. Current Chrome installs without one, and iOS
Add to Home Screen never needed one. Web Push will add it, at a root path, so
its scope can cover every application route.

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
