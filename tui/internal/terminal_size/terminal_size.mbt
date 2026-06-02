///|
const DefaultTerminalRows : Int = 24

///|
const DefaultTerminalCols : Int = 80

///|
/// On-screen terminal dimensions, guaranteed positive.
///
/// The type is opaque and can only be built through `TerminalSize::new` or
/// `TerminalSize::default`, which replace the non-positive dimensions a terminal
/// may report (for example a zero size queried before the first `ioctl`) with
/// sane defaults. Consumers can therefore treat `rows`/`cols` as always `>= 1`
/// without re-validating.
struct TerminalSize {
  rows : Int
  cols : Int
}

///|
/// Build a terminal size, replacing any non-positive dimension with its default.
pub fn TerminalSize::new(rows~ : Int, cols~ : Int) -> TerminalSize {
  {
    rows: if rows < 1 {
      DefaultTerminalRows
    } else {
      rows
    },
    cols: if cols < 1 {
      DefaultTerminalCols
    } else {
      cols
    },
  }
}

///|
/// The fallback size used before a real terminal size is known.
pub fn TerminalSize::default() -> TerminalSize {
  { rows: DefaultTerminalRows, cols: DefaultTerminalCols }
}

///|
/// Number of on-screen rows.
pub fn TerminalSize::rows(self : TerminalSize) -> Int {
  self.rows
}

///|
/// Number of on-screen columns.
pub fn TerminalSize::cols(self : TerminalSize) -> Int {
  self.cols
}
