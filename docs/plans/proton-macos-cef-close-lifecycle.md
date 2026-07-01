# Proton macOS CEF Close Lifecycle

## Goal

Make the packaged macOS desktop app exit cleanly when the user closes the
window, without showing Chromium top-level window chrome and without leaving
OpenSeek or CEF helper processes running.

## Accepted Design

- Keep Proton as the owner of the AppKit `NSWindow`.
- Keep CEF embedded as the browser child view instead of using a CEF-owned
  top-level window.
- Use an `NSWindowDelegate` to coordinate close requests with CEF through
  `is_ready_to_be_closed`, `try_close_browser`, and `close_browser`.
- Treat AppKit `windowWillClose` as the terminal Proton window lifecycle point:
  request a forced CEF browser close, detach the browser view, clear native
  AppKit references, and wake the runtime wait source. Keep the CEF browser
  reference alive until `on_before_close` reports completion; that callback
  marks the Proton window closed, removes pending bridge requests for that
  browser, releases the browser reference, and wakes the runtime wait source.
- Keep CEF `on_before_close` as a cleanup path, but do not require it as the
  only signal that a Proton window has closed.
- Make `proton_window_close` request an engine close instead of destroying the
  engine window synchronously; registry invalidation happens when the runtime
  sync observes the engine window closed.
- When macOS browser creation is deferred until the AppKit run loop is pumping,
  create the CEF browser at `about:blank` first, then load the pending
  `initial_url` after the browser id has been registered to the Proton window.
  This prevents the first `proton://app/` navigation from reaching the scheme
  handler before `proton_engine_window_from_browser()` can resolve the window.
- Preserve the existing `proton://` HTML asset resource handler and
  `load_html_with_assets` behavior.

This follows the updated upstream direction in
`moonbit-community/lepus#28` at commit
`c82aa54c4077057b758eca9fefe2838cd8e39867`, adapted on top of the local
OpenSeek asset-serving changes.

## Target Files And Surfaces

- `desktop/lepus/native/src/engine/cef_mac/proton_engine_cef_mac.m`
- `desktop/lepus/proton/prebuilt/darwin-arm64/lib/libproton.dylib`

## API / Interface Diff

- No MoonBit public API changes are intended.
- No generated `.mbti` changes are expected.
- Native macOS close behavior changes from waiting primarily on CEF
  `on_before_close` alone to using AppKit `windowWillClose` as the native close
  boundary while still retaining CEF browser ownership until `on_before_close`.
- Native macOS initial loading changes from creating the browser directly at the
  pending Proton URL to creating `about:blank` first and navigating after
  browser registration.

## Open Questions

- Manual packaged-app smoke is still required because close behavior depends on
  macOS AppKit and CEF process lifecycle.

## Next Implementation Step

Apply the latest PR #28 pending-browser update so deferred macOS browser
creation starts at `about:blank` and then loads the saved initial Proton URL
after browser registration, while preserving the local resource handler and
asset-loading changes.

## Validation Plan

- Run `git diff --check`.
- Build the native Proton library for macOS.
- Run native CMake smoke tests if the build directory is available.
- Rebuild the desktop package so it picks up the updated prebuilt library.
- Ask the user to run the packaged app with `PROTON_NATIVE_LOG=1`, click the red
  close button, and confirm that logs include window close events and that no
  OpenSeek/CEF helper processes remain.
