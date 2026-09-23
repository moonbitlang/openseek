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
  @fsx.ensure_dir(source.join("events"))
  @fsx.write_text(source.join("meta.json"), "{}")
  @fsx.write_text(source.join("events/1.jsonl"), "first\n")
  let destination = root.join("destination")
  @fsx.ensure_dir(destination)
  @fsx.write_text(destination.join("meta.json"), "stale")
  @fsx.write_text(destination.join("only-here.json"), "kept")
  @fsx.copy_dir(source, destination)
  assert_eq(@fsx.read_text(destination.join("meta.json")), "{}")
  assert_eq(@fsx.read_text(destination.join("events/1.jsonl")), "first\n")
  assert_eq(@fsx.read_text(destination.join("only-here.json")), "kept")
  // The source stays: the caller decides when — and whether — to erase it.
  assert_eq(@fsx.read_text(source.join("meta.json")), "{}")
}
