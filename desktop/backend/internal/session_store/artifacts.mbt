///|
/// Read the live session's attachments. A draft, an archived record, or a
/// missing sidecar has no live attachments.
pub async fn list_artifacts(
  session : String,
) -> @desktop_protocol.SessionArtifacts {
  guard safe_session_id(session) else { raise StoreError("invalid session id") }
  guard root_of(session) is Some(root) else {
    return @desktop_protocol.SessionArtifacts::empty()
  }
  read_artifacts(root.join("sessions").join(session))
}

///|
/// Read the atomically written sidecar at an already resolved record path.
pub async fn read_artifacts(
  directory : @pathx.Absolute,
) -> @desktop_protocol.SessionArtifacts {
  match @fsx.read_text_if_exists(directory.join("artifacts.json").to_path()) {
    Some(text) => @json.from_json(@json.parse(text))
    None => @desktop_protocol.SessionArtifacts::empty()
  }
}
