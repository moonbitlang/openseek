///|
/// Atomic process-lifetime view of every unresolved OpenSeek permission request.
/// A claimed request stays visible as answered until the engine resolves it.
pub(all) struct ApprovalSnapshot {
  generation : Int32
  approvals : Array[PendingApprovalPayload]
} derive(Debug, Eq)

///|
pub impl ToJson for ApprovalSnapshot with fn to_json(self) {
  { "generation": self.generation, "approvals": Json(self.approvals) }
}

///|
pub impl FromJson for ApprovalSnapshot with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "approval snapshot")
  let generation = object.required_int("generation")
  guard generation >= 0 else {
    raise JsonDecodeError((path, "negative approval generation"))
  }
  let approvals : Array[PendingApprovalPayload] = @json.from_json(
    object.required_json("approvals"),
    path=path.add_key("approvals"),
  )
  { generation, approvals, }
}

///|
pub extend ApprovalSnapshot with ToJson::{to_json}

///|
pub extend ApprovalSnapshot with FromJson::{from_json}

///|
pub extend ApprovalSnapshot with Debug::{to_repr}

///|
pub extend ApprovalSnapshot with Eq::{equal, not_equal}
