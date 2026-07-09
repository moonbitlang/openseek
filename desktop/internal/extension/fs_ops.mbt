// Host-local filesystem ops backing the editor side-panel: list a directory
// and read a file, both resolved under the conversation's workspace. Pure
// request/response — none of this touches the engine pump. The host derives
// the workspace root from the session id and rejects any path that escapes
// it, so the webview can browse a conversation's directory but nothing else.

///|
/// Largest file the viewer will load. Bigger files return a notice instead of
/// reading the whole thing into memory.
const MaxReadFileBytes = 1048576

///|
async fn read_directory_op(payload : ReadDirPayload) -> ReadDirReply {
  guard @engine.resolve_in_workspace(
      payload.session,
      payload.path,
      workspace?=payload.workspace,
    )
    is Some(dir) else {
    raise HostError("path is outside the conversation workspace")
  }
  // A conversation's workspace directory is created lazily on its first run,
  // so before then it does not exist yet. Treat that as an empty workspace
  // rather than an error, so the panel can browse a new conversation.
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
    let child = dir.join((name : @path.Path)).to_string()
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
/// Most files `list_files` will index before giving up — a guard against
/// pathological workspaces (say, an untracked build tree the prune list
/// misses), not a target. The reply says when the cap cut the walk short.
const MaxIndexedFiles = 20000

///|
/// Enumerate every file under the conversation's workspace for the panel's
/// fuzzy finder: depth-first, each directory's entries in lexicographic
/// order, pruning the same churn directories the watcher skips.
async fn list_files_op(payload : ListFilesPayload) -> ListFilesReply {
  guard @engine.resolve_in_workspace(
      payload.session,
      "",
      workspace?=payload.workspace,
    )
    is Some(root) else {
    raise HostError("path is outside the conversation workspace")
  }
  let files : Array[String] = []
  // A workspace directory that does not exist yet (created lazily on the
  // first run) reads as empty, matching `read_directory`.
  let truncated = if @fs.exists(root.to_string()) {
    collect_files(root, "", files)
  } else {
    false
  }
  { files, truncated }
}

///|
/// Append `dir`'s files (as `/`-separated paths relative to the walk root;
/// `prefix` is `dir`'s own relative path, `""` at the root) to `into`,
/// recursing into unpruned subdirectories. Returns whether the file cap
/// stopped the walk. An unreadable directory skips itself — the rest of the
/// workspace still gets indexed.
async fn collect_files(
  dir : @path.Path,
  prefix : String,
  into : Array[String],
) -> Bool {
  let listing = @fs.opendir(dir.to_string()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return false
  }
  defer listing.close()
  let entries : Array[@fs.DirectoryEntry] = []
  for ;; {
    let entry = listing.next() catch {
      error if @async.is_being_cancelled() => raise error
      _ => None
    }
    guard entry is Some(entry) else { break }
    entries.push(entry)
  }
  // Lexicographic like `read_directory` (see the shortlex note there), so
  // the index's base order matches the tree's.
  entries.sort_by((a, b) => a.name.lexical_compare(b.name))
  for entry in entries {
    let relative = if prefix.is_empty() {
      entry.name
    } else {
      prefix + "/" + entry.name
    }
    if entry.is_dir {
      if ignored_watch_path(relative) {
        continue
      }
      if collect_files(dir.join((entry.name : @path.Path)), relative, into) {
        return true
      }
    } else {
      if into.length() >= MaxIndexedFiles {
        return true
      }
      into.push(relative)
    }
  }
  false
}

///|
async fn read_file_op(payload : ReadFilePayload) -> ReadFileReply {
  guard @engine.resolve_in_workspace(
      payload.session,
      payload.path,
      workspace?=payload.workspace,
    )
    is Some(file) else {
    raise HostError("path is outside the conversation workspace")
  }
  let absolute = file.to_string()
  let source = @fs.open(absolute, mode=ReadOnly) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise HostError("failed to read file: \{error}")
  }
  defer source.close()
  // Check the size before reading anything: a multi-gigabyte build artifact
  // must produce the notice, not a host-sized allocation.
  if source.size() > MaxReadFileBytes.to_int64() {
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
  Content(content~, absolute~, sig="\{seconds}:\{nanos}")
}

///|
/// The mtime signatures of the open tabs' files (see `StatFilesPayload`).
/// A path that stopped resolving inside the workspace reads as missing
/// rather than an error: to the panel, a file it can no longer address is a
/// deleted file.
async fn stat_files_op(payload : StatFilesPayload) -> StatFilesReply {
  let stats : Array[FileStat] = []
  for path in payload.paths {
    let sig = match
      @engine.resolve_in_workspace(
        payload.session,
        path,
        workspace?=payload.workspace,
      ) {
      Some(file) => file_signature(file.to_string())
      None => ""
    }
    stats.push({ path, sig })
  }
  { stats, }
}

///|
/// `"{seconds}:{nanos}"` of the file's mtime, or `""` when it cannot be
/// stat'ed — a missing file, by far the common case; any other stat failure
/// reads the same way, and the panel's read-on-change then surfaces the real
/// error if the file actually exists.
async fn file_signature(absolute : String) -> String {
  let (seconds, nanos) = @fs.mtime(absolute) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return ""
  }
  "\{seconds}:\{nanos}"
}
