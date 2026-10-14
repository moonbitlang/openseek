///|
/// Reattach to a host-retained terminal. The id is an opaque capability from
/// terminal.open; sequence is the last output already held by the emulator.
pub(all) struct TerminalAttachPayload {
  id : String
  sequence : Int32
} derive(Debug, Eq)

///|
pub impl FromJson for TerminalAttachPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "terminal attach payload")
  let id = object.required_string("id")
  let sequence = object.required_int("sequence")
  guard !id.is_empty() && sequence >= 0 else {
    raise JsonDecodeError(
      (path, "expected terminal id and nonnegative output sequence"),
    )
  }
  { id, sequence, }
}

///|
pub impl ToJson for TerminalAttachPayload with fn to_json(self) {
  { "id": self.id, "sequence": self.sequence }
}

///|
/// False means the session expired or the host restarted. Transport errors
/// and invalid attachment requests remain errors, never a missing session.
pub(all) struct TerminalAttachReply {
  attached : Bool
} derive(Debug, Eq)

///|
pub impl FromJson for TerminalAttachReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "terminal attach reply")
  { attached: object.required_bool("attached"), }
}

///|
pub impl ToJson for TerminalAttachReply with fn to_json(self) {
  { "attached": self.attached }
}

///|
pub extend TerminalAttachPayload with Debug::{to_repr}

///|
pub extend TerminalAttachPayload with Eq::{equal, not_equal}

///|
pub extend TerminalAttachPayload with FromJson::{from_json}

///|
pub extend TerminalAttachPayload with ToJson::{to_json}

///|
pub extend TerminalAttachReply with Debug::{to_repr}

///|
pub extend TerminalAttachReply with Eq::{equal, not_equal}

///|
pub extend TerminalAttachReply with FromJson::{from_json}

///|
pub extend TerminalAttachReply with ToJson::{to_json}
