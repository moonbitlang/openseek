///|
/// Immutable image storage. The root is the attachments directory itself.
pub struct AttachmentStore {
  priv root : String
} derive(Debug)

///|
pub extend AttachmentStore with @debug.Debug::{to_repr}

///|
/// Bind all attachment operations to a directory; creates files only on save.
pub fn AttachmentStore::AttachmentStore(root : String) -> AttachmentStore {
  { root, }
}

///|
/// Construct the executing host's user-level attachment store.
pub fn AttachmentStore::default() -> AttachmentStore raise {
  AttachmentStore(default_home() + "/attachments")
}

///|
/// Resolve the host's user-level OpenSeek data directory.
pub fn default_home() -> String raise {
  let home = if @async.platform is Windows {
    if @env.get_env_var("USERPROFILE") is Some(value) {
      Some(value)
    } else {
      @env.get_env_var("HOME")
    }
  } else {
    @env.get_env_var("HOME")
  }
  guard home is Some(home) && !home.is_blank() else {
    fail("cannot resolve the user home for image attachments")
  }
  "\{home}/.openseek"
}

///|
/// Content identity of the original image bytes, without transcoding.
pub fn digest(bytes : Bytes) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
}

///|
/// Locate a validated reference below the host's attachment store.
pub fn AttachmentStore::path(
  self : AttachmentStore,
  reference : @protocol.ImageRef,
) -> String {
  let hash = reference.attachment_id.strip_prefix("sha256:").unwrap_or("")
  "\{self.root}/v1/objects/\{hash[:2]}/\{hash}"
}

///|
/// Flush a directory entry where directory syncing is supported.
pub async fn sync_directory(path : String) -> Unit {
  let file = @fs.open(path, mode=ReadOnly) catch { _ => return }
  defer file.close()
  file.sync() catch {
    _ => ()
  }
}

///|
/// Atomically publish complete data; concurrent callers never share a temp file.
/// The caller creates the parent and owns any read/modify/write lock.
pub async fn write_atomic(path : String, data : Bytes) -> Unit {
  guard @env.rand(16) is Some(random) else {
    fail("cannot allocate atomic file identity")
  }
  let temporary = "\{path}.\{digest(random)}.tmp"
  let file = @fs.open(
    temporary,
    mode=ReadWrite,
    create_mode=CreateNew,
    permission=0o600,
  )
  defer (@fs.remove(temporary) catch { _ => () })
  {
    defer file.close()
    file.write(data)
    file.sync(only_data=true)
  }
  @fs.rename(temporary, path, replace=true)
}

///|
/// Save immutable original bytes before publishing a reference in any session.
pub async fn AttachmentStore::save(
  self : AttachmentStore,
  image : @protocol.Image,
) -> @protocol.ImageRef {
  let reference = @protocol.ImageRef::ImageRef(
    attachment_id="sha256:\{digest(image.bytes)}",
    media_type=image.media_type,
    bytes=image.bytes.length(),
  )
  let file_path = self.path(reference)
  let hash = digest(image.bytes)
  let objects = "\{self.root}/v1/objects"
  let shard = "\{objects}/\{hash[:2]}"
  @fs.mkdir(shard, recursive=true, allow_exist=true, permission=0o700)
  if @fs.exists(file_path) {
    ignore(self.read(reference))
  } else {
    write_atomic(file_path, image.bytes)
  }
  for
    directory in [
      shard,
      objects,
      "\{self.root}/v1",
      self.root,
      self.root + "/..",
    ] {
    sync_directory(directory)
  }
  reference
}

///|
/// Read bounded bytes and verify digest and metadata before display or upload.
pub async fn AttachmentStore::read(
  self : AttachmentStore,
  reference : @protocol.ImageRef,
) -> @protocol.Image {
  let file = @fs.open(self.path(reference), mode=ReadOnly)
  defer file.close()
  guard file.size() == reference.bytes.to_int64() else {
    fail("image attachment size mismatch: \{reference.attachment_id}")
  }
  let bytes = file.read_exactly(reference.bytes)
  guard "sha256:\{digest(bytes)}" == reference.attachment_id else {
    fail("image attachment digest mismatch: \{reference.attachment_id}")
  }
  let image = @protocol.Image::from_bytes(bytes)
  guard image.media_type == reference.media_type else {
    fail("image attachment media type mismatch: \{reference.attachment_id}")
  }
  image
}

///|
/// Admit inline images to durable storage while preserving mixed-content order.
pub async fn AttachmentStore::admit(
  self : AttachmentStore,
  content : @protocol.Content,
) -> @protocol.Content {
  let parts : Array[@protocol.ContentPart] = []
  for part in content.0 {
    parts.push(
      match part {
        Image(image) => ImageRef(self.save(image))
        ImageRef(reference) => {
          ignore(self.read(reference))
          part
        }
        Text(_) => part
      },
    )
  }
  Content(parts)
}

///|
/// Restore bytes only for a deliberately portable export, never normal history.
pub async fn AttachmentStore::restore(
  self : AttachmentStore,
  content : @protocol.Content,
) -> @protocol.Content {
  let parts : Array[@protocol.ContentPart] = []
  for part in content.0 {
    parts.push(
      match part {
        ImageRef(reference) => Image(self.read(reference))
        _ => part
      },
    )
  }
  Content(parts)
}
