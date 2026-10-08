///| Shared live model facts read by the model-owned tokenization part.

///|
/// Construction-safe state shared by `TextModel` and its tokenization part.
/// Mutable facts stay behind `Ref`s so token work reads them at the same source
/// moment as the owning model transition; no document lines are copied.
priv struct TokenizationModelState {
  snapshot : Ref[TextSnapshot]
  language_id : String
  attached_count : Ref[Int]
  too_large : Bool
  line_limit : TokenizationLineLimit
  disposing : Ref[Bool]
  scheduler : Ref[TokenizationScheduler?]
  report_unexpected_error : (String) -> Unit
}

///|
/// Creates the package-private shared state after the model's normalized
/// snapshot and construction-fixed facts are known.
fn TokenizationModelState::TokenizationModelState(
  snapshot~ : Ref[TextSnapshot],
  language_id~ : String,
  attached_count~ : Ref[Int],
  too_large~ : Bool,
  disposing~ : Ref[Bool],
  scheduler~ : Ref[TokenizationScheduler?],
  report_unexpected_error~ : (String) -> Unit,
  line_limit? : TokenizationLineLimit = Characters(20000),
) -> TokenizationModelState {
  {
    snapshot,
    language_id,
    attached_count,
    too_large,
    line_limit,
    disposing,
    scheduler,
    report_unexpected_error,
  }
}
