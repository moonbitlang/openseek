// The unified model chip: one composer control whose grouped menu spans both
// agents. Picking an option decides an (agent, model) pair — the state is two
// facts even though the control is one select. A conversation's agent is
// fixed by its first turn; only a composing conversation (an OpenSeek chat
// with nothing sent, or a Codex draft with no app-server thread) may still be
// handed to the other agent, so only those chips offer both groups.

///|
/// Which agent runs a conversation. Persisted as the default for the next
/// "New chat"; a conversation that has begun never changes agents.
priv enum AgentChoice {
  OpenSeekAgent
  CodexAgent
} derive(Eq)

///|
fn AgentChoice::wire(self : AgentChoice) -> String {
  match self {
    OpenSeekAgent => "openseek"
    CodexAgent => "codex"
  }
}

///|
fn AgentChoice::parse(value : String) -> AgentChoice? {
  match value.trim().to_owned() {
    "openseek" => Some(OpenSeekAgent)
    "codex" => Some(CodexAgent)
    _ => None
  }
}

///|
/// One pick in the unified model chip, encoded into the native select's
/// option value. Codex ids live in their own namespace so one can never be
/// mistaken for an OpenSeek tier — `EngineModel::parse` adopts any unknown
/// string as a custom tier, which is exactly the silent misroute the
/// prefixes exist to prevent.
priv enum ModelChoice {
  OpenSeekModel(EngineModel)
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
    OpenSeekModel(model) => OpenSeekChoicePrefix + model.wire()
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
    return EngineModel::parse(rest.to_owned()).map(model => OpenSeekModel(model))
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
    ModelChoice::parse("openseek:deepseek-v4-pro") is Some(OpenSeekModel(DsPro)),
  )
  assert_true(
    ModelChoice::parse("openseek:glm-5.3") is Some(OpenSeekModel(Glm53)),
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
    ModelChoice::OpenSeekModel(DsFlash).wire(),
    content="openseek:deepseek-v4-flash",
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
/// The OpenSeek group offers the configured provider's models: the DeepSeek
/// service tiers, the GLM models, or — for a custom endpoint, where the key
/// follows whichever model is named — every model this build knows. A
/// conversation running a model outside that list keeps it visible, same as
/// the old selector.
fn openseek_model_group(
  provider : ApiProvider,
  selected : EngineModel,
) -> @composer.ModelGroup {
  let listed : Array[EngineModel] = match provider {
    Deepseek => [DsPro, DsFlash]
    Glm => [Glm53, Glm53Flash]
    Custom => [DsPro, DsFlash, Glm53, Glm53Flash]
  }
  let options = listed.map(model => @composer.ModelOption::{
    value: ModelChoice::OpenSeekModel(model).wire(),
    label: model.label(),
  })
  if !listed.contains(selected) {
    options.push({
      value: ModelChoice::OpenSeekModel(selected).wire(),
      label: selected.label(),
    })
  }
  { label: "OpenSeek", options, }
}

///|
test "the model group follows the configured provider" {
  let deepseek = openseek_model_group(Deepseek, DsPro)
  assert_eq(deepseek.options.map(option => option.label), ["DS Pro", "DS Flash"])
  let glm = openseek_model_group(Glm, Glm53)
  assert_eq(glm.options.map(option => option.value), [
    "openseek:glm-5.3", "openseek:glm-5.3-flash",
  ])
  // A conversation carried across a provider switch keeps its model visible,
  // same as an unknown wire name always did.
  let carried = openseek_model_group(Glm, DsPro)
  assert_eq(carried.options.map(option => option.label), [
    "GLM 5.3", "GLM 5.3 Flash", "DS Pro",
  ])
  let custom = openseek_model_group(Custom, Other("proxy-model"))
  assert_eq(custom.options.map(option => option.label), [
    "DS Pro", "DS Flash", "GLM 5.3", "GLM 5.3 Flash", "proxy-model",
  ])
}

///|
/// Codex's group mirrors the fetched catalog; without one it offers the one
/// row that leads to the Codex page instead of hiding the agent entirely.
fn Model::codex_model_group(self : Model) -> @composer.ModelGroup {
  match self.codex.model_listing() {
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
    openseek_model_group(self.api_provider, conv.engine_model),
  ]
  if self.composing_new_chat() {
    groups.push(self.codex_model_group())
  }
  {
    id: "openseek-model-picker",
    groups,
    selected: ModelChoice::OpenSeekModel(conv.engine_model).wire(),
    disabled: false,
    open: self.select_menu == Some(OpenSeekModelMenu),
    title: "Model: \{conv.engine_model.label()}",
  }
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
  let reasoning = self.reasoning_for(conv.engine_model)
  let options : Array[@composer.ModelOption] = [
    {
      value: ReasoningOff.wire(),
      label: ReasoningOff.label_for_model(conv.engine_model),
    },
    { value: ReasoningHigh.wire(), label: "High", },
    { value: ReasoningMax.wire(), label: "Max", },
  ]
  Some({
    id: "openseek-reasoning-picker",
    options,
    selected: reasoning.wire(),
    disabled: false,
    open: self.select_menu == Some(OpenSeekReasoningMenu),
    title: "Reasoning effort: \{reasoning.label_for_model(conv.engine_model)}",
  })
}

///|
/// The unified model chip on the Codex page. A composing draft may still be
/// handed back to OpenSeek; a stored thread's transcript is Codex's alone,
/// so its menu narrows to Codex models.
fn Model::codex_model_chip(self : Model) -> @composer.ModelSelect {
  let groups : Array[@composer.ModelGroup] = []
  if self.codex.composing_draft() {
    groups.push(openseek_model_group(self.api_provider, self.default_model))
  }
  groups.push(self.codex_model_group())
  let selected = match self.codex.model_listing() {
    CodexModels(_, selected~) => ModelChoice::CodexModel(selected).wire()
    CodexModelsUnavailable(_) => CodexUnavailableChoiceWire
  }
  {
    id: "codex-model-picker",
    groups,
    selected,
    disabled: false,
    open: self.select_menu == Some(CodexModelMenu),
    title: "Codex model",
  }
}
