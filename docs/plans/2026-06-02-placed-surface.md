# PlacedSurface viewport refactor

## Goal

Reduce repeated `Surface + top` parameter passing in `tui/internal/viewport` by introducing a private type for a surface after terminal placement.

## Accepted design

- Add a private `PlacedSurface` in `tui/internal/viewport/surface_placement.mbt`.
- Shape: `surface : @surface.Surface` plus `top : Int`.
- Do not store `height`; use `surface.height()` so placement cannot diverge from the surface content.
- Keep `@geometry.Geometry` for terminal row regions and stale footprints where no trusted surface content exists.
- Split redraw of placed surfaces into separate cached and uncached paths: one function receives an old `PlacedSurface` and diffs rows/cursor, the other handles stale/unknown content by repainting the redraw span.
- Inline redraw span calculation in both placed-surface redraw helpers instead of calling `@geometry.calculate_redraw_span`.
- Match `FrameCache` directly in `Viewport::redraw`, removing `FrameCache::footprint`; cached redraw derives its old footprint from the old `PlacedSurface`, while stale redraw still receives the remembered `Geometry`.
- Add labels to public calls where positional arguments are easy to confuse: `Viewport::replay_scrollback(..., scrollback~, surface~)`, `@geometry.clamp_height(..., height~)`, and `@geometry.clamp_top(..., height~, top~)`.
- Lift terminal auto-wrap disable/enable out of per-line drawing and into live viewport redraw batches. Scrollback insertion keeps normal auto-wrap behavior because it writes transcript rows plus `\r\n` through the terminal's scroll region.
- Move terminal size reading out of `viewport`: `@terminal_size.read(@tty.Tty)` owns querying and normalizing the current terminal dimensions, while `Viewport` only consumes `TerminalSize`.

## Target files/surfaces

- `tui/internal/viewport/surface_placement.mbt`
- `tui/internal/viewport/viewport.mbt`
- `tui/internal/terminal_size/terminal_size.mbt`
- `tui/internal/terminal_size/moon.pkg`
- Potentially `tui/internal/viewport/frame_cache.mbt` and white-box tests if helper signatures change.

## API/interface diff

- No public API change is intended from the `PlacedSurface` refactor itself.
- `PlacedSurface` must remain private and should not appear in `tui/internal/viewport/pkg.generated.mbti`.
- Existing public `Viewport` source methods keep their signatures.
- Validation found an existing mismatch: source exposes `Viewport::replay_scrollback`, while the caller, README, and generated interface still refer to `replay_with_rows_before`. Align those stale references to the current source name so full project checks can run.
- Labelled arguments intentionally update the generated interface for `@geometry.clamp_height`, `@geometry.clamp_top`, and `Viewport::replay_scrollback`.
- Auto-wrap batching is private implementation only and should not change any `.mbti`.
- Add `pub fn read(@tty.Tty) -> TerminalSize` to `internal/terminal_size`.
- Remove `pub fn read_terminal_size(@tty.Tty) -> TerminalSize` from `internal/viewport`.

## Open questions

- Empty `Surface` remains representable; `PlacedSurface` will derive its footprint height from `surface.height()`.

## Next implementation step

Add `@terminal_size.read`, update viewport and UI callers to use it, remove `@viewport.read_terminal_size`, and update README/generated interfaces.

## Validation plan

- Run `moon check`.
- Run `moon test`.
- Run `moon info && moon fmt`.
- Review `pkg.generated.mbti` and git diff to confirm no unintended public API changes.
