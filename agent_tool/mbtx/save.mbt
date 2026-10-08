///|
/// Save without clobbering user edits, using the same canonical containment
/// checks as file tools and exclusive creation to reject a racing file.
async fn save_script(
  workspace_root : String,
  filename : String,
  source : String,
  read_only~ : Bool,
  file_state~ : @agent_tool.FileStateMap,
  session_dir? : String,
  write_scope? : @write_scope.WriteScope,
) -> Unit {
  guard !read_only else {
    fail(
      "this read-only tool cannot save scripts. Run an existing filename without source, or use source alone",
    )
  }
  let path = resolve_filename(workspace_root, filename, session_dir?)
  let root = if @tool_path.is_session(filename) && session_dir is Some(session) {
    session
  } else {
    workspace_root
  }
  let write_scope = @tool_path.scope(workspace_root, write_scope, session_dir)
  let scope = match @write_scope.WriteScope::create(root~) {
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
  file_state.create_parent_directories(path)
  check_scope()
  @fs.write_file(path, source, create_mode=CreateNew)
  file_state.record_created(path, @agent_tool.content_digest(source))
}
