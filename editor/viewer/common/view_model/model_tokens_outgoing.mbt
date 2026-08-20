///|
/// Browser-neutral inclusive view-line range produced by the common ViewModel
/// before the browser tier constructs its frozen `ViewTokensChangedEvent`.
pub struct ViewTokensChangedRange {
  from_line_number : Int
  to_line_number : Int
} derive(Eq, Debug)

///|
/// Keeps existing headless `ViewModel` callers source-compatible. The browser
/// Viewer supplies the live callback through `with_options`.
fn view_model_no_token_event_sink(
  _ranges : Array[ViewTokensChangedRange],
) -> Unit {
  ()
}

///|
/// Subscribes to the source-shaped outgoing model-token wrapper. The browser
/// root uses this instead of listening to `TextModel` directly.
pub fn ViewModel::on_model_tokens_changed(
  self : ViewModel,
  listener : (ModelTokensChangedOutgoingEvent) -> Unit,
) -> @base_common.Disposable {
  self.cursor_event_dispatcher.on_model_tokens_changed(listener)
}

///|
/// Enqueues the original model event only after the browser ViewEvent callback
/// has returned (`viewModelImpl.ts:521-522`).
fn ViewModel::emit_model_tokens_changed(
  self : ViewModel,
  event : @model.ModelTokensChangedEvent,
) -> Unit {
  self.cursor_event_dispatcher.emit_model_tokens_changed(
    ModelTokensChangedOutgoingEvent(event),
  )
}

///|
pub extend ViewTokensChangedRange with Debug::{to_repr}

///|
pub extend ViewTokensChangedRange with Eq::{equal, not_equal}
