///|
/// Decode the complete workspace-relative file index. Unknown fields are ignored.
fn decode_file_index(json : Json) -> Array[String] raise RequestError {
  guard json is { "files": Array(files), .. } else {
    raise RequestError(Malformed)
  }
  files.map(file => {
    guard file is String(path) else { raise RequestError(Malformed) }
    path
  })
}

///|
/// Read one complete snapshot for the composer's existing file candidates.
pub async fn read_file_index(token : String, session : String) -> Array[String] {
  decode_file_index(
    request(
      CloudOrigin,
      "/v1/sessions/\{@uri.encode_component(session)}/files/index",
      Get,
      token~,
    ),
  )
}

///|
/// Read the immediate children of a session's workspace-relative directory.
pub async fn read_directory(
  token : String,
  session : String,
  path : String,
) -> @protocol.ReadDirReply {
  let json = request(
    CloudOrigin,
    "/v1/sessions/\{@uri.encode_component(session)}/files?path=\{@uri.encode_component(path)}",
    Get,
    token~,
  )
  @json.from_json(json) catch {
    _ => raise RequestError(Malformed)
  }
}

///|
fn file_content_path(
  session : String,
  path : String,
  allow_large : Bool,
) -> String {
  let query = if allow_large { "&allow_large=true" } else { "" }
  "/v1/sessions/\{@uri.encode_component(session)}/files/content?path=\{@uri.encode_component(path)}\{query}"
}

///|
/// A Cloud content signature is the server's opaque HTTP validator. It stays
/// with the existing cached document; Host signatures keep their own meaning.
fn validated_reply(
  json : Json,
  etag : String?,
) -> @protocol.ReadFileReply raise RequestError {
  let reply : @protocol.ReadFileReply = @json.from_json(json) catch {
    _ => raise RequestError(Malformed)
  }
  match reply {
    Content(content~, absolute~, ..) => {
      guard etag is Some(sig) && !sig.is_empty() else {
        raise RequestError(Malformed)
      }
      Content(content~, absolute~, sig~)
    }
    BinaryContent(data_base64~, media_type~, ..) => {
      guard etag is Some(sig) && !sig.is_empty() else {
        raise RequestError(Malformed)
      }
      BinaryContent(data_base64~, media_type~, sig~)
    }
    Binary | Oversized => reply
  }
}

///|
/// Read a body under the existing size policy and retain its HTTP validator.
pub async fn read_file(
  token : String,
  session : String,
  path : String,
  allow_large~ : Bool = false,
) -> @protocol.ReadFileReply {
  let (response, data) = @http.request(
    CloudOrigin + file_content_path(session, path, allow_large),
    Get,
    { "Authorization": "Bearer " + token },
    "",
  ) catch {
    _ => raise RequestError(Unreachable)
  }
  check_status(response.code)
  let json = data.json() catch { _ => raise RequestError(Malformed) }
  validated_reply(json, response.headers.get("ETag"))
}

///|
/// Validate the complete representation without downloading its body. A
/// changed file must still be read through the default preview size limit.
pub async fn file_unchanged(
  token : String,
  session : String,
  path : String,
  etag : String,
) -> Bool {
  let (response, _) = @http.request(
    CloudOrigin + file_content_path(session, path, true),
    Head,
    { "Authorization": "Bearer " + token, "If-None-Match": etag },
    "",
  ) catch {
    _ => raise RequestError(Unreachable)
  }
  if response.code == 304 {
    return true
  }
  check_status(response.code)
  false
}

///|
/// The session owns the workspace; only relative selection data crosses HTTP.
pub async fn materialize_semantic_selection(
  token : String,
  session : String,
  payload : @protocol.MaterializeSemanticSelectionPayload,
) -> @protocol.MaterializeSemanticSelectionReply {
  let body : Json = {
    "artifact_id": payload.artifact_id,
    "patterns": payload.patterns,
    "include_glob": payload.include_glob,
    "exclude_glob": payload.exclude_glob,
    "matches": payload.matches,
  }
  let json = request(
    CloudOrigin,
    "/v1/sessions/\{@uri.encode_component(session)}/files/search/semantic/selection",
    Post,
    token~,
    body~,
  ) catch {
    RequestError(Busy) => raise RequestError(Http(409))
    error => raise error
  }
  @json.from_json(json) catch {
    _ => raise RequestError(Malformed)
  }
}
