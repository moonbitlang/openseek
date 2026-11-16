///|
/// A user-clicked task in one completed assistant message. Source location
/// identifies the suggestion; prompt and run settings are captured on its
/// first creation attempt and reused after a lost reply or host restart.
#derive(Debug, Eq)
pub(all) struct SessionCreateFromMessagePayload {
  session : String
  workspace : String
  sequence : Int32
  block : Int32
  prompt : String
  model : String
  thinking : Thinking
  approval : OpenSeekApproval
}

///|
#derive(Debug, Eq)
pub(all) struct SessionCreateFromMessageReply {
  session : String
  archived : Bool
}

///|
#derive(Debug, Eq)
pub(all) struct SessionSuggestionsPayload {
  session : String
  workspace : String
}

///|
#derive(Debug, Eq)
pub(all) struct SessionSuggestion {
  sequence : Int32
  block : Int32
  session : String
  archived : Bool
}

///|
#derive(Debug, Eq)
pub(all) struct SessionSuggestionsReply {
  suggestions : Array[SessionSuggestion]
}

///|
pub impl FromJson for SessionCreateFromMessagePayload with fn from_json(
  json,
  path,
) {
  let object = JsonObject::decode(json, path, "session creation from message")
  {
    session: object.required_string("session"),
    workspace: object.required_string("workspace"),
    sequence: object.required_int("sequence"),
    block: object.required_int("block"),
    prompt: object.required_string("prompt"),
    model: object.required_string("model"),
    thinking: @json.from_json(
      object.required_json("thinking"),
      path=path.add_key("thinking"),
    ),
    approval: @json.from_json(
      object.required_json("approval"),
      path=path.add_key("approval"),
    ),
  }
}

///|
pub impl ToJson for SessionCreateFromMessagePayload with fn to_json(self) {
  {
    "session": self.session,
    "workspace": self.workspace,
    "sequence": self.sequence,
    "block": self.block,
    "prompt": self.prompt,
    "model": self.model,
    "thinking": self.thinking,
    "approval": self.approval,
  }
}

///|
pub impl FromJson for SessionCreateFromMessageReply with fn from_json(
  json,
  path,
) {
  let object = JsonObject::decode(json, path, "created session")
  {
    session: object.required_string("session"),
    archived: object.required_bool("archived"),
  }
}

///|
pub impl ToJson for SessionCreateFromMessageReply with fn to_json(self) {
  { "session": self.session, "archived": self.archived }
}

///|
pub impl FromJson for SessionSuggestionsPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session suggestions request")
  {
    session: object.required_string("session"),
    workspace: object.required_string("workspace"),
  }
}

///|
pub impl ToJson for SessionSuggestionsPayload with fn to_json(self) {
  { "session": self.session, "workspace": self.workspace }
}

///|
pub impl FromJson for SessionSuggestion with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session suggestion")
  {
    sequence: object.required_int("sequence"),
    block: object.required_int("block"),
    session: object.required_string("session"),
    archived: object.required_bool("archived"),
  }
}

///|
pub impl ToJson for SessionSuggestion with fn to_json(self) {
  {
    "sequence": self.sequence,
    "block": self.block,
    "session": self.session,
    "archived": self.archived,
  }
}

///|
pub impl FromJson for SessionSuggestionsReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session suggestions")
  {
    suggestions: @json.from_json(
      object.required_json("suggestions"),
      path=path.add_key("suggestions"),
    ),
  }
}

///|
pub impl ToJson for SessionSuggestionsReply with fn to_json(self) {
  { "suggestions": self.suggestions }
}

///|
pub extend SessionCreateFromMessagePayload with Debug::{to_repr}

///|
pub extend SessionCreateFromMessagePayload with Eq::{equal, not_equal}

///|
pub extend SessionCreateFromMessagePayload with FromJson::{from_json}

///|
pub extend SessionCreateFromMessagePayload with ToJson::{to_json}

///|
pub extend SessionCreateFromMessageReply with Debug::{to_repr}

///|
pub extend SessionCreateFromMessageReply with Eq::{equal, not_equal}

///|
pub extend SessionCreateFromMessageReply with FromJson::{from_json}

///|
pub extend SessionCreateFromMessageReply with ToJson::{to_json}

///|
pub extend SessionSuggestionsPayload with Debug::{to_repr}

///|
pub extend SessionSuggestionsPayload with Eq::{equal, not_equal}

///|
pub extend SessionSuggestionsPayload with FromJson::{from_json}

///|
pub extend SessionSuggestionsPayload with ToJson::{to_json}

///|
pub extend SessionSuggestion with Debug::{to_repr}

///|
pub extend SessionSuggestion with Eq::{equal, not_equal}

///|
pub extend SessionSuggestion with FromJson::{from_json}

///|
pub extend SessionSuggestion with ToJson::{to_json}

///|
pub extend SessionSuggestionsReply with Debug::{to_repr}

///|
pub extend SessionSuggestionsReply with Eq::{equal, not_equal}

///|
pub extend SessionSuggestionsReply with FromJson::{from_json}

///|
pub extend SessionSuggestionsReply with ToJson::{to_json}
