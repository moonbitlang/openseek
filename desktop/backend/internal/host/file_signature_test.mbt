///|
priv struct FileSignatureApi {
  read : @endpoint.Endpoint
  stat : @endpoint.Endpoint
}

///|
fn FileSignatureApi::new() -> FileSignatureApi? {
  let actor = @engine.new_engine_actor("unused-test-engine")
  let endpoints = @host.endpoints(
    @host.new_host_state("unused-test-engine"),
    HostConnection(),
    actor.manager(),
    () => (),
  )
  let read = endpoints
    .iter()
    .filter(endpoint => endpoint.name() == "fs.read_file")
    .next()
  let stat = endpoints
    .iter()
    .filter(endpoint => endpoint.name() == "fs.stat_files")
    .next()
  match (read, stat) {
    (Some(read), Some(stat)) => Some({ read, stat, })
    _ => None
  }
}

///|
async fn FileSignatureApi::read_text(
  self : FileSignatureApi,
  path : String,
) -> (String, String) {
  let payload : @protocol.ReadFilePayload = { path, root: None, }
  let reply : @protocol.ReadFileReply = @json.from_json(
    self.read.invoke(payload.to_json()),
  )
  guard reply is Content(content~, sig~, ..) else {
    fail("expected text content for \{path}")
  }
  (content, sig)
}

///|
async fn FileSignatureApi::signature(
  self : FileSignatureApi,
  path : String,
) -> @protocol.FileSignature {
  let payload : @protocol.StatFilesPayload = { paths: [path], }
  let reply : @protocol.StatFilesReply = @json.from_json(
    self.stat.invoke(payload.to_json()),
  )
  guard reply.stats is [stat] && stat.path == path else {
    fail("expected one stat result for \{path}")
  }
  stat.signature
}

///|
#cfg(not(platform="windows"))
async test "file signatures detect atomic replacement with preserved mtime" {
  guard FileSignatureApi::new() is Some(api) else {
    fail("file endpoints missing")
  }
  let dir = @fs.tmpdir(prefix="openseek-file-signature-")
  defer @fs.rmdir(dir, recursive=true)
  let path = "\{dir}/document.txt"
  @fs.write_file(path, "original", create_mode=CreateOrTruncate)
  let original_signature = api.signature(path)
  let original_mtime = @fs.mtime(path)

  // Replace the contents while preserving the original modification time.
  let replacement = "\{dir}/replacement"
  @fs.write_file(replacement, "changed contents", create_mode=CreateOrTruncate)
  let (code, _, _) = @processx.collect_output_no_stdin("touch", [
    "-r", path, replacement,
  ])
  assert_eq(code, 0)
  @fs.rename(replacement, path, replace=true)

  assert_eq(@fs.mtime(path), original_mtime)
  let changed_signature = api.signature(path)
  assert_true(changed_signature != original_signature)
  let (content, read_signature) = api.read_text(path)
  assert_eq(content, "changed contents")
  assert_eq(changed_signature, Present(read_signature))
}

///|
#cfg(not(platform="windows"))
async test "read and stat signatures follow the same symlink target" {
  guard FileSignatureApi::new() is Some(api) else {
    fail("file endpoints missing")
  }
  let dir = @fs.tmpdir(prefix="openseek-file-signature-")
  defer @fs.rmdir(dir, recursive=true)
  let target = "\{dir}/document.txt"
  let link = "\{dir}/link"
  @fs.write_file(target, "target contents", create_mode=CreateOrTruncate)
  @fs.symlink(link, target~)

  let (target_content, target_signature) = api.read_text(target)
  let (linked_content, linked_signature) = api.read_text(link)
  assert_eq(linked_content, target_content)
  assert_eq(linked_signature, target_signature)
  assert_eq(api.signature(target), Present(target_signature))
  assert_eq(api.signature(link), Present(target_signature))
}
