///|
/// Native Browser focus is window-local. An absent id means no Browser tab
/// owns focus; query failures are reported separately as command failures.
pub(all) struct AppFocusedBrowserReply {
  id : Int?
} derive(Debug, Eq)

///|
pub impl FromJson for AppFocusedBrowserReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "focused Browser reply")
  { id: object.optional_int("id"), }
}

///|
pub impl ToJson for AppFocusedBrowserReply with fn to_json(self) {
  match self.id {
    Some(id) => { "id": id.to_json() }
    None => Json::empty_object()
  }
}

///|
pub extend AppFocusedBrowserReply with Debug::{to_repr}

///|
pub extend AppFocusedBrowserReply with Eq::{equal, not_equal}

///|
pub extend AppFocusedBrowserReply with FromJson::{from_json}

///|
pub extend AppFocusedBrowserReply with ToJson::{to_json}
