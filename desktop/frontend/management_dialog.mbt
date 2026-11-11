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
    Some(Settings(_)) => @settings.text(model.locale, Settings)
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
    class="dialog-surface dialog-size-large dialog-scroll-layout",
    close_label=shell_text(model.locale, DismissLabel),
    on_close=_ => dispatch(CloseManagementDialog),
    attrs=@html.Attrs::build().aria_labelledby("management-dialog-title"),
    on_cancel=dispatch(
      if model.delete_confirm is Open(_) {
        CancelDeleteSession
      } else {
        CloseManagementDialog
      },
    ),
    [
      @rui.dialog_header([
        @rui.dialog_title(id="management-dialog-title", title),
      ]),
      @html.div(
        class=if model.management_dialog is Some(Settings(_)) &&
          !model.host_incompatible() {
          "dialog-scroll-body dialog-pane-container"
        } else {
          "dialog-scroll-body dialog-content"
        },
        [
          // Stable panes retain their DOM while the shared dialog is closed.
          pane(
            Settings(model.settings_section()),
            settings_page(dispatch, model, archived_chats_html),
          ),
          pane(Skills, skills_html),
          pane(Schedules, schedules_page(dispatch, model)),
          if model.management_dialog is Some(_) && model.host_incompatible() {
            console_gate_view(
              locale=model.locale,
              dispatch,
              model.console,
              account_error=model.account_error,
              host_incompatible=true,
            )
          } else {
            @html.nothing
          },
        ],
      ),
    ],
  )
}
