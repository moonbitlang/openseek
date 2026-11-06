///|
pub fn is_html_file(path : String) -> Bool {
  let lower = path.to_lower()
  lower.has_suffix(".html") || lower.has_suffix(".htm")
}
