// Browser-test-only offer for the private attachment-count diagnostic. Product
// pages do not install the receiver, so constructing a model has no observable
// browser side effect outside the focused fixture.

///|
extern "js" fn offer_text_model_browser_diagnostic(
  get_attached_count : (TextModel) -> Int32,
) -> Unit =
  #| (getAttachedCount) => globalThis.__viewerPrivateTestProbe?.acceptTextModelAttachedCount?.(getAttachedCount)
