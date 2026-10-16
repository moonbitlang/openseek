///|
/// Each SSH route owns its cache. Remote paths are keys, never local destinations.
priv struct PreviewEntry {
  source : String
  media_type : String
  local_path : String
  bytes : Int32
}

///|
struct PreviewCache {
  directory : String
  entries : Array[PreviewEntry]
  gate : @semaphore.Semaphore
  limit : Int32
  mut closed : Bool
}

///|
fn PreviewCache::PreviewCache(
  directory : String,
  limit~ : Int32 = 64 * 1024 * 1024,
) -> PreviewCache {
  { directory, entries: [], gate: Semaphore(1), limit, closed: false, }
}

///|
async fn PreviewCache::close(self : PreviewCache) -> Unit {
  self.gate.acquire()
  defer self.gate.release()
  self.closed = true
  @fs.rmdir(self.directory, recursive=true)
}

///|
async fn PreviewCache::load(
  self : PreviewCache,
  source : String,
  fetch : async () -> @protocol.FilePreviewContent,
) -> String {
  self.gate.acquire()
  defer self.gate.release()
  guard !self.closed else { raise SshError("Preview window is closed") }
  let content = fetch()
  // The service enforces this too. Validate the actual decoded payload before
  // writing a file, including when a remote peer returns a malformed reply.
  guard content.data_base64.length() <= 12 * 1024 * 1024 else {
    raise SshError("Preview content exceeds the file limit")
  }
  let bytes = @base64.decode(content.data_base64)
  guard bytes.length() <= 8 * 1024 * 1024 else {
    raise SshError("Preview content exceeds the file limit")
  }
  let media_type = match @filekind.classify(bytes) {
    Image(media_type~) => media_type
    Pdf => "application/pdf"
    _ => raise SshError("Unsupported preview content")
  }
  guard media_type == content.media_type else {
    raise SshError("Preview content does not match its media type")
  }
  let old = self.entries
    .iter()
    .filter(entry => entry.source == source && entry.media_type == media_type)
    .next()
  let used = self.entries.fold(init=0, (sum, entry) => sum + entry.bytes)
  guard used - old.map(entry => entry.bytes).unwrap_or(0) + bytes.length() <=
    self.limit &&
    (old is Some(_) || self.entries.length() < 128) else {
    raise SshError(
      "This window's preview cache is full; reopen the window to release it",
    )
  }
  let extension = match media_type {
    "image/png" => "png"
    "image/jpeg" => "jpg"
    "image/gif" => "gif"
    "image/webp" => "webp"
    _ => "pdf"
  }
  let destination = match old {
    Some(entry) => entry.local_path
    None => self.directory + "/" + @uuid.mint() + "." + extension
  }
  let staging = self.directory + "/" + @uuid.mint() + ".partial"
  @fs.write_file(staging, bytes, create_mode=CreateNew)
  defer @fsx.remove_if_exists(Path(staging))
  @fs.rename(staging, destination, replace=true)
  let entry = PreviewEntry::{
    source,
    media_type,
    local_path: destination,
    bytes: bytes.length(),
  }
  if old is Some(old) {
    for index in 0..<self.entries.length() {
      if self.entries[index].local_path == old.local_path {
        self.entries[index] = entry
        break
      }
    }
  } else {
    self.entries.push(entry)
  }
  destination
}
