///|
pub(all) enum GithubCheckoutReply {
  CheckoutSuccess(String)
  CheckoutNeedsConfirmation
  CheckoutFailure(String, String?)
} derive(Eq, Debug)

///|
pub impl FromJson for GithubCheckoutReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GitHub checkout reply")
  match object.required_string("status") {
    "success" => CheckoutSuccess(object.required_string("branch"))
    "uncommitted_changes" => CheckoutNeedsConfirmation
    "error" =>
      CheckoutFailure(
        object.required_string("message"),
        object.optional_string("details"),
      )
    _ =>
      raise JsonDecodeError(
        (path.add_key("status"), "expected checkout status"),
      )
  }
}

///|
pub impl ToJson for GithubCheckoutReply with fn to_json(self) {
  match self {
    CheckoutSuccess(branch) => { "status": "success", "branch": branch }
    CheckoutNeedsConfirmation => { "status": "uncommitted_changes" }
    CheckoutFailure(message, details) => {
      let fields : Map[String, Json] = {
        "status": "error",
        "message": message.to_json(),
      }
      if details is Some(details) {
        fields["details"] = details.to_json()
      }
      Json(fields)
    }
  }
}

///|
pub extend GithubCheckoutReply with Eq::{equal, not_equal}

///|
pub extend GithubCheckoutReply with Debug::{to_repr}

///|
pub extend GithubCheckoutReply with FromJson::{from_json}

///|
pub extend GithubCheckoutReply with ToJson::{to_json}

///|
pub(all) enum GithubCheckoutChanges {
  Ask
  Stash
  Discard
  Carry
} derive(Eq, Debug)

///|
pub(all) struct GithubCheckoutPayload {
  cwd : String
  repository_url : String
  number : Int
  changes : GithubCheckoutChanges
  update : Bool
} derive(Eq, Debug)

///|
pub impl FromJson for GithubCheckoutPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GitHub checkout request")
  let changes = match object.required_string("changes") {
    "ask" => Ask
    "stash" => Stash
    "discard" => Discard
    "carry" => Carry
    _ =>
      raise JsonDecodeError(
        (path.add_key("changes"), "expected checkout changes action"),
      )
  }
  {
    cwd: object.required_string("cwd"),
    repository_url: object.required_string("repository_url"),
    number: object.required_int("number"),
    changes,
    update: object.required_bool("update"),
  }
}

///|
pub impl ToJson for GithubCheckoutPayload with fn to_json(self) {
  {
    "cwd": self.cwd,
    "repository_url": self.repository_url,
    "number": self.number,
    "update": self.update,
    "changes": match self.changes {
      Ask => "ask"
      Stash => "stash"
      Discard => "discard"
      Carry => "carry"
    },
  }
}

///|
pub(all) struct GithubWorkspacePayload {
  cwd : String
} derive(Eq, Debug)

///|
pub impl FromJson for GithubWorkspacePayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GitHub workspace request")
  { cwd: object.required_string("cwd"), }
}

///|
pub impl ToJson for GithubWorkspacePayload with fn to_json(self) {
  { "cwd": self.cwd }
}

///|
pub(all) struct GithubCheckoutStatus {
  branch : String?
  pull_request_url : String?
  has_open_pull_request : Bool
} derive(Eq, Debug)

///|
pub impl FromJson for GithubCheckoutStatus with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GitHub checkout status")
  {
    branch: object.optional_string("branch"),
    pull_request_url: object.optional_string("pull_request_url"),
    has_open_pull_request: object.required_bool("has_open_pull_request"),
  }
}

///|
pub impl ToJson for GithubCheckoutStatus with fn to_json(self) {
  let fields : Map[String, Json] = {
    "has_open_pull_request": self.has_open_pull_request.to_json(),
  }
  if self.branch is Some(branch) {
    fields["branch"] = branch.to_json()
  }
  if self.pull_request_url is Some(url) {
    fields["pull_request_url"] = url.to_json()
  }
  Json(fields)
}

///|
pub extend GithubCheckoutChanges with Eq::{equal, not_equal}

///|
pub extend GithubCheckoutStatus with Eq::{equal, not_equal}

///|
pub extend GithubCheckoutPayload with ToJson::{to_json}

///|
pub extend GithubCheckoutPayload with FromJson::{from_json}

///|
pub extend GithubWorkspacePayload with ToJson::{to_json}

///|
pub extend GithubWorkspacePayload with FromJson::{from_json}

///|
pub extend GithubCheckoutStatus with ToJson::{to_json}

///|
pub extend GithubCheckoutStatus with FromJson::{from_json}

///|
pub extend GithubCheckoutChanges with Debug::{to_repr}

///|
pub extend GithubCheckoutPayload with Eq::{equal, not_equal}

///|
pub extend GithubCheckoutPayload with Debug::{to_repr}

///|
pub extend GithubWorkspacePayload with Eq::{equal, not_equal}

///|
pub extend GithubWorkspacePayload with Debug::{to_repr}

///|
pub extend GithubCheckoutStatus with Debug::{to_repr}
