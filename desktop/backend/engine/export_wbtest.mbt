///|
async test "remote export shares its record budget across direct subruns" {
  let root = @pathx.Path(@fs.tmpdir(prefix="bounded-export-")).resolve()
  defer @fs.rmdir(root.to_string(), recursive=true)
  for id in ["parent", "parent-sr-1", "parent-sr-1-sr-1"] {
    let path = @session_record.record_path(root, id)
    @fsx.ensure_dir(path.dirname())
    @fs.write_file(path.to_string(), "中文")
  }
  let request : SessionExport = {
    manager: new_engine_manager("unused"),
    session: "parent",
    workspace: root,
    root,
    title: "Remote conversation",
  }
  try {
    ignore(request.sessions(max_record_bytes=11))
    fail("each file was bounded but their sum was not")
  } catch {
    EngineError(_) => ()
    error => raise error
  }
  // Nested descendants belong to their direct parent, so only two records
  // consume this export's budget. The refused attempt releases its read claim.
  assert_eq(request.sessions(max_record_bytes=12).length(), 2)
  assert_eq(request.sessions().length(), 2)
}
