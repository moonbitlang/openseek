///|
/// A pull request lookup by address alone, with no checkout or conversation
/// behind it.
pub(all) struct GithubPullRequestSummaryPayload {
  url : String
} derive(Eq, Debug)

///|
pub impl FromJson for GithubPullRequestSummaryPayload with fn from_json(
  json,
  path,
) {
  let object = JsonObject::decode(json, path, "GithubPullRequestSummaryPayload")
  { url: normalize_pr_url(object.required_string("url"), path), }
}

///|
pub impl ToJson for GithubPullRequestSummaryPayload with fn to_json(self) {
  { "url": self.url }
}

///|
/// `pull_request` is absent when the address is not a pull request's; a
/// lookup that failed answers through the error channel instead.
pub(all) struct GithubPullRequestSummaryReply {
  pull_request : GitPullRequest?
} derive(Eq, Debug)

///|
pub impl FromJson for GithubPullRequestSummaryReply with fn from_json(
  json,
  path,
) {
  let object = JsonObject::decode(json, path, "GithubPullRequestSummaryReply")
  {
    pull_request: object
    .optional_json("pull_request")
    .map(value => @json.from_json(value, path=path.add_key("pull_request"))),
  }
}

///|
pub impl ToJson for GithubPullRequestSummaryReply with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  if self.pull_request is Some(pull_request) {
    fields["pull_request"] = pull_request.to_json()
  }
  Json(fields)
}

///|
pub extend GithubPullRequestSummaryPayload with Eq::{equal, not_equal}

///|
pub extend GithubPullRequestSummaryPayload with Debug::{to_repr}

///|
pub extend GithubPullRequestSummaryPayload with FromJson::{from_json}

///|
pub extend GithubPullRequestSummaryPayload with ToJson::{to_json}

///|
pub extend GithubPullRequestSummaryReply with Eq::{equal, not_equal}

///|
pub extend GithubPullRequestSummaryReply with Debug::{to_repr}

///|
pub extend GithubPullRequestSummaryReply with FromJson::{from_json}

///|
pub extend GithubPullRequestSummaryReply with ToJson::{to_json}
