// The chat model and thinking level a run uses. They live in the protocol
// module because every layer names them: the engine's `--model`/`--thinking`,
// a session's recorded `model.json`, `sessions list`, and the Desktop host and
// frontend. The JSON spelling is the same wire name `--model` and
// `--thinking` accept, so one decoder serves all of them.

///|
/// DeepSeek chat model variants.
///
/// `V4Flash` is the DeepSeek flash tier under its canonical wire name
/// `deepseek-flash`. The retired `deepseek-v4-flash` name is still accepted as
/// an alias and served by the same model.
#derive(Eq, Debug)
pub(all) enum DsVariant {
  V4Flash
  V4Pro
}

///|
/// Kimi chat model variants.
#derive(Eq, Debug)
pub(all) enum KimiVariant {
  K27Code
  K27CodeHighSpeed
}

///|
/// Z.AI GLM chat model variants.
#derive(Eq, Debug)
pub(all) enum GlmVariant {
  G53
  G53Flash
}

///|
/// Supported chat models grouped by provider.
#derive(Eq, Debug)
pub(all) enum Model {
  Deepseek(DsVariant)
  Kimi(KimiVariant)
  Glm(GlmVariant)
}

///|
/// Returns the wire name for a DeepSeek chat model variant.
impl Show for DsVariant with fn to_string(self : DsVariant) -> String {
  match self {
    V4Flash => "deepseek-flash"
    V4Pro => "deepseek-v4-pro"
  }
}

///|
/// Returns the wire name for a Kimi chat model variant.
impl Show for KimiVariant with fn to_string(self : KimiVariant) -> String {
  match self {
    K27Code => "kimi-k2.7-code"
    K27CodeHighSpeed => "kimi-k2.7-code-highspeed"
  }
}

///|
/// Returns the wire name for a Z.AI GLM chat model variant.
impl Show for GlmVariant with fn to_string(self : GlmVariant) -> String {
  match self {
    G53 => "glm-5.3"
    G53Flash => "glm-5.3-flash"
  }
}

///|
/// Returns the wire name for a chat model.
pub impl Show for Model with fn to_string(self : Model) -> String {
  match self {
    Deepseek(variant) => "\{variant}"
    Kimi(variant) => "\{variant}"
    Glm(variant) => "\{variant}"
  }
}

///|
/// Parses a wire model name into a typed model.
pub fn Model::parse(input : String) -> Model raise {
  match input {
    "deepseek-flash" | "deepseek-v4-flash" => Deepseek(V4Flash)
    "deepseek-v4-pro" => Deepseek(V4Pro)
    "kimi-k2.7-code" => Kimi(K27Code)
    "kimi-k2.7-code-highspeed" => Kimi(K27CodeHighSpeed)
    "glm-5.3" => Glm(G53)
    "glm-5.3-flash" => Glm(G53Flash)
    other => fail("unknown model: \{other}")
  }
}

///|
/// Context window served by the official API, in tokens.
///
/// Every DeepSeek variant serves 1M context ("1M context is now the default
/// across all official DeepSeek services", api-docs.deepseek.com news260424);
/// the kimi-k2.7-code family serves 256K. These are the totals a request's
/// prompt and completion must fit within, used by the agent loop as the
/// ceiling for its auto-compaction guard. Per-variant match so adding a
/// variant forces an explicit choice here.
pub fn Model::context_window(self : Model) -> Int32 {
  match self {
    Deepseek(V4Flash | V4Pro) => 1_000_000
    Kimi(K27Code | K27CodeHighSpeed) => 262_144
    Glm(G53 | G53Flash) => 1_000_000
  }
}

///|
/// The model's wire name; decoding accepts exactly what `Model::parse` does.
pub impl ToJson for Model with fn to_json(self) {
  Json(self.to_string())
}

///|
pub impl FromJson for Model with fn from_json(json, path) {
  guard json is String(name) else {
    raise JsonDecodeError((path, "expected a model name"))
  }
  Model::parse(name) catch {
    _ => raise JsonDecodeError((path, "unknown model: \{name}"))
  }
}

///|
/// DeepSeek thinking control for V4 models.
///
/// `No` disables thinking. `High` and `Max` enable thinking and select the
/// corresponding reasoning effort.
#derive(Eq, Debug)
pub(all) enum ThinkingMode {
  No
  High
  Max
}

///|
/// Returns the user-facing name for a thinking mode.
pub impl Show for ThinkingMode with fn to_string(self : ThinkingMode) -> String {
  match self {
    No => "no"
    High => "high"
    Max => "max"
  }
}

///|
/// Parses a thinking mode from its user-facing name (`no`/`high`/`max`),
/// raising on anything else.
///
/// The legacy `disabled` and `enabled` names remain accepted as aliases for
/// `No` and `Max` so existing environment settings keep working.
pub fn ThinkingMode::parse(input : String) -> ThinkingMode raise {
  match input {
    "no" | "disabled" => No
    "high" => High
    "max" | "enabled" => Max
    other => fail("unknown thinking mode: \{other} (use no, high, or max)")
  }
}

///|
/// The thinking mode's wire name; decoding accepts exactly what
/// `ThinkingMode::parse` does.
pub impl ToJson for ThinkingMode with fn to_json(self) {
  Json(self.to_string())
}

///|
pub impl FromJson for ThinkingMode with fn from_json(json, path) {
  guard json is String(name) else {
    raise JsonDecodeError((path, "expected no, high, or max"))
  }
  ThinkingMode::parse(name) catch {
    _ => raise JsonDecodeError((path, "expected no, high, or max"))
  }
}

///|
/// The chat model and thinking mode one session runs on, as the engine
/// records them beside its transcript (`model.json`) and reports them in
/// `sessions list`.
#derive(Eq, Debug)
pub(all) struct SessionModel {
  model : Model
  thinking : ThinkingMode
}

///|
/// `{"model": …, "thinking": …}` with the same wire names `--model` and
/// `--thinking` accept. Both fields are required; unknown fields are ignored.
pub impl ToJson for SessionModel with fn to_json(self) {
  { "model": self.model, "thinking": self.thinking }
}

///|
pub impl FromJson for SessionModel with fn from_json(json, path) {
  guard json is Object(fields) else {
    raise JsonDecodeError((path, "session model must be an object"))
  }
  guard fields.get("model") is Some(model) else {
    raise JsonDecodeError((path, "session model needs a model"))
  }
  guard fields.get("thinking") is Some(thinking) else {
    raise JsonDecodeError((path, "session model needs a thinking mode"))
  }
  {
    model: @json.from_json(model, path=path.add_key("model")),
    thinking: @json.from_json(thinking, path=path.add_key("thinking")),
  }
}

///|
#doc(hidden)
#deprecated
pub extend DsVariant with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend DsVariant with Eq::{equal, not_equal}

///|
#doc(hidden)
#deprecated
pub extend KimiVariant with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend KimiVariant with Eq::{equal, not_equal}

///|
#doc(hidden)
#deprecated
pub extend GlmVariant with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend GlmVariant with Eq::{equal, not_equal}

///|
#doc(hidden)
#deprecated
pub extend Model with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend Model with Eq::{equal, not_equal}

///|
pub extend Model with Show::{output, to_string}

///|
pub extend Model with ToJson::{to_json}

///|
pub extend Model with FromJson::{from_json}

///|
#doc(hidden)
#deprecated
pub extend ThinkingMode with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend ThinkingMode with Eq::{equal, not_equal}

///|
pub extend ThinkingMode with Show::{output, to_string}

///|
pub extend ThinkingMode with ToJson::{to_json}

///|
pub extend ThinkingMode with FromJson::{from_json}

///|
#doc(hidden)
#deprecated
pub extend SessionModel with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend SessionModel with Eq::{equal, not_equal}

///|
pub extend SessionModel with ToJson::{to_json}

///|
pub extend SessionModel with FromJson::{from_json}
