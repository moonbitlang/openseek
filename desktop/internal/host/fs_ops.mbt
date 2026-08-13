// Host-local filesystem ops backing the editor side-panel. Each request names
// its absolute target directly; none of these operations consult the engine
// or derive a path from a conversation id.

///|
async fn read_directory_op(payload : ReadDirPayload) -> ReadDirReply {
  let dir = WirePath::parse(payload.path).absolute
  // A requested root can be created lazily by the engine. Treat a missing
  // directory as empty so the panel can keep its ordinary loading behavior.
  if !@fs.exists(dir.to_string()) {
    return { entries: [] }
  }
  let names = @fs.readdir(dir.to_string()) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise HostError("failed to list directory: \{error}")
  }
  // Plain lexicographic order, not `readdir(sort=true)`: that sorts with
  // String's `Compare`, which is shortlex — length before content — and
  // reads wrong in a file listing ("z.mbt" before "main.mbt").
  names.sort_by((a, b) => a.lexical_compare(b))
  let entries : Array[DirEntry] = []
  for name in names {
    let child = dir.join((name : @pathx.Relative)).to_string()
    let is_dir = (@fs.kind(child) catch {
        error if @async.is_being_cancelled() => raise error
        _ => Unknown
      })
      is Directory
    entries.push({ name, is_dir })
  }
  // Directories first, then files; the sort above already orders each
  // group by name, and the partition preserves that order.
  let dirs = entries.filter(entry => entry.is_dir)
  let files = entries.filter(entry => !entry.is_dir)
  { entries: dirs + files }
}

///|
async fn read_file_op(payload : ReadFilePayload) -> ReadFileReply {
  let file = if payload.root is Some(root) {
    WirePath::parse(root).resolve(payload.path)
  } else {
    WirePath::parse(payload.path).absolute
  }
  let native = file.to_string()
  let source = @fs.open(native, mode=ReadOnly) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise HostError("failed to read file: \{error}")
  }
  defer source.close()
  // Check the size before reading anything: a multi-gigabyte build artifact
  // must produce the notice, not a host-sized allocation.
  if source.size() > @openpath.MaxEditorFileBytes.to_int64() {
    return Oversized
  }
  let data = source.read_all() catch {
    error if @async.is_being_cancelled() => raise error
    error => raise HostError("failed to read file: \{error}")
  }
  // The change-detection baseline, from the same open handle as the content
  // so the two cannot disagree about which version of the file was read.
  let (seconds, nanos) = source.mtime() catch {
    error if @async.is_being_cancelled() => raise error
    error => raise HostError("failed to read file: \{error}")
  }
  // Return supported raster files as bounded display bytes. The extension and
  // model-provided MIME are not trusted; a signature decides whether bytes may
  // enter a data URL. The same one-megabyte cap above bounds bridge pressure.
  let bytes = data.binary()
  if bytes.image_media_type() is Some(media_type) {
    return BinaryContent(data_base64=@base64.encode(bytes), media_type~)
  }
  // `text()` raises on invalid UTF-8 — treat that as a binary file the
  // read-only viewer cannot render.
  let content = data.text() catch { _ => return Binary }
  let absolute = file.resource_path()
  Content(content~, absolute~, sig="\{seconds}:\{nanos}")
}

///|
/// MIME for the small raster formats the transcript can render safely from a
/// `data:` URL. Signatures, rather than filename extensions, decide whether
/// bytes are allowed into that URL.
fn Bytes::image_media_type(self : Bytes) -> String? {
  match self {
    [b'\x89', b'P', b'N', b'G', b'\r', b'\n', b'\x1a', b'\n', ..] =>
      Some("image/png")
    [b'\xff', b'\xd8', b'\xff', ..] => Some("image/jpeg")
    [b'G', b'I', b'F', b'8', b'7', b'a', ..]
    | [b'G', b'I', b'F', b'8', b'9', b'a', ..] => Some("image/gif")
    [b'R', b'I', b'F', b'F', _, _, _, _, b'W', b'E', b'B', b'P', ..] =>
      Some("image/webp")
    _ => None
  }
}

///|
async test "binary file reads expose only recognized raster signatures" {
  let dir = "_build/host-read-file-image-test"
  if @fs.exists(dir) {
    @fs.rmdir(dir, recursive=true)
  }
  @fs.mkdir(dir, recursive=true)
  let image = "\{dir}/image.png"
  @fs.write_file(image, b"\x89PNG\r\n\x1a\nsmall", create_mode=CreateOrTruncate)
  let absolute = @pathx.Path(@fs.realpath(image))
    .to_absolute()
    .unwrap()
    .to_uri_path()
    .unwrap()
  assert_eq(
    read_file_op({ path: absolute, root: None }),
    BinaryContent(data_base64="iVBORw0KGgpzbWFsbA==", media_type="image/png"),
  )
  let root = @pathx.Path(@fs.realpath(dir))
    .to_absolute()
    .unwrap()
    .to_uri_path()
    .unwrap()
  assert_eq(
    read_file_op({ path: "image.png", root: Some(root) }),
    BinaryContent(data_base64="iVBORw0KGgpzbWFsbA==", media_type="image/png"),
  )
  let disguised = "\{dir}/not-an-image.png"
  @fs.write_file(disguised, b"\xffnot an image", create_mode=CreateOrTruncate)
  let disguised_absolute = @pathx.Path(@fs.realpath(disguised))
    .to_absolute()
    .unwrap()
    .to_uri_path()
    .unwrap()
  assert_eq(read_file_op({ path: disguised_absolute, root: None }), Binary)
  @fs.rmdir(dir, recursive=true)
}

///|
/// The mtime signatures of the open tabs' files (see `StatFilesPayload`).
/// A path that can no longer be stat'ed reads as missing rather than an error:
/// to the panel, the file was deleted.
async fn stat_files_op(payload : StatFilesPayload) -> StatFilesReply {
  let stats : Array[FileStat] = []
  for path in payload.paths {
    let file = WirePath::parse(path).absolute
    let sig = file_signature(file.to_string())
    stats.push({ path, sig: sig.unwrap_or("") })
  }
  { stats, }
}

///|
/// `"{seconds}:{nanos}"` of the file's mtime, or None when it cannot be
/// stat'ed — a missing file, by far the common case; any other stat failure
/// reads the same way, and the panel's read-on-change then surfaces the real
/// error if the file actually exists.
async fn file_signature(absolute : String) -> String? {
  let (seconds, nanos) = @fs.mtime(absolute) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  Some("\{seconds}:\{nanos}")
}
