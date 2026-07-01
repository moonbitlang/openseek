# Proton macOS CEF Close Ordering

## Goal

Make the packaged macOS desktop app close cleanly from the red window button,
without showing Chromium top-level window chrome and without leaving OpenSeek or
CEF helper processes running.

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
- Keep CEF `on_before_close` as a supported browser cleanup path, but do not
  require it as the only signal that a Proton window has closed.
- Keep normal CEF shutdown aligned with upstream PR #28: runtime destroy always
  calls `cef_shutdown()` through the native shutdown helper, and the helper does
  not unload the CEF framework as part of normal shutdown.
- Preserve OpenSeek's existing `proton://` HTML asset resource handler and
  `load_html_with_assets` behavior.

This follows the updated upstream direction in
`moonbit-community/lepus#28` at commit
`d431d163fb4be2f2ef5a6d304bb9d13d2f673fab`, adapted on top of the local
OpenSeek asset-serving changes. The earlier CEF-owned Alloy window experiment
closed processes correctly but showed or risked Chromium window chrome, so it
is replaced by this AppKit-owned lifecycle.

## Target Files

- `desktop/lepus/native/src/engine/cef_mac/proton_engine_cef_mac.m`
- `desktop/lepus/proton/prebuilt/darwin-arm64/lib/libproton.dylib`
- Outer submodule pointer in `desktop/lepus`

## API Diff

No MoonBit public API change is expected. No generated `.mbti` change should be
required.

Native-only internal behavior changes:

- split browser release from public window closed marking
- add a macOS close-state flag for AppKit/CEF coordination
- restore the AppKit `NSWindowDelegate` close bridge
- remove the CEF-owned top-level Alloy window path
- avoid marking `window.closed` directly from `window_close()`
- remove the local `runtime_destroy()` special case that skipped
  `cef_shutdown()` when AppKit app termination had been requested
- keep CEF framework unload out of the normal shutdown helper

## Open Questions

- Manual packaged-app smoke is still required because close behavior depends on
  macOS AppKit and CEF process lifecycle.

## Next Step

Build the desktop macOS package from `haoxiang/file-side-panel`, run it with
`PROTON_NATIVE_LOG=1`, close the app window, and inspect the log/process state.
This pass first aligns local shutdown semantics with upstream PR #28 before
adding any new close workaround.

## Validation Plan

- Run `git diff --check`.
- Run the native Proton CMake build and CTest.
- Verify the native link config.
- Run Proton native MoonBit tests with `PROTON_NATIVE_DIST` pointing at the
  freshly built native dist.
- Build the examples module against the freshly built native dist.
- Run `moon info` and `moon fmt` for the Lepus submodule.
- Build `desktop/package/macos`.
- Verify the app bundle signature.
- Manually close the packaged app and verify the close log and process cleanup.
