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
  let names = @fs.readdir(dir.to_string(), sort=true) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise HostError("failed to list directory: \{error}")
  }
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
  // Directories first, then files; `readdir(sort=true)` already orders each
  // group by name, and the partition preserves that order.
  let dirs = entries.filter(entry => entry.is_dir)
  let files = entries.filter(entry => !entry.is_dir)
  { entries: dirs + files }
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
    return {
      content: "File is too large to preview.",
      truncated: true,
      absolute,
    }
  }
  let data = source.read_all() catch {
    error if @async.is_being_cancelled() => raise error
    error => raise HostError("failed to read file: \{error}")
  }
  // `text()` raises on invalid UTF-8 — treat that as a binary file the
  // read-only viewer cannot render.
  let content = data.text() catch {
    _ =>
      return {
        content: "Binary file is not previewable.",
        truncated: true,
        absolute,
      }
  }
  { content, truncated: false, absolute }
}
