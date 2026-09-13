///|
/// Optional workspace-list metadata can fail independently of the registry.
pub(all) enum ChatWorkspaceRoot {
  Ready(String)
  Failed(String)
} derive(Debug, Eq)

///|
pub impl ToJson for ChatWorkspaceRoot with fn to_json(self) {
  match self {
    Ready(path) => path.to_json()
    Failed(message) => { "error": message.to_json() }
  }
}

///|
pub impl FromJson for ChatWorkspaceRoot with fn from_json(json, path) {
  match json {
    String(root) => Ready(root)
    _ =>
      Failed(
        JsonObject::decode(json, path, "chat storage failure").required_string(
          "error",
        ),
      )
  }
}

///|
fn decode_chat_workspace_root(
  object : JsonObject,
) -> ChatWorkspaceRoot? raise @json.JsonDecodeError {
  match object.optional_json("chat_root") {
    Some(json) => Some(@json.from_json(json))
    None => None
  }
}

///|
pub extend ChatWorkspaceRoot with Debug::{to_repr}

///|
pub extend ChatWorkspaceRoot with Eq::{equal, not_equal}

///|
pub extend ChatWorkspaceRoot with ToJson::{to_json}

///|
pub extend ChatWorkspaceRoot with FromJson::{from_json}
