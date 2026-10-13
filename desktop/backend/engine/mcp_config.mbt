// The MCP server configuration a conversation's engine runs with: one
// user-level file beside the global session store, in the de-facto
// `{"mcpServers": {...}}` shape the engine's `--mcp-config` decodes.
//
// The host points every engine it starts at the file and never interprets
// it — the engine connects the servers and reports what it could not use.
// An engine connects them once, when it starts, so the host also reads the
// file before each prompt and keeps a digest of it in the engine
// fingerprint: an edit starts a new engine on the next prompt.
//
// Host and engine each read the file, a moment apart. An edit that lands
// between the two leaves the engine running newer content than the digest
// the host recorded; the next prompt sees a different digest and starts one
// more engine than was needed. Only an edit that is also undone inside that
// moment goes unnoticed, until the file changes again.

///|
/// Where the desktop looks for the user's MCP server configuration, or
/// `None` when the host has no home directory to look in. The user writes
/// the file by hand; the host only reads it.
fn mcp_config_path() -> @pathx.Absolute? {
  guard @workspaces.global_store_root() is Some(root) else { return None }
  Some(root.join("mcp.json"))
}

///|
/// What the host found in the configuration file. A file that exists but
/// cannot be read is its own observation, not an absent one: the engine is
/// still pointed at it and reports the failure.
priv enum McpConfigRevision {
  /// The SHA-256 of the file's content, in hex. A run config can outlive the
  /// read, so what it keeps of the file must not grow with the file.
  Digest(String)
  ReadFailed(String)
}

///|
/// The revision of a file holding `text`.
fn McpConfigRevision::of_text(text : String) -> McpConfigRevision {
  Digest(@crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(text))))
}

///|
/// The user's MCP configuration as the host found it for one run.
priv struct McpConfig {
  path : @pathx.Absolute
  revision : McpConfigRevision
}

///|
/// Read the user's MCP configuration. An absent file is the ordinary
/// unconfigured state and names nothing, which leaves an
/// `OPENSEEK_MCP_CONFIG` inherited from the launching shell in effect exactly
/// as it is for the CLI. Called before the workspace lifecycle lock is taken,
/// never under it.
async fn resolved_mcp_config() -> McpConfig? {
  guard mcp_config_path() is Some(path) else { return None }
  let text = @fsx.read_text_if_exists(path.to_path()) catch {
    error => return Some({ path, revision: ReadFailed("\{error}"), })
  }
  guard text is Some(text) else { return None }
  Some({ path, revision: McpConfigRevision::of_text(text), })
}

///|
/// The fingerprint component for a run's MCP configuration. The tags keep a
/// read failure from ever colliding with a digest of the same text.
fn mcp_config_fingerprint(config : McpConfig?) -> String {
  guard config is Some({ path, revision, }) else { return "none" }
  match revision {
    Digest(digest) => "sha256\u{1}\{path}\u{1}\{digest}"
    ReadFailed(error) => "unreadable\u{1}\{path}\u{1}\{error}"
  }
}

///|
/// Whether an engine started with `config` and the environment `env` has an
/// MCP configuration to load: the user's file, or — when the host passes
/// none — the one an inherited `OPENSEEK_MCP_CONFIG` names. The engine reads
/// an empty variable as none, and so does this.
fn mcp_configured(config : RunConfig, env : Map[String, String]) -> Bool {
  config.mcp_config is Some(_) ||
  (env.get("OPENSEEK_MCP_CONFIG") is Some(path) && !path.is_empty())
}

///|
/// What a conversation's engine holds of its MCP servers. The host keeps no
/// connections of its own — each engine connects its servers when it starts
/// and reports what came of it, then again whenever that changes — so this is
/// the conversation's live engine's latest report, as the host kept it. A
/// conversation with no engine running has none, and an engine that has not
/// reported yet is still connecting; both are answers, not errors. Nothing is
/// started and the engine is not asked.
pub fn mcp_status(
  manager : EngineManager,
  payload : @protocol.McpStatusPayload,
) -> @protocol.McpStatusReply raise EngineError {
  guard mcp_config_path() is Some(config_path) else {
    raise EngineError(
      "there is no home directory to look for the MCP configuration in",
    )
  }
  let config_path = config_path.to_string()
  guard manager.pump is Serving(sessions~) &&
    sessions.get(payload.session) is Some(slot) &&
    slot.live() is Some(engine) else {
    return { config_path, engine: NotRunning, }
  }
  match engine.mcp_status {
    Some(status) => { config_path, engine: Running(status), }
    None => { config_path, engine: Connecting, }
  }
}

///|
async test "an absent MCP configuration names nothing; a present one is read" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous_home = @sys.get_env_var(test_home_env_name())
  defer restore_home_env(previous_home)
  let root : @pathx.Path = Path(
    @fs.realpath(@fs.tmpdir(prefix="openseek-mcp-config-")),
  )
  defer @fs.rmdir(root.to_string(), recursive=true)
  set_test_home(root.to_string())
  assert_true(resolved_mcp_config() is None)
  guard mcp_config_path() is Some(path) else {
    fail("a home directory should place the MCP configuration")
  }
  assert_eq(path.to_string(), root.join(".openseek/mcp.json").to_string())
  @fsx.ensure_dir(path.to_path().dirname())
  @fsx.write_text(path.to_path(), "{\"mcpServers\": {}}")
  guard resolved_mcp_config() is Some(empty) else {
    fail("a present file should be resolved")
  }
  assert_eq(empty.path, path)
  assert_true(empty.revision is Digest(_))
  // Only the content decides: reading the same file twice is one revision,
  // and any edit is another.
  assert_eq(
    mcp_config_fingerprint(Some(empty)),
    mcp_config_fingerprint(resolved_mcp_config()),
  )
  @fsx.write_text(path.to_path(), "{\"mcpServers\": {\"a\": {}}}")
  let edited = resolved_mcp_config()
  assert_true(
    mcp_config_fingerprint(Some(empty)) != mcp_config_fingerprint(edited),
  )
  assert_true(mcp_config_fingerprint(None) != mcp_config_fingerprint(edited))
  // What is kept is a digest, not the text: it does not grow with the file.
  assert_false(mcp_config_fingerprint(edited).contains("mcpServers"))
}

///|
async test "an unreadable MCP configuration is carried, not treated as absent" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous_home = @sys.get_env_var(test_home_env_name())
  defer restore_home_env(previous_home)
  let root : @pathx.Path = Path(
    @fs.realpath(@fs.tmpdir(prefix="openseek-mcp-config-unreadable-")),
  )
  defer @fs.rmdir(root.to_string(), recursive=true)
  set_test_home(root.to_string())
  // A directory where the file belongs exists but can never be read as one,
  // on every platform and regardless of the user's permissions.
  @fsx.ensure_dir(root.join(".openseek/mcp.json"))
  guard resolved_mcp_config() is Some(config) else {
    fail("a configuration that exists but cannot be read must not be dropped")
  }
  assert_true(config.revision is ReadFailed(_))
  assert_true(
    mcp_config_fingerprint(Some(config)) !=
    mcp_config_fingerprint(
      Some({ ..config, revision: McpConfigRevision::of_text(""), }),
    ),
  )
}

///|
#cfg(not(platform="windows"))
async test "a broken MCP configuration is reported once, not once per conversation" {
  let manager = new_engine_manager("/bin/sh")
  let emitted : Array[EngineEvent] = []
  let sink = EventSink(event => emitted.push(event))
  let source = "/home/.openseek/mcp.json"
  // What reached pages: the error of each report that was forwarded.
  fn reported() -> Array[String] {
    let errors : Array[String] = []
    for event in emitted {
      if event is StreamEvent({ event: McpConfigInvalid(error~, ..), .. }) {
        errors.push(error)
      }
    }
    errors
  }

  fn finished(session : String) -> Bool {
    emitted.any(event => {
      event is StreamEvent({ event: McpConnectFailed(server~, ..), .. }) &&
      server == session
    })
  }

  @async.with_task_group(group => {
    // Stands in for a serve engine pointed at the user's configuration. With
    // an error to report it says it could not decode the file; with none it
    // says the configuration loaded. Then it says one more thing, so the
    // test knows it has been heard.
    async fn start(session : String, error : String?) -> Unit {
      let script =
        #|if [ -n "$2" ]; then
        #|  printf '{"event":"mcp_config_invalid","path":"%s","error":"%s"}\n' "$3" "$2"
        #|else
        #|  printf '{"event":"mcp_tools_registered","servers":0,"tools":0,"names":[]}\n'
        #|fi
        #|printf '{"event":"mcp_connect_failed","server":"%s","error":"marker"}\n' "$1"
        #|cat >/dev/null
      let (child_stdin, writer) = @process.write_to_process()
      let (reader, child_stdout) = @process.read_from_process()
      let process = @process.spawn(
        group,
        "/bin/sh",
        ["-c", script, "sh", session, error.unwrap_or(""), source],
        stdin=child_stdin,
        stdout=child_stdout,
        no_wait=true,
      )
      let engine = test_serve_engine(
        session,
        writer,
        process,
        sink,
        phase=Idle(last_run=None),
      )
      group.spawn_bg(no_wait=true, allow_failure=true, () => {
        ignore(engine.consume(manager, reader))
      })
      @async.with_timeout(10000, () => {
        while !finished(session) {
          @async.sleep(20)
        }
      })
    }

    // Two conversations start engines on the same broken file. A person
    // hears it once.
    start("s-1", Some("bad"))
    @debug.assert_eq(reported(), ["bad"])
    start("s-2", Some("bad"))
    @debug.assert_eq(reported(), ["bad"])
    // A different error is a new thing to say.
    start("s-3", Some("worse"))
    @debug.assert_eq(reported(), ["bad", "worse"])
    start("s-4", Some("worse"))
    @debug.assert_eq(reported(), ["bad", "worse"])
    // Once a configuration has loaded, the same mistake made again is news.
    start("s-5", None)
    assert_true(manager.mcp_error is None)
    start("s-6", Some("worse"))
    @debug.assert_eq(reported(), ["bad", "worse", "worse"])
  })
}

///|
test "an inherited MCP configuration counts as one the engine will load" {
  let config = pump_test_config("s-configured")
  let mcp : McpConfig = {
    path: @pathx.Path("/home/.openseek/mcp.json").resolve(),
    revision: McpConfigRevision::of_text("{}"),
  }
  // The user's file, whatever the environment says.
  assert_true(mcp_configured({ ..config, mcp_config: Some(mcp), }, {}))
  // No file: the engine falls back to what its environment names, and a
  // broken file there is reported like any other — so it must not look like
  // there is nothing to go wrong.
  assert_true(
    mcp_configured(config, { "OPENSEEK_MCP_CONFIG": "/tmp/mcp.json" }),
  )
  // Neither, or the variable set to nothing, which is how MCP is turned off.
  assert_false(mcp_configured(config, {}))
  assert_false(mcp_configured(config, { "OPENSEEK_MCP_CONFIG": "" }))
}

///|
async test "MCP status has nothing to report when the conversation has no engine" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous_home = @sys.get_env_var(test_home_env_name())
  defer restore_home_env(previous_home)
  let root : @pathx.Path = Path(
    @fs.realpath(@fs.tmpdir(prefix="openseek-mcp-status-")),
  )
  defer @fs.rmdir(root.to_string(), recursive=true)
  set_test_home(root.to_string())
  let manager = new_engine_manager("unused")
  // The host is not serving at all, then serving but not this conversation.
  let reply = mcp_status(manager, { session: "s-idle", })
  assert_true(reply.engine is NotRunning)
  assert_eq(reply.config_path, root.join(".openseek/mcp.json").to_string())
  manager.pump = Serving(sessions=Map([]))
  assert_true(mcp_status(manager, { session: "s-idle", }).engine is NotRunning)
}

///|
#cfg(not(platform="windows"))
async test "MCP status is the live engine's latest report" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous_home = @sys.get_env_var("HOME")
  defer restore_home_env(previous_home)
  let root = @fs.realpath(@fs.tmpdir(prefix="openseek-mcp-status-engine-"))
  defer @fs.rmdir(root, recursive=true)
  @sys.set_env_var("HOME", root)
  let manager = new_engine_manager("/bin/sh")
  let emitted : Array[EngineEvent] = []
  let sink = EventSink(event => emitted.push(event))
  // Stands in for a serve engine: reports its one server connected, then
  // lost a moment later, as the real one does when a server exits. Nothing
  // is ever written to it.
  let script =
    #|printf '{"event":"mcp_status","status":{"config":"loaded","path":"/p/mcp.json","servers":[{"name":"a","transport":"stdio","target":"a","state":"connected","tools":[{"name":"mcp__a__ping","description":"ping"}]}]}}\n'
    #|sleep 0.3
    #|printf '{"event":"mcp_status","status":{"config":"loaded","path":"/p/mcp.json","servers":[{"name":"a","transport":"stdio","target":"a","state":"lost","tools":[{"name":"mcp__a__ping","description":"ping"}]}]}}\n'
    #|cat >/dev/null
  @async.with_task_group(group => {
    let (child_stdin, writer) = @process.write_to_process()
    let (reader, child_stdout) = @process.read_from_process()
    let process = @process.spawn(
      group,
      "/bin/sh",
      ["-c", script],
      stdin=child_stdin,
      stdout=child_stdout,
      no_wait=true,
    )
    let engine = test_serve_engine(
      "s-live",
      writer,
      process,
      sink,
      phase=Idle(last_run=None),
    )
    let sessions : Map[String, SessionSlot] = Map([])
    slot_for(sessions, "s-live").engine = Some(engine)
    manager.pump = Serving(sessions~)
    // Nothing of the engine's output has been read yet: it is running and
    // has not reported, which is neither stopped nor an empty configuration.
    assert_true(
      mcp_status(manager, { session: "s-live", }).engine is Connecting,
    )
    let stderr_task = group.spawn(no_wait=true, () => "")
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      engine.run(manager, reader, stderr_task)
    })
    fn server_state() -> @wire.McpServerState? raise EngineError {
      match mcp_status(manager, { session: "s-live", }).engine {
        Running(Configured(path="/p/mcp.json", servers=[server])) =>
          Some(server.state)
        _ => None
      }
    }

    // Each report replaces the last, so the reply ends on the newest one.
    @async.with_timeout(10000, () => {
      while !(server_state() is Some(Lost(_))) {
        @async.sleep(20)
      }
    })
    // Both reports also went out to pages, in order: that is what tells a
    // page already showing the status to read it again.
    let reported : Array[@wire.McpServerState] = []
    for event in emitted {
      if event
        is StreamEvent(
          {
            session: "s-live",
            event: McpStatus(status=Configured(servers=[server], ..)),
            ..
          }
        ) {
        reported.push(server.state)
      }
    }
    assert_true(reported is [Connected(_), Lost(_)])
    // Another conversation is not answered by this one's engine.
    assert_true(
      mcp_status(manager, { session: "s-other", }).engine is NotRunning,
    )
  })
}
