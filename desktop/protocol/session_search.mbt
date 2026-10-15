// Title search across the host’s registered session stores.

///|
pub(all) struct SessionSearchPayload {
  query : String
  include_archived : Bool
} derive(Debug, Eq)

///|
pub impl FromJson for SessionSearchPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session search")
  {
    query: object.required_string("query"),
    include_archived: object.required_bool("include_archived"),
  }
}

///|
pub impl ToJson for SessionSearchPayload with fn to_json(self) {
  let fields : Map[String, Json] = {
    "query": ToJson::to_json(self.query),
    "include_archived": ToJson::to_json(self.include_archived),
  }
  Json(fields)
}

///|
pub extend SessionSearchPayload with Debug::{to_repr}

///|
pub extend SessionSearchPayload with Eq::{equal, not_equal}

///|
pub extend SessionSearchPayload with FromJson::{from_json}

///|
pub extend SessionSearchPayload with ToJson::{to_json}

///|
pub(all) struct SessionSearchHit {
  session : String
  workspace : String
  title : String
  archived : Bool
  updated_at_ms : Double?
} derive(Debug, Eq)

///|
pub impl FromJson for SessionSearchHit with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session search")
  {
    session: object.required_string("session"),
    workspace: object.required_string("workspace"),
    title: object.required_string("title"),
    archived: object.required_bool("archived"),
    updated_at_ms: object
    .optional_json("updated_at_ms")
    .map(value => @json.from_json(value, path=path.add_key("updated_at_ms"))),
  }
}

///|
pub impl ToJson for SessionSearchHit with fn to_json(self) {
  let fields : Map[String, Json] = {
    "session": ToJson::to_json(self.session),
    "workspace": ToJson::to_json(self.workspace),
    "title": ToJson::to_json(self.title),
    "archived": ToJson::to_json(self.archived),
  }
  if self.updated_at_ms is Some(value) {
    fields["updated_at_ms"] = Json(value)
  }
  Json(fields)
}

///|
pub extend SessionSearchHit with Debug::{to_repr}

///|
pub extend SessionSearchHit with Eq::{equal, not_equal}

///|
pub extend SessionSearchHit with FromJson::{from_json}

///|
pub extend SessionSearchHit with ToJson::{to_json}

///|
pub(all) struct SessionSearchReply {
  hits : Array[SessionSearchHit]
  errors : Array[String]
  has_more : Bool
} derive(Debug, Eq)

///|
pub impl FromJson for SessionSearchReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "session search")
  {
    hits: @json.from_json(
      object.required_json("hits"),
      path=path.add_key("hits"),
    ),
    errors: @json.from_json(
      object.required_json("errors"),
      path=path.add_key("errors"),
    ),
    has_more: object.required_bool("has_more"),
  }
}

///|
pub impl ToJson for SessionSearchReply with fn to_json(self) {
  let fields : Map[String, Json] = {
    "hits": ToJson::to_json(self.hits),
    "errors": ToJson::to_json(self.errors),
    "has_more": ToJson::to_json(self.has_more),
  }
  Json(fields)
}

///|
pub extend SessionSearchReply with Debug::{to_repr}

///|
pub extend SessionSearchReply with Eq::{equal, not_equal}

///|
pub extend SessionSearchReply with FromJson::{from_json}

///|
pub extend SessionSearchReply with ToJson::{to_json}
