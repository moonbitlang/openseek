// The in-app folder picker's data source: list one host directory's
// subdirectories. Unlike `read_directory` this is not scoped to a
// conversation's workspace — its whole purpose is choosing a new workspace
// anywhere on the host, and the gateway's token already gates full host
// access (the engine executes arbitrary tools). The frontend renders the
// picker itself, so desktop and browser share one flow and the directories
// shown are always the host machine's.

///|
type BrowseDirectoryPayload = @protocol.BrowseDirectoryPayload

///|
type BrowseDirectoryReply = @protocol.BrowseDirectoryReply

///|
/// A refusal (bad path, not a directory, unreadable) travels inside the
/// reply: the local bridge would flatten a raised error down to
/// "op ext:openseek/fs.browse failed".
async fn browse_directory_op(
  payload : BrowseDirectoryPayload,
) -> BrowseDirectoryReply {
  browse_directory_listing(payload) catch {
    error if @async.is_being_cancelled() => raise error
    HostError(message) => BrowseError(message)
    error => raise error
  }
}

///|
async fn browse_directory_listing(
  payload : BrowseDirectoryPayload,
) -> BrowseDirectoryReply {
  let requested = payload.path.unwrap_or("").trim().to_owned()
  let target : @pathx.Absolute = if requested.is_empty() {
    guard @home.dir() is Some(home) else {
      raise HostError("cannot determine the home directory")
    }
    home.resolve()
  } else if @pathx.Absolute::from_uri_path(requested) is Some(absolute) {
    // Breadcrumb and directory-row clicks return the URI path from the
    // preceding reply, including `/C:/...` on Windows.
    absolute
  } else {
    @pathx.Path(
      // A pasted path is an operating-system boundary: accept the host's
      // ordinary spelling (`C:\...` on Windows), `~`, and the same relative
      // spellings the picker accepted before frontend resources were typed.
      requested,
    )
    .expand_home()
    .resolve()
  }
  let dir = target.normalize()
  // Fail before reading a directory we cannot name back to the frontend.
  // In particular, UNC cannot share the resource URI's device authority.
  let encoded_dir = dir.resource_path()
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
    let child = dir.join((name : @pathx.Relative)).to_string()
    let is_dir = (@fs.kind(child) catch {
        error if @async.is_being_cancelled() => raise error
        _ => Unknown
      })
      is Directory
    if is_dir {
      entries.push(name)
    }
  }
  // Parent discovery is only used to serialize the picker reply, so drop the
  // absolute classification at this output boundary.
  let parent_path = dir.to_path().dirname()
  let parent = if parent_path.to_string() == dir.to_string() {
    None
  } else {
    guard parent_path.to_absolute() is Some(parent) else {
      raise HostError("directory parent is not absolute")
    }
    Some(parent.resource_path())
  }
  Listing(path=encoded_dir, parent~, entries~)
}

///|
async test "directory browsing accepts native input and returns URI paths" {
  let dir = @fs.tmpdir(prefix="openseek-browse-path-")
  @fsx.ensure_dir(Path(dir + "/child"))
  let absolute = @pathx.Path(dir).resolve().normalize()
  guard browse_directory_op({ path: Some(dir) }) is Listing(path~, entries~, ..) else {
    fail("expected a listing for an existing directory")
  }
  assert_eq(path, absolute.resource_path())
  assert_true(entries.contains("child"))
  // Navigation sends the path from the preceding reply back unchanged.
  guard browse_directory_op({ path: Some(path) }) is Listing(path=again, ..) else {
    fail("expected a listing for the resource path")
  }
  assert_eq(again, path)
  @fs.rmdir(dir, recursive=true)
}

///|
async test "a bad browse path reports its refusal in the reply" {
  guard browse_directory_op({ path: Some("/definitely/not/here-openseek") })
    is BrowseError(message) else {
    fail("expected a browse refusal")
  }
  assert_true(message.contains("no such directory"))
}
