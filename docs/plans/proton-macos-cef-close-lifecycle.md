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
  AppKit references, remove pending bridge requests for that browser, and wake
  the runtime wait source. Keep the CEF browser reference alive until
  `on_before_close` reports completion; that callback marks the Proton window
  closed, removes any remaining pending bridge requests for that browser,
  releases the browser reference, and wakes the runtime wait source.
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
- Mark packaged macOS CEF helper apps as `LSUIElement` agents. Without that
  metadata, LaunchServices can relaunch a helper bundle as a standalone app
  during main-app termination; that helper has no CEF subprocess arguments and
  traps inside `cef_execute_process`.

This follows the merged upstream direction in `moonbit-community/lepus#30`,
adapted on top of the local OpenSeek asset-serving changes.

## Target Files And Surfaces

- `desktop/lepus/native/src/engine/cef_mac/proton_engine_cef_mac.m`
- `desktop/lepus/proton/prebuilt/darwin-arm64/lib/libproton.dylib`
- `desktop/package/macos/main.mbt`
- `desktop/package/macos/main_wbtest.mbt`

## API / Interface Diff

- No MoonBit public API changes are intended.
- No generated `.mbti` changes are expected.
- Native macOS close behavior changes from waiting primarily on CEF
  `on_before_close` alone to using AppKit `windowWillClose` as the native close
  boundary while still retaining CEF browser ownership until `on_before_close`.
- Native macOS initial loading changes from creating the browser directly at the
  pending Proton URL to creating `about:blank` first and navigating after
  browser registration.
- Native macOS close handling drops pending bridge requests as soon as
  `windowWillClose` runs, so bridge dispatch cannot keep the app alive after
  AppKit has entered final window close.
- The packaged helper app Info.plist gains `LSUIElement=true`; this is bundle
  metadata only and does not change the MoonBit or native Proton API.

## Open Questions

- Manual packaged-app smoke is still required because close behavior depends on
  macOS AppKit and CEF process lifecycle.

## Latest Checkpoint

PR #30 was merged into `moonbit-community/lepus` as commit `7824def`, but the
packaged desktop app still crashed on window close when it used the merged
prebuilt `proton/prebuilt/darwin-arm64/lib/libproton.dylib` artifact
(`06f4...`). The crash report was for the main `openseek-desktop` process, not
the helper, and showed `EXC_BAD_ACCESS / SIGBUS` on the `CrBrowserMain` thread
under `proton_engine_runtime_destroy -> proton_runtime_destroy`.

As a control, replacing only the generated app bundle's `libproton.dylib` with
the local native rebuild from the merged PR #30 source (`562c...`) made the same
close-button smoke test exit cleanly with no new main-process or helper crash
report. The accepted follow-up fix is therefore to refresh the lepus darwin
arm64 prebuilt `libproton.dylib` artifact from the final PR #30 source, then
point OpenSeek's submodule at that lepus commit.

## Next Implementation Step

Refresh only `desktop/lepus/proton/prebuilt/darwin-arm64/lib/libproton.dylib`
from the locally rebuilt `desktop/lepus/native/dist/lib/libproton.dylib`, commit
that artifact update in the lepus submodule, update the outer OpenSeek
submodule pointer, and rerun the packaged-app close validation.

## Validation Plan

- Run `git diff --check`.
- Build and install the native Proton library for macOS from the merged PR #30
  source.
- Run native CMake smoke tests and Proton native MoonBit tests.
- Verify the refreshed prebuilt `libproton.dylib` hash matches the native
  rebuild output.
- Rebuild the desktop package so it picks up the updated prebuilt library.
- Verify the packaged app's bundled `libproton.dylib` hash matches the refreshed
  prebuilt artifact.
- Click the packaged app's red close button and verify no new
  `openseek-desktop-*.ips` or `OpenSeek Desktop Helper-*.ips` crash report is
  created.
- Verify no OpenSeek app or helper process remains after close.
