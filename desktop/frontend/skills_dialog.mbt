///|
fn Model::skills_detail_dialog_open(self : Model) -> Bool {
  self.management_dialog is Some(Skills) &&
  self.skills.detail_open(self.skills_input().library) &&
  self.skills_input().available()
}

///|
fn skills_detail_dialog_view(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  content : @html.Html,
) -> @html.Html {
  @rui.dialog(
    id="skill-detail-dialog",
    class="dialog-size-medium dialog-scroll-layout",
    close_label=shell_text(model.locale, DismissLabel),
    on_close=_ => {
      @cmd.batch([
        dispatch(Skills(@skills.BackToList)),
        @cmd.custom_cmd(_ => {
          // Native close restores a surviving card. A filter or uninstall can
          // remove that button while the detail is open.
          let doc = @dom.document()
          if doc.query_selector(".skills-page .skill-summary:focus").to_option()
            is None &&
            doc
            .query_selector(
              "#management-dialog:modal .management-dialog-pane:not([hidden]) #skills-search",
            )
            .to_option()
            is Some(element) &&
            element.to_html_element() is Some(search) {
            search.focus()
          }
        }),
      ])
    },
    attrs=@html.Attrs::build().aria_labelledby("skill-detail-dialog-title"),
    on_cancel=dispatch(Skills(@skills.BackToList)),
    [
      @rui.dialog_header([
        @rui.dialog_title(
          id="skill-detail-dialog-title",
          @skills.detail_title(model.locale),
        ),
      ]),
      @html.div(class="dialog-scroll-body dialog-content", [content]),
    ],
  )
}
