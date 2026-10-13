///|
/// Creates a directly cancellable token for compatibility. New request owners
/// should create a `CancellationTokenSource` and pass its token instead.
pub fn CancellationToken::CancellationToken() -> CancellationToken {
  {
    state: CompatibilityMutable(
      MutableCancellationToken(schedule_cancellation_inline),
    ),
  }
}

///|
/// Shared token whose cancellation has already been requested.
pub fn CancellationToken::cancelled() -> CancellationToken {
  cancellation_cancelled
}

///|
/// Requests cancellation for a compatibility token. Source-owned and shared
/// tokens keep their source-defined behavior.
pub fn CancellationToken::cancel(self : CancellationToken) -> Unit {
  match self.state {
    CompatibilityMutable(token) => token.cancel()
    NeverCancelled | AlreadyCancelled(_) | SourceMutable(_) => ()
  }
}

///|
/// Requests cancellation once. Cancellation before the first token read avoids
/// mutable listener state but retains this source's scheduler, so a late
/// listener still has next-turn/disposable delivery semantics.
pub fn CancellationTokenSource::cancel(self : CancellationTokenSource) -> Unit {
  match self.token_value {
    None => self.token_value = Some({ state: AlreadyCancelled(self.schedule), })
    Some({ state: SourceMutable(token), }) => token.cancel()
    Some(
      { state: NeverCancelled | AlreadyCancelled(_) | CompatibilityMutable(_), }
    ) => ()
  }
}

///|
pub fn LanguageSelector::matches(
  self : LanguageSelector,
  model : @model.TextModel,
) -> Bool {
  self.matches_impl(model)
}

///|
pub fn LanguageFilter::matches(
  self : LanguageFilter,
  model : @model.TextModel,
) -> Bool {
  self.matches_impl(model)
}

///|
pub fn LanguageFilter::score(
  self : LanguageFilter,
  model : @model.TextModel,
) -> Int32 {
  self.score_impl(model)
}

///|
/// Asynchronous references provider retained as the documented host/protocol
/// contract even though the Viewer does not currently register one.
pub(open) trait ReferencesProvider {
  async fn provide_references(
    Self,
    @model.TextModel,
    @base_common.Position,
    CancellationToken,
  ) -> Array[Location]
}
