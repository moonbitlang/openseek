///|
/// A native session command plus the existing settings needed to restore its
/// host. Turn commands retain the existing host admission and ownership checks.
pub(all) struct SessionCommandPayload {
  command : @wire.Command
  settings : SessionCommandSettings
  run_id : String?
} derive(Eq, Debug)

///|
pub impl FromJson for SessionCommandPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "agent.command payload")
  let command = match @wire.Command::parse(object.required_json("command")) {
    Ok(command) => command
    Err(reason) => raise JsonDecodeError((path.add_key("command"), reason))
  }
  {
    command,
    settings: @json.from_json(json, path~),
    run_id: object.optional_string("run_id"),
  }
}

///|
pub impl ToJson for SessionCommandPayload with fn to_json(self) {
  guard self.settings.to_json() is Object(fields) else {
    abort("object settings")
  }
  let fields = fields.copy()
  fields["command"] = self.command.to_json()
  if self.run_id is Some(id) {
    fields["run_id"] = Json(id)
  }
  Json(fields)
}

///|
pub(all) struct SessionCommandReply {
  accepted : Bool
} derive(Eq, Debug)

///|
pub impl FromJson for SessionCommandReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "agent.command reply")
  { accepted: object.required_bool("accepted"), }
}

///|
pub impl ToJson for SessionCommandReply with fn to_json(self) {
  { "accepted": self.accepted }
}

///|
pub extend SessionCommandPayload with Eq::{equal, not_equal}

///|
pub extend SessionCommandPayload with Debug::{to_repr}

///|
pub extend SessionCommandPayload with ToJson::{to_json}

///|
pub extend SessionCommandPayload with FromJson::{from_json}

///|
pub extend SessionCommandReply with Eq::{equal, not_equal}

///|
pub extend SessionCommandReply with Debug::{to_repr}

///|
pub extend SessionCommandReply with ToJson::{to_json}

///|
pub extend SessionCommandReply with FromJson::{from_json}
