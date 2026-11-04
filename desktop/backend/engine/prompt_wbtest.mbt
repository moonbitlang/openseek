///|
async test "creation prompts survive retries and cannot be overwritten on resume" {
  let dir = @fs.realpath(@fs.tmpdir(prefix="openseek-prompt-capture-"))
  defer @fs.rmdir(dir, recursive=true)
  let root = @pathx.Path(dir).resolve()
  let store = @store.SessionStore(dir)
  for i, text in ["", "  Custom instructions\n中文\n"] {
    let session = "s-\{i}"
    let id = @agent_session.SessionId(session)
    let config = {
      ..pump_test_config(session),
      session_root: Some(root),
      system_prompt: Some(text),
    }
    let path = session_prompt_path(store, id)
    let flag = "--system-prompt-file=\{path.to_string()}"
    assert_true(engine_process_args(config).contains(flag))
    for incoming in [Some("changed page preference"), None] {
      let args = engine_process_args({ ..config, system_prompt: incoming, })
      assert_true(args.contains(flag))
      assert_eq(saved_session_prompt(store, id), Some(text))
    }
    store.create(Session(id, system_prompt="durable runtime prompt"))
    let resumed = engine_process_args({
      ..config,
      system_prompt: Some("changed after reopening"),
    })
    assert_false(resumed.contains(flag))
    assert_eq(saved_session_prompt(store, id), Some(text))
    assert_eq(store.load(id).system_prompt(), "durable runtime prompt")
  }
  let legacy = @agent_session.SessionId("legacy")
  store.create(Session(legacy, system_prompt="legacy prompt"))
  assert_true(
    capture_session_prompt(store, legacy, Some("new default")) is None,
  )
  assert_true(saved_session_prompt(store, legacy) is None)
  assert_true(capture_session_prompt(store, SessionId("absent"), None) is None)
  assert_false(store.exists(SessionId("absent")))
}
