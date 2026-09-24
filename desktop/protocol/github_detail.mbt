///|
pub(all) struct GithubPullRequestPayload {
  cwd : String
  repository_url : String
  number : Int
} derive(Eq, Debug)

///|
pub impl FromJson for GithubPullRequestPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GitHub pull request payload")
  {
    cwd: object.required_string("cwd"),
    repository_url: object.required_string("repository_url"),
    number: object.required_int("number"),
  }
}

///|
pub impl ToJson for GithubPullRequestPayload with fn to_json(self) {
  {
    "cwd": self.cwd,
    "repository_url": self.repository_url,
    "number": self.number,
  }
}

///|
pub(all) struct GithubComment {
  author : String?
  body_html : String
  url : String
  created_at : String
} derive(Eq, Debug)

///|
pub impl FromJson for GithubComment with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GitHub comment")
  {
    author: object.optional_string("author"),
    body_html: object.required_string("body_html"),
    url: object.required_string("url"),
    created_at: object.required_string("created_at"),
  }
}

///|
pub impl ToJson for GithubComment with fn to_json(self) {
  let fields : Map[String, Json] = {
    "body_html": self.body_html.to_json(),
    "url": self.url.to_json(),
    "created_at": self.created_at.to_json(),
  }
  if self.author is Some(author) {
    fields["author"] = author.to_json()
  }
  Json(fields)
}

///|
pub(all) struct GithubCheck {
  name : String
  state : String
  url : String?
  workflow : String?
} derive(Eq, Debug)

///|
pub impl FromJson for GithubCheck with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GitHub check")
  {
    name: object.required_string("name"),
    state: object.required_string("state"),
    url: object.optional_string("url"),
    workflow: object.optional_string("workflow"),
  }
}

///|
pub impl ToJson for GithubCheck with fn to_json(self) {
  let fields : Map[String, Json] = {
    "name": self.name.to_json(),
    "state": self.state.to_json(),
  }
  if self.url is Some(url) {
    fields["url"] = url.to_json()
  }
  if self.workflow is Some(workflow) {
    fields["workflow"] = workflow.to_json()
  }
  Json(fields)
}

///|
pub(all) struct GithubReviewer {
  name : String
  state : String
} derive(Eq, Debug)

///|
pub impl FromJson for GithubReviewer with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GitHub reviewer")
  {
    name: object.required_string("name"),
    state: object.required_string("state"),
  }
}

///|
pub impl ToJson for GithubReviewer with fn to_json(self) {
  { "name": self.name, "state": self.state }
}

///|
pub(all) struct GithubPullRequestDetail {
  item : GithubItem
  state : String
  mergeable : String
  body_html : String
  base : String
  head : String
  additions : Int
  deletions : Int
  changed_files : Int
  comments : Array[GithubComment]
  checks : Array[GithubCheck]
  created_at : String
  reviewers : Array[GithubReviewer]
  assignees : Array[String]
  labels : Array[String]
  milestone : String?
} derive(Eq, Debug)

///|
pub impl FromJson for GithubPullRequestDetail with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GitHub pull request detail")
  {
    item: @json.from_json(
      object.required_json("item"),
      path=path.add_key("item"),
    ),
    state: object.required_string("state"),
    mergeable: object.required_string("mergeable"),
    body_html: object.required_string("body_html"),
    base: object.required_string("base"),
    head: object.required_string("head"),
    additions: object.required_int("additions"),
    deletions: object.required_int("deletions"),
    changed_files: object.required_int("changed_files"),
    comments: object.required_array_of("comments"),
    checks: object.required_array_of("checks"),
    created_at: object.required_string("created_at"),
    reviewers: object.required_array_of("reviewers"),
    assignees: object.required_array_of("assignees"),
    labels: object.required_array_of("labels"),
    milestone: object.optional_string("milestone"),
  }
}

///|
pub impl ToJson for GithubPullRequestDetail with fn to_json(self) {
  let fields : Map[String, Json] = {
    "item": self.item.to_json(),
    "state": self.state,
    "mergeable": self.mergeable,
    "body_html": self.body_html,
    "base": self.base,
    "head": self.head,
    "additions": self.additions,
    "deletions": self.deletions,
    "changed_files": self.changed_files,
    "comments": self.comments.to_json(),
    "checks": self.checks.to_json(),
    "created_at": self.created_at.to_json(),
    "reviewers": self.reviewers.to_json(),
    "assignees": self.assignees.to_json(),
    "labels": self.labels.to_json(),
  }
  if self.milestone is Some(milestone) {
    fields["milestone"] = milestone.to_json()
  }
  Json(fields)
}

///|
pub extend GithubPullRequestPayload with Eq::{equal, not_equal}

///|
pub extend GithubPullRequestPayload with Debug::{to_repr}

///|
pub extend GithubPullRequestPayload with FromJson::{from_json}

///|
pub extend GithubPullRequestPayload with ToJson::{to_json}

///|
pub extend GithubComment with Eq::{equal, not_equal}

///|
pub extend GithubComment with Debug::{to_repr}

///|
pub extend GithubComment with FromJson::{from_json}

///|
pub extend GithubComment with ToJson::{to_json}

///|
pub extend GithubCheck with Eq::{equal, not_equal}

///|
pub extend GithubCheck with Debug::{to_repr}

///|
pub extend GithubCheck with FromJson::{from_json}

///|
pub extend GithubCheck with ToJson::{to_json}

///|
pub extend GithubReviewer with Eq::{equal, not_equal}

///|
pub extend GithubReviewer with Debug::{to_repr}

///|
pub extend GithubReviewer with FromJson::{from_json}

///|
pub extend GithubReviewer with ToJson::{to_json}

///|
pub extend GithubPullRequestDetail with Eq::{equal, not_equal}

///|
pub extend GithubPullRequestDetail with Debug::{to_repr}

///|
pub extend GithubPullRequestDetail with FromJson::{from_json}

///|
pub extend GithubPullRequestDetail with ToJson::{to_json}
