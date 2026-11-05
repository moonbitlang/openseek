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
  @ui.dialog(
    id="skill-detail-dialog",
    size=Medium,
    show_close=false,
    attrs=@html.Attrs::build().aria_labelledby("skill-detail-dialog-title"),
    on_cancel=dispatch(Skills(@skills.BackToList)),
    [
      @ui.dialog_header([
        @html.div(class="desktop-dialog-heading", [
          @html.button(
            class="icon-button",
            attrs=@html.Attrs::build().aria_label(
              shell_text(model.locale, BackToSkills),
            ),
            on_click=dispatch(Skills(@skills.BackToList)),
            @icons.icon(@icons.icon_arrow_left),
          ),
          @ui.dialog_title(
            id="skill-detail-dialog-title",
            @sidebar_messages.text(model.locale, Skills),
          ),
        ]),
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
      @ui.dialog_body([content]),
    ],
  )
}
