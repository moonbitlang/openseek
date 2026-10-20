///|
/// The URL scopes every file operation to one session's workspace.
pub async fn prepare_attachment(
  token : String,
  session : String,
  source : @protocol.AttachmentSource,
) -> Result[@protocol.PrepareAttachmentReply, Failure] {
  let json = request(
    CloudOrigin,
    "/v1/sessions/\{@uri.encode_component(session)}/files/prepare",
    Post,
    token~,
    body={ "source": source.to_json() },
  ) catch {
    RequestError(failure) => return Err(failure)
    _ => return Err(Unreachable)
  }
  Ok(@json.from_json(json)) catch {
    _ => Err(Malformed)
  }
}

///|
pub async fn import_attachment(
  token : String,
  session : String,
  source : @protocol.AttachmentSource,
) -> Result[@protocol.ImportAttachmentReply, Failure] {
  let json = request(
    CloudOrigin,
    "/v1/sessions/\{@uri.encode_component(session)}/files/import",
    Post,
    token~,
    body={ "source": source.to_json() },
  ) catch {
    RequestError(failure) => return Err(failure)
    _ => return Err(Unreachable)
  }
  Ok(@json.from_json(json)) catch {
    _ => Err(Malformed)
  }
}
