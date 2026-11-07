///|
/// Content layout inside a dialog scroll area; the caller owns scrolling.
pub fn dialog_page(
  content : Array[@html.Html],
  class~ : String,
  attrs~ : @html.Attrs = @html.Attrs::build(),
) -> @html.Html {
  @html.section(class="dialog-page " + class, attrs~, [
    @html.div(class="dialog-page-content", content),
  ])
}
