///|
#derive(ToJson, FromJson)
priv struct UploadRecord {
  scope : String
  attachment_id : String
  file_id : String
  expires_at : Int64
}

///|
/// The provider no longer recognizes a Files API reference in the request.
/// Callers that own the reference forget its cached id and upload it again.
pub suberror RejectedImageFile {
  RejectedImageFile(String)
}

///|
impl Show for RejectedImageFile with fn output(self, logger) {
  match self {
    RejectedImageFile(text) =>
      logger.write_string("DeepSeek rejected image file: \{text}")
  }
}

///|
/// Only explicit file-reference errors before any completion are recoverable.
fn check_rejected_file(status : Int32, text : String) -> Unit raise {
  if status != 400 && status != 404 {
    return
  }
  let json = @json.parse(text) catch { _ => return }
  if json is { "error": { "code": String(code), .. }, .. } &&
    code is ("file_not_found" | "file_expired" | "invalid_file_id") {
    raise RejectedImageFile(text)
  }
}

///|
fn Client::upload_scope(self : Client) -> String {
  @attachments.digest(@utf8.encode("\{self.api_url}\u0000\{self.api_key}"))
}

///|
fn now_seconds() -> Int64 {
  @env.now().reinterpret_as_int64() / 1000
}

///|
/// The index is a cache: a missing or unreadable index has no reusable uploads.
async fn read_upload_records(path : String) -> Array[UploadRecord] {
  let data = @fs.read_file(path) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => return []
    error => raise error
  }
  @json.from_json(@json.parse(data.text())) catch {
    _ => []
  }
}

///|
fn reusable_upload(
  records : Array[UploadRecord],
  scope : String,
  attachment_id : String,
  now : Int64,
) -> String? {
  records
  .iter()
  .find_first(record => {
    record.scope == scope &&
    record.attachment_id == attachment_id &&
    record.expires_at > now + 300
  })
  .map(record => record.file_id)
}

///|
/// Rewrite the index beside the image objects under its lock. Network IO never
/// happens while the lock is held.
async fn update_upload_records(
  attachments : @attachments.AttachmentStore,
  update : (Array[UploadRecord]) -> Array[UploadRecord],
) -> Unit {
  let directory = attachments.root()
  @fs.mkdir(directory, recursive=true, allow_exist=true, permission=0o700)
  let lock = @fs.open(
    "\{directory}/files-v1.lock",
    mode=ReadWrite,
    create_mode=OpenOrCreate,
    permission=0o600,
  )
  defer lock.close()
  lock.lock(Exclusive)
  defer lock.unlock()
  let path = "\{directory}/files-v1.json"
  let records = update(read_upload_records(path))
  let temporary = "\{path}.tmp"
  @fs.write_file(
    temporary,
    Json(records).stringify() + "\n",
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Data,
  )
  @fs.rename(temporary, path, replace=true)
}

///|
async fn Client::upload_record(
  self : Client,
  attachments : @attachments.AttachmentStore,
  scope : String,
  reference : @protocol.ImageRef,
) -> UploadRecord {
  let image = attachments.read(reference)
  let uploaded = self.upload_image(
    image.bytes,
    filename="openseek-\{reference.attachment_id.strip_prefix("sha256:").unwrap_or("")}",
    expires_after_seconds=86400,
  )
  guard uploaded.expires_at is Some(expires_at) else {
    fail("image upload omitted expiry")
  }
  {
    scope,
    attachment_id: reference.attachment_id,
    file_id: uploaded.id,
    expires_at,
  }
}

///|
/// Resolve local images to reusable Files API ids, keyed by attachment id.
/// Cached ids are returned without reading the images. Misses are read,
/// verified, and uploaded concurrently, then recorded in one locked rewrite;
/// an id another process recorded first wins.
pub async fn Client::upload_attachments(
  self : Client,
  attachments : @attachments.AttachmentStore,
  references : Array[@protocol.ImageRef],
) -> Map[String, String] {
  guard self.supports_image_input() else { raise UnsupportedProvider }
  let scope = self.upload_scope()
  let records = read_upload_records("\{attachments.root()}/files-v1.json")
  let now = now_seconds()
  let file_ids : Map[String, String] = Map([])
  let missing : Array[@protocol.ImageRef] = []
  for reference in references {
    if reusable_upload(records, scope, reference.attachment_id, now)
      is Some(file_id) {
      file_ids[reference.attachment_id] = file_id
    } else {
      missing.push(reference)
    }
  }
  if missing.is_empty() {
    return file_ids
  }
  let uploaded : Array[UploadRecord] = []
  @async.with_task_group() <| group => {
    let permits = @semaphore.Semaphore(4)
    for reference in missing {
      group.spawn_bg(() => {
        permits.acquire()
        defer permits.release()
        uploaded.push(self.upload_record(attachments, scope, reference))
      })
    }
  }
  update_upload_records(attachments, records => {
    let now = now_seconds()
    let records = records.filter(record => record.expires_at > now)
    for record in uploaded {
      if reusable_upload(records, scope, record.attachment_id, now)
        is Some(file_id) {
        // The duplicate remote file expires on its own; never delete provider
        // files from here.
        file_ids[record.attachment_id] = file_id
      } else {
        records.retain(existing => {
          !(existing.scope == scope &&
          existing.attachment_id == record.attachment_id)
        })
        records.push(record)
        file_ids[record.attachment_id] = record.file_id
      }
    }
    records
  })
  file_ids
}

///|
/// Forget cached ids the provider rejected so the next resolution uploads the
/// images again.
pub async fn Client::forget_uploads(
  self : Client,
  attachments : @attachments.AttachmentStore,
  file_ids : Array[String],
) -> Unit {
  let scope = self.upload_scope()
  update_upload_records(attachments, records => {
    records.filter(record => {
      !(record.scope == scope && file_ids.contains(record.file_id))
    })
  })
}
