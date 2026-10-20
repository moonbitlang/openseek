///|
/// Read the immediate children of a session's workspace-relative directory.
pub async fn read_directory(
  token : String,
  session : String,
  path : String,
) -> Result[@protocol.ReadDirReply, Failure] {
  let json = request(
    CloudOrigin,
    "/v1/sessions/\{@uri.encode_component(session)}/files?path=\{@uri.encode_component(path)}",
    Get,
    token~,
  ) catch {
    CloudError(failure) => return Err(failure)
    _ => return Err(Unreachable)
  }
  Ok(@json.from_json(json)) catch {
    _ => Err(Malformed)
  }
}

///|
/// File replies use the same content classification as Host file previews.
pub async fn read_file(
  token : String,
  session : String,
  path : String,
  allow_large~ : Bool = false,
) -> Result[@protocol.ReadFileReply, Failure] {
  let query = if allow_large { "&allow_large=true" } else { "" }
  let json = request(
    CloudOrigin,
    "/v1/sessions/\{@uri.encode_component(session)}/files/content?path=\{@uri.encode_component(path)}\{query}",
    Get,
    token~,
  ) catch {
    CloudError(failure) => return Err(failure)
    _ => return Err(Unreachable)
  }
  Ok(@json.from_json(json)) catch {
    _ => Err(Malformed)
  }
}
