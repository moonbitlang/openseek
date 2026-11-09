///|
/// The persisted part of a Cloud history page. Live status and predictions
/// are derived from current observations instead of being restored from disk.
pub(all) struct CloudHistoryCachePage {
  session : SessionDocument
  messages : Array[Json]
  offset : Int32?
  etag : String?
}

///|
pub(all) enum CloudHistoryCacheAction {
  List
  Read(session~ : String)
  Write(session~ : String, page~ : CloudHistoryCachePage)
  Remove(session~ : String)
}

///|
pub(all) struct CloudHistoryCacheRequest {
  token : String
  action : CloudHistoryCacheAction
}

///|
pub(all) struct CloudHistoryCacheEntry {
  session : String
  label : String
}

///|
pub(all) enum CloudHistoryCacheReply {
  Done
  Page(CloudHistoryCachePage?)
  Entries(Array[CloudHistoryCacheEntry])
}

///|
pub impl FromJson for CloudHistoryCachePage with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "Cloud history cache page")
  {
    session: @json.from_json(
      object.required_json("session"),
      path=path.add_key("session"),
    ),
    messages: @json.from_json(
      object.required_json("messages"),
      path=path.add_key("messages"),
    ),
    offset: object.optional_int("offset"),
    etag: object.optional_string("etag"),
  }
}

///|
pub impl ToJson for CloudHistoryCachePage with fn to_json(self) {
  {
    "session": self.session.to_json(),
    "messages": Json(self.messages),
    "offset": self.offset.map_or(Json::null(), value => Json(value)),
    "etag": self.etag.map_or(Json::null(), value => Json(value)),
  }
}

///|
pub impl FromJson for CloudHistoryCacheRequest with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "Cloud history cache request")
  let action = match object.required_string("action") {
    "list" => List
    "read" => Read(session=object.required_string("session"))
    "write" =>
      Write(
        session=object.required_string("session"),
        page=@json.from_json(
          object.required_json("page"),
          path=path.add_key("page"),
        ),
      )
    "remove" => Remove(session=object.required_string("session"))
    _ =>
      raise JsonDecodeError((path.add_key("action"), "unknown cache operation"))
  }
  { token: object.required_string("token"), action, }
}

///|
pub impl ToJson for CloudHistoryCacheRequest with fn to_json(self) {
  let fields : Map[String, Json] = { "token": Json(self.token) }
  match self.action {
    List => fields["action"] = Json("list")
    Read(session~) => {
      fields["action"] = Json("read")
      fields["session"] = Json(session)
    }
    Write(session~, page~) => {
      fields["action"] = Json("write")
      fields["session"] = Json(session)
      fields["page"] = Json(page)
    }
    Remove(session~) => {
      fields["action"] = Json("remove")
      fields["session"] = Json(session)
    }
  }
  Json(fields)
}

///|
pub impl FromJson for CloudHistoryCacheEntry with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "Cloud history cache entry")
  {
    session: object.required_string("session"),
    label: object.required_string("label"),
  }
}

///|
pub impl ToJson for CloudHistoryCacheEntry with fn to_json(self) {
  { "session": self.session, "label": self.label }
}

///|
pub impl FromJson for CloudHistoryCacheReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "Cloud history cache reply")
  match object.required_string("kind") {
    "done" => Done
    "page" =>
      Page(
        object
        .optional_json("page")
        .map(value => @json.from_json(value, path=path.add_key("page"))),
      )
    "entries" =>
      Entries(
        @json.from_json(
          object.required_json("entries"),
          path=path.add_key("entries"),
        ),
      )
    _ => raise JsonDecodeError((path.add_key("kind"), "unknown cache reply"))
  }
}

///|
pub impl ToJson for CloudHistoryCacheReply with fn to_json(self) {
  match self {
    Done => { "kind": "done" }
    Page(page) =>
      {
        "kind": "page",
        "page": page.map_or(Json::null(), value => value.to_json()),
      }
    Entries(entries) => { "kind": "entries", "entries": Json(entries) }
  }
}

///|
pub extend CloudHistoryCachePage with FromJson::{from_json}

///|
pub extend CloudHistoryCachePage with ToJson::{to_json}

///|
pub extend CloudHistoryCacheRequest with FromJson::{from_json}

///|
pub extend CloudHistoryCacheRequest with ToJson::{to_json}

///|
pub extend CloudHistoryCacheEntry with FromJson::{from_json}

///|
pub extend CloudHistoryCacheEntry with ToJson::{to_json}

///|
pub extend CloudHistoryCacheReply with FromJson::{from_json}

///|
pub extend CloudHistoryCacheReply with ToJson::{to_json}

///|
pub fn CloudHistoryCachePage::label(
  page : CloudHistoryCachePage,
  session : String,
) -> String {
  for message in page.messages {
    guard message is { "kind": "user", .. } else { continue }
    let text = match message {
      { "engine_sequence": Number(sequence, ..), .. } if sequence > 0 &&
        sequence == sequence.to_int().to_double() =>
        page.session.events
        .unwrap_or([])
        .iter()
        .find_first(event => {
          event.sequence == sequence.to_int() && event.item is User(_)
        })
        .map_or("", event => {
          match event.item {
            User(user) => user.content.text()
            _ => ""
          }
        })
      { "data": { "content": String(text), .. }, .. } => text
      { "data": { "content": Array(parts), .. }, .. } =>
        parts
        .iter()
        .filter_map(part => {
          match part {
            { "type": "text", "text": String(text), .. } => Some(text)
            _ => None
          }
        })
        .head()
        .unwrap_or("")
      _ => ""
    }
    if !text.is_blank() {
      let line = text.trim().to_owned().split("\n").head().unwrap_or("")
      return String::from_iter(line.iter().take(80))
    }
  }
  session
}
