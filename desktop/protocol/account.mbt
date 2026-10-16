///|
/// Stable account identity; login and avatar are display metadata.
pub(all) struct AccountUser {
  user_id : String
  login : String
  avatar_url : String
} derive(Eq)

///|
/// The current client's account credential, never part of host broadcasts.
pub(all) struct AccountSession {
  token : String
  user : AccountUser
} derive(Eq)

///|
pub(all) struct AccountSessionReply {
  session : AccountSession?
} derive(Eq)

///|
pub(all) struct RemoteAccessPayload {
  enabled : Bool
} derive(Eq)

///|
pub impl FromJson for AccountUser with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "account user")
  let user_id = object.required_string("user_id")
  let login = object.required_string("login")
  guard !user_id.is_blank() && !login.is_blank() else {
    raise JsonDecodeError((path, "account identity must not be blank"))
  }
  { user_id, login, avatar_url: object.required_string("avatar_url"), }
}

///|
pub impl ToJson for AccountUser with fn to_json(self) {
  {
    "user_id": self.user_id,
    "login": self.login,
    "avatar_url": self.avatar_url,
  }
}

///|
pub impl FromJson for AccountSession with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "account session")
  let token = object.required_string("token")
  guard token.has_prefix("ts_") && token.length() > 3 else {
    raise JsonDecodeError((path.add_key("token"), "expected account token"))
  }
  {
    token,
    user: @json.from_json(
      object.required_json("user"),
      path=path.add_key("user"),
    ),
  }
}

///|
pub impl ToJson for AccountSession with fn to_json(self) {
  { "token": self.token, "user": self.user.to_json() }
}

///|
pub impl FromJson for AccountSessionReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "account session reply")
  {
    session: object
    .optional_json("session")
    .map(value => @json.from_json(value, path=path.add_key("session"))),
  }
}

///|
pub impl ToJson for AccountSessionReply with fn to_json(self) {
  match self.session {
    Some(session) => { "session": session.to_json() }
    None => {
      let fields : Map[String, Json] = Map([])
      Json(fields)
    }
  }
}

///|
pub impl FromJson for RemoteAccessPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "remote access payload")
  {
    enabled: @json.from_json(
      object.required_json("enabled"),
      path=path.add_key("enabled"),
    ),
  }
}

///|
pub impl ToJson for RemoteAccessPayload with fn to_json(self) {
  { "enabled": self.enabled }
}

///|
pub extend AccountUser with Eq::{equal, not_equal}

///|
pub extend AccountUser with FromJson::{from_json}

///|
pub extend AccountUser with ToJson::{to_json}

///|
pub extend AccountSession with Eq::{equal, not_equal}

///|
pub extend AccountSession with FromJson::{from_json}

///|
pub extend AccountSession with ToJson::{to_json}

///|
pub extend AccountSessionReply with Eq::{equal, not_equal}

///|
pub extend AccountSessionReply with FromJson::{from_json}

///|
pub extend AccountSessionReply with ToJson::{to_json}

///|
pub extend RemoteAccessPayload with Eq::{equal, not_equal}

///|
pub extend RemoteAccessPayload with FromJson::{from_json}

///|
pub extend RemoteAccessPayload with ToJson::{to_json}
