// `mcp.status`: what a conversation's engine holds of its MCP servers. The
// state itself is the engine's (`@wire.McpStatus`, the payload of its
// `mcp_status` event), kept by the host as last reported; the host adds only
// what the engine cannot say — that no engine is running or that it has not
// reported yet.

///|
/// The conversation whose engine is asked.
pub(all) struct McpStatusPayload {
  session : String
} derive(Eq, Debug)

///|
pub impl FromJson for McpStatusPayload with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "MCP status request")
  { session: object.required_string("session"), }
}

///|
pub impl ToJson for McpStatusPayload with fn to_json(self) {
  { "session": self.session }
}

///|
pub extend McpStatusPayload with Eq::{equal, not_equal}

///|
pub extend McpStatusPayload with Debug::{to_repr}

///|
pub extend McpStatusPayload with FromJson::{from_json}

///|
pub extend McpStatusPayload with ToJson::{to_json}

///|
/// The reply of `mcp.status`: whether the conversation has an engine, and
/// what it last reported.
pub(all) enum McpStatusReply {
  /// The conversation has no engine running — it has not been sent a message
  /// since the host started, or its engine has exited. Servers connect when
  /// the next message starts one.
  Stopped
  /// An engine is running and has not reported yet: it is still starting,
  /// which includes connecting its servers.
  Connecting
  /// The running engine's own latest account of its servers.
  Running(@wire.McpStatus)
} derive(Eq, Debug)

///|
pub impl FromJson for McpStatusReply with fn from_json(json, path) {
  let object = JsonObject::decode(json, path, "MCP status reply")
  match object.required_string("engine") {
    "stopped" => Stopped
    "connecting" => Connecting
    "running" =>
      Running(
        @json.from_json(
          object.required_json("status"),
          path=path.add_key("status"),
        ),
      )
    _ =>
      raise JsonDecodeError((path.add_key("engine"), "expected engine state"))
  }
}

///|
pub impl ToJson for McpStatusReply with fn to_json(self) {
  match self {
    Stopped => { "engine": "stopped" }
    Connecting => { "engine": "connecting" }
    Running(status) => { "engine": "running", "status": Json(status) }
  }
}

///|
pub extend McpStatusReply with Eq::{equal, not_equal}

///|
pub extend McpStatusReply with Debug::{to_repr}

///|
pub extend McpStatusReply with FromJson::{from_json}

///|
pub extend McpStatusReply with ToJson::{to_json}
