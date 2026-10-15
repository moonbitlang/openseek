///|
/// A durable association with a pull request or remote branch. The URL is
/// the identity; resolving its display metadata never changes the binding.
pub struct SessionPrBinding {
  url : String
} derive(Eq, Debug)

///|
pub impl FromJson for SessionPrBinding with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session PR binding")
  guard object.fields.length() == 1 else {
    raise JsonDecodeError((path, "a binding contains only url"))
  }
  let url = object.required_string("url").trim().trim_end(chars="/").to_owned()
  let parts = url.split("/").collect()
  guard parts is ["https:", "", authority, .. rest] &&
    !authority.is_empty() &&
    !authority.contains("@") &&
    !authority.contains("?") &&
    !authority.contains("#") &&
    !rest.is_empty() &&
    rest.any(part => !part.is_empty()) &&
    !url.contains("\\") &&
    !url.iter().any(c => c <= ' ' || c == '\u007f') else {
    raise JsonDecodeError(
      (path.add_key("url"), "expected an HTTPS pull request or branch URL"),
    )
  }
  { url, }
}

///|
pub impl ToJson for SessionPrBinding with fn to_json(self) {
  { "url": self.url }
}

///|
/// Complete replacement, not a patch. A missing/null bindings field is an
/// error; an explicit empty array clears the list. First occurrence wins.
pub struct SessionPrBindings {
  bindings : Array[SessionPrBinding]
} derive(Eq, Debug)

///|
pub impl FromJson for SessionPrBindings with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session PR bindings")
  let entries : Array[SessionPrBinding] = @json.from_json(
    object.required_json("bindings"),
    path=path.add_key("bindings"),
  )
  let bindings : Array[SessionPrBinding] = []
  for entry in entries {
    if !bindings.contains(entry) {
      bindings.push(entry)
    }
  }
  { bindings, }
}

///|
pub impl ToJson for SessionPrBindings with fn to_json(self) {
  { "bindings": Json(self.bindings) }
}

///|
pub fn SessionPrBindings::empty() -> SessionPrBindings {
  { bindings: [], }
}

///|
pub fn SessionPrBindings::without(
  self : SessionPrBindings,
  url : String,
) -> SessionPrBindings {
  { bindings: self.bindings.filter(item => item.url != url), }
}

///|
/// Display-only metadata for a resolved PR. Request identity and lookup
/// failures belong to the caller, not the metadata.
pub(all) struct SessionPrDetail {
  pull_request : GitPullRequest
  head_url : String?
} derive(Eq, Debug)

///|
pub impl FromJson for SessionPrDetail with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session PR detail")
  {
    pull_request: @json.from_json(
      object.required_json("pull_request"),
      path=path.add_key("pull_request"),
    ),
    head_url: object.optional_string("head_url"),
  }
}

///|
pub impl ToJson for SessionPrDetail with fn to_json(self) {
  let fields : Map[String, Json] = {
    "pull_request": self.pull_request.to_json(),
  }
  if self.head_url is Some(value) {
    fields["head_url"] = Json(value)
  }
  Json(fields)
}

///|
/// Commands use object replies; an absent detail means this URL has no PR
/// enrichment. Lookup failures travel through the command error channel.
pub(all) struct SessionPrDetailReply {
  detail : SessionPrDetail?
} derive(Eq, Debug)

///|
pub impl FromJson for SessionPrDetailReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session PR detail reply")
  {
    detail: match object.optional_json("detail") {
      Some(value) => Some(@json.from_json(value, path=path.add_key("detail")))
      None => None
    },
  }
}

///|
pub impl ToJson for SessionPrDetailReply with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  if self.detail is Some(detail) {
    fields["detail"] = detail.to_json()
  }
  Json(fields)
}

///|
/// Desktop's remove affordance deletes just this URL on the host. Unlike a
/// stale frontend read/replace, it cannot erase a concurrent agent addition.
pub(all) struct SessionPrRemovePayload {
  session : String
  url : String
} derive(Eq, Debug)

///|
pub impl FromJson for SessionPrRemovePayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session PR removal")
  {
    session: object.required_string("session"),
    url: object.required_string("url"),
  }
}

///|
pub impl ToJson for SessionPrRemovePayload with fn to_json(self) {
  { "session": self.session, "url": self.url }
}

///|
pub(all) struct SessionPrChangedPayload {
  session : String
} derive(Eq, Debug)

///|
pub impl FromJson for SessionPrChangedPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session PR identity")
  { session: object.required_string("session"), }
}

///|
pub impl ToJson for SessionPrChangedPayload with fn to_json(self) {
  { "session": self.session }
}

///|
pub extend SessionPrBinding with Eq::{equal, not_equal}

///|
pub extend SessionPrBinding with Debug::{to_repr}

///|
pub extend SessionPrBinding with ToJson::{to_json}

///|
pub extend SessionPrBinding with FromJson::{from_json}

///|
pub extend SessionPrBindings with Eq::{equal, not_equal}

///|
pub extend SessionPrBindings with Debug::{to_repr}

///|
pub extend SessionPrBindings with ToJson::{to_json}

///|
pub extend SessionPrBindings with FromJson::{from_json}

///|
pub extend SessionPrDetail with Eq::{equal, not_equal}

///|
pub extend SessionPrDetail with Debug::{to_repr}

///|
pub extend SessionPrDetail with ToJson::{to_json}

///|
pub extend SessionPrDetail with FromJson::{from_json}

///|
pub extend SessionPrRemovePayload with Eq::{equal, not_equal}

///|
pub extend SessionPrRemovePayload with Debug::{to_repr}

///|
pub extend SessionPrRemovePayload with ToJson::{to_json}

///|
pub extend SessionPrRemovePayload with FromJson::{from_json}

///|
pub extend SessionPrChangedPayload with Eq::{equal, not_equal}

///|
pub extend SessionPrChangedPayload with Debug::{to_repr}

///|
pub extend SessionPrChangedPayload with ToJson::{to_json}

///|
pub extend SessionPrChangedPayload with FromJson::{from_json}

///|
pub extend SessionPrDetailReply with Eq::{equal, not_equal}

///|
pub extend SessionPrDetailReply with Debug::{to_repr}

///|
pub extend SessionPrDetailReply with ToJson::{to_json}

///|
pub extend SessionPrDetailReply with FromJson::{from_json}
