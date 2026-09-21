///|
pub(all) enum GithubListKind {
  CreatedByMe
  AllOpen
  Issues
} derive(Eq, Debug)

///|
pub impl FromJson for GithubListKind with fn from_json(json, path) {
  match json {
    String("created_by_me") => CreatedByMe
    String("all_open") => AllOpen
    String("issues") => Issues
    _ => raise JsonDecodeError((path, "expected GitHub list kind"))
  }
}

///|
pub impl ToJson for GithubListKind with fn to_json(self) {
  match self {
    CreatedByMe => "created_by_me"
    AllOpen => "all_open"
    Issues => "issues"
  }
}

///|
pub(all) struct GithubListPayload {
  cwd : String
  kind : GithubListKind
  limit : Int
} derive(Eq, Debug)

///|
pub impl FromJson for GithubListPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GitHub list payload")
  {
    cwd: object.required_string("cwd"),
    kind: @json.from_json(
      object.required_json("kind"),
      path=path.add_key("kind"),
    ),
    limit: object.required_int("limit"),
  }
}

///|
pub impl ToJson for GithubListPayload with fn to_json(self) {
  { "cwd": self.cwd, "kind": self.kind.to_json(), "limit": self.limit }
}

///|
pub(all) struct GithubItem {
  number : Int
  title : String
  url : String
  author : String?
  avatar_url : String?
  draft : Bool
} derive(Eq, Debug)

///|
pub impl FromJson for GithubItem with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GitHub item")
  {
    number: object.required_int("number"),
    title: object.required_string("title"),
    url: object.required_string("url"),
    author: object.optional_string("author"),
    avatar_url: object.optional_string("avatar_url"),
    draft: object.required_bool("draft"),
  }
}

///|
pub impl ToJson for GithubItem with fn to_json(self) {
  let fields : Map[String, Json] = {
    "number": self.number.to_json(),
    "title": self.title.to_json(),
    "url": self.url.to_json(),
    "draft": self.draft.to_json(),
  }
  if self.author is Some(author) {
    fields["author"] = author.to_json()
  }
  if self.avatar_url is Some(url) {
    fields["avatar_url"] = url.to_json()
  }
  Json(fields)
}

///|
pub(all) struct GithubListReply {
  repository : String
  repository_url : String
  items : Array[GithubItem]
  has_more : Bool
  avatar_error : String?
} derive(Eq, Debug)

///|
pub impl FromJson for GithubListReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GitHub list reply")
  {
    repository: object.required_string("repository"),
    repository_url: object.required_string("repository_url"),
    items: object.required_array_of("items"),
    has_more: object.required_bool("has_more"),
    avatar_error: object.optional_string("avatar_error"),
  }
}

///|
pub impl ToJson for GithubListReply with fn to_json(self) {
  let fields : Map[String, Json] = {
    "repository": self.repository.to_json(),
    "repository_url": self.repository_url.to_json(),
    "items": self.items.to_json(),
    "has_more": self.has_more.to_json(),
  }
  if self.avatar_error is Some(error) {
    fields["avatar_error"] = error.to_json()
  }
  Json(fields)
}

///|
pub extend GithubListKind with Eq::{equal, not_equal}

///|
pub extend GithubListKind with Debug::{to_repr}

///|
pub extend GithubListKind with FromJson::{from_json}

///|
pub extend GithubListKind with ToJson::{to_json}

///|
pub extend GithubListPayload with Eq::{equal, not_equal}

///|
pub extend GithubListPayload with Debug::{to_repr}

///|
pub extend GithubListPayload with FromJson::{from_json}

///|
pub extend GithubListPayload with ToJson::{to_json}

///|
pub extend GithubItem with Eq::{equal, not_equal}

///|
pub extend GithubItem with Debug::{to_repr}

///|
pub extend GithubItem with FromJson::{from_json}

///|
pub extend GithubItem with ToJson::{to_json}

///|
pub extend GithubListReply with Eq::{equal, not_equal}

///|
pub extend GithubListReply with Debug::{to_repr}

///|
pub extend GithubListReply with FromJson::{from_json}

///|
pub extend GithubListReply with ToJson::{to_json}
