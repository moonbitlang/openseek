///|
priv enum Source {
  Builtin
  Custom
} derive(Eq)

///|
/// The host's committed preference and a client-local, unsaved editor buffer.
/// New drafts use only committed settings, never text still being edited.
pub struct Model {
  priv source : Source
  priv custom_text : String
  priv draft : String?
} derive(Eq)

///|
#doc(hidden)
#deprecated
pub extend Model with Eq::{equal, not_equal}

///|
pub(all) enum Msg {
  Selected(String)
  Edited(String)
  Save
}

///|
pub fn Model::new() -> Model {
  { source: Builtin, custom_text: "", draft: None, }
}

///|
pub fn Model::receive(self : Model, source : String, text : String) -> Model {
  {
    source: if source == "custom" {
      Custom
    } else {
      Builtin
    },
    custom_text: text,
    draft: if self.draft == Some(text) {
      None
    } else {
      self.draft
    },
  }
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
pub fn Model::draft_text(self : Model) -> String? {
  self.draft
}

///|
pub fn Model::update(self : Model, msg : Msg) -> (@cmd.Cmd, Model) {
  match msg {
    Edited(text) =>
      (
        @cmd.none,
        {
          ..self,
          draft: if text == self.custom_text {
            None
          } else {
            Some(text)
          },
        },
      )
    Selected(_) | Save => (@cmd.none, self)
  }
}
