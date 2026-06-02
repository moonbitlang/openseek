// Pure geometry for placing the live input viewport on the terminal.
//
// Coordinate model (all rows 1-based, matching ANSI cursor addressing):
//
//   row 1          ─┐
//   ...             │  scrollback: committed transcript, owned by the
//   top - 1         ─┘  terminal's native scroll history (above the live area)
//   top            ─┐
//   ...             │  live area: `height` rows redrawn in place by the app
//   top+height-1   ─┘  (this row is `bottom`)
//   ...                blank rows below the live area, if any
//   size.rows()        last on-screen row
//
// `top` is the terminal row where the live area starts, `height` how many rows
// it occupies, and `bottom = top + height - 1`. The live area must fit on
// screen, so `top` is clamped to `calculate_max_top` — the lowest start row that
// still leaves `height` rows above `size.rows()`.
//
// Every function here is total and side-effect free: results are clamped into a
// drawable range so the viewport never has to re-validate geometry. They take an
// already-normalized `@terminal_size.TerminalSize`, so screen dimensions are always
// positive; only the app-chosen `top`/`height` are clamped here.

///|
/// A rectangular block of terminal rows: 1-based start row `top` and row count
/// `height` (so `bottom = top + height - 1`).
///
/// Used for the live area's current placement — which additionally satisfies the
/// viewport invariant `1 <= height <= size.rows` and `1 <= top <= max_top` — and
/// for a previous frame's footprint, which is the same shape but may predate a
/// resize. The type itself enforces no invariant; it is just a row region.
struct Geometry {
  top : Int
  height : Int
}

///|
/// Build a row region from a start row and a height.
pub fn Geometry::new(top~ : Int, height~ : Int) -> Geometry {
  { top, height }
}

///|
/// 1-based start row of the region.
pub fn Geometry::top(self : Geometry) -> Int {
  self.top
}

///|
/// Number of rows the region spans.
pub fn Geometry::height(self : Geometry) -> Int {
  self.height
}

///|
/// Bottom-most row the region occupies (`top + height - 1`).
pub fn Geometry::bottom(self : Geometry) -> Int {
  self.top + self.height - 1
}

///|
/// Clamp a desired live-area height into `1 ..= size.rows()`.
pub fn clamp_height(size : @terminal_size.TerminalSize, height~ : Int) -> Int {
  height.clamp(min=1, max=size.rows())
}

///|
/// The lowest the live area's `top` may sit and still fit entirely on screen,
/// floored at row 1 when the live area is taller than the screen.
///
/// This is just `bottom <= size.rows()` solved for `top`. The live area spans
/// `top ..= top + height - 1`, so requiring its last row to land on or above the
/// last physical row gives:
///
///   top + height - 1 <= size.rows()   ⟺   top <= size.rows() - height + 1
///
/// Clamping `top` to this bound therefore guarantees the whole `height`-row
/// block is visible — e.g. `rows=24, height=7` gives `18`, and `bottom = 18 + 7
/// - 1 = 24` sits exactly on the screen bottom. `height` is pre-clamped to
/// `<= rows` by `clamp_height`, so the bound is always `>= 1` and the clamp
/// range stays non-empty.
pub fn calculate_max_top(
  size : @terminal_size.TerminalSize,
  height : Int,
) -> Int {
  let top = size.rows() - height + 1
  if top < 1 {
    1
  } else {
    top
  }
}

///|
/// Clamp an app-desired `top` into `1 ..= calculate_max_top(size, height)`.
///
/// The desired `top` comes from outside terminal geometry — the queried cursor
/// row on the first draw, or the previous frame's `top` afterwards — so it can
/// sit too low to fit the live area below it; clamping raises it just enough.
pub fn clamp_top(
  size : @terminal_size.TerminalSize,
  height~ : Int,
  top~ : Int,
) -> Int {
  top.clamp(min=1, max=calculate_max_top(size, height))
}
