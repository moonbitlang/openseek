///|
#cfg(not(platform="windows"))
async fn read_text(path : String) -> (String, String) {
  guard @files.read_file({ path, root: None, max_bytes: None, })
    is Content(content~, sig~, ..) else {
    fail("expected text content for \{path}")
  }
  (content, sig)
}

///|
#cfg(not(platform="windows"))
async fn signature(path : String) -> @protocol.FileSignature {
  guard @files.stat_files({ paths: [path], }).stats is [stat] &&
    stat.path == path else {
    fail("expected one stat result for \{path}")
  }
  stat.signature
}

///|
#cfg(not(platform="windows"))
async test "file signatures detect atomic replacement with preserved mtime" {
  let dir = @fs.tmpdir(prefix="openseek-file-signature-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/document.txt"
  @fs.write_text(path, "original", create_mode=CreateOrTruncate)
  let original_signature = signature(path)
  let original_mtime = @fs.mtime(path)

  // Replace the contents while preserving the original modification time.
  let replacement = "\{dir}/replacement"
  @fs.write_text(replacement, "changed contents", create_mode=CreateOrTruncate)
  let result = @processx.collect_output_no_stdin("touch", [
    "-r", path, replacement,
  ])
  let code = result.exit_code
  assert_eq(code, 0)
  @fs.rename(replacement, path, replace=true)

  assert_eq(@fs.mtime(path), original_mtime)
  let changed_signature = signature(path)
  assert_true(changed_signature != original_signature)
  let (content, read_signature) = read_text(path)
  assert_eq(content, "changed contents")
  assert_eq(changed_signature, Present(read_signature))
}

///|
#cfg(not(platform="windows"))
async test "read and stat signatures follow the same symlink target" {
  let dir = @fs.tmpdir(prefix="openseek-file-signature-")
  defer @fs.rmdir(dir, recursive=true)
  let target = "\{dir}/document.txt"
  let link = "\{dir}/link"
  @fs.write_text(target, "target contents", create_mode=CreateOrTruncate)
  @fs.symlink(link, target~)

  let (target_content, target_signature) = read_text(target)
  let (linked_content, linked_signature) = read_text(link)
  assert_eq(linked_content, target_content)
  assert_eq(linked_signature, target_signature)
  assert_eq(signature(target), Present(target_signature))
  assert_eq(signature(link), Present(target_signature))
}
