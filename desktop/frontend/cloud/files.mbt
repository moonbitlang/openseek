///|
/// Decode the complete workspace-relative file index. Unknown fields are ignored.
fn decode_file_index(json : Json) -> Array[String] raise CloudError {
  guard json is { "files": Array(files), .. } else {
    raise CloudError(Malformed)
  }
  files.map(file => {
    guard file is String(path) else { raise CloudError(Malformed) }
    path
  })
}

///|
/// Read one complete snapshot for the composer's existing file candidates.
pub async fn read_file_index(
  token : String,
  session : String,
) -> Result[Array[String], Failure] {
  Ok(
    decode_file_index(
      request(
        CloudOrigin,
        "/v1/sessions/\{@uri.encode_component(session)}/files/index",
        Get,
        token~,
      ),
    ),
  ) catch {
    CloudError(failure) => Err(failure)
    _ => Err(Unreachable)
  }
}

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
