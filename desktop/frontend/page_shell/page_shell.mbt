///|
/// Header contents for the persistent main topbar. Global navigation lives
/// beside the sidebar toggle, outside this page shell.
pub fn header(title : String) -> Array[@html.Html] {
  [@html.h1(class="topbar-title", title)]
}

///|
/// One scrolling body and content column for every independent management
/// page. Feature classes identify local content; the shell owns its layout.
pub fn body(
  content : Array[@html.Html],
  class~ : String,
  attrs? : @html.Attrs = @html.Attrs::build(),
) -> @html.Html {
  @html.section(class="management-page " + class, attrs~, [
    @html.div(class="management-page-content", content),
  ])
}
