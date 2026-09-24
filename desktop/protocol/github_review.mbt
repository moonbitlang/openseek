// GitHub review threads are independent of agent feedback. Drafts never cross
// this boundary; only an explicit Send produces a mutation.

///|
pub(all) enum GithubReviewAction {
  Post(
    path~ : String,
    side~ : String,
    line~ : Int,
    body~ : String,
    head~ : String
  )
  Reply(comment~ : String, body~ : String)
  Delete(comment~ : String)
  Resolve(thread~ : String, resolved~ : Bool)
} derive(Eq, Debug)

///|
pub impl FromJson for GithubReviewAction with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GitHub review action")
  match object.required_string("kind") {
    "post" =>
      Post(
        path=object.required_string("path"),
        side=object.required_string("side"),
        line=object.required_int("line"),
        body=object.required_string("body"),
        head=object.required_string("head"),
      )
    "reply" =>
      Reply(
        comment=object.required_string("comment"),
        body=object.required_string("body"),
      )
    "delete" => Delete(comment=object.required_string("comment"))
    "resolve" =>
      Resolve(
        thread=object.required_string("thread"),
        resolved=object.required_bool("resolved"),
      )
    _ => raise JsonDecodeError((path, "expected GitHub review action"))
  }
}

///|
pub impl ToJson for GithubReviewAction with fn to_json(self) {
  match self {
    Post(path~, side~, line~, body~, head~) =>
      {
        "kind": "post",
        "path": path,
        "side": side,
        "line": line,
        "body": body,
        "head": head,
      }
    Reply(comment~, body~) =>
      { "kind": "reply", "comment": comment, "body": body }
    Delete(comment~) => { "kind": "delete", "comment": comment }
    Resolve(thread~, resolved~) =>
      { "kind": "resolve", "thread": thread, "resolved": resolved }
  }
}

///|
pub extend GithubReviewAction with Eq::{equal, not_equal}

///|
pub extend GithubReviewAction with Debug::{to_repr}

///|
pub(all) enum GithubReviewReply {
  ReviewLoaded(GithubReview?)
  ReviewLoadFailed(String)
} derive(Eq, Debug)

///|
pub impl FromJson for GithubReviewReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GitHub review reply")
  match object.required_string("status") {
    "ok" =>
      ReviewLoaded(
        object.optional_json("review").map(value => @json.from_json(value)),
      )
    "error" => ReviewLoadFailed(object.required_string("message"))
    _ => raise JsonDecodeError((path, "expected review reply status"))
  }
}

///|
pub impl ToJson for GithubReviewReply with fn to_json(self) {
  match self {
    ReviewLoaded(Some(review)) => { "status": "ok", "review": review.to_json() }
    ReviewLoaded(None) => { "status": "ok" }
    ReviewLoadFailed(message) => { "status": "error", "message": message }
  }
}

///|
pub(all) enum GithubReviewMutationReply {
  ReviewMutationSuccess
  ReviewMutationFailure(String)
} derive(Eq, Debug)

///|
pub impl FromJson for GithubReviewMutationReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GitHub review mutation reply")
  match object.required_string("status") {
    "ok" => ReviewMutationSuccess
    "error" => ReviewMutationFailure(object.required_string("message"))
    _ => raise JsonDecodeError((path, "expected review mutation status"))
  }
}

///|
pub impl ToJson for GithubReviewMutationReply with fn to_json(self) {
  match self {
    ReviewMutationSuccess => { "status": "ok" }
    ReviewMutationFailure(message) => { "status": "error", "message": message }
  }
}

///|
pub(all) struct GithubReviewComment {
  id : String
  body_html : String
  url : String
  author : String?
  avatar_url : String?
  created_at : String
  can_delete : Bool
} derive(Eq, Debug)

///|
pub impl FromJson for GithubReviewComment with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GithubReviewComment")
  {
    id: object.required_string("id"),
    body_html: object.required_string("body_html"),
    url: object.required_string("url"),
    author: object.optional_string("author"),
    avatar_url: object.optional_string("avatar_url"),
    created_at: object.required_string("created_at"),
    can_delete: object.required_bool("can_delete"),
  }
}

///|
pub impl ToJson for GithubReviewComment with fn to_json(self) {
  let fields : Map[String, Json] = {
    "id": self.id.to_json(),
    "body_html": self.body_html.to_json(),
    "url": self.url.to_json(),
    "created_at": self.created_at.to_json(),
    "can_delete": self.can_delete.to_json(),
  }
  if self.author is Some(value) {
    fields["author"] = value.to_json()
  }
  if self.avatar_url is Some(value) {
    fields["avatar_url"] = value.to_json()
  }
  Json(fields)
}

///|
pub extend GithubReviewComment with Eq::{equal, not_equal}

///|
pub extend GithubReviewComment with Debug::{to_repr}

///|
pub(all) struct GithubReviewThread {
  id : String
  path : String
  side : String
  line : Int?
  original_line : Int?
  resolved : Bool
  outdated : Bool
  can_reply : Bool
  can_resolve : Bool
  can_unresolve : Bool
  comments : Array[GithubReviewComment]
} derive(Eq, Debug)

///|
pub impl FromJson for GithubReviewThread with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GithubReviewThread")
  {
    id: object.required_string("id"),
    path: object.required_string("path"),
    side: object.required_string("side"),
    line: object.optional_int("line"),
    original_line: object.optional_int("original_line"),
    resolved: object.required_bool("resolved"),
    outdated: object.required_bool("outdated"),
    can_reply: object.required_bool("can_reply"),
    can_resolve: object.required_bool("can_resolve"),
    can_unresolve: object.required_bool("can_unresolve"),
    comments: @json.from_json(object.required_json("comments")),
  }
}

///|
pub impl ToJson for GithubReviewThread with fn to_json(self) {
  let fields : Map[String, Json] = {
    "id": self.id.to_json(),
    "path": self.path.to_json(),
    "side": self.side.to_json(),
    "resolved": self.resolved.to_json(),
    "outdated": self.outdated.to_json(),
    "can_reply": self.can_reply.to_json(),
    "can_resolve": self.can_resolve.to_json(),
    "can_unresolve": self.can_unresolve.to_json(),
    "comments": self.comments.to_json(),
  }
  if self.line is Some(value) {
    fields["line"] = value.to_json()
  }
  if self.original_line is Some(value) {
    fields["original_line"] = value.to_json()
  }
  Json(fields)
}

///|
pub extend GithubReviewThread with Eq::{equal, not_equal}

///|
pub extend GithubReviewThread with Debug::{to_repr}

///|
pub(all) struct GithubReviewFile {
  path : String
  original : String?
  modified : String?
} derive(Eq, Debug)

///|
pub impl FromJson for GithubReviewFile with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GithubReviewFile")
  {
    path: object.required_string("path"),
    original: object.optional_string("original"),
    modified: object.optional_string("modified"),
  }
}

///|
pub impl ToJson for GithubReviewFile with fn to_json(self) {
  let fields : Map[String, Json] = { "path": self.path.to_json() }
  if self.original is Some(text) {
    fields["original"] = text.to_json()
  }
  if self.modified is Some(text) {
    fields["modified"] = text.to_json()
  }
  Json(fields)
}

///|
pub extend GithubReviewFile with Eq::{equal, not_equal}

///|
pub extend GithubReviewFile with Debug::{to_repr}

///|
pub(all) struct GithubReviewFilePayload {
  cwd : String
  path : String
  base : String
  head : String
} derive(Eq, Debug)

///|
pub impl FromJson for GithubReviewFilePayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GitHub review file request")
  {
    cwd: object.required_string("cwd"),
    path: object.required_string("path"),
    base: object.required_string("base"),
    head: object.required_string("head"),
  }
}

///|
pub impl ToJson for GithubReviewFilePayload with fn to_json(self) {
  { "cwd": self.cwd, "path": self.path, "base": self.base, "head": self.head }
}

///|
pub(all) enum GithubReviewFileReply {
  ReviewFileLoaded(GithubReviewFile?)
  ReviewFileFailed(String)
} derive(Eq, Debug)

///|
pub impl FromJson for GithubReviewFileReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GitHub review file reply")
  match object.required_string("status") {
    "ok" =>
      ReviewFileLoaded(
        object.optional_json("file").map(value => @json.from_json(value)),
      )
    "error" => ReviewFileFailed(object.required_string("message"))
    _ => raise JsonDecodeError((path, "expected review file reply status"))
  }
}

///|
pub impl ToJson for GithubReviewFileReply with fn to_json(self) {
  match self {
    ReviewFileLoaded(Some(file)) => { "status": "ok", "file": file.to_json() }
    ReviewFileLoaded(None) => { "status": "ok" }
    ReviewFileFailed(message) => { "status": "error", "message": message }
  }
}

///|
pub extend GithubReviewFilePayload with Eq::{equal, not_equal}

///|
pub extend GithubReviewFilePayload with Debug::{to_repr}

///|
pub extend GithubReviewFilePayload with FromJson::{from_json}

///|
pub extend GithubReviewFilePayload with ToJson::{to_json}

///|
pub extend GithubReviewFileReply with Eq::{equal, not_equal}

///|
pub extend GithubReviewFileReply with Debug::{to_repr}

///|
pub extend GithubReviewFileReply with FromJson::{from_json}

///|
pub extend GithubReviewFileReply with ToJson::{to_json}

///|
pub(all) struct GithubReview {
  url : String
  head : String
  base : String
  threads : Array[GithubReviewThread]
  commentable : Array[GithubCommentableFile]
} derive(Eq, Debug)

///|
pub impl FromJson for GithubReview with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GithubReview")
  {
    url: object.required_string("url"),
    head: object.required_string("head"),
    base: object.required_string("base"),
    threads: @json.from_json(object.required_json("threads")),
    commentable: @json.from_json(object.required_json("commentable")),
  }
}

///|
pub impl ToJson for GithubReview with fn to_json(self) {
  {
    "url": self.url.to_json(),
    "head": self.head.to_json(),
    "base": self.base.to_json(),
    "threads": self.threads.to_json(),
    "commentable": self.commentable.to_json(),
  }
}

///|
pub extend GithubReview with Eq::{equal, not_equal}

///|
pub extend GithubReview with Debug::{to_repr}

///|
pub(all) struct GithubReviewMutationPayload {
  cwd : String
  url : String
  action : GithubReviewAction
} derive(Eq, Debug)

///|
pub impl FromJson for GithubReviewMutationPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GithubReviewMutationPayload")
  {
    cwd: object.required_string("cwd"),
    url: object.required_string("url"),
    action: @json.from_json(object.required_json("action")),
  }
}

///|
pub impl ToJson for GithubReviewMutationPayload with fn to_json(self) {
  let fields : Map[String, Json] = {
    "cwd": self.cwd.to_json(),
    "url": self.url.to_json(),
    "action": self.action.to_json(),
  }
  Json(fields)
}

///|
pub extend GithubReviewMutationPayload with Eq::{equal, not_equal}

///|
pub extend GithubReviewMutationPayload with Debug::{to_repr}

///|
pub extend GithubReviewAction with ToJson::{to_json}

///|
pub extend GithubReviewAction with FromJson::{from_json}

///|
pub extend GithubReviewReply with ToJson::{to_json}

///|
pub extend GithubReviewReply with FromJson::{from_json}

///|
pub extend GithubReviewReply with Eq::{equal, not_equal}

///|
pub extend GithubReviewReply with Debug::{to_repr}

///|
pub extend GithubReviewMutationReply with ToJson::{to_json}

///|
pub extend GithubReviewMutationReply with FromJson::{from_json}

///|
pub extend GithubReviewMutationReply with Eq::{equal, not_equal}

///|
pub extend GithubReviewMutationReply with Debug::{to_repr}

///|
pub extend GithubReviewComment with ToJson::{to_json}

///|
pub extend GithubReviewComment with FromJson::{from_json}

///|
pub extend GithubReviewThread with ToJson::{to_json}

///|
pub extend GithubReviewThread with FromJson::{from_json}

///|
pub extend GithubReviewFile with ToJson::{to_json}

///|
pub extend GithubReviewFile with FromJson::{from_json}

///|
pub extend GithubReview with ToJson::{to_json}

///|
pub extend GithubReview with FromJson::{from_json}

///|
pub extend GithubReviewMutationPayload with ToJson::{to_json}

///|
pub extend GithubReviewMutationPayload with FromJson::{from_json}
