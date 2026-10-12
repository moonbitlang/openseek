///|
/// A manager whose host offers tools, with the directory its engine configs
/// are written to.
async fn mcp_test_manager() -> (EngineManager, @pathx.Path) {
  let dir = @pathx.Path(@fs.tmpdir(prefix="openseek-engine-mcp-"))
  let server = @mcp.Server([], version="test", config_dir=dir)
  (new_engine_manager("unused", mcp=server), dir)
}

///|
/// The `mcpServers` names in the config at `path`.
async fn configured_servers(path : @pathx.Path) -> Array[String] {
  guard @json.parse(@fsx.read_text(path))
    is { "mcpServers": Object(servers), .. } else {
    fail("no MCP config at \{path}")
  }
  servers.keys().to_array()
}

///|
async test "an engine without host tools is left on the config it inherits" {
  let manager = new_engine_manager("unused")
  let config = { ..pump_test_config("s-plain"), session_root: None, }
  let env = { "OPENSEEK_MCP_CONFIG": "/home/user/mcp.json" }
  assert_true(engine_mcp_config(manager, config, env) is None)
  @debug.assert_eq(engine_process_args(config), [
    "serve", "--session=s-plain", "--dir", ".", "--approval", "ask",
  ])
}

///|
async test "an engine with host tools starts on a config naming the host server" {
  let (manager, dir) = mcp_test_manager()
  defer (@fs.rmdir(dir.to_string(), recursive=true) catch { _ => () })
  let config = { ..pump_test_config("s-tools"), session_root: None, }
  guard engine_mcp_config(manager, config, {}) is Some(path) else {
    fail("the host server was not configured")
  }
  assert_eq(path.to_string(), dir.join("s-tools.json").to_string())
  assert_eq(configured_servers(path), ["seekmoon"])
  @debug.assert_eq(engine_process_args(config, mcp_config=path), [
    "serve",
    "--session=s-tools",
    "--mcp-config=\{path.to_string()}",
    "--dir",
    ".",
    "--approval",
    "ask",
  ])
}

///|
async test "the host server is added to the config the engine would have inherited" {
  let (manager, dir) = mcp_test_manager()
  defer (@fs.rmdir(dir.to_string(), recursive=true) catch { _ => () })
  let workspace = @pathx.Path(@fs.tmpdir(prefix="openseek-engine-mcp-cwd-"))
  defer (@fs.rmdir(workspace.to_string(), recursive=true) catch { _ => () })
  @fsx.write_text(
    workspace.join("mcp.json"),
    ({ "mcpServers": { "codex": { "command": "codex" } } } : Json).stringify(),
  )
  let config = { ..pump_test_config("s-merge"), cwd: Some(workspace), }
  // Absolute, and relative to the engine's working directory: the two ways
  // the engine itself would have found the file.
  for value in [workspace.join("mcp.json").to_string(), "mcp.json"] {
    guard engine_mcp_config(manager, config, { "OPENSEEK_MCP_CONFIG": value })
      is Some(path) else {
      fail("the host server was not configured")
    }
    assert_eq(configured_servers(path), ["codex", "seekmoon"])
  }
  // Empty is the engine's "no config", not a path.
  guard engine_mcp_config(manager, config, { "OPENSEEK_MCP_CONFIG": "" })
    is Some(path) else {
    fail("the host server was not configured")
  }
  assert_eq(configured_servers(path), ["seekmoon"])
}

///|
async test "a session id that is not a path component gets no config file" {
  let (manager, dir) = mcp_test_manager()
  defer (@fs.rmdir(dir.to_string(), recursive=true) catch { _ => () })
  let refused = try
    engine_mcp_config(manager, pump_test_config("../escape"), {})
  catch {
    EngineError(message) => Some(message)
    error => raise error
  } noraise {
    _ => None
  }
  assert_eq(refused, Some("session id must be a single path component"))
  assert_false(@fsx.exists(dir.dirname().join("escape.json")))
}
