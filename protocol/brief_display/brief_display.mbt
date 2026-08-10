///|
/// The canonical display text for an optional tool-result brief. Producers may
/// omit a brief, and older or third-party producers may write whitespace; UI
/// consumers should treat both cases as absent and never expose padding.
pub fn text(brief : String?) -> String? {
  guard brief is Some(brief) else { return None }
  let brief = brief.trim()
  if brief.is_empty() {
    None
  } else {
    Some(brief.to_owned())
  }
}

///|
/// A tool-call summary for views that flag failures inline. Views with a
/// separate accessible failure badge can use `text` and render that badge in
/// their own layout.
pub fn call_text(brief : String?, is_error : Bool) -> String? {
  match (text(brief), is_error) {
    (None, false) => None
    (None, true) => Some("🚩")
    (Some(text), false) => Some(text)
    (Some(text), true) => Some("\{text} 🚩")
  }
}
