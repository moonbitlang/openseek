///|
/// Header contents for the persistent main topbar. The return action always
/// occupies its trailing action slot, independent of page-local navigation.
pub fn header(
  title : String,
  return_label : String,
  return_action : @cmd.Cmd,
) -> Array[@html.Html] {
  [
    @html.h1(class="topbar-title", title),
    @html.div(class="management-page-actions", [
      @html.button(
        class="button secondary management-page-return",
        on_click=return_action,
        return_label,
      ),
    ]),
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
