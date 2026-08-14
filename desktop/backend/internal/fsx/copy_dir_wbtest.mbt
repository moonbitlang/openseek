///|
/// A copied tree has to arrive whole: nested directories, every file, and the
/// destination's own files left alone. This is how a session record crosses
/// from one filesystem to another when `rename` cannot span them.
#cfg(not(platform="windows"))
async test "copy_dir reproduces a nested tree over what is already there" {
  let dir = @fs.tmpdir(prefix="openseek-copy-dir-")
  defer @fs.rmdir(dir, recursive=true)
  let root : @pathx.Path = Path(dir)
  let source = root.join("source")
  ensure_dir(source.join("events"))
  write_text(source.join("meta.json"), "{}")
  write_text(source.join("events/1.jsonl"), "first\n")
  let destination = root.join("destination")
  ensure_dir(destination)
  write_text(destination.join("meta.json"), "stale")
  write_text(destination.join("only-here.json"), "kept")
  copy_dir(source, destination)
  assert_eq(read_text(destination.join("meta.json")), "{}")
  assert_eq(read_text(destination.join("events/1.jsonl")), "first\n")
  assert_eq(read_text(destination.join("only-here.json")), "kept")
  // The source stays: the caller decides when — and whether — to erase it.
  assert_eq(read_text(source.join("meta.json")), "{}")
}
