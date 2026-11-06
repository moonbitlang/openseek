// The in-app folder picker's data source: list one host directory's
// subdirectories. Unlike `read_directory` this is not scoped to a
// conversation's workspace — its whole purpose is choosing a new workspace
// anywhere on the host, and the gateway's token already gates full host
// access (the engine executes arbitrary tools). The frontend renders the
// picker itself, so desktop and browser share one flow and the directories
// shown are always the host machine's.

///|
/// A refusal (bad path, not a directory, unreadable) travels inside the
/// reply: the local bridge would flatten a raised error down to
/// "op ext:openseek/fs.browse failed".
pub async fn browse(
  payload : @protocol.BrowseDirectoryPayload,
) -> @protocol.BrowseDirectoryReply {
  browse_directory_listing(payload) catch {
    error => BrowseError("\{error}")
  }
}

///|
async fn browse_directory_listing(
  payload : @protocol.BrowseDirectoryPayload,
) -> @protocol.BrowseDirectoryReply {
  let requested = payload.path.unwrap_or("").trim().to_owned()
  // The resource-path root "/" is a real location in every listing's URI
  // space, but on Windows no directory lives there: the level above the
  // drive roots is the drive list, and answering it is what lets the picker
  // reach another drive letter.
  if requested == "/" && @async.platform is Windows {
    return Drives(entries=windows_drive_list())
  }
  let target : @pathx.Absolute = if requested.is_empty() {
    guard @home.dir() is Some(home) else { raise NoHomeDirectory }
    home.resolve()
  } else {
    // Breadcrumb and directory-row clicks return the URI path from the
    // preceding reply, including `/C:/...` on Windows.
    @pathx.Absolute::parse_resource_path(requested) catch {
      InvalidResourcePath =>
        // Pasted paths also accept native Windows spelling, `~`, and relative
        // paths. Only this input-format mismatch selects the native parser.
        @home.expand(Path(requested)).resolve()
    }
  }
  let dir = target.normalize()
  // Fail before reading a directory we cannot name back to the frontend.
  // In particular, UNC cannot share the resource URI's device authority.
  let encoded_dir = dir.resource_path()
  let kind = @fs.kind(dir.to_string()) catch {
    _ => raise InvalidRequest("no such directory: \{dir}")
  }
  guard kind is Directory else {
    raise InvalidRequest("not a directory: \{dir}")
  }
  let names = @fs.readdir(dir.to_string())
  // Lexicographic, not shortlex — see the note in `read_directory`.
  names.sort_by((a, b) => a.lexical_compare(b))
  let entries : Array[String] = []
  for name in names {
    if name.has_prefix(".") {
      continue
    }
    let child = dir.join((name : @pathx.Relative)).to_string()
    let is_dir = (@fs.kind(child) catch { _ => Unknown }) is Directory
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
    Some(parent_path.resolve().resource_path())
  }
  Listing(path=encoded_dir, parent~, entries~)
}

///|
/// Create one folder directly under a location the picker already listed,
/// then return the new folder's listing. The frontend can therefore enter the
/// folder using the same fenced reply path as ordinary navigation.
pub async fn create_directory(
  payload : @protocol.CreateDirectoryPayload,
) -> @protocol.BrowseDirectoryReply {
  create_directory_listing(payload) catch {
    error => BrowseError("\{error}")
  }
}

///|
async fn create_directory_listing(
  payload : @protocol.CreateDirectoryPayload,
) -> @protocol.BrowseDirectoryReply {
  let name = payload.name.trim().to_owned()
  guard !name.is_empty() else {
    raise InvalidRequest("folder name cannot be empty")
  }
  guard name != "." && name != ".." && !name.contains_any(chars="/\\") else {
    raise InvalidRequest("folder name must be a single name")
  }
  let parent = @pathx.Absolute::parse_resource_path(payload.parent)
  let kind = @fs.kind(parent.to_string()) catch {
    _ => raise InvalidRequest("no such directory: \{parent}")
  }
  guard kind is Directory else {
    raise InvalidRequest("not a directory: \{parent}")
  }
  let target = parent.join((name : @pathx.Relative)).normalize()
  // `name` is a single leaf, but keep this containment assertion close to the
  // mutation so future path-policy changes cannot turn it into traversal.
  // Compare relative paths: normalization preserves a parent's trailing slash,
  // and dirname uses host separators rather than the serialized path spelling.
  guard target.relative_to(root=parent) is Some(relative) &&
    relative == (name : @pathx.Relative) else {
    raise InvalidRequest("folder name must be a single name")
  }
  if @fs.exists(target.to_string()) {
    raise InvalidRequest("a folder named “\{name}” already exists")
  }
  @fs.mkdir(target.to_string())
  browse_directory_listing({ path: Some(target.resource_path()), })
}

///|
/// The mounted Windows drives, by probing every letter: 26 stats are cheap
/// next to the listing's readdir, and a letter without media simply fails
/// the probe. Spellings are bare ("C:") because they are the drive list's
/// row names; the frontend enters a drive through its resource path.
async fn windows_drive_list() -> Array[String] {
  let drives : Array[String] = []
  for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
    let kind = @fs.kind("\{letter}:\\") catch { _ => continue }
    if kind is Directory {
      drives.push("\{letter}:")
    }
  }
  drives
}

///|
async test "directory browsing accepts native input and returns URI paths" {
  let dir = @fs.tmpdir(prefix="openseek-browse-path-")
  defer @fs.rmdir(dir, recursive=true)
  @fsx.ensure_dir(Path(dir + "/child"))
  let absolute = @pathx.Path(dir).resolve().normalize()
  guard browse({ path: Some(dir), }) is Listing(path~, entries~, ..) else {
    fail("expected a listing for an existing directory")
  }
  assert_eq(path, absolute.resource_path())
  assert_true(entries.contains("child"))
  // Navigation sends the path from the preceding reply back unchanged.
  guard browse({ path: Some(path), }) is Listing(path=again, ..) else {
    fail("expected a listing for the resource path")
  }
  assert_eq(again, path)
}

///|
async test "the resource root stays a real listing on POSIX hosts" {
  // On Windows the same address answers the drive list; POSIX hosts must
  // keep serving the filesystem root as an ordinary directory.
  if @async.platform is Windows {
    return
  }
  guard browse({ path: Some("/"), }) is Listing(path~, parent~, ..) else {
    fail("expected the filesystem root to list")
  }
  assert_eq(path, "/")
  assert_true(parent is None)
}

///|
async test "a bad browse path reports its refusal in the reply" {
  guard browse({ path: Some("/definitely/not/here-openseek"), })
    is BrowseError(message) else {
    fail("expected a browse refusal")
  }
  assert_true(message.contains("no such directory"))
}

///|
async test "directory creation makes and enters one direct child" {
  let dir = @fs.tmpdir(prefix="openseek-create-directory-")
  defer @fs.rmdir(dir, recursive=true)
  let parent = @pathx.Path(dir).resolve().normalize()
  guard create_directory({
      parent: parent.resource_path(),
      name: "new project",
    })
    is Listing(path~, parent=listed_parent, entries~) else {
    fail("expected the created directory to be listed")
  }
  assert_eq(
    path,
    parent.join(("new project" : @pathx.Relative)).resource_path(),
  )
  assert_eq(listed_parent, Some(parent.resource_path()))
  assert_true(entries.is_empty())
  assert_true(
    @fs.exists(parent.join(("new project" : @pathx.Relative)).to_string()),
  )
}

///|
async test "directory creation rejects traversal and existing names" {
  let dir = @fs.tmpdir(prefix="openseek-create-directory-refusal-")
  defer @fs.rmdir(dir, recursive=true)
  let parent = @pathx.Path(dir).resolve().normalize()
  @fs.mkdir(parent.join(("taken" : @pathx.Relative)).to_string())
  for name in ["../outside", "taken"] {
    guard create_directory({ parent: parent.resource_path(), name, })
      is BrowseError(_) else {
      fail("expected folder creation to reject \{name}")
    }
  }
}
