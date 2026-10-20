///|
/// Keep completed imports only while an unacknowledged submission can retry.
pub struct UploadedAttachment {
  source : @protocol.AttachmentSource
  path : String
} derive(Eq)

///|
pub extend UploadedAttachment with Eq::{equal, not_equal}

///|
fn prompt_content(draft : @composer.Draft) -> @wire.Content raise RequestError {
  let parts : Array[@wire.ContentPart] = [Text(draft.prompt())]
  for image in draft.images {
    parts.push(
      Image(
        @wire.Image::from_data_url(image.url) catch {
          _ => raise @cloud_client.RequestError(InvalidImage)
        },
      ),
    )
  }
  Content(parts)
}

///|
/// Persist the original image bytes before sending the immutable model input.
/// A failed send can reuse imports whose replies reached this client.
async fn prepare_submission(
  token : String,
  session : String,
  draft : @composer.Draft,
  attachments : Array[@protocol.AttachmentSource],
  cached : Array[UploadedAttachment],
  stored : (@protocol.AttachmentSource, String) -> Unit,
) -> @composer.Draft {
  let cached = cached.copy()
  let mut draft = draft
  for source in attachments {
    let prepared = @cloud_client.prepare_attachment(token, session, source)
    let path = if prepared is @protocol.WorkspaceAttachment(path~) {
      path
    } else {
      match cached.iter().find_first(upload => upload.source == source) {
        Some(upload) => upload.path
        None => {
          let reply = @cloud_client.import_attachment(token, session, source)
          cached.push({ source, path: reply.path, })
          stored(source, reply.path)
          reply.path
        }
      }
    }
    draft = match prepared {
      @protocol.AttachmentImage(name~, url~) =>
        { ..draft, images: [..draft.images, { name, url, }], }
      _ => draft.with_mention({ ref_: File(path~), range: None, })
    }
  }
  for image in draft.images {
    let image_data = @wire.Image::from_data_url(image.url) catch {
      _ => raise @cloud_client.RequestError(InvalidImage)
    }
    let source = @protocol.AttachmentBytes(
      name=image.name,
      data_base64=@base64.encode(image_data.bytes),
    )
    if cached.any(upload => upload.source == source) {
      continue
    }
    let reply = @cloud_client.import_attachment(token, session, source)
    cached.push({ source, path: reply.path, })
    stored(source, reply.path)
  }
  draft
}
