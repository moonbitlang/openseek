///|
/// A pull request lookup by address alone, with no checkout or conversation
/// behind it.
pub(all) struct GithubPrDetailPayload {
  url : String
} derive(Eq, Debug)

///|
pub impl FromJson for GithubPrDetailPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GithubPrDetailPayload")
  { url: normalize_pr_url(object.required_string("url"), path), }
}

///|
pub impl ToJson for GithubPrDetailPayload with fn to_json(self) {
  { "url": self.url }
}

///|
/// `pull_request` is absent when the address is not a pull request's; a
/// lookup that failed answers through the error channel instead.
pub(all) struct GithubPrDetailReply {
  pull_request : GitPullRequest?
} derive(Eq, Debug)

///|
pub impl FromJson for GithubPrDetailReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GithubPrDetailReply")
  {
    pull_request: object
    .optional_json("pull_request")
    .map(value => @json.from_json(value, path=path.add_key("pull_request"))),
  }
}

///|
pub impl ToJson for GithubPrDetailReply with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  if self.pull_request is Some(pull_request) {
    fields["pull_request"] = pull_request.to_json()
  }
  Json(fields)
}

///|
pub extend GithubPrDetailPayload with Eq::{equal, not_equal}

///|
pub extend GithubPrDetailPayload with Debug::{to_repr}

///|
pub extend GithubPrDetailPayload with FromJson::{from_json}

///|
pub extend GithubPrDetailPayload with ToJson::{to_json}

///|
pub extend GithubPrDetailReply with Eq::{equal, not_equal}

///|
pub extend GithubPrDetailReply with Debug::{to_repr}

///|
pub extend GithubPrDetailReply with FromJson::{from_json}

///|
pub extend GithubPrDetailReply with ToJson::{to_json}
