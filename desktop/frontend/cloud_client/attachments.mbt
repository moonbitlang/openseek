///|
/// The URL scopes every file operation to one session's workspace.
pub async fn prepare_attachment(
  token : String,
  session : String,
  source : @protocol.AttachmentSource,
) -> @protocol.PrepareAttachmentReply {
  let json = request(
    CloudOrigin,
    "/v1/sessions/\{@uri.encode_component(session)}/files/prepare",
    Post,
    token~,
    body={ "source": source.to_json() },
  )
  @json.from_json(json) catch {
    _ => raise RequestError(Malformed)
  }
}

///|
pub async fn import_attachment(
  token : String,
  session : String,
  source : @protocol.AttachmentSource,
) -> @protocol.ImportAttachmentReply {
  let json = request(
    CloudOrigin,
    "/v1/sessions/\{@uri.encode_component(session)}/files/import",
    Post,
    token~,
    body={ "source": source.to_json() },
  )
  @json.from_json(json) catch {
    _ => raise RequestError(Malformed)
  }
}
