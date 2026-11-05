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
  @html.dialog(
    id="management-dialog",
    class="modal management-dialog",
    on_cancel=dispatch(
      if model.delete_confirm is Some(_) {
        CancelDeleteSession
      } else {
        CloseManagementDialog
      },
    ),
    attrs=@html.Attrs::build()
      .aria_label(title)
      .on_click(event => {
        if event.target().to_element() is Some(element) &&
          element.get_property("id").to_option() is Some("management-dialog") {
          dispatch(CloseManagementDialog)
        } else {
          @cmd.none
        }
      }),
    [
      @html.div(class="management-dialog-header", [
        @html.div(class="management-dialog-heading", [
          if model.management_dialog is Some(Skills) &&
            model.skills.detail_open() {
            @html.button(
              class="icon-button",
              attrs=@html.Attrs::build().aria_label(
                shell_text(model.locale, BackToSkills),
              ),
              on_click=dispatch(Skills(@skills.BackToList)),
              @icons.icon(@icons.icon_arrow_left),
            )
          } else {
            @html.nothing
          },
          @html.h1(class="topbar-title", title),
        ]),
        @html.button(
          class="icon-button",
          attrs=@html.Attrs::build().aria_label(
            shell_text(model.locale, DismissLabel),
          ),
          on_click=dispatch(CloseManagementDialog),
          @icons.icon(@icons.icon_close),
        ),
      ]),
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
    ],
  )
}
