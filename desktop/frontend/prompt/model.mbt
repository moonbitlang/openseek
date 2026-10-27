///|
const StorageKey : String = "openseek.prompt"

///|
priv enum Source {
  Builtin
  Custom
} derive(Eq)

///|
/// The preference for future conversations. Call text once when creating a
/// draft; that draft owns its resulting string independently of this model.
pub struct Model {
  priv source : Source
  priv custom_text : String
} derive(Eq)

///|
#doc(hidden)
#deprecated
pub extend Model with Eq::{equal, not_equal}

///|
pub(all) enum Msg {
  Loaded(Model)
  Selected(String)
  Edited(String)
}

///|
pub fn Model::new() -> Model {
  { source: Builtin, custom_text: "", }
}

///|
pub fn Model::text(self : Model, model : @deepseek.Model) -> String {
  @content.system_prompt_for_model(
    model,
    prompt=match self.source {
      Builtin => BuiltinMoonBitGuide
      Custom => Custom(self.custom_text)
    },
  )
}

///|
impl ToJson for Model with fn to_json(self) {
  {
    "kind": match self.source {
      Builtin => "builtin_moonbit_guide"
      Custom => "custom"
    },
    "text": self.custom_text,
  }
}

///|
impl @json.FromJson for Model with fn from_json(json, path) {
  match json {
    { "kind": "builtin_moonbit_guide", "text": String(text), .. } =>
      { source: Builtin, custom_text: text, }
    { "kind": "builtin_moonbit_guide", .. } => Model::new()
    { "kind": "custom", "text": String(text), .. } =>
      { source: Custom, custom_text: text, }
    _ => raise @json.JsonDecodeError((path, "invalid prompt preference"))
  }
}

///|
pub fn Model::update(self : Model, msg : Msg) -> (@cmd.Cmd, Model) {
  let next : Model = match msg {
    Loaded(model) => return (@cmd.none, model)
    Selected("builtin_moonbit_guide") => { ..self, source: Builtin, }
    Selected("custom") => { ..self, source: Custom, }
    Selected(_) => return (@cmd.none, self)
    Edited(text) => { source: Custom, custom_text: text, }
  }
  (
    @cmd.custom_cmd(_ => {
      // Like the other page-local preferences, a denied store keeps the
      // in-memory choice and falls back to defaults on the next launch.
      @browser.local_storage_set(StorageKey, ToJson::to_json(next).stringify())
      |> ignore
    }),
    next,
  )
}

///|
fn stored(key : String) -> String? {
  match @browser.local_storage_get(key) {
    Ok(value) => value
    Err(_) => None
  }
}

///|
fn load_model() -> Model {
  if stored(StorageKey) is Some(value) {
    let model : Model? = Some(@json.from_json(@json.parse(value))) catch {
      _ => None
    }
    if model is Some(model) {
      return model
    }
  }
  // Preserve the previous preference when first opening this version.
  if stored("openseek.moonbit_guide") == Some("false") {
    { source: Custom, custom_text: "", }
  } else {
    Model::new()
  }
}

///|
/// Load the preference without altering any existing conversation's prompt.
pub fn load(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => scheduler.add(dispatch(Loaded(load_model()))))
}
