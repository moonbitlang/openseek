///|
async test "--continue resolves the most recently active session" {
  let root = @fs.tmpdir(prefix="openseek-tui-continue-")
  let store = @store.SessionStore(root)
  store.create(Session(SessionId("older"), system_prompt="system"))
  // Filesystem mtimes need a beat between writes to order reliably.
  @async.sleep(50)
  store.create(Session(SessionId("newer"), system_prompt="system"))
  let parsed = cli_command().parse(
    argv=["--continue", "--session-root", root],
    env={ "DEEPSEEK": "test-key" },
  )
  let config = with_latest_session(parse_config(parsed))
  assert_eq(config.session_id.value(), "newer")
  // An empty store keeps the generated fresh session: nothing to continue,
  // so the TUI starts a new conversation instead of refusing to launch.
  let empty_root = @fs.tmpdir(prefix="openseek-tui-continue-empty-")
  let parsed = cli_command().parse(
    argv=["--continue", "--session-root", empty_root],
    env={ "DEEPSEEK": "test-key" },
  )
  let fresh = with_latest_session(parse_config(parsed))
  assert_true(fresh.session_id.value().has_prefix("tui-"))
  @fs.rmdir(root, recursive=true)
  @fs.rmdir(empty_root, recursive=true)
}
