// Host filesystem browsing packets: the repository picker lists absolute
// directories on the server host and switches the served workspace root.
// These packets are host-level concerns — a `RemoteServer` policy layer
// without a native host rejects them.

///|
/// Request addressed by an absolute host filesystem path. An empty path asks
/// the server to start from the current workspace root.
pub(all) struct HostPathRequest {
  id : String
  path : String
} derive(Debug)

///|
/// One child directory in a host filesystem listing. `is_workspace` marks
/// directories that look like a repository root (a `moon.mod`,
/// `moon.mod.json`, or `.git` entry).
pub(all) struct HostDirectoryEntry {
  name : String
  path : String
  is_workspace : Bool
} derive(Debug, Eq)

///|
/// One resolved host directory level: the absolute listed path, its parent
/// (`None` at the filesystem root), and its child directories.
pub(all) struct HostDirectoryListing {
  path : String
  parent : String?
  entries : Array[HostDirectoryEntry]
} derive(Debug, Eq)

///|
/// Response payload for `ListHostDirectory`.
pub(all) struct HostDirectoryListedPayload {
  id : String
  listing : HostDirectoryListing
} derive(Debug)

///|
/// The served workspace root changed. Carries the requester's id on the
/// direct response and an empty id on the broadcast to every other session.
pub(all) struct WorkspaceSwitchedPayload {
  id : String
  root : String
  name : String
} derive(Debug)

///|
fn host_path_request_json(kind : String, request : HostPathRequest) -> Json {
  let fields = packet_fields(kind, request.id)
  fields["path"] = request.path.to_json()
  Json(fields)
}

///|
fn decode_host_path_client(
  packet : Json,
  id : String,
  build : (HostPathRequest) -> ClientPacket,
) -> ClientPacketDecodeResult {
  match json_string_field(packet, "path") {
    Some(path) => DecodedClientPacket(build({ id, path, }))
    None =>
      ClientPacketDecodeError(
        ProtocolError(
          ProtocolInvalidPacket,
          "Remote protocol packet is missing path.",
          request_id=id,
        ),
      )
  }
}

///|
/// `parent` is omitted at the filesystem root so the decoder can tell "no
/// parent" from an empty string.
fn host_directory_listed_json(payload : HostDirectoryListedPayload) -> Json {
  let fields = packet_fields("HostDirectoryListed", payload.id)
  fields["path"] = payload.listing.path.to_json()
  if payload.listing.parent is Some(parent) {
    fields["parent"] = parent.to_json()
  }
  fields["entries"] = Json(
    payload.listing.entries.map(host_directory_entry_json),
  )
  Json(fields)
}

///|
fn host_directory_entry_json(entry : HostDirectoryEntry) -> Json {
  {
    "name": entry.name.to_json(),
    "path": entry.path.to_json(),
    "isWorkspace": entry.is_workspace.to_json(),
  }
}

///|
fn decode_host_directory_listed_payload(
  packet : Json,
  id : String,
) -> ServerPacketDecodeResult {
  match json_string_field(packet, "path") {
    Some(path) =>
      DecodedServerPacket(
        HostDirectoryListed({
          id,
          listing: {
            path,
            parent: json_string_field(packet, "parent"),
            entries: json_array_field(
              packet, "entries", parse_host_directory_entry,
            ),
          },
        }),
      )
    None =>
      ServerPacketDecodeError(
        ProtocolError(
          ProtocolInvalidPacket,
          "Host directory packet is missing path.",
          request_id=id,
        ),
      )
  }
}

///|
fn parse_host_directory_entry(value : Json) -> HostDirectoryEntry? {
  guard value is Object(_) else { return None }
  guard json_string_field(value, "name") is Some(name) else { return None }
  guard json_string_field(value, "path") is Some(path) else { return None }
  let is_workspace = json_field(value, "isWorkspace") is Some(True)
  Some({ name, path, is_workspace, })
}

///|
fn workspace_switched_json(payload : WorkspaceSwitchedPayload) -> Json {
  let fields = packet_fields("WorkspaceSwitched", payload.id)
  fields["root"] = payload.root.to_json()
  fields["name"] = payload.name.to_json()
  Json(fields)
}

///|
fn decode_workspace_switched_payload(
  packet : Json,
  id : String,
) -> ServerPacketDecodeResult {
  match json_string_field(packet, "root") {
    Some(root) =>
      DecodedServerPacket(
        WorkspaceSwitched({
          id,
          root,
          name: json_string_field(packet, "name").unwrap_or(""),
        }),
      )
    None =>
      ServerPacketDecodeError(
        ProtocolError(
          ProtocolInvalidPacket,
          "Workspace switched packet is missing root.",
          request_id=id,
        ),
      )
  }
}

///|
pub extend HostDirectoryEntry with Debug::{to_repr}

///|
pub extend HostDirectoryEntry with Eq::{equal, not_equal}

///|
pub extend HostDirectoryListedPayload with Debug::{to_repr}

///|
pub extend HostDirectoryListing with Debug::{to_repr}

///|
pub extend HostDirectoryListing with Eq::{equal, not_equal}

///|
pub extend HostPathRequest with Debug::{to_repr}

///|
pub extend WorkspaceSwitchedPayload with Debug::{to_repr}
