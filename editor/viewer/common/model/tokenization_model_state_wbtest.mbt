///| White-box state construction for tokenization unit and reference tests.

///|
fn test_tokenization_model_state(
  lines : Array[String],
  language_id : String,
  attached_count : Ref[Int32],
  too_large : Bool,
  disposing : Ref[Bool],
  scheduler : Ref[TokenizationScheduler?],
  report_unexpected_error : (String) -> Unit,
) -> TokenizationModelState {
  TokenizationModelState(
    snapshot=Ref(TextSnapshot(lines.join("\n"))),
    language_id~,
    attached_count~,
    too_large~,
    disposing~,
    scheduler~,
    report_unexpected_error~,
  )
}
