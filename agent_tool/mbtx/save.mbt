///|
/// Save without clobbering user edits, using the same canonical containment
/// checks as file tools and exclusive creation to reject a racing file.
async fn save_script(
  workspace_root : String,
  filename : String,
  source : String,
  read_only~ : Bool,
  file_state~ : @agent_tool.FileStateMap,
  write_scope? : @write_scope.WriteScope,
) -> Unit {
  guard !read_only else {
    fail(
      "this read-only tool cannot save scripts. Run an existing filename without source, or use source alone",
    )
  }
  let path = resolve_filename(workspace_root, filename, None)
  let scope = match @write_scope.WriteScope::create(root=workspace_root) {
    Ok(scope) => scope
    Err(reason) => fail(reason)
  }
  async fn check_scope() {
    if scope.deny_reason(path) is Some(reason) {
      fail("save blocked: \{reason}")
    }
    if write_scope is Some(worker) && worker.deny_reason(path) is Some(reason) {
      fail("save blocked: \{reason}")
    }
  }
  check_scope()
  if @fs.exists(path) {
    let existing = @fs.read_file(path).text()
    guard existing == source else {
      fail(
        "\{filename} already exists with different content; nothing was overwritten or run. Use the edit tool to change it, choose a new filename, or omit source to run the existing file",
      )
    }
    return
  }
  if @workspace_path.parent_dir(path) is Some(parent) && !@fs.exists(parent) {
    @fs.mkdir(parent, recursive=true)
  }
  check_scope()
  @fs.write_file(path, source, create_mode=CreateNew)
  file_state.record_created(path, @agent_tool.content_digest(source))
}

///|
async fn check_builtin_containment(path : String, references : String) -> Unit {
  let scope = match
    @write_scope.WriteScope::create(
      root=@workspace_path.resolve(references, "workflow"),
    ) {
    Ok(scope) => scope
    Err(reason) => fail("bundled workflows unavailable: \{reason}")
  }
  if scope.deny_reason(path) is Some(reason) {
    fail("bundled script must remain inside @builtin/: \{reason}")
  }
}
