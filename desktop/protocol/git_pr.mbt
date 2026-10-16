///|
/// A remote PR lookup independent of any session association.
pub(all) struct GitPrDetailPayload {
  url : String
} derive(Eq, Debug)

///|
pub impl FromJson for GitPrDetailPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GitPrDetailPayload")
  { url: normalize_pr_url(object.required_string("url"), path), }
}

///|
pub impl ToJson for GitPrDetailPayload with fn to_json(self) {
  { "url": self.url }
}

///|
/// No enrichment is an empty object; lookup failures use the error channel.
pub(all) struct GitPrDetailReply {
  pull_request : GitPullRequest?
} derive(Eq, Debug)

///|
pub impl FromJson for GitPrDetailReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GitPrDetailReply")
  {
    pull_request: object
    .optional_json("pull_request")
    .map(value => @json.from_json(value, path=path.add_key("pull_request"))),
  }
}

///|
pub impl ToJson for GitPrDetailReply with fn to_json(self) {
  let fields : Map[String, Json] = Map([])
  if self.pull_request is Some(pr) {
    fields["pull_request"] = pr.to_json()
  }
  Json(fields)
}

///|
pub extend GitPrDetailPayload with Eq::{equal, not_equal}

///|
pub extend GitPrDetailPayload with Debug::{to_repr}

///|
pub extend GitPrDetailPayload with FromJson::{from_json}

///|
pub extend GitPrDetailPayload with ToJson::{to_json}

///|
pub extend GitPrDetailReply with Eq::{equal, not_equal}

///|
pub extend GitPrDetailReply with Debug::{to_repr}

///|
pub extend GitPrDetailReply with FromJson::{from_json}

///|
pub extend GitPrDetailReply with ToJson::{to_json}

///|
fn normalize_pr_url(
  raw : String,
  path : @json.JsonPath,
) -> String raise @json.JsonDecodeError {
  let url = raw.trim().trim_end(chars="/").to_owned()
  let parts = url.split("/").collect()
  guard parts is ["https:", "", authority, .. rest] &&
    !authority.is_empty() &&
    !authority.contains("@") &&
    !authority.contains("?") &&
    !authority.contains("#") &&
    !rest.is_empty() &&
    rest.any(part => !part.is_empty()) &&
    !url.contains("\\") &&
    !url.iter().any(c => c <= ' ' || c == '\u007f') else {
    raise JsonDecodeError(
      (path.add_key("url"), "expected an HTTPS pull request or branch URL"),
    )
  }
  url
}
