///|
/// How many names `fresh_call_dir` draws before giving up. A draw only fails
/// when one of the few call directories alive under the same owner holds the
/// same 32 random bits, so a second draw is already a rarity; the bound is
/// there so a name can never be drawn forever.
const CallDirAttempts : Int32 = 8

///|
/// Create one call's own directory under a caller-owned `parent` and return
/// its path: `<parent>/<prefix><8 hex digits>`.
///
/// The name is short on purpose. Windows tools (moonc, the C compiler, the
/// linker) refuse a path of 260 characters or more, and below a build
/// directory moon appends over 100 for one dependency artifact
/// (`_build/snippet.mbtx/<target>/debug/build/.mooncakes/<owner>/<module>/<package>/<package>.core`)
/// on top of the user's temp directory and the session's job dir. A full UUID
/// here spends 28 characters of that budget on uniqueness the filesystem
/// gives for free: `mkdir` creates the leaf exclusively, so a name that is
/// already taken is simply drawn again.
async fn fresh_call_dir(parent : String, prefix : String) -> String {
  for _ in 0..<CallDirAttempts {
    // The tail of a UUIDv7 is the random part; its head is a timestamp that
    // calls made close together would share.
    let id = @uuid.v7()
    let dir = "\{parent}/\{prefix}\{id[id.length() - 8:]}"
    @fs.mkdir(dir, recursive=true) catch {
      @os_error.OSError(_) as error if error.is_EEXIST() => continue
      error => raise error
    }
    return dir
  }
  fail("no free name for a call directory under \{parent}")
}
