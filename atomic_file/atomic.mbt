///|
/// Write a complete file beside `path`, then publish it with a single rename.
/// The caller supplies an admitted destination with an existing parent; this
/// replaces the directory entry itself, including when it is a symbolic link.
/// `replace=false` makes publication fail if the entry already exists.
///
/// `write_temp` borrows the open temporary file until it returns. The file is
/// closed before `before_commit`, where callers can recheck their application
/// conditions. Errors or cancellation before publication leave the old target
/// in place and trigger best-effort temporary-file cleanup. The short rename is
/// protected from cancellation so a successful commit returns to the caller.
/// `permission` applies to the new file. Callers requiring file-data durability
/// can sync the handle in `write_temp`; directory durability is separate.
pub async fn write_atomic(
  path : String,
  write_temp : async (@fs.File) -> Unit,
  replace~ : Bool,
  permission~ : Int32 = 0o644,
  before_commit? : async () -> Unit,
) -> Unit {
  // Reject a NUL before passing the path to the native filesystem APIs.
  guard !path.contains("\u{0}") else { fail("file path contains a NUL") }
  let basename = @path.Path(path).basename()
  guard !basename.is_empty() && path.has_suffix(basename) else {
    fail("atomic write requires a file path")
  }
  // Keep the directory prefix verbatim and the temporary basename short,
  // even when the destination already uses the full basename length limit.
  let parent = path[:path.length() - basename.length()]
  guard @env.rand(16) is Some(bytes) else {
    fail("could not name a private temporary file beside \{path}")
  }
  let suffix = StringBuilder()
  for byte in bytes {
    suffix.write_string(byte.to_hex())
  }
  let temp = "\{parent}.openseek-write-\{suffix}"
  // Do not register cleanup until exclusive creation succeeds: on collision
  // the existing directory entry is not ours to remove.
  let file = @async.protect_from_cancel(() => {
    @fs.open(temp, mode=WriteOnly, create_mode=CreateNew, permission~)
  })
  errdefer (@fs.remove(temp, allow_missing=true) catch { _ => () })
  {
    defer file.close()
    write_temp(file)
  }
  if before_commit is Some(recheck) {
    recheck()
  }
  // Honor cancellation that arrived while acquiring the handle, including for
  // an empty write. Otherwise do not yield between the caller's check and rename.
  if @async.is_being_cancelled() {
    @async.pause()
  }
  @async.protect_from_cancel(() => @fs.rename(temp, path, replace~))
}

///|
/// Publish UTF-8 text atomically, replacing a file at `path` if it exists.
/// `permission` applies to the temporary file from its creation onward.
pub async fn write_text_atomic(
  path : String,
  content : String,
  permission~ : Int32 = 0o644,
) -> Unit {
  write_atomic(
    path,
    file => file.text.write(content),
    replace=true,
    permission~,
  )
}
