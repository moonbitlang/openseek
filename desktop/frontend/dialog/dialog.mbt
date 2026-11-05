///|
pub(all) enum Size {
  Small
  Medium
  Large
}

///|
fn Size::class_name(self : Size) -> String {
  match self {
    Small => "desktop-dialog-small"
    Medium => "desktop-dialog-medium"
    Large => "desktop-dialog-large"
  }
}

///|
pub fn view(
  id~ : String,
  title~ : String,
  close_label~ : String,
  size~ : Size,
  closedby? : String,
  on_dismiss~ : @cmd.Cmd,
  body~ : @html.Html,
  actions? : @html.Html,
) -> @html.Html {
  let title_id = id + "-title"
  @html.dialog(
    id~,
    class="desktop-dialog " + size.class_name(),
    closedby?,
    on_cancel=on_dismiss,
    attrs=@html.Attrs::build().aria_labelledby(title_id),
    [
      @html.div(class="desktop-dialog-header", [
        @html.h2(id=title_id, class="desktop-dialog-title", title),
        @html.button(
          type_="button",
          class="icon-button desktop-dialog-close",
          attrs=@html.Attrs::build().aria_label(close_label),
          on_click=on_dismiss,
          @icons.icon(@icons.icon_close),
        ),
      ]),
      @html.div(class="desktop-dialog-body", body),
      ..actions.map_or([], content => {
        [@html.div(class="desktop-dialog-actions", content)]
      }),
    ],
  )
}
