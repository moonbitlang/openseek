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

The page registers it only in a browser, never in the window. Its strings
mirror `frontend/system_notification.mbt`, and live here because a closed
app has no page to format them. `sw.test.mjs` runs it against a fake worker
scope:

```bash
node --test sw.test.mjs
```

A click focuses an open console window and asks its page, with a
`seekmoon.open` message and a reply port, to show the link in place; the
worker navigates the window only when the page does not answer `true`
within a second. With no window open, it opens one.

## Push payload

The relay (moonbitlang/openseek-api) encrypts this JSON with RFC 8291; the
worker and the relay's sender must agree on it:

```json
{"v":1,"kind":"finished","locale":"zh-Hans","url":"/device/d_1/chat/session/s1",
 "device_name":"MacBook","status":"finished","answer":"…"}
{"v":1,"kind":"approval","locale":"en","url":"/device/d_1/chat/session/s1",
 "device_name":"MacBook","tool":"mbtx","detail":"…"}
{"v":1,"kind":"cloud_finished","locale":"en","url":"/cloud/session/c1",
 "status":"completed","answer":"…"}
{"v":1,"kind":"test","locale":"en","url":"/cloud"}
```

- `locale` is the subscription's stored tag, one of the `@i18n.Locale::tag`
  values: `en`, `zh-Hans`, `zh-Hant`, `ja`, `es`. Anything else reads as
  `en`.
- `url` is a root-relative application path, resolved against the worker's
  origin. It is also the notification `tag`, so a newer push about the same
  conversation replaces the older one.
- `answer` is optional; without it the body is the fallback text.
- `status` is the host's run status for `finished`: `finished`,
  `max_steps_exhausted`, or anything else, which reads as failed. For
  `cloud_finished` it is Cloud's `completed` or `failed`.
- A payload the worker cannot parse still shows a generic "SeekMoon"
  notification: iOS revokes subscriptions whose pushes show nothing.

The host side of `finished` and `approval` is the `notify` control frame in
`docs/remote-protocol.md`.

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
