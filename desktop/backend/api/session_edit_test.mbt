///|
#cfg(not(platform="windows"))
async test "session.edit returns a structured refusal instead of raising" {
  home_env_test_lock.acquire()
  defer home_env_test_lock.release()
  let root = @pathx.Path(
    @fs.realpath(@fs.tmpdir(prefix="seekmoon-session-edit-api-")),
  ).resolve()
  defer @fs.remove(root.to_string(), recursive=true)
  let previous = @sys.get_env_var("HOME")
  @sys.set_env_var("HOME", root.to_string())
  defer (match previous {
    Some(value) => @sys.set_env_var("HOME", value)
    None => @sys.unset_env_var("HOME")
  })
  let workspace = root.join("project")
  @fs.mkdir(workspace.to_string())
  ignore(@workspaces.add(workspace.to_string(), _ => ()))
  let workspace_path = workspace.resource_path()
  let state = @api.ApiState(engine="unused")
  let base : @protocol.SessionEditPayload = {
    session: "s-source",
    workspace: workspace_path,
    through: None,
    model: "deepseek-flash",
    source_title: "Source",
    source_sequence: 1,
    task: "edited",
    images: [],
    attachment_paths: [],
    thinking: None,
    approval: None,
    max_steps: None,
  }

  // EngineError: invalid source sequence returns EditError in JSON.
  let invalid_reply : @protocol.SessionEditReply = @json.from_json(
    invoke_shared(
      state,
      "session.edit",
      ({ ..base, source_sequence: 0, } : @protocol.SessionEditPayload).to_json(),
    ),
  )
  assert_eq(invalid_reply, EditError("invalid edited message"))

  // StoreError: unregistered workspace returns EditError in JSON.
  let unregistered_reply : @protocol.SessionEditReply = @json.from_json(
    invoke_shared(
      state,
      "session.edit",
      (
        { ..base, workspace: root.join("missing").resource_path(), } :
        @protocol.SessionEditPayload).to_json(),
    ),
  )
  assert_true(unregistered_reply is EditError(_))

  // FilesError: attachment staging failures travel in EditError too.
  let source_dir = workspace.join(".openseek/sessions/s-source")
  @fs.mkdir(source_dir.to_string(), recursive=true)
  @fs.write_text(
    source_dir.join("openseek_session-s-source.jsonl").to_string(),
    "{\"version\":1,\"id\":\"s-source\",\"system_prompt\":\"\"}\n{\"sequence\":1,\"ts\":0,\"item\":{\"kind\":\"user\",\"payload\":{\"content\":\"hello\"}}}\n",
  )
  let attachment_reply : @protocol.SessionEditReply = @json.from_json(
    invoke_shared(
      state,
      "session.edit",
      (
        { ..base, attachment_paths: [".openseek/attachments/bad/escape.txt"], } :
        @protocol.SessionEditPayload).to_json(),
    ),
  )
  assert_eq(
    attachment_reply,
    EditError("only imported workspace attachments can be staged"),
  )
}
