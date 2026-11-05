///|
fn Model::codex_work_selected(self : Model) -> Bool {
  self.screen is Codex
}

///|
fn management_dialog_view(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  skills_html : @html.Html,
  archived_chats_html : @html.Html,
) -> @html.Html {
  let title = match model.management_dialog {
    Some(Settings) => @settings.text(model.locale, Settings)
    Some(ArchivedChats) => @archived_chats.text(model.locale, Title)
    Some(Skills) => @sidebar_messages.text(model.locale, Skills)
    Some(Schedules) => ui(model.locale, ScheduledTasks)
    None => ""
  }
  fn pane(kind : ManagementDialog, content : @html.Html) -> @html.Html {
    @html.div(
      class="management-dialog-pane",
      hidden=model.host_incompatible() || model.management_dialog != Some(kind),
      content,
    )
  }
  @rui.dialog(
    id="management-dialog",
    class="dialog-size-large",
    show_close=false,
    attrs=@html.Attrs::build().aria_labelledby("management-dialog-title"),
    on_cancel=dispatch(
      if model.delete_confirm is Some(_) {
        CancelDeleteSession
      } else {
        CloseManagementDialog
      },
    ),
    [
      @rui.dialog_header([
        @rui.dialog_title(id="management-dialog-title", title),
        @html.button(
          type_="button",
          class="icon-button",
          attrs=@html.Attrs::build()
            .data_set("slot", "dialog-close")
            .aria_label(shell_text(model.locale, DismissLabel)),
          on_click=@dialog.request_close("management-dialog"),
          @icons.icon(@icons.icon_close),
        ),
      ]),
      @html.div([
        // Stable panes retain their DOM while the shared dialog is closed.
        pane(Settings, settings_page(dispatch, model)),
        pane(ArchivedChats, archived_chats_html),
        pane(Skills, skills_html),
        pane(Schedules, schedules_page(dispatch, model)),
        if model.management_dialog is Some(_) && model.host_incompatible() {
          console_gate_view(
            locale=model.locale,
            dispatch,
            model.console,
            host_incompatible=true,
          )
        } else {
          @html.nothing
        },
        if model.management_dialog is Some(ArchivedChats) &&
          model.delete_confirm is Some(confirm) {
          delete_modal(locale=model.locale, dispatch, confirm, model.cloud)
        } else {
          @html.nothing
        },
      ]),
    ],
  )
}
