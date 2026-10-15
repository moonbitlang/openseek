// User MCP configuration lives beside the global session store, in the de-facto
// `{"mcpServers": {...}}` shape the engine's `--mcp-config` decodes.
//
// The host points every engine it starts at the file and never interprets
// it — the engine connects the servers and reports what it could not use.
// Hosts with tools also supply a generated default config before the user file.
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
/// Host MCP state shared by the engines managed by this Desktop host.
priv struct McpState {
  // Engines receive access to this server through their environment.
  server : @mcp.Server?
  // The latest launch owns error reporting even if it exits before loading
  // MCP; older engines never take ownership back.
  mut current_engine_id : String?
  // Errors already forwarded to pages, keyed by source file. Successful
  // configuration loading forgets repaired files without repeating failures.
  mut errors : Map[String, String]
}

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
async test "MCP configs reuse valid host defaults and report broken files once" {
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
    let runtime = @pathx.Path(@fs.tmpdir(prefix="openseek-host-config-reuse-"))
    group.add_defer(() => {
      @async.protect_from_cancel(() => {
        @fs.chmod(runtime.to_string(), 0o700)
        @fs.rmdir(runtime.to_string(), recursive=true)
      })
    })
    let args = engine_mcp_args(None, Some(runtime), {}, host_mcp=true)
    let host_path = runtime.join("host-mcp.json")
    let template = @fsx.read_text(host_path)
    // A valid default remains usable when its directory becomes read-only.
    @fs.chmod(runtime.to_string(), 0o500)
    assert_eq(engine_mcp_args(None, Some(runtime), {}, host_mcp=true), args)
    @fs.chmod(runtime.to_string(), 0o700)
    // A changed template is still regenerated when writing is possible.
    @fsx.write_text(host_path, "stale configuration")
    assert_eq(engine_mcp_args(None, Some(runtime), {}, host_mcp=true), args)
    assert_eq(@fsx.read_text(host_path), template)
    // Stands in for a serve engine pointed at the user's configuration. With
    // an error to report it says it could not decode the file; with none it
    // says the configuration loaded. Then it says one more thing, so the
    // test knows it has been heard.
    async fn launch(
      session : String,
      error : String?,
      second_error : String,
      delayed : Bool,
    ) -> ServeEngine {
      let script =
        #|if [ -n "$2" ]; then
        #|  printf '{"event":"mcp_config_invalid","path":"%s","error":"%s"}\n' "$3" "$2"
        #|fi
        #|if [ -n "$4" ]; then
        #|  printf '{"event":"mcp_config_invalid","path":"%s.other","error":"%s"}\n' "$3" "$4"
        #|fi
        #|if [ "$5" = "true" ]; then
        #|  printf '{"event":"mcp_connect_failed","server":"%s-paused","error":"marker"}\n' "$1"
        #|  read -r resume
        #|  printf '{"event":"mcp_config_invalid","path":"%s.late","error":"late"}\n' "$3"
        #|fi
        #|printf '{"event":"mcp_tools_registered","servers":1,"tools":0,"names":[]}\n'
        #|printf '{"event":"mcp_connect_failed","server":"%s","error":"marker"}\n' "$1"
        #|cat >/dev/null
      let (child_stdin, writer) = @process.write_to_process()
      let (reader, child_stdout) = @process.read_from_process()
      let process = @process.spawn(
        group,
        "/bin/sh",
        [
          "-c",
          script,
          "sh",
          session,
          error.unwrap_or(""),
          source,
          second_error,
          delayed.to_string(),
        ],
        stdin=child_stdin,
        stdout=child_stdout,
        no_wait=true,
      )
      let engine_id = @uuid.mint()
      manager.mcp.current_engine_id = Some(engine_id)
      let engine = test_serve_engine(
        session,
        writer,
        process,
        sink,
        phase=Idle(last_run=None),
        id=engine_id,
      )
      group.spawn_bg(no_wait=true, allow_failure=true, () => {
        ignore(engine.consume(manager, reader))
      })
      @async.with_timeout(10000, () => {
        while !finished(if delayed { "\{session}-paused" } else { session }) {
          @async.sleep(20)
        }
      })
      engine
    }

    async fn start(
      session : String,
      error : String?,
      second_error : String,
    ) -> Unit {
      ignore(launch(session, error, second_error, false))
    }

    // Two conversations start engines on the same broken file. A person
    // hears it once.
    start("s-1", Some("bad"), "")
    @debug.assert_eq(reported(), ["bad"])
    start("s-2", Some("bad"), "")
    @debug.assert_eq(reported(), ["bad"])
    // A different error is a new thing to say.
    start("s-3", Some("worse"), "")
    @debug.assert_eq(reported(), ["bad", "worse"])
    start("s-4", Some("worse"), "")
    @debug.assert_eq(reported(), ["bad", "worse"])
    // Once a configuration has loaded, the same mistake made again is news.
    start("s-5", None, "")
    assert_true(manager.mcp.errors.is_empty())
    start("s-6", Some("worse"), "")
    @debug.assert_eq(reported(), ["bad", "worse", "worse"])
    // Two files can fail with identical text; each gets one report even when
    // other files registered successfully. Repairing one forgets only it.
    start("s-7", Some("worse"), "worse")
    start("s-8", Some("worse"), "worse")
    @debug.assert_eq(reported(), ["bad", "worse", "worse", "worse"])
    start("s-9", Some("worse"), "")
    start("s-10", Some("worse"), "worse")
    @debug.assert_eq(reported(), ["bad", "worse", "worse", "worse", "worse"])
    // An older engine has read the broken file but is still connecting when
    // a newer launch loads the repair. Its late errors and registration must
    // neither notify again nor restore its obsolete error snapshot.
    let older = launch("s-old", Some("worse"), "worse", true)
    start("s-repaired", None, "")
    assert_true(manager.mcp.errors.is_empty())
    older.writer.write("resume\n")
    @async.with_timeout(10000, () => {
      while !finished("s-old") {
        @async.sleep(20)
      }
    })
    assert_true(manager.mcp.errors.is_empty())
    @debug.assert_eq(reported(), ["bad", "worse", "worse", "worse", "worse"])
    start("s-regressed", Some("worse"), "")
    @debug.assert_eq(reported(), [
      "bad", "worse", "worse", "worse", "worse", "worse",
    ])
    // A new launch immediately takes ownership, even if it then exits
    // without any MCP events. Late reports cannot revive the old owner.
    let reporter = launch("s-reporter", None, "", true)
    manager.mcp.current_engine_id = Some(@uuid.mint())
    reporter.writer.write("resume\n")
    @async.with_timeout(10000, () => {
      while !finished("s-reporter") {
        @async.sleep(20)
      }
    })
    assert_eq(manager.mcp.errors.get(source), Some("worse"))
    assert_eq(manager.mcp.errors.get("\{source}.late"), None)
    @debug.assert_eq(reported(), [
      "bad", "worse", "worse", "worse", "worse", "worse",
    ])
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
/// Put the host defaults before the user's configuration. Once an explicit
/// host path is passed, argparse no longer reads OPENSEEK_MCP_CONFIG, so carry
/// that fallback explicitly when the user's usual file is absent.
async fn engine_mcp_args(
  config : McpConfig?,
  runtime_dir : @pathx.Path?,
  env : Map[String, String],
  host_mcp~ : Bool,
) -> Array[String] {
  let args : Array[String] = []
  if host_mcp {
    let directory = match runtime_dir {
      Some(directory) => directory
      None => {
        guard @workspaces.global_store_root() is Some(root) else {
          raise EngineError(
            "Host MCP configuration needs a runtime or home directory",
          )
        }
        root.to_path()
      }
    }
    let path = directory.join("host-mcp.json").resolve()
    // Only placeholders are persisted. Grants remain conversation-specific
    // environment variables, including when two hosts share a runtime directory.
    let text =
      #|{"mcpServers":{"seekmoon":{"url":"${OPENSEEK_DESKTOP_TOOLS_URL}","headers":{"Authorization":"Bearer ${OPENSEEK_DESKTOP_TOOLS_TOKEN}"}}}}
    if @fsx.read_text_if_exists(path.to_path()) != Some(text) {
      @fsx.ensure_dir(path.to_path().dirname())
      @fsx.write_text_atomic(path.to_path(), text)
    }
    args.push("--mcp-config=\{path.to_string()}")
  }
  if config is Some(mcp) {
    args.push("--mcp-config=\{mcp.path.to_string()}")
  } else if host_mcp &&
    env.get("OPENSEEK_MCP_CONFIG") is Some(path) &&
    !path.is_empty() {
    args.push("--mcp-config=\{path}")
  }
  args
}
