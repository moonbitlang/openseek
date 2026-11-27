// The unified model chip: one composer control whose grouped menu spans both
// agents. Picking an option decides an (agent, model) pair — the state is two
// facts even though the control is one select. A conversation's agent is
// fixed by its first turn; only a composing conversation (an OpenSeek chat
// with nothing sent, or a Codex draft with no app-server thread) may still be
// handed to the other agent, so only those chips offer both groups.

///|
/// Which agent runs a conversation. Persisted as the default for the next
/// "New chat"; a conversation that has begun never changes agents.
#derive(Eq)
priv enum AgentChoice {
  OpenSeekAgent
  CodexAgent
}

///|
fn AgentChoice::wire(self : AgentChoice) -> String {
  match self {
    OpenSeekAgent => "openseek"
    CodexAgent => "codex"
  }
}

///|
fn AgentChoice::parse(value : String) -> AgentChoice? {
  match value.trim() {
    "openseek" => Some(OpenSeekAgent)
    "codex" => Some(CodexAgent)
    _ => None
  }
}

///|
/// One pick in the unified model chip, encoded into the native select's
/// option value. Codex ids live in their own namespace so one can never be
/// mistaken for an OpenSeek model, even when both services use the same name.
priv enum ModelChoice {
  OpenSeekModel(@deepseek.Model)
  CodexModel(String)
  // The Codex group's only row while no model catalog is usable. Picking it
  // is a request to open the Codex page, where sign-in and connection state
  // live; it never changes the selected model.
  CodexUnavailablePick
}

///|
const OpenSeekChoicePrefix = "openseek:"

///|
const CodexChoicePrefix = "codex:"

///|
const CodexUnavailableChoiceWire = "codex.unavailable"

///|
fn ModelChoice::wire(self : ModelChoice) -> String {
  match self {
    OpenSeekModel(model) => OpenSeekChoicePrefix + model.to_string()
    CodexModel(id) => CodexChoicePrefix + id
    CodexUnavailablePick => CodexUnavailableChoiceWire
  }
}

///|
fn ModelChoice::parse(value : String) -> ModelChoice? {
  if value == CodexUnavailableChoiceWire {
    return Some(CodexUnavailablePick)
  }
  if value.strip_prefix(OpenSeekChoicePrefix) is Some(rest) {
    return parse_engine_model(rest).map(model => OpenSeekModel(model))
  }
  if value.strip_prefix(CodexChoicePrefix) is Some(rest) {
    let id = rest.to_owned()
    if !id.trim().is_empty() {
      return Some(CodexModel(id))
    }
  }
  None
}

///|
test "model choices round-trip and the agent namespaces stay disjoint" {
  assert_true(
    ModelChoice::parse("openseek:deepseek-v4-pro")
    is Some(OpenSeekModel(Deepseek(V4Pro))),
  )
  assert_true(
    ModelChoice::parse("openseek:glm-5.3") is Some(OpenSeekModel(Glm(G53))),
  )
  // A tier's wire name inside the Codex namespace is a Codex id, never a
  // tier — and a bare wire name belongs to neither agent.
  assert_true(
    ModelChoice::parse("codex:deepseek-v4-pro")
    is Some(CodexModel("deepseek-v4-pro")),
  )
  assert_true(ModelChoice::parse("deepseek-v4-pro") is None)
  assert_true(
    ModelChoice::parse("codex.unavailable") is Some(CodexUnavailablePick),
  )
  assert_true(ModelChoice::parse("codex:") is None)
  assert_true(ModelChoice::parse("openseek:") is None)
  inspect(
    ModelChoice::OpenSeekModel(Deepseek(V4Flash)).wire(),
    content="openseek:deepseek-flash",
  )
  inspect(ModelChoice::CodexModel("gpt-5.4").wire(), content="codex:gpt-5.4")
  assert_true(
    ModelChoice::parse(ModelChoice::CodexModel("gpt-5.4").wire())
    is Some(CodexModel("gpt-5.4")),
  )
}

///|
test "agent choices round-trip their wire names" {
  assert_true(AgentChoice::parse("openseek") is Some(OpenSeekAgent))
  assert_true(AgentChoice::parse("codex") is Some(CodexAgent))
  assert_true(AgentChoice::parse("") is None)
  assert_true(AgentChoice::parse("claude") is None)
  inspect(AgentChoice::OpenSeekAgent.wire(), content="openseek")
  inspect(AgentChoice::CodexAgent.wire(), content="codex")
}

///|
/// The OpenSeek group offers the models the configured provider serves: the
/// DeepSeek service tiers, the GLM models, or — for a custom endpoint — only the
/// entries saved for it, because that endpoint's models and their windows are
/// named in the section above and nothing else is known to be served by it. A
/// conversation running a model outside that list keeps it visible, same as the
/// old selector.
fn openseek_model_group(
  provider : ApiProvider,
  selected : @deepseek.Model,
  saved : Array[@protocol.CustomModel],
  locale : @i18n.Locale,
) -> @composer.ModelGroup {
  let listed : Array[@deepseek.Model] = match provider {
    Deepseek | SeekMoon | OpenRouter => [Deepseek(V4Pro), Deepseek(V4Flash)]
    Glm => [Glm(G53), Glm(G53Flash)]
    Custom => []
  }
  let options = listed.map(model => @composer.ModelOption::{
    value: ModelChoice::OpenSeekModel(model).wire(),
    label: model.label(),
  })
  if provider is Custom {
    for entry in saved {
      options.push({
        value: ModelChoice::OpenSeekModel(custom_model_engine_model(entry)).wire(),
        label: custom_model_display_name(entry),
      })
    }
  }
  let selected_is_listed = listed.contains(selected) ||
    (provider is Custom && find_custom_model(saved, selected) is Some(_))
  if !selected_is_listed {
    let name = if provider is Custom || selected is @deepseek.Custom(_) {
      find_custom_model(saved, selected)
      .map(custom_model_display_name)
      .unwrap_or(selected.label())
    } else {
      selected.label()
    }
    options.push({
      value: ModelChoice::OpenSeekModel(selected).wire(),
      label: if model_availability_for(provider, selected, saved) is ModelReady {
        name
      } else {
        name + " " + @settings.text(locale, ModelNotOnEndpointLabel)
      },
    })
  }
  { label: "OpenSeek", options, }
}

///|
/// Codex's group mirrors the fetched catalog; without one it offers the one
/// row that leads to the Codex page instead of hiding the agent entirely.
fn Model::codex_model_group(self : Model) -> @composer.ModelGroup {
  match self.codex.model_listing(locale=self.locale) {
    CodexModels(options, selected=_) => {
      let prefixed = options.map(option => @composer.ModelOption::{
        value: ModelChoice::CodexModel(option.value).wire(),
        label: option.label,
      })
      { label: "Codex", options: prefixed, }
    }
    CodexModelsUnavailable(label) =>
      {
        label: "Codex",
        options: [{ value: CodexUnavailableChoiceWire, label, }],
      }
  }
}

///|
/// The unified model chip on an OpenSeek conversation. A conversation that
/// has not begun may still be handed to Codex, so its chip offers both
/// groups; once the transcript exists the agent is fixed and the menu
/// narrows to OpenSeek's tiers.
fn Model::openseek_model_chip(
  self : Model,
  conv : Conversation,
) -> @composer.ModelSelect {
  let groups : Array[@composer.ModelGroup] = [
    openseek_model_group(
      self.api_provider(),
      conv.engine_model,
      self.host_settings().map(settings => settings.models).unwrap_or([]),
      self.locale,
    ),
  ]
  if self.composing_new_chat() {
    groups.push(self.codex_model_group())
  }
  {
    id: "openseek-model-picker",
    groups,
    selected: ModelChoice::OpenSeekModel(conv.engine_model).wire(),
    // Nothing to pick until the section names a model, so the menu stays
    // closed rather than offering the placeholder this chat carries.
    disabled: self.model_availability(conv.engine_model) is ModelNoneSaved ||
    conv.controls.edit is Some(_) ||
    conv.controls.pending is Some(_) ||
    conv.pending_semantic_submission is Some(_),
    open: self.select_menu is Some(OpenSeekModelMenu),
    title: (match self.locale {
      SimplifiedChinese => "模型："
      TraditionalChinese => "模型："
      Japanese => "モデル："
      English => "Model: "
      Spanish => "Modelo: "
    }) +
    self.selected_model_name(conv.engine_model),
  }
}

///|
/// The name a conversation's model goes by: the entry's own name when the user
/// gave it one (on Custom or for a custom entry), the built-in's product name
/// otherwise.
fn Model::selected_model_name(self : Model, model : @deepseek.Model) -> String {
  if self.api_provider() is Custom || model is @deepseek.Custom(_) {
    if find_custom_model(self.custom_models(), model) is Some(entry) {
      return custom_model_display_name(entry)
    }
  }
  model.label()
}

///|
/// OpenSeek's reasoning chip shares the same control as Codex but offers only
/// the values its request format defines. An unknown model may be a
/// provider such as Kimi, so hiding the chip there is safer than sending a
/// setting that provider deliberately ignores. GLM 5.3 cannot disable
/// thinking — the engine maps `no` to GLM's lowest supported effort — so its
/// first option says "Low" rather than promising "Off".
fn Model::openseek_reasoning_chip(
  self : Model,
  conv : Conversation,
) -> @composer.ReasoningSelect? {
  guard conv.engine_model.supports_reasoning() else { return None }
  Some(
    openseek_reasoning_control(
      conv.engine_model,
      self.conversation_reasoning(conv),
      locale=self.locale,
      open=self.select_menu is Some(OpenSeekReasoningMenu),
      disabled=false,
    ),
  )
}

///|
fn openseek_reasoning_control(
  model : @deepseek.Model,
  reasoning : @protocol.Thinking,
  locale~ : @i18n.Locale,
  open~ : Bool,
  disabled~ : Bool,
) -> @composer.ReasoningSelect {
  let options : Array[@composer.ModelOption] = [
    {
      value: @protocol.ThinkingOff.wire(),
      label: @protocol.ThinkingOff.label_for_model(locale~, model),
    },
    {
      value: @protocol.ThinkingHigh.wire(),
      label: @protocol.ThinkingHigh.label(locale~),
    },
    {
      value: @protocol.ThinkingMax.wire(),
      label: @protocol.ThinkingMax.label(locale~),
    },
  ]
  {
    id: "openseek-reasoning-picker",
    options,
    selected: reasoning.wire(),
    disabled,
    open,
    title: (match locale {
      SimplifiedChinese => "推理强度："
      TraditionalChinese => "推理強度："
      Japanese => "推論の強度："
      English => "Reasoning effort: "
      Spanish => "Esfuerzo de razonamiento: "
    }) +
    reasoning.label_for_model(locale~, model),
  }
}

///|
/// The unified model chip on the Codex page. A composing draft may still be
/// handed back to OpenSeek; a stored thread's transcript is Codex's alone,
/// so its menu narrows to Codex models.
fn Model::codex_model_chip(self : Model) -> @composer.ModelSelect {
  let groups : Array[@composer.ModelGroup] = []
  if self.codex.composing_draft() {
    groups.push(
      openseek_model_group(
        self.api_provider(),
        self.default_model,
        self.host_settings().map(settings => settings.models).unwrap_or([]),
        self.locale,
      ),
    )
  }
  groups.push(self.codex_model_group())
  let selected = match self.codex.model_listing(locale=self.locale) {
    CodexModels(_, selected~) => ModelChoice::CodexModel(selected).wire()
    CodexModelsUnavailable(_) => CodexUnavailableChoiceWire
  }
  {
    id: "codex-model-picker",
    groups,
    selected,
    disabled: self.codex_project_adoption_pending(),
    open: self.select_menu is Some(CodexModelMenu),
    title: match self.locale {
      SimplifiedChinese => "Codex 模型"
      TraditionalChinese => "Codex 模型"
      Japanese => "Codex モデル"
      English => "Codex model"
      Spanish => "Modelo de Codex"
    },
  }
}

///|
test "the model menu lists saved entries under their own names" {
  let saved : Array[@protocol.CustomModel] = [
    {
      id: "gemini-4-carbon",
      label: Some("Gemini 4 Carbon"),
      context_window: @protocol.DefaultCustomModelContextWindow,
    },
    {
      id: "o3-mini",
      label: None,
      context_window: @protocol.DefaultCustomModelContextWindow,
    },
  ]
  let group = openseek_model_group(Deepseek, Deepseek(V4Flash), saved, English)
  assert_eq(group.options.map(option => option.label), [
    "DeepSeek Pro", "DeepSeek Flash",
  ])
  let stale = openseek_model_group(
    Deepseek,
    @deepseek.Custom(
      "gone-model",
      context_window=@protocol.DefaultCustomModelContextWindow,
    ),
    saved,
    English,
  )
  assert_eq(stale.options.map(option => option.label), [
    "DeepSeek Pro", "DeepSeek Flash", "gone-model (not served here)",
  ])
  let on_entry = openseek_model_group(
    Deepseek,
    @deepseek.Custom(
      "gemini-4-carbon",
      context_window=@protocol.DefaultCustomModelContextWindow,
    ),
    saved,
    English,
  )
  assert_eq(on_entry.options.map(option => option.label), [
    "DeepSeek Pro", "DeepSeek Flash", "Gemini 4 Carbon (not served here)",
  ])
  let custom = openseek_model_group(
    Custom,
    @deepseek.Custom(
      "gemini-4-carbon",
      context_window=@protocol.DefaultCustomModelContextWindow,
    ),
    saved,
    English,
  )
  assert_eq(custom.options.map(option => option.label), [
    "Gemini 4 Carbon", "o3-mini",
  ])
  let kept = openseek_model_group(Custom, Deepseek(V4Flash), saved, English)
  assert_eq(kept.options.map(option => option.label), [
    "Gemini 4 Carbon", "o3-mini", "DeepSeek Flash (not served here)",
  ])
  let with_flash : Array[@protocol.CustomModel] = [
    ..saved,
    { id: "deepseek-flash", label: None, context_window: 131_072, },
  ]
  let served = openseek_model_group(
    Custom,
    Deepseek(V4Flash),
    with_flash,
    English,
  )
  assert_eq(served.options.map(option => option.label), [
    "Gemini 4 Carbon", "o3-mini", "DeepSeek Flash",
  ])
  assert_eq(served.options[2].value, "openseek:deepseek-flash")
}

///|
/// Whether the selected provider can run `model`, and why not when it cannot.
priv enum ModelAvailability {
  ModelReady
  ModelEntryDeleted
  ModelNotOnEndpoint
  ModelNoneSaved
}

///|
fn model_availability_for(
  provider : ApiProvider,
  model : @deepseek.Model,
  saved : Array[@protocol.CustomModel],
) -> ModelAvailability {
  match (provider, model) {
    (Custom, _) if saved.is_empty() => ModelNoneSaved
    (Custom, _) =>
      if find_custom_model(saved, model) is Some(_) {
        ModelReady
      } else if model is @deepseek.Custom(_) {
        ModelEntryDeleted
      } else {
        ModelNotOnEndpoint
      }
    (_, @deepseek.Custom(_)) => ModelNotOnEndpoint
    _ => ModelReady
  }
}

///|
fn Model::model_availability(
  self : Model,
  model : @deepseek.Model,
) -> ModelAvailability {
  model_availability_for(self.api_provider(), model, self.custom_models())
}

///|
fn Model::conversation_model_ready(
  self : Model,
  model : @deepseek.Model,
) -> Bool {
  self.model_availability(model) is ModelReady
}
