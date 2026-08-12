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
  let file = WirePath::parse(payload.path).absolute
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
  // `text()` raises on invalid UTF-8 — treat that as a binary file the
  // read-only viewer cannot render.
  let content = data.text() catch { _ => return Binary }
  let absolute = file.resource_path()
  Content(content~, absolute~, sig="\{seconds}:\{nanos}")
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
