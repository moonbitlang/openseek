// Formatting shared by more than one component's chrome. A number rendered
// two ways in two places on the same screen is a defect the reader sees
// before anyone else does, so these live in one package rather than being
// copied into each view that needs them.

///|
/// A count compacted for a pill or a status line: exact under a thousand,
/// otherwise one decimal of k/M with a whole value's ".0" dropped — 999 →
/// "999", 12_345 → "12.3k", 10_000 → "10k", 1_230_000 → "1.2M".
pub fn compact_count(value : Int) -> String {
  fn scaled(tenths : Int, unit : String) -> String {
    if tenths % 10 == 0 {
      "\{tenths / 10}\{unit}"
    } else {
      "\{tenths / 10}.\{tenths % 10}\{unit}"
    }
  }

  if value < 1000 {
    value.to_string()
  } else if value < 999_950 {
    // Rounded tenths of a thousand; the cap keeps the k form from rounding
    // up to "1000k" — beyond it the M form takes over.
    scaled((value + 50) / 100, "k")
  } else {
    scaled((value + 50_000) / 100_000, "M")
  }
}
