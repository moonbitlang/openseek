///|
fn label(
  locale : @i18n.Locale,
  english : String,
  chinese : String,
  traditional : String,
  japanese : String,
  spanish : String,
) -> String {
  match locale {
    English => english
    SimplifiedChinese => chinese
    TraditionalChinese => traditional
    Japanese => japanese
    Spanish => spanish
  }
}

///|
pub fn Card::options_open(self : Card) -> Bool {
  !(self.editor is Closed)
}

///|
pub fn Card::render(
  self : Card,
  locale : @i18n.Locale,
  models : Array[@select_control.ViewOption],
  connected : Bool,
  emit : @cmd.Emit[Msg],
  details? : @html.Html,
  here_available~ : Bool = true,
) -> @html.Html {
  let action = emit.map(action => {
    Interact(source=self.source, request=self.proposal.request_id, action)
  })
  if !self.is_visible() {
    return @html.nothing
  }
  if self.proposal.status == "started" &&
    self.proposal.target_session is Some(_) {
    return @html.button(
      class="session-start-folded",
      on_click=action(Open),
      attrs=@html.Attrs::build().data_set("focus-owner", ""),
      [
        @html.span(class="session-start-folded-title", self.proposal.title),
        @html.span(
          class="session-start-chevron",
          attrs=@html.Attrs::build().aria_hidden("true"),
          "›",
        ),
      ],
    )
  }
  let busy = self.delivery is Sending(_, ..) ||
    self.proposal.status == "starting"
  let disabled = busy || !connected || self.source.archived
  let start_disabled = disabled ||
    self.proposal.target_session == Some(self.source.session)
  let here_disabled = disabled ||
    !here_available ||
    (
      self.proposal.target_session is Some(target) &&
      target != self.source.session
    )
  let title = label(
    locale, "New session", "新建会话", "新增會話", "新しいセッション",
    "Nueva sesión",
  )
  let options = label(
    locale, "Options", "选项", "選項", "オプション", "Opciones",
  )
  let start = if self.delivery is Sending("start", ..) ||
    (
      self.proposal.status == "starting" &&
      self.proposal.target_session != Some(self.source.session)
    ) {
    label(
      locale, "Starting…", "正在创建…", "正在建立…", "作成中…",
      "Iniciando…",
    )
  } else {
    label(locale, "Start", "开始", "開始", "開始", "Iniciar")
  }
  let children : Array[@html.Html] = [
    @html.div(class="session-start-header", title),
    @html.div(class="session-start-body", [
      @html.div(class="session-start-heading", [
        @html.strong(class="session-start-title", self.proposal.title),
        @html.button(
          class="session-start-dismiss",
          disabled~,
          attrs=@html.Attrs::build().aria_label(
            label(
              locale, "Dismiss suggestion", "关闭建议", "關閉建議", "提案を閉じる",
              "Descartar sugerencia",
            ),
          ),
          on_click=action(Decide("dismiss")),
          @icons.icon_close(),
        ),
      ]),
      @html.div(class="session-start-task", self.proposal.task),
      @html.div(class="session-start-actions", [
        @html.button(
          class="session-start-options-toggle",
          disabled~,
          on_click=action(ToggleOptions),
          attrs=@html.Attrs::build().aria_expanded(
            self.options_open().to_string(),
          ),
          options,
        ),
        @html.div(class="session-start-actions-right", [
          @html.button(
            class="session-start-here",
            disabled=here_disabled,
            on_click=action(Decide("here")),
            if self.delivery is Sending("here", ..) ||
              (
                self.proposal.status == "starting" &&
                self.proposal.target_session == Some(self.source.session)
              ) {
              label(
                locale, "Submitting…", "正在提交…", "正在提交…", "送信中…",
                "Enviando…",
              )
            } else {
              label(
                locale, "Do it here", "在此处操作", "在此處操作", "ここで実行",
                "Hacerlo aquí",
              )
            },
          ),
          @html.button(
            class="session-start-submit",
            disabled=start_disabled,
            on_click=action(Decide("start")),
            start,
          ),
        ]),
      ]),
    ]),
  ]
  if self.options_open() {
    let model_label = label(
      locale, "Model", "模型", "模型", "モデル", "Modelo",
    )
    let workspace_label = label(
      locale, "Workspace mode", "工作目录", "工作目錄", "作業ディレクトリ",
      "Directorio de trabajo",
    )
    let inherited = label(
      locale, "Project default", "项目默认", "專案預設", "プロジェクトの既定",
      "Predeterminado del proyecto",
    )
    let choices : Array[@select_control.ViewOption] = [
      { value: "", label: inherited, },
      ..models,
    ]
    let selected = self.model.unwrap_or("")
    if !choices.any(option => option.value == selected) {
      choices.push({ value: selected, label: selected, })
    }
    let id = "session-start-" +
      self.source.session +
      "-" +
      self.proposal.request_id
    let model_control : @select_control.Control = {
      id: id + "-model",
      groups: [{ label: model_label, options: choices, }],
      selected,
      disabled,
      open: self.editor is ModelMenu,
      toggle: action(ToggleModel),
      dismiss: action(CloseMenu),
      change: action.map(value => ModelChanged(value)),
      title: model_label,
      aria_label: model_label,
      presentation: Setting,
    }
    let workspace_control : @select_control.Control = {
      id: id + "-workspace",
      groups: [
        {
          label: workspace_label,
          options: [
            {
              value: "local",
              label: label(
                locale, "Local", "本地", "本機", "ローカル", "Local",
              ),
            },
            { value: "worktree", label: "Worktree", },
          ],
        },
      ],
      selected: self.workspace_mode,
      disabled,
      open: self.editor is WorkspaceMenu,
      toggle: action(ToggleWorkspace),
      dismiss: action(CloseMenu),
      change: action.map(value => WorkspaceChanged(value)),
      title: workspace_label,
      aria_label: workspace_label,
      presentation: Setting,
    }
    let fields = [
      @html.div(class="session-start-option", [
        @html.span(model_label),
        model_control.render(),
      ]),
      @html.div(class="session-start-option", [
        @html.span(workspace_label),
        workspace_control.render(),
      ]),
    ]
    if !self.proposal.workspace.is_empty() {
      fields.push(
        @html.div(class="session-start-workspace", self.proposal.workspace),
      )
    }
    if details is Some(details) {
      fields.push(details)
    }
    children.push(@html.div(class="session-start-options", fields))
  }
  let error = if self.delivery is Failed(error) {
    Some(error)
  } else {
    self.proposal.error
  }
  if error is Some(error) {
    children.push(
      @html.div(
        class="session-start-error",
        attrs=@html.Attrs::build().role("status"),
        error,
      ),
    )
  }
  @html.div(class="session-start-card", children)
}
