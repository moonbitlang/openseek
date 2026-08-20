///|
/// Parsed remote directory URI. The root uses an empty path and display name
/// `workspace`.
pub(all) enum RemoteDirectoryResult {
  /// Root-relative directory path ("" for the workspace root itself) plus
  /// the directory's display name.
  ParsedRemoteDirectory(String, String)
  RemoteDirectoryError(@remote_protocol.ProtocolError)
} derive(Debug)

///|
/// Resolves a directory URI to its root-relative path. Accepts the bare
/// `readonly-remote://workspace` root, which `resolve_remote_document_uri`
/// rejects because documents always carry a path.
pub fn resolve_remote_directory_uri(
  uri : @base_common.Uri,
  request_id? : String = "",
) -> RemoteDirectoryResult {
  if uri.to_string() == "readonly-remote://workspace" {
    return ParsedRemoteDirectory("", "workspace")
  }
  match resolve_remote_document_uri(uri, request_id~) {
    ParsedRemotePath(path) =>
      ParsedRemoteDirectory(path.to_string(), directory_name(path.to_string()))
    RemotePathError(error) => RemoteDirectoryError(error)
  }
}

///|
#deprecated
pub extend RemoteDirectoryResult with Debug::{to_repr}
