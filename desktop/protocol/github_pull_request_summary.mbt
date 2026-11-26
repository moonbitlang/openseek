///|
/// A pull request lookup by address alone, with no checkout or conversation
/// behind it.
#derive(Eq, Debug)
pub(all) struct GithubPullRequestSummaryPayload {
  url : String
}

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
#derive(Eq, Debug)
pub(all) struct GithubPullRequestSummaryReply {
  pull_request : GitPullRequest?
}

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
/// A batched pull request lookup by address alone, used to resolve sidebar
/// status across many sessions in minimal GraphQL queries.
#derive(Eq, Debug)
pub(all) struct GithubPullRequestSummariesPayload {
  urls : Array[String]
}

///|
pub impl FromJson for GithubPullRequestSummariesPayload with fn from_json(
  json,
  path,
) {
  let object = JsonObject::decode(
    json, path, "GithubPullRequestSummariesPayload",
  )
  let raw_urls : Array[String] = @json.from_json(
    object.required_json("urls"),
    path=path.add_key("urls"),
  )
  let urls : Array[String] = []
  let urls_path = path.add_key("urls")
  for index, url in raw_urls {
    let normalized = normalize_pr_url(url, urls_path.add_index(index))
    if !urls.contains(normalized) {
      urls.push(normalized)
    }
  }
  { urls, }
}

///|
pub impl ToJson for GithubPullRequestSummariesPayload with fn to_json(self) {
  { "urls": Json(self.urls) }
}

///|
/// Resolved pull request summaries keyed by requested URL. Addresses that do
/// not name a pull request or failed to resolve are omitted.
#derive(Eq, Debug)
pub(all) struct GithubPullRequestSummariesReply {
  pull_requests : Map[String, GitPullRequest]
}

///|
pub impl FromJson for GithubPullRequestSummariesReply with fn from_json(
  json,
  path,
) {
  let object = JsonObject::decode(json, path, "GithubPullRequestSummariesReply")
  let entries = JsonObject::decode(
    object.required_json("pull_requests"),
    path.add_key("pull_requests"),
    "GithubPullRequestSummariesReply.pull_requests",
  )
  let pull_requests : Map[String, GitPullRequest] = Map([])
  let map_path = path.add_key("pull_requests")
  for url, value in entries.fields {
    pull_requests[url] = @json.from_json(value, path=map_path.add_key(url))
  }
  { pull_requests, }
}

///|
pub impl ToJson for GithubPullRequestSummariesReply with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  for url, pull_request in self.pull_requests {
    fields[url] = pull_request.to_json()
  }
  { "pull_requests": Json(fields) }
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

///|
pub extend GithubPullRequestSummariesPayload with Eq::{equal, not_equal}

///|
pub extend GithubPullRequestSummariesPayload with Debug::{to_repr}

///|
pub extend GithubPullRequestSummariesPayload with FromJson::{from_json}

///|
pub extend GithubPullRequestSummariesPayload with ToJson::{to_json}

///|
pub extend GithubPullRequestSummariesReply with Eq::{equal, not_equal}

///|
pub extend GithubPullRequestSummariesReply with Debug::{to_repr}

///|
pub extend GithubPullRequestSummariesReply with FromJson::{from_json}

///|
pub extend GithubPullRequestSummariesReply with ToJson::{to_json}
