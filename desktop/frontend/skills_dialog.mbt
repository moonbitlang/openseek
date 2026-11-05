///|
fn Model::skills_detail_dialog_open(self : Model) -> Bool {
  self.management_dialog is Some(Skills) &&
  self.skills.detail_open(self.focused) &&
  !self.host_incompatible()
}

///|
fn skills_detail_dialog_view(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  content : @html.Html,
) -> @html.Html {
  @rui.dialog(
    id="skill-detail-dialog",
    show_close=false,
    attrs=@html.Attrs::build().aria_labelledby("skill-detail-dialog-title"),
    on_cancel=dispatch(Skills(@skills.BackToList)),
    [
      @rui.dialog_header([
        @rui.dialog_title(
          id="skill-detail-dialog-title",
          @skills.detail_title(model.locale),
        ),
        @html.button(
          type_="button",
          class="icon-button",
          attrs=@html.Attrs::build()
            .data_set("slot", "dialog-close")
            .aria_label(shell_text(model.locale, DismissLabel)),
          on_click=@dialog.request_close("skill-detail-dialog"),
          @icons.icon(@icons.icon_close),
        ),
      ]),
      @html.div([content]),
    ],
  )
}
