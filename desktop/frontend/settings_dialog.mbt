///|
fn SettingsSection::id(self : SettingsSection) -> String {
  match self {
    General => "general"
    Account => "account"
    Engine => "engine"
    Connections => "connections"
    ArchivedChats => "archived-chats"
    SystemSettings => "system"
  }
}

///|
fn SettingsSection::label(
  self : SettingsSection,
  locale : @i18n.Locale,
) -> String {
  match self {
    General => @settings.text(locale, General)
    Account => @settings.text(locale, Account)
    Engine => @settings.text(locale, Engine)
    Connections => @settings.text(locale, Connections)
    ArchivedChats => @archived_chats.text(locale, Title)
    SystemSettings => @settings.text(locale, SystemSettings)
  }
}

///|
fn SettingsSection::available(self : SettingsSection, model : Model) -> Bool {
  match self {
    General | Account | ArchivedChats => true
    Engine => model.has_host()
    Connections | SystemSettings => model.is_desktop
  }
}

///|
fn Model::settings_section(self : Model) -> SettingsSection {
  match self.management_dialog {
    Some(Settings(section)) => section
    _ => General
  }
}

///|
fn settings_page(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  archived_chats_html : @html.Html,
) -> @html.Html {
  let selected = model.settings_section()
  let orientation = if model.narrow {
    @rui.TabsHorizontal
  } else {
    @rui.TabsVertical
  }
  let triggers : Array[@html.Html] = []
  let panels : Array[@html.Html] = []
  for
    section in [
      General,
      Engine,
      Account,
      Connections,
      ArchivedChats,
      SystemSettings,
    ] {
    if !section.available(model) {
      continue
    }
    let value = section.id()
    let trigger_id = "settings-tab-" + value
    let panel_id = "settings-panel-" + value
    let label = section.label(model.locale)
    triggers.push(
      @rui.tabs_trigger(
        value~,
        selected=section == selected,
        id=trigger_id,
        controls=panel_id,
        on_value_change=@cmd.Emit(_ => {
          dispatch(SettingsSectionSelected(section))
        }),
        class="settings-tab",
        style=[
          "flex:none;justify-content:flex-start;text-align:start;min-height:2.5em;padding:0.5em 0.75em;font-size:var(--font-size-md);white-space:var(--settings-tab-white-space,normal);overflow-wrap:anywhere",
        ],
        label,
      ),
    )
    let content = match section {
      General => [settings_general_group(dispatch, model)]
      Account =>
        [
          @ui.form_section(
            icon_key,
            label,
            settings_account_rows(dispatch, model),
          ),
        ]
      Engine => {
        let subtitle = if !model.host_settings_loaded() {
          @settings.text(model.locale, LoadingSettings)
        } else if model.api_ready() {
          @settings.text(model.locale, RuntimeSettings)
        } else {
          match model.api_provider() {
            Deepseek => @settings.text(model.locale, DeepseekKey)
            Glm => @settings.text(model.locale, GlmKey)
            OpenRouter => @settings.text(model.locale, OpenRouterKey)
            Custom => @settings.text(model.locale, CustomEndpoint)
          }
        }
        [
          @html.div(class="page-subtitle", subtitle),
          ..settings_runtime_groups(dispatch, model),
        ]
      }
      Connections =>
        [
          ssh_settings(dispatch, model),
          @ui.form_section(
            icon_link_external,
            @settings.text(model.locale, RemoteAccess),
            remote_access_rows(dispatch, model),
          ),
        ]
      ArchivedChats => [archived_chats_html]
      SystemSettings =>
        [
          settings_updates_group(dispatch, model),
          settings_diagnostics_group(dispatch, model),
        ]
    }
    panels.push(
      @rui.tabs_content(
        value~,
        selected=section == selected,
        force_mount=true,
        id=panel_id,
        labelledby=trigger_id,
        class="settings-tab-panel dialog-content",
        style=["font-size:var(--font-size-md)"],
        [
          @html.div(
            class="form-layout",
            [
              ..if section == Engine ||
                section == Connections ||
                section == ArchivedChats ||
                section == SystemSettings {
                [@html.h2(label)]
              } else {
                []
              },
              ..content,
            ],
          ),
        ],
      ),
    )
  }
  @rui.tabs_root(
    value=selected.id(),
    orientation~,
    class="settings-page settings-tabs",
    style=[
      "display:grid;grid-template-columns:var(--settings-columns);grid-template-rows:var(--settings-rows);gap:0;align-items:stretch;height:100%;min-height:0",
    ],
    [
      @rui.tabs_list(
        orientation~,
        aria_label=@settings.text(model.locale, Preferences),
        class="settings-tab-list",
        style=[
          "width:auto;min-width:0;min-height:0;flex:none;gap:var(--space-2);border-radius:0;padding:var(--space-4);overflow:auto;background:transparent;align-items:stretch",
        ],
        triggers,
      ),
      @html.div(class="settings-tab-panels", panels),
    ],
  )
}
