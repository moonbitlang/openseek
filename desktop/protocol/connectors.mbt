///|
#derive(Debug, Eq)
pub(all) struct ConnectorRequest {
  id : String
  attempt : String?
}

///|
pub impl ToJson for ConnectorRequest with fn to_json(self) {
  {
    "id": Json(self.id),
    "attempt": if self.attempt is Some(value) {
      Json(value)
    } else {
      Json::null()
    },
  }
}

///|
pub impl FromJson for ConnectorRequest with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "ConnectorRequest")
  {
    id: @json.from_json(object.required_json("id"), path=path.add_key("id")),
    attempt: if object.required_json("attempt") is Null {
      None
    } else {
      Some(
        @json.from_json(
          object.required_json("attempt"),
          path=path.add_key("attempt"),
        ),
      )
    },
  }
}

///|
pub extend ConnectorRequest with Eq::{equal, not_equal}

///|
pub extend ConnectorRequest with Debug::{to_repr}

///|
pub extend ConnectorRequest with ToJson::{to_json}

///|
pub extend ConnectorRequest with FromJson::{from_json}

///|
#derive(Debug, Eq)
pub(all) struct ConnectorAuthorization {
  attempt : String
  url : String
  code : String
}

///|
pub impl ToJson for ConnectorAuthorization with fn to_json(self) {
  {
    "attempt": Json(self.attempt),
    "url": Json(self.url),
    "code": Json(self.code),
  }
}

///|
pub impl FromJson for ConnectorAuthorization with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "ConnectorAuthorization")
  {
    attempt: @json.from_json(
      object.required_json("attempt"),
      path=path.add_key("attempt"),
    ),
    url: @json.from_json(object.required_json("url"), path=path.add_key("url")),
    code: @json.from_json(
      object.required_json("code"),
      path=path.add_key("code"),
    ),
  }
}

///|
pub extend ConnectorAuthorization with Eq::{equal, not_equal}

///|
pub extend ConnectorAuthorization with Debug::{to_repr}

///|
pub extend ConnectorAuthorization with ToJson::{to_json}

///|
pub extend ConnectorAuthorization with FromJson::{from_json}

///|
#derive(Debug, Eq)
pub(all) struct ConnectorInfo {
  id : String
  name : String
  skill : String
  source : String
  // "oauth" means configuration validated; credential errors retain actions.
  auth : String
  connected : Bool
  error : String?
}

///|
pub impl ToJson for ConnectorInfo with fn to_json(self) {
  {
    "id": Json(self.id),
    "name": Json(self.name),
    "skill": Json(self.skill),
    "source": Json(self.source),
    "auth": Json(self.auth),
    "connected": Json(self.connected),
    "error": if self.error is Some(value) {
      Json(value)
    } else {
      Json::null()
    },
  }
}

///|
pub impl FromJson for ConnectorInfo with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "ConnectorInfo")
  {
    id: @json.from_json(object.required_json("id"), path=path.add_key("id")),
    name: @json.from_json(
      object.required_json("name"),
      path=path.add_key("name"),
    ),
    skill: @json.from_json(
      object.required_json("skill"),
      path=path.add_key("skill"),
    ),
    source: @json.from_json(
      object.required_json("source"),
      path=path.add_key("source"),
    ),
    auth: @json.from_json(
      object.required_json("auth"),
      path=path.add_key("auth"),
    ),
    connected: @json.from_json(
      object.required_json("connected"),
      path=path.add_key("connected"),
    ),
    error: if object.required_json("error") is Null {
      None
    } else {
      Some(
        @json.from_json(
          object.required_json("error"),
          path=path.add_key("error"),
        ),
      )
    },
  }
}

///|
pub extend ConnectorInfo with Eq::{equal, not_equal}

///|
pub extend ConnectorInfo with Debug::{to_repr}

///|
pub extend ConnectorInfo with ToJson::{to_json}

///|
pub extend ConnectorInfo with FromJson::{from_json}

///|
#derive(Debug, Eq)
pub(all) struct ConnectorReply {
  connectors : Array[ConnectorInfo]
  authorization : ConnectorAuthorization?
  error : String?
}

///|
pub impl ToJson for ConnectorReply with fn to_json(self) {
  {
    "connectors": Json(self.connectors),
    "authorization": if self.authorization is Some(value) {
      Json(value)
    } else {
      Json::null()
    },
    "error": if self.error is Some(value) {
      Json(value)
    } else {
      Json::null()
    },
  }
}

///|
pub impl FromJson for ConnectorReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "ConnectorReply")
  {
    connectors: @json.from_json(
      object.required_json("connectors"),
      path=path.add_key("connectors"),
    ),
    authorization: if object.required_json("authorization") is Null {
      None
    } else {
      Some(
        @json.from_json(
          object.required_json("authorization"),
          path=path.add_key("authorization"),
        ),
      )
    },
    error: if object.required_json("error") is Null {
      None
    } else {
      Some(
        @json.from_json(
          object.required_json("error"),
          path=path.add_key("error"),
        ),
      )
    },
  }
}

///|
pub extend ConnectorReply with Eq::{equal, not_equal}

///|
pub extend ConnectorReply with Debug::{to_repr}

///|
pub extend ConnectorReply with ToJson::{to_json}

///|
pub extend ConnectorReply with FromJson::{from_json}
