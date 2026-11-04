///|
fn management_link_dialog(target : @routes.Target) -> ManagementDialog? {
  match target {
    Settings => Some(Settings)
    Skills | InstalledSkill(_) | MarketSkill(_) => Some(Skills)
    Schedules => Some(Schedules)
    _ => None
  }
}

///|
fn Model::codex_work_selected(self : Model) -> Bool {
  self.screen is Codex
}

///|
fn management_dialog_view(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  skills_html : @html.Html,
) -> @html.Html {
  let title = match model.management_dialog {
    Some(Settings) => @settings.text(model.locale, Settings)
    Some(Skills) => @sidebar_messages.text(model.locale, Skills)
    Some(Schedules) => ui(model.locale, ScheduledTasks)
    None => ""
  }
  @html.dialog(
    id="management-dialog",
    class="modal management-dialog",
    on_cancel=dispatch(CloseManagementDialog),
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
            model.skills.detail() is Some(_) {
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
      ..match model.management_dialog {
        Some(_) if model.host_incompatible() =>
          [
            console_gate_view(
              locale=model.locale,
              dispatch,
              model.console,
              host_incompatible=true,
            ),
          ]
        Some(Settings) => [settings_page(dispatch, model)]
        Some(Skills) =>
          if model.navigation.location.map_or(false, location => {
              management_link_dialog(location.target) is Some(_)
            }) &&
            navigation_notice(dispatch, model) is Some(notice) {
            [notice]
          } else {
            [skills_html]
          }
        Some(Schedules) => [schedules_page(dispatch, model)]
        None => []
      },
    ],
  )
}
