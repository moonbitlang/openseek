///|
/// Floating annotation input for host-rendered documents. The representation,
/// event listeners, positioning, and selection painting remain module-private.
struct FeedbackComposer {
  inner : @feedback_widget.FeedbackComposerWidget
}

///|
/// Mount a composer using this viewer service bundle's live localization.
/// The host supplies an empty positioned container with editor theme styles,
/// the scrolling viewport, and its document subtree as `layout_source`.
/// The host owns the returned composer and must dispose it before removing
/// its container or disposing these services. `on_submit` receives the text
/// and whether to apply it immediately rather than queue it in Batch mode.
pub fn ViewerServices::create_feedback_composer(
  self : ViewerServices,
  container : @rdom.Element,
  viewport~ : @rdom.Element,
  layout_source~ : @rdom.Element,
  on_submit~ : (String, Bool) -> Unit,
  on_change~ : (String) -> Unit,
  on_cancel~ : () -> Unit,
) -> FeedbackComposer {
  {
    inner: FeedbackComposerWidget(
      container,
      viewport~,
      layout_source~,
      localization=self.code_services().localization(),
      on_submit~,
      on_change~,
      on_cancel~,
    ),
  }
}

///|
/// Start a fresh draft while preserving Batch. The callbacks measure live
/// client-coordinate geometry; `None` hides an unavailable selection anchor.
/// `selection_rects` supplies text fragments to retain while the input owns
/// focus. They are clipped to the container and refreshed with its layout.
pub fn FeedbackComposer::show(
  self : FeedbackComposer,
  anchor : () -> @rdom.DOMRect?,
  prefer_below~ : Bool,
  selection_rects~ : () -> Array[@rdom.DOMRect],
) -> Unit {
  self.inner.show(anchor, prefer_below~, selection_rects~)
}

///|
/// Clear the current draft and source highlight, retaining the mounted input.
pub fn FeedbackComposer::hide(self : FeedbackComposer) -> Unit {
  self.inner.hide()
}

///|
/// Remove the composer and release its DOM and localization subscriptions.
pub fn FeedbackComposer::dispose(self : FeedbackComposer) -> Unit {
  self.inner.dispose()
}
