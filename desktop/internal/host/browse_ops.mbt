// The in-app folder picker's data source: list one host directory's
// subdirectories. Unlike `read_directory` this is not scoped to a
// conversation's workspace — its whole purpose is choosing a new workspace
// anywhere on the host, and the gateway's token already gates full host
// access (the engine executes arbitrary tools). The frontend renders the
// picker itself, so desktop and browser share one flow and the directories
// shown are always the host machine's.

///|
priv struct BrowseDirectoryPayload {
  // The directory to list; absent or blank = the user's home directory. A
  // leading `~` expands like `open_path`'s.
  path : String?
} derive(FromJson)

///|
priv struct BrowseDirectoryReply {
  // The listed directory, resolved absolute — what a confirm registers.
  path : String
  // Its parent for upward navigation; None at the filesystem root.
  parent : String?
  // Subdirectory names (not paths), sorted, dotfiles skipped.
  entries : Array[String]
} derive(ToJson)

///|
async fn browse_directory_op(
  payload : BrowseDirectoryPayload,
) -> BrowseDirectoryReply {
  let requested = payload.path.unwrap_or("").trim().to_owned()
  let target : @path.Path = if requested.is_empty() {
    guard @home.dir() is Some(home) else {
      raise HostError("cannot determine the home directory")
    }
    home
  } else {
    Path(expand_home(requested))
  }
  let dir = target.resolve().normalize()
  let kind = @fs.kind(dir.to_string()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => raise HostError("no such directory: \{dir}")
  }
  guard kind is Directory else { raise HostError("not a directory: \{dir}") }
  let names = @fs.readdir(dir.to_string()) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise HostError("failed to list directory: \{error}")
  }
  // Lexicographic, not shortlex — see the note in `read_directory`.
  names.sort_by((a, b) => a.lexical_compare(b))
  let entries : Array[String] = []
  for name in names {
    if name.has_prefix(".") {
      continue
    }
    let child = dir.join((name : @path.Path)).to_string()
    let is_dir = (@fs.kind(child) catch {
        error if @async.is_being_cancelled() => raise error
        _ => Unknown
      })
      is Directory
    if is_dir {
      entries.push(name)
    }
  }
  let parent_path = dir.dirname()
  let parent = if parent_path.to_string() == dir.to_string() {
    None
  } else {
    Some(parent_path.to_string())
  }
  { path: dir.to_string(), parent, entries }
}
