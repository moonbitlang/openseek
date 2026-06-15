# Desktop Review: Session Root And Transcript Links

## Goal

Address the two active #56 review threads from the desktop PR:

- Resolve relative `OPENSEEK_SESSION_ROOT` / payload session roots before they
  are reused by both long-running serve engines and one-shot session queries.
- Prevent Markdown transcript links from replacing the OpenSeek app shell in the
  desktop webview.

## Accepted Design

- Normalize any explicit desktop session root through `moonbitlang/x/path`
  `Path::resolve()`. The default home-based session root is already absolute.
- Render Markdown anchors with `target=_blank` and keep
  `rel="noopener noreferrer"`. The app does not currently register Lepus'
  Windows-only shell extension, so a host-level external-open bridge is left for
  a future cross-platform capability.

## Target Files And Surfaces

- `desktop/internal/sessiondirs/store.mbt`
- `desktop/internal/sessiondirs/store_wbtest.mbt`
- `desktop/frontend/markdown/markdown.mbt`
- `desktop/frontend/markdown/markdown_wbtest.mbt`

## API / Interface Diff

No intended public API change. `resolved_session_root` keeps the same signature
and returns an absolute string for explicit relative inputs.

## Open Questions

None for this PR. A future desktop PR can add a cross-platform host command for
opening external links if Lepus grows non-Windows shell support.

## Next Implementation Step

Add a small private path helper for explicit session roots, update link
rendering, and cover both behaviors with focused tests.

## Validation Plan

- `moon -C desktop test internal/sessiondirs`
- `moon -C desktop test --target js frontend/markdown`
- `moon -C desktop fmt`
- `moon -C desktop info`
