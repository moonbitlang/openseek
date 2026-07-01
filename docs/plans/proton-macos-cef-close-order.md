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
  request a forced CEF browser close, detach the browser view, clear native
  AppKit references, remove pending bridge requests for that browser, and wake
  the runtime wait source. Keep the CEF browser reference alive until
  `on_before_close` reports completion; that callback marks the Proton window
  closed, removes any remaining pending bridge requests for that browser,
  releases the browser reference, and wakes the runtime wait source.
- Keep CEF `on_before_close` as a supported browser cleanup path, but do not
  require it as the only signal that a Proton window has closed.
- Keep normal CEF shutdown aligned with merged PR #30: runtime destroy always
  calls `cef_shutdown()` through the native shutdown helper, and the helper does
  not unload the CEF framework as part of normal shutdown.
- Make `proton_window_close` request an engine close instead of destroying the
  engine window synchronously; registry invalidation happens when the runtime
  sync observes the engine window closed.
- When deferred macOS browser creation runs after the AppKit run loop starts,
  create the CEF browser at `about:blank` first and load the saved
  `initial_url` only after the browser id is registered to the Proton window.
  This avoids an initial `proton://app/` navigation reaching the scheme handler
  before the browser-to-window lookup is available.
- Preserve OpenSeek's existing `proton://` HTML asset resource handler and
  `load_html_with_assets` behavior.
- Mark packaged macOS CEF helper apps as `LSUIElement` agents so they are not
  relaunched as standalone app-like bundles during main-app termination.

This follows the merged upstream direction in `moonbit-community/lepus#30`,
adapted on top of the local OpenSeek asset-serving changes. The earlier
CEF-owned Alloy window experiment closed processes correctly but showed or
risked Chromium window chrome, so it is replaced by this AppKit-owned
lifecycle.

## Target Files

- `desktop/lepus/native/src/engine/cef_mac/proton_engine_cef_mac.m`
- `desktop/lepus/proton/prebuilt/darwin-arm64/lib/libproton.dylib`
- Outer submodule pointer in `desktop/lepus`
- `desktop/package/macos/main.mbt`
- `desktop/package/macos/main_wbtest.mbt`

## API Diff

No MoonBit public API change is expected. No generated `.mbti` change should be
required.

Native-only internal behavior changes:

- split browser release from public window closed marking
- add macOS close-state flags for AppKit/CEF coordination
- add native window ids and pending browser creation so browser creation happens
  after the main run loop starts pumping
- make deferred macOS browser creation start at `about:blank`, then load the
  pending Proton URL after browser registration
- remove pending bridge requests in `windowWillClose` before forcing browser
  close
- mark packaged macOS CEF helper apps as `LSUIElement` agents so
  LaunchServices does not relaunch them as standalone apps during main-app
  termination
- restore the AppKit `NSWindowDelegate` close bridge
- remove the CEF-owned top-level Alloy window path
- avoid marking `window.closed` directly from `window_close()`
- make `proton_window_close` request close on engine-backed windows instead of
  calling destroy directly
- remove the local `runtime_destroy()` special case that skipped
  `cef_shutdown()` when AppKit app termination had been requested
- keep CEF framework unload out of the normal shutdown helper
- add `LSUIElement=true` to generated helper Info.plist files; this is a
  packaging metadata change only and should not affect MoonBit public
  interfaces

## Open Questions

- Manual packaged-app smoke is still required because close behavior depends on
  macOS AppKit and CEF process lifecycle.

## Latest Checkpoint

PR #30 was merged into `moonbit-community/lepus`, but the packaged desktop app
still crashed on window close when it used the merged prebuilt darwin arm64
`libproton.dylib` artifact. Replacing only the generated app bundle's
`libproton.dylib` with the local native rebuild from the same merged source made
the close-button smoke test exit cleanly. The accepted follow-up fix is to
refresh the darwin arm64 prebuilt `libproton.dylib` artifact and point OpenSeek
at that lepus submodule commit.

## Next Step

Refresh the lepus prebuilt `libproton.dylib`, rebuild the packaged app, and
verify that app quit leaves neither lingering processes nor a new main-process
or helper crash report.

## Validation Plan

- Run `git diff --check`.
- Run the native Proton CMake build and CTest.
- Verify the native link config.
- Run Proton native MoonBit tests with `PROTON_NATIVE_DIST` pointing at the
  freshly built native dist.
- Build `desktop/package/macos`.
- Verify the app bundle signature.
- Manually close the packaged app and verify the close log, process cleanup,
  and absence of new `openseek-desktop-*.ips` or
  `OpenSeek Desktop Helper-*.ips` crash reports.
