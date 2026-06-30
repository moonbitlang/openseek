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
  release the CEF browser reference, clear native AppKit references, mark the
  Proton window closed, remove pending bridge requests for that browser, and
  wake the runtime wait source.
- Keep CEF `on_before_close` as a cleanup path, but do not require it as the
  only signal that a Proton window has closed.
- Preserve the existing `proton://` HTML asset resource handler and
  `load_html_with_assets` behavior.

This follows the updated upstream direction in
`moonbit-community/lepus#28` at commit
`d431d163fb4be2f2ef5a6d304bb9d13d2f673fab`, adapted on top of the local
OpenSeek asset-serving changes.

## Target Files And Surfaces

- `desktop/lepus/native/src/engine/cef_mac/proton_engine_cef_mac.m`
- `desktop/lepus/proton/prebuilt/darwin-arm64/lib/libproton.dylib`

## API / Interface Diff

- No MoonBit public API changes are intended.
- No generated `.mbti` changes are expected.
- Native macOS close behavior changes from waiting primarily on CEF
  `on_before_close` to using AppKit `windowWillClose` as the Proton lifecycle
  boundary.

## Open Questions

- Manual packaged-app smoke is still required because close behavior depends on
  macOS AppKit and CEF process lifecycle.

## Next Implementation Step

Replace the current local macOS close lifecycle implementation with the PR #28
AppKit-owned `NSWindow` lifecycle, while preserving the local resource handler
and asset-loading changes.

## Validation Plan

- Run `git diff --check`.
- Build the native Proton library for macOS.
- Run native CMake smoke tests if the build directory is available.
- Rebuild the desktop package so it picks up the updated prebuilt library.
- Ask the user to run the packaged app with `PROTON_NATIVE_LOG=1`, click the red
  close button, and confirm that logs include window close events and that no
  OpenSeek/CEF helper processes remain.
