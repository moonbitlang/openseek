///|
/// Save without clobbering user edits, using the same canonical containment
/// checks as file tools and exclusive creation to reject a racing file.
/// Returns the resolved path the script lives at.
async fn save_script(
  workspace_root : String,
  filename : String,
  source : String,
  read_only~ : Bool,
  file_state~ : @agent_tool.FileStateMap,
  write_scope? : @write_scope.WriteScope,
  scratch_dir? : String,
) -> String {
  guard !read_only else {
    fail(
      "this read-only tool cannot save scripts. Run an existing filename without source, or use source alone",
    )
  }
  let path = @workspace_path.resolve(workspace_root, filename)
  async fn scope_at(root : String) -> @write_scope.WriteScope {
    match @write_scope.WriteScope::create(root~) {
      Ok(scope) => scope
      Err(reason) => fail(reason)
    }
  }
  let scope = scope_at(workspace_root)
  let scratch_scope = match scratch_dir {
    Some(root) => Some(scope_at(root))
    None => None
  }
  async fn check_scope() {
    if scope.deny_reason(path) is Some(reason) &&
      !(scratch_scope is Some(scratch) && scratch.deny_reason(path) is None) {
      fail("save blocked: \{reason}")
    }
    if write_scope is Some(worker) && worker.deny_reason(path) is Some(reason) {
      fail("save blocked: \{reason}")
    }
  }
  check_scope()
  let existing = try @fs.read_file(path).text() catch {
    @os_error.OSError(_) as error if error.is_ENOENT() => None
    error => raise error
  } noraise {
    existing => Some(existing)
  }
  if existing is Some(existing) {
    guard existing == source else {
      fail(
        "\{filename} already exists with different content; nothing was overwritten or run. Use the edit tool to change it, choose a new filename, or omit source to run the existing file",
      )
    }
    return path
  }
  file_state.create_parent_directories(path)
  check_scope()
  @fs.write_file(path, source, create_mode=CreateNew)
  file_state.record_created(path, @agent_tool.content_digest(source))
  path
}
