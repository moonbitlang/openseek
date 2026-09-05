// Explicit codecs for the Desktop Git-history boundary. Unknown fields are
// ignored for forward evolution; every consumed field deliberately specifies
// missing, null, malformed, and encoded behavior.

///|
pub impl FromJson for GitHistoryPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "Git history payload")
  let snapshot = match object.optional_json("snapshot") {
    Some(raw) => Some(@json.from_json(raw, path=path.add_key("snapshot")))
    None => None
  }
  {
    session: object.required_string("session"),
    workspace: object.optional_string("workspace"),
    snapshot,
    skip: object.required_int("skip"),
    limit: object.required_int("limit"),
  }
}

///|
pub impl ToJson for GitHistoryPayload with fn to_json(self) {
  let fields : Map[String, Json] = {
    "session": self.session.to_json(),
    "skip": self.skip.to_json(),
    "limit": self.limit.to_json(),
  }
  if self.workspace is Some(workspace) {
    fields["workspace"] = workspace.to_json()
  }
  if self.snapshot is Some(snapshot) {
    fields["snapshot"] = ToJson::to_json(snapshot)
  }
  Json(fields)
}

///|
pub impl FromJson for GitCommitChangesPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "Git commit-changes payload")
  {
    session: object.required_string("session"),
    workspace: object.optional_string("workspace"),
    commit: object.required_string("commit"),
  }
}

///|
pub impl ToJson for GitCommitChangesPayload with fn to_json(self) {
  let fields : Map[String, Json] = {
    "session": self.session.to_json(),
    "commit": self.commit.to_json(),
  }
  if self.workspace is Some(workspace) {
    fields["workspace"] = workspace.to_json()
  }
  Json(fields)
}

///|
pub impl FromJson for GitHistoryRef with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "Git history ref")
  {
    name: object.required_string("name"),
    revision: object.required_string("revision"),
    kind: object.required_string("kind"),
  }
}

///|
pub impl ToJson for GitHistoryRef with fn to_json(self) {
  { "name": self.name, "revision": self.revision, "kind": self.kind }
}

///|
pub impl FromJson for GitHistorySnapshot with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "Git history snapshot")
  let refs : Array[GitHistoryRef] = object.required_array_of("refs")
  {
    head: object.optional_string("head"),
    branch: object.optional_string("branch"),
    refs,
    tips: object.required_string_array("tips"),
  }
}

///|
pub impl ToJson for GitHistorySnapshot with fn to_json(self) {
  let fields : Map[String, Json] = {
    "refs": self.refs.to_json(),
    "tips": self.tips.to_json(),
  }
  if self.head is Some(head) {
    fields["head"] = head.to_json()
  }
  if self.branch is Some(branch) {
    fields["branch"] = branch.to_json()
  }
  Json(fields)
}

///|
pub impl FromJson for GitHistoryCommit with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "Git history commit")
  {
    id: object.required_string("id"),
    parent_ids: object.required_string_array("parent_ids"),
    subject: object.required_string("subject"),
    author: object.required_string("author"),
    authored_at: object.required_string("authored_at"),
  }
}

///|
pub impl ToJson for GitHistoryCommit with fn to_json(self) {
  {
    "id": self.id,
    "parent_ids": self.parent_ids,
    "subject": self.subject,
    "author": self.author,
    "authored_at": self.authored_at,
  }
}

///|
pub impl FromJson for GitHistoryReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "Git history reply")
  let snapshot : GitHistorySnapshot = @json.from_json(
    object.required_json("snapshot"),
    path=path.add_key("snapshot"),
  )
  let commits : Array[GitHistoryCommit] = object.required_array_of("commits")
  {
    repository: object.required_bool("repository"),
    snapshot,
    commits,
    has_more: object.required_bool("has_more"),
  }
}

///|
pub impl ToJson for GitHistoryReply with fn to_json(self) {
  {
    "repository": self.repository,
    "snapshot": self.snapshot,
    "commits": self.commits,
    "has_more": self.has_more,
  }
}

///|
pub impl FromJson for GitHistoricalChange with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "Git historical change")
  {
    path: object.required_string("path"),
    original_path: object.optional_string("original_path"),
    status: object.required_string("status"),
    kind: object.required_string("kind"),
  }
}

///|
pub impl ToJson for GitHistoricalChange with fn to_json(self) {
  let fields : Map[String, Json] = {
    "path": self.path.to_json(),
    "status": self.status.to_json(),
    "kind": self.kind.to_json(),
  }
  if self.original_path is Some(original_path) {
    fields["original_path"] = original_path.to_json()
  }
  Json(fields)
}

///|
pub impl FromJson for GitCommitChangesReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "Git commit-changes reply")
  let changes : Array[GitHistoricalChange] = object.required_array_of("changes")
  {
    commit: object.required_string("commit"),
    parent: object.optional_string("parent"),
    changes,
  }
}

///|
pub impl ToJson for GitCommitChangesReply with fn to_json(self) {
  let fields : Map[String, Json] = {
    "commit": self.commit.to_json(),
    "changes": self.changes.to_json(),
  }
  if self.parent is Some(parent) {
    fields["parent"] = parent.to_json()
  }
  Json(fields)
}
