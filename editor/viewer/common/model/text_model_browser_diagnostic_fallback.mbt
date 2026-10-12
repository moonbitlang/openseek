// Non-JavaScript targets have no browser fixture and therefore no diagnostic
// receiver.

///|
fn offer_text_model_browser_diagnostic(
  _get_attached_count : (TextModel) -> Int32,
) -> Unit {
  ()
}
