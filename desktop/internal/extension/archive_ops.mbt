// Archiving a conversation: zip its workspace folder away and remember the
// session id so the sidebar can tuck the row under "Archived". The engine's
// durable session store is untouched — an archived conversation still opens
// and reads back its transcript; only the working directory is packed up
// (into `<workspace root>/Archived/<session>.zip`) and removed.

///|
const ArchivedListFile = "archived_sessions.txt"

///|
/// The recorded archived session ids, oldest first. Missing or unreadable
/// state reads as "nothing archived".
async fn archived_ids(runtime_dir : @path.Path?) -> Array[String] {
  guard runtime_dir is Some(dir) else { return [] }
  let data = @fs.read_file(dir.join(ArchivedListFile).to_string()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return []
  }
  let text = data.text() catch { _ => return [] }
  let ids : Array[String] = []
  for line in text.split("\n") {
    let line = line.trim().to_owned()
    if !line.is_empty() && !ids.contains(line) {
      ids.push(line)
    }
  }
  ids
}

///|
async fn archived_sessions_op(
  runtime_dir : @path.Path?,
) -> ArchivedSessionsReply {
  { sessions: archived_ids(runtime_dir) }
}

///|
async fn archive_session_op(
  runtime_dir : @path.Path?,
  payload : ArchiveSessionPayload,
) -> ArchivedSessionsReply {
  let session = payload.session.trim().to_owned()
  guard !session.is_empty() else { raise HostError("empty session id") }
  guard runtime_dir is Some(dir) else {
    raise HostError("no runtime directory to record archives in")
  }
  // Pack the workspace away first — only a successful zip removes the live
  // folder. A conversation that never ran has no folder; just record it.
  let cwd = @engine.session_cwd(session)
  let has_workspace = !cwd.is_empty() &&
    (@fs.kind(cwd) catch {
      error if @async.is_being_cancelled() => raise error
      _ => Unknown
    })
    is Directory
  if has_workspace {
    let workspace : @path.Path = Path(cwd)
    let parent = workspace.dirname().to_string()
    let archive_dir = workspace.dirname().join("Archived").to_string()
    if !((@fs.kind(archive_dir) catch { _ => Unknown }) is Directory) {
      @fs.mkdir(archive_dir, recursive=true) catch {
        error if @async.is_being_cancelled() => raise error
        error => raise HostError("could not create \{archive_dir}: \{error}")
      }
    }
    let destination = workspace
      .dirname()
      .join("Archived")
      .join("\{session}.zip")
      .to_string()
    let code = zip_directory(parent, session, destination) catch {
      error if @async.is_being_cancelled() => raise error
      error => raise HostError("could not archive the workspace: \{error}")
    }
    guard code == 0 else {
      raise HostError("could not archive the workspace (zip exited \{code})")
    }
    @fs.rmdir(cwd, recursive=true) catch {
      error if @async.is_being_cancelled() => raise error
      error =>
        raise HostError("archived, but could not remove \{cwd}: \{error}")
    }
  }
  let ids = archived_ids(runtime_dir)
  if !ids.contains(session) {
    ids.push(session)
    @fs.write_file(
      dir.join(ArchivedListFile).to_string(),
      ids.join("\n") + "\n",
      create_mode=CreateOrTruncate,
    ) catch {
      error if @async.is_being_cancelled() => raise error
      error => raise HostError("could not record the archive: \{error}")
    }
  }
  { sessions: ids }
}

///|
/// Zip `name` (a directory inside `parent`) into `destination`, returning the
/// archiver's exit code.
#cfg(not(platform="windows"))
async fn zip_directory(
  parent : String,
  name : String,
  destination : String,
) -> Int {
  @process.run("zip", ["-qry", destination, name], cwd=parent)
}

///|
#cfg(platform="windows")
async fn zip_directory(
  parent : String,
  name : String,
  destination : String,
) -> Int {
  @process.run(
    "powershell",
    [
      "-NoProfile",
      "-Command",
      "Compress-Archive -Force -Path '" +
      name +
      "' -DestinationPath '" +
      destination +
      "'",
    ],
    cwd=parent,
  )
}
