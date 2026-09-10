///|
/// Numbered source and JSON-quoted file headings are data printed by file
/// inspection workflows, not runtime diagnostics. This only classifies output;
/// the sandbox enforces access independently of anything a program prints.
fn is_file_content_line(line : StringView) -> Bool {
  if line.has_prefix("=== \"") && line.has_suffix("\" ===") {
    return true
  }
  guard line.split_once(" |") is Some((gutter, _)) else { return false }
  let number = gutter.trim()
  !number.is_empty() && number.all(char => char.is_ascii_digit())
}
