///|
/// Display width of `text` in terminal cells, accounting for East-Asian wide
/// characters.
pub fn display_width(text : String) -> Int {
  @unicodewidth.str_width(text)
}

///|
/// Truncate `text` to fit within `cols` display cells, appending an ellipsis
/// (`…`) when content is dropped. Returns `""` for `cols <= 0` and the input
/// unchanged when it already fits. Breaks on grapheme boundaries.
pub fn truncate_line(text : String, cols : Int) -> String {
  if cols <= 0 {
    ""
  } else if display_width(text) <= cols {
    text
  } else {
    let suffix = "…"
    let suffix_width = @unicodewidth.str_width(suffix)
    let content_cols = cols - suffix_width
    let builder = StringBuilder()
    let mut width = 0
    for grapheme in @grapheme.grapheme_iter(text) {
      let next_width = @unicodewidth.str_width(grapheme)
      if width + next_width > content_cols {
        break
      }
      builder.write_stringview(grapheme)
      width = width + next_width
    }
    builder.write_string(suffix)
    builder.to_string()
  }
}

///|
/// Split `text` into lines on `\n`. Always returns at least one element.
pub fn split_lines(text : String) -> Array[String] {
  text.split("\n").map(line => line.to_owned()).collect()
}

///|
/// The line at `index`, or `""` when `index` is out of range.
pub fn line_at(lines : Array[String], index : Int) -> String {
  if index < 0 || index >= lines.length() {
    ""
  } else {
    lines[index]
  }
}

///|
/// Number of grapheme clusters in `text`.
pub fn grapheme_count(text : String) -> Int {
  @grapheme.graphemes(text).length()
}

///|
/// Slice `text` by grapheme cluster index over `[start, end)`. Bounds are
/// clamped into range, so out-of-range indices never error.
pub fn grapheme_slice(text : String, start : Int, end : Int) -> String {
  let graphemes = @grapheme.graphemes(text)
  let length = graphemes.length()
  let start = start.clamp(min=0, max=length)
  let end = end.clamp(min=start, max=length)
  graphemes[start:end].to_string()
}
