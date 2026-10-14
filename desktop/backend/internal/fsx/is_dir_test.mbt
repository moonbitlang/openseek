///|
/// The two answers `is_dir` gives without raising: a directory is `true`, and
/// everything that is plainly not one is `false` — a regular file, a name
/// nothing holds, and a name below a regular file, which the filesystem
/// reports as ENOTDIR rather than ENOENT.
#cfg(not(platform="windows"))
async test "is_dir reads only a path that is not there as false" {
  let dir = @fs.tmpdir(prefix="openseek-is-dir-")
  defer @fs.rmdir(dir, recursive=true)
  let root : @pathx.Path = Path(dir)
  let file = root.join("file")
  @fsx.write_text(file, "")
  assert_true(@fsx.is_dir(root))
  assert_false(@fsx.is_dir(file))
  assert_false(@fsx.is_dir(root.join("missing")))
  assert_false(@fsx.is_dir(file.join("below-a-file")))
}

///|
/// A probe that could not look has no answer. Neither case needs permission
/// bits, which a test running as root would sail past: a path component
/// longer than any filesystem allows fails with ENAMETOOLONG, and a symlink
/// that names itself fails with ELOOP.
#cfg(not(platform="windows"))
async test "is_dir raises when the path cannot be inspected" {
  let dir = @fs.tmpdir(prefix="openseek-is-dir-unreadable-")
  defer @fs.rmdir(dir, recursive=true)
  let root : @pathx.Path = Path(dir)
  let too_long = root.join("n".repeat(300))
  let overlong = try @fsx.is_dir(too_long) catch {
    _ => None
  } noraise {
    answer => Some(answer)
  }
  assert_eq(overlong, None)
  let cycle = root.join("cycle")
  @fs.symlink(cycle.to_string(), target=cycle.to_string())
  let looped = try @fsx.is_dir(cycle) catch {
    _ => None
  } noraise {
    answer => Some(answer)
  }
  assert_eq(looped, None)
}
