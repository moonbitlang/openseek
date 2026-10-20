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
    RequestError(failure) => Err(failure)
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
    RequestError(failure) => return Err(failure)
    _ => return Err(Unreachable)
  }
  Ok(@json.from_json(json)) catch {
    _ => Err(Malformed)
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
) -> @protocol.ReadFileReply raise {
  let reply : @protocol.ReadFileReply = @json.from_json(json)
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
) -> Result[@protocol.ReadFileReply, Failure] {
  try {
    let (response, data) = @http.request(
      CloudOrigin + file_content_path(session, path, allow_large),
      Get,
      { "Authorization": "Bearer " + token },
      "",
    ) catch {
      _ => raise RequestError(Unreachable)
    }
    check_status(response.code)
    Ok(validated_reply(data.json(), response.headers.get("ETag")))
  } catch {
    RequestError(failure) => Err(failure)
    _ => Err(Malformed)
  }
}

///|
/// Validate the complete representation without downloading its body. A
/// changed file must still be read through the default preview size limit.
pub async fn file_unchanged(
  token : String,
  session : String,
  path : String,
  etag : String,
) -> Result[Bool, Failure] {
  try {
    let (response, _) = @http.request(
      CloudOrigin + file_content_path(session, path, true),
      Head,
      { "Authorization": "Bearer " + token, "If-None-Match": etag },
      "",
    ) catch {
      _ => raise RequestError(Unreachable)
    }
    if response.code == 304 {
      return Ok(true)
    }
    check_status(response.code)
    Ok(false)
  } catch {
    RequestError(failure) => Err(failure)
  }
}
