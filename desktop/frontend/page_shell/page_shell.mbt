///|
/// Scrollable management content shared by the three dialogs.
pub fn body(
  content : Array[@html.Html],
  class~ : String,
  attrs~ : @html.Attrs = @html.Attrs::build(),
) -> @html.Html {
  @html.section(class="management-page " + class, attrs~, [
    @html.div(class="management-page-content", content),
  ])
}
