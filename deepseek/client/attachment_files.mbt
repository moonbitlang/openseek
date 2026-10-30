///|
priv struct UploadRecord {
  scope : String
  attachment_id : String
  file_id : String
  expires_at : Int64
} derive(ToJson, FromJson)

///|
priv struct UploadIndex {
  version : Int32
  records : Array[UploadRecord]
} derive(ToJson, FromJson)

///|
fn Client::upload_scope(self : Client) -> String {
  @attachments.digest(@utf8.encode("\{self.api_url}\u0000\{self.api_key}"))
}

///|
async fn read_upload_index(path : String) -> UploadIndex {
  let data = @fs.read_file(path) catch {
    @os_error.OSError(_) as error if error.is_ENOENT() =>
      return { version: 1, records: [], }
    error => raise error
  }
  let index : UploadIndex = @json.from_json(@json.parse(data.text()))
  guard index.version == 1 else {
    fail("unsupported image upload index version")
  }
  for record in index.records {
    guard !record.file_id.is_blank() && record.expires_at > 0 else {
      fail("invalid image upload index record")
    }
  }
  index
}

///|
fn UploadIndex::lookup(
  self : UploadIndex,
  scope : String,
  id : String,
) -> UploadRecord? {
  let now = @env.now().reinterpret_as_int64() / 1000
  self.records
  .iter()
  .find_first(record => {
    record.scope == scope &&
    record.attachment_id == id &&
    record.expires_at > now + 300
  })
}

///|
/// Resolve a local image to a reusable provider file. Network IO happens outside
/// the index lock. A concurrent winner is reused after rereading under the lock.
pub async fn Client::upload_attachment(
  self : Client,
  reference : @protocol.ImageRef,
) -> String {
  guard self.supports_image_input() else { raise UnsupportedProvider }
  let directory = self.upload_index_dir.unwrap_or_else(() => {
    @attachments.default_home() + "/deepseek"
  })
  let path = "\{directory}/files-v1.json"
  let scope = self.upload_scope()
  // Verify the durable source even on cache hits; corrupt/missing local history
  // must not silently become dependent on a temporary provider file.
  let store = self.attachments.unwrap_or_else(() => {
    @attachments.AttachmentStore::default()
  })
  let image = store.read(reference)
  if read_upload_index(path).lookup(scope, reference.attachment_id)
    is Some(record) {
    return record.file_id
  }
  let uploaded = self.upload_image(
    image.bytes,
    filename="openseek-\{reference.attachment_id.strip_prefix("sha256:").unwrap_or("")}",
    expires_after_seconds=86400,
  )
  guard uploaded.expires_at is Some(expires_at) else {
    fail("image upload omitted expiry")
  }
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
  let index = read_upload_index(path)
  if index.lookup(scope, reference.attachment_id) is Some(record) {
    // The duplicate remote file has a bounded lifetime; do not delete arbitrary
    // provider files or hold the global index lock across a network operation.
    return record.file_id
  }
  let now = @env.now().reinterpret_as_int64() / 1000
  let records = index.records.filter(record => {
    record.expires_at > now &&
    !(record.scope == scope && record.attachment_id == reference.attachment_id)
  })
  records.push({
    scope,
    attachment_id: reference.attachment_id,
    file_id: uploaded.id,
    expires_at,
  })
  let next : UploadIndex = { version: 1, records, }
  @attachments.write_atomic(path, @utf8.encode(Json(next).stringify() + "\n"))
  @attachments.sync_directory(directory)
  @attachments.sync_directory(directory + "/..")
  uploaded.id
}

///|
async fn Client::resolve_attachments(
  self : Client,
  messages : Array[@deepseek.ChatMessage],
) -> Array[@deepseek.ChatMessage] {
  let resolved : Map[String, String] = Map([])
  @async.with_task_group() <| group => {
    let pending : Map[String, @async.Task[String]] = Map([])
    let permits = @semaphore.Semaphore(4)
    for message in messages {
      for part in message.content.0 {
        if part is ImageUrl(url~) &&
          url.has_prefix("openseek-attachment:") &&
          !pending.contains(url) {
          let reference = @protocol.ImageRef::from_url(url)
          pending[url] = group.spawn(() => {
            permits.acquire()
            defer permits.release()
            self.upload_attachment(reference)
          })
        }
      }
    }
    for url, task in pending {
      resolved[url] = task.wait()
    }
  }
  let result : Array[@deepseek.ChatMessage] = []
  for message in messages {
    let parts : Array[@deepseek.ContentPart] = []
    for part in message.content.0 {
      if part is ImageUrl(url~) && url.has_prefix("openseek-attachment:") {
        guard resolved.get(url) is Some(id) else {
          fail("image upload resolution missing")
        }
        parts.push(File(file_id=id))
      } else {
        parts.push(part)
      }
    }
    result.push(
      ChatMessage(
        message.role,
        content=parts,
        tool_calls=message.tool_calls,
        reasoning_content?=message.reasoning_content,
      ),
    )
  }
  result
}

///|
priv suberror RejectedImageFile {
  RejectedImageFile(String)
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
async fn Client::invalidate_uploads(
  self : Client,
  messages : Array[@deepseek.ChatMessage],
) -> Unit {
  let ids : Array[String] = []
  for message in messages {
    for part in message.content.0 {
      if part is File(file_id~) {
        ids.push(file_id)
      }
    }
  }
  if ids.is_empty() {
    return
  }
  let directory = self.upload_index_dir.unwrap_or_else(() => {
    @attachments.default_home() + "/deepseek"
  })
  let path = "\{directory}/files-v1.json"
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
  let index = read_upload_index(path)
  let scope = self.upload_scope()
  let records = index.records.filter(record => {
    !(record.scope == scope && ids.contains(record.file_id))
  })
  let next : UploadIndex = { version: 1, records, }
  @attachments.write_atomic(path, @utf8.encode(Json(next).stringify() + "\n"))
  @attachments.sync_directory(directory)
}
