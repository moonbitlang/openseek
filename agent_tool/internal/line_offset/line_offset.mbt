///|
/// Where a 1-based line begins in `content`, as a code-unit offset.
///
/// Line 1 — and any lower number — begins at 0; every other line begins right
/// after the previous one ends. A line past the end of `content` yields
/// `content.length()`, so a range anchored beyond EOF selects an empty slice
/// instead of failing.
pub fn line_start_offset(content : String, line : Int) -> Int {
  // Line `line` starts right after line `line - 1` ends (nobreak: both scans
  // land on content.length() for a line past EOF).
  if line <= 1 {
    0
  } else {
    line_end_offset(content, line - 1)
  }
}

///|
/// Where a 1-based line ends in `content`, as a code-unit offset.
///
/// The offset is *past* the line's terminating newline, so
/// `line_end_offset(content, n)` and `line_start_offset(content, n + 1)` name
/// the same position. A line that is not newline-terminated — the last one, or
/// any line past the end — ends at `content.length()`.
pub fn line_end_offset(content : String, line : Int) -> Int {
  let len = content.length()
  for cursor in 0..<len; current_line = 1 {
    if content[cursor] == '\n' {
      if current_line == line {
        break cursor + 1
      }
      continue current_line + 1
    } else {
      continue current_line
    }
  } nobreak {
    len
  }
}
