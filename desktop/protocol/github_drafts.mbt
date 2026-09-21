///|
pub(all) enum GithubDraftTarget {
  Line(path~ : String, side~ : String, line~ : Int, head~ : String)
  Thread(thread~ : String, comment~ : String)
} derive(Eq)

///|
pub(all) struct GithubDraft {
  target : GithubDraftTarget
  body : String
} derive(Eq)

///|
pub impl ToJson for GithubDraftTarget with fn to_json(self) {
  match self {
    Line(path~, side~, line~, head~) =>
      { "kind": "line", "path": path, "side": side, "line": line, "head": head }
    Thread(thread~, comment~) =>
      { "kind": "thread", "thread": thread, "comment": comment }
  }
}

///|
pub impl FromJson for GithubDraftTarget with fn from_json(json, path) {
  match json {
    {
      "kind": String("line"),
      "path": String(file),
      "side": String(side),
      "line": line,
      "head": String(head),
      ..
    } => {
      let line : Int = @json.from_json(line)
      guard line > 0 && (side == "LEFT" || side == "RIGHT") else {
        raise JsonDecodeError((path, "invalid local comment anchor"))
      }
      Line(path=file, side~, line~, head~)
    }
    {
      "kind": String("thread"),
      "thread": String(thread),
      "comment": String(comment),
      ..
    } => Thread(thread~, comment~)
    _ => raise JsonDecodeError((path, "invalid local comment target"))
  }
}

///|
pub impl ToJson for GithubDraft with fn to_json(self) {
  { "target": ToJson::to_json(self.target), "body": self.body }
}

///|
pub impl FromJson for GithubDraft with fn from_json(json, path) {
  match json {
    { "target": target, "body": String(body), .. } =>
      { target: @json.from_json(target), body, }
    _ => raise JsonDecodeError((path, "invalid local comment draft"))
  }
}

///|
pub fn GithubDraftTarget::key(self : GithubDraftTarget) -> String {
  ToJson::to_json(self).stringify()
}

///|
pub extend GithubDraftTarget with Eq::{equal, not_equal}

///|
pub extend GithubDraft with Eq::{equal, not_equal}

///|
pub(all) struct GithubDrafts {
  url : String
  drafts : Array[GithubDraft]
} derive(Eq)

///|
pub impl ToJson for GithubDrafts with fn to_json(self) {
  { "url": self.url, "drafts": self.drafts.to_json() }
}

///|
pub impl FromJson for GithubDrafts with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GitHub comment drafts")
  {
    url: object.required_string("url"),
    drafts: object.required_array_of("drafts"),
  }
}

///|
pub extend GithubDraftTarget with ToJson::{to_json}

///|
pub extend GithubDraftTarget with FromJson::{from_json}

///|
pub extend GithubDraft with ToJson::{to_json}

///|
pub extend GithubDraft with FromJson::{from_json}

///|
pub(all) struct GithubDraftsKey {
  url : String
}

///|
pub impl ToJson for GithubDraftsKey with fn to_json(self) {
  { "url": self.url }
}

///|
pub impl FromJson for GithubDraftsKey with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "GitHub comment draft key")
  { url: object.required_string("url"), }
}

///|
pub extend GithubDrafts with Eq::{equal, not_equal}

///|
pub extend GithubDrafts with ToJson::{to_json}

///|
pub extend GithubDrafts with FromJson::{from_json}

///|
pub extend GithubDraftsKey with ToJson::{to_json}

///|
pub extend GithubDraftsKey with FromJson::{from_json}
