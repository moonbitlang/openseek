///|
/// A private snapshot of the selected source for validation and publication.
priv struct StagedFile {
  file : @fs.File
  bytes : Int64
  digest : String
}

///|
fn is_mbt_source(path : String) -> Bool {
  path.has_suffix(".mbt") || path.has_suffix(".mbt.md")
}

///|
fn requires_text(path : String) -> Bool {
  is_mbt_source(path) ||
  path.has_suffix(".mbtx") ||
  path.has_suffix(".mbti") ||
  @manifest_path.is_moon_mod_path(path) ||
  @manifest_path.is_moon_mod_json_path(path) ||
  @manifest_path.is_moon_pkg_path(path)
}

///|
async fn publish_file(
  candidate : StagedFile,
  path : String,
  target : String,
  existed : Bool,
  authorization : @permission.Authorization,
  file_state : @agent_tool.FileStateMap,
) -> Unit {
  // Rename the resolved file, not the link the user named. For new files
  // CreateNew semantics are enforced by rename(replace=false).
  let requested_destination = if existed { target } else { path }
  let basename = @path.Path(requested_destination).basename()
  guard !basename.is_empty() && requested_destination.has_suffix(basename) else {
    fail("copy requires a file destination")
  }
  let parent = @path.Path(requested_destination).dirname().to_string()
  let destination_parent = @fs.realpath(parent)
  // Place the temporary file under the resolved parent so a retargeted
  // directory symlink cannot move its cleanup path while the gate is released.
  let destination = @path.Path(destination_parent)
    .join(Path(basename.to_owned()))
    .to_string()
  async fn recheck_path() -> Unit {
    if authorization.deny_reason(path) is Some(reason) {
      fail("copy blocked: \{reason}")
    }
    guard @fs.realpath(parent) == destination_parent else {
      fail("file target directory changed before copying; re-read and retry")
    }
    if existed {
      guard @fs.exists(path) && @fs.realpath(path) == target else {
        fail("file target changed before copying; re-read and retry")
      }
      guard @fs.kind(target) is Regular && @fs.can_write(target) else {
        fail("copy can only replace writable regular files")
      }
    }
  }
  recheck_path()
  @atomic_file.write_atomic(
    destination,
    temp => {
      file_state.without_access(() => {
        let actual = @file_content.transfer(candidate.file, destination=temp)
        guard actual == (candidate.bytes, candidate.digest) else {
          fail("staged source changed before copying; re-read and retry")
        }
        // Flush before replacing the old file so allocation errors surface
        // while the destination is still intact.
        temp.sync(only_data=true)
      })
    },
    replace=existed,
    // A replacement installs a new file. Use a private mode so it cannot
    // widen access to an existing file whose full mode/ACL we cannot copy.
    permission=if existed { 0o600 } else { 0o644 },
    before_commit=() => {
      authorization.recheck()
      recheck_path()
    },
  )
}
