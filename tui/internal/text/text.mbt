///|
/// Terminal tab stop width: tabs expand to the next multiple of this.
pub const TabWidth : Int = 8

///|
/// Whether a display-safe text unit is a C0 control character or DEL.
pub fn is_control_unit(unit : StringView) -> Bool {
  match unit {
    [c, ..] => {
      let code = c.to_int()
      code < 0x20 || code == 0x7f
    }
    [] => false
  }
}

///|
/// Display-cell width of a unit slice inside `line`.
pub fn unit_width(
  line : @displaytext.DisplayText,
  start~ : @displaytext.TextualPosition,
  end~ : @displaytext.TextualPosition,
) -> Int {
  line.display_position(end).column() - line.display_position(start).column()
}

///|
/// Normalize user-provided text so it can be echoed live — in the composer or
/// queued previews — without mutating the terminal or confusing the cursor math.
///
/// Carriage returns become newlines so pasted line breaks survive; every other
/// C0 control and `DEL` is dropped — including `ESC`, and therefore every ANSI
/// escape sequence that could move or clear the cursor. Tabs are expanded to
/// spaces at the next `TabWidth` stop so the stored width matches what is drawn
/// (a raw `\t` counts as one column but renders as a jump). `\n` is preserved.
pub fn sanitize(text : String) -> String {
  let builder = StringBuilder()
  for index, line in @displaytext.split_lines(text) {
    if index > 0 {
      builder.write_string("\n")
    }
    builder.write_string(sanitize_line(line))
  }
  builder.to_string()
}

///|
/// Sanitize `text` and return one display-ready `DisplayText` per hard line,
/// applying the same policy as `sanitize` (drop C0 controls and `DEL`, expand
/// tabs, keep `\n` as the line split). Callers that need segmented lines should
/// use this directly instead of re-splitting `sanitize`'s joined output.
pub fn sanitize_lines(text : String) -> Array[@displaytext.DisplayText] {
  @displaytext.split_lines(text).map(line => DisplayText(sanitize_line(line)))
}

///|
/// Sanitize one already-segmented hard line into a plain string: expand tabs to
/// the next `TabWidth` stop and drop C0 controls and `DEL`. Shared by `sanitize`
/// (which joins the results) and `sanitize_lines` (which re-wraps each in a
/// `DisplayText`), so the string path never builds a throwaway `DisplayText`.
fn sanitize_line(line : @displaytext.DisplayText) -> String {
  let builder = StringBuilder()
  let mut col = 0
  let mut start = line.start()
  while line.next(start) is Some(end) {
    let unit = line.view(start, end)
    if unit == "\t" {
      let spaces = TabWidth - col % TabWidth
      builder.write_string(String::make(spaces, ' '))
      col = col + spaces
    } else if !is_control_unit(unit) {
      builder.write_stringview(unit)
      col = col + unit_width(line, start~, end~)
    }
    start = end
  }
  builder.to_string()
}
