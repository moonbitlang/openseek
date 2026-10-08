///|
/// Header contents for the persistent main topbar. The return arrow precedes
/// the page title, independent of page-local navigation.
pub fn header(
  title : String,
  return_label : String,
  return_action : @cmd.Cmd,
) -> Array[@html.Html] {
  [
    @html.button(
      class="icon-button management-page-return",
      title=return_label,
      attrs=@html.Attrs::build().aria_label(return_label),
      on_click=return_action,
      @icons.icon(@icons.icon_arrow_left),
    ),
    @html.h1(class="topbar-title", title),
  ]
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
