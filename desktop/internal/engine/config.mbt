// Turning a `start` payload into the validated configuration a serve engine
// is spawned with.

///|
const DefaultModel = "deepseek-v4-pro"

///|
const DefaultMaxSteps = 1000

///|
/// Sent as the API key when an OpenSeek or custom endpoint has no stored key:
/// the engine refuses to start with an empty key, so this preserves the request
/// shape when no user credential is available.
const PlaceholderApiKey = "unused"

///|
priv struct RunConfig {
  task : String
  api_key : String
  // Custom chat-completions endpoint; None means the engine's built-in
  // default (the official DeepSeek endpoint).
  api_url : String?
  model : String
  max_steps : Int
  engine : String
  cwd : @pathx.Path?
  session : String
  session_root : @pathx.Absolute?
}

///|
fn configured_api_key(
  stored_key? : String,
  api_url? : String,
  deepseek_env? : String,
) -> String raise EngineError {
  if stored_key is Some(value) {
    return value
  }
  if api_url is Some(_) {
    return PlaceholderApiKey
  }
  if deepseek_env is Some(value) {
    return value
  }
  raise EngineError(
    "DeepSeek API key is required; add it in Settings or set DEEPSEEK",
  )
}

///|
fn configured_max_steps(value : Int?) -> Int raise EngineError {
  let parsed = if value is Some(value) {
    value
  } else if @env.get("OPENSEEK_MAX_STEPS") is Some(text) {
    @string.parse_int(text) catch {
      _ => raise EngineError("OPENSEEK_MAX_STEPS must be a positive integer")
    }
  } else {
    DefaultMaxSteps
  }
  guard parsed > 0 else {
    raise EngineError("max_steps must be a positive integer")
  }
  parsed
}

///|
async fn run_config(
  manager : EngineManager,
  payload : @protocol.StartPayload,
) -> RunConfig {
  let task = payload.task.trim().to_owned()
  guard !task.is_empty() else { raise EngineError("task must not be empty") }
  let session = payload.session.trim().to_owned()
  guard !session.is_empty() else {
    raise EngineError("session id must not be empty")
  }
  serve_config(
    task,
    manager,
    model?=payload.model,
    max_steps?=payload.max_steps,
    session~,
    workspace?=payload.workspace,
  )
}

///|
/// The config a compaction spawns an engine with when its conversation has
/// none live (resumed after a restart, or the process died between turns):
/// the same settings a start carries, pinned to the compacted session. The
/// blank task is never sent — `compact_run` writes only the compact command,
/// and the fingerprint deliberately excludes the task.
async fn compact_config(
  manager : EngineManager,
  payload : @protocol.CompactPayload,
) -> RunConfig {
  session_command_config(
    manager,
    payload.session,
    model?=payload.model,
    max_steps?=payload.max_steps,
    workspace?=payload.workspace,
  )
}

///|
/// The config a goal update spawns an engine with when its conversation has
/// none live — the same taskless shape as `compact_config`, pinned to the
/// goal's session.
async fn goal_config(
  manager : EngineManager,
  payload : @protocol.GoalPayload,
) -> RunConfig {
  session_command_config(
    manager,
    payload.session,
    model?=payload.model,
    max_steps?=payload.max_steps,
    workspace?=payload.workspace,
  )
}

///|
async fn session_command_config(
  manager : EngineManager,
  session : String,
  model? : String,
  max_steps? : Int,
  workspace? : String,
) -> RunConfig {
  let session = session.trim().to_owned()
  guard !session.is_empty() else {
    raise EngineError("session id must not be empty")
  }
  serve_config("", manager, model?, max_steps?, session~, workspace?)
}

///|
/// The validated configuration shared by every op that can spawn a serve
/// engine. The endpoint (provider, key, URL) comes from the host-owned
/// settings store, never from the request — a client carries no credentials
/// (docs/remote-protocol.md).
async fn serve_config(
  task : String,
  manager : EngineManager,
  model? : String,
  max_steps? : Int,
  session~ : String,
  workspace? : String,
) -> RunConfig {
  let engine = manager.engine
  let (settings, _) = manager.settings_snapshot()
  let endpoint = resolved_endpoint(settings)
  // A workspace run happens in the project directory itself, with the
  // session's durable record in the in-project store. Only registered
  // workspaces qualify — the registry, not the payload, decides which
  // directories a run may work in.
  let workspace : @pathx.Absolute? = if workspace is Some(path) {
    guard @pathx.Absolute::from_uri_path(path) is Some(absolute) else {
      raise EngineError("workspace is not a supported absolute resource path")
    }
    match @workspaces.registered_dir(absolute) {
      Some(dir) => Some(dir)
      None => raise EngineError("\{path} is not a registered workspace")
    }
  } else {
    None
  }
  {
    task,
    api_key: endpoint.api_key,
    api_url: endpoint.api_url,
    model: match model {
      Some(model) => model
      // The engine takes its model from OPENSEEK_MODEL (DEEPSEEK_MODEL is
      // deliberately ignored — see `serve_engine_env`), so the host's
      // fallback must read the same variable.
      None => @env.get("OPENSEEK_MODEL").unwrap_or(DefaultModel)
    },
    max_steps: configured_max_steps(max_steps),
    engine,
    cwd: if workspace is Some(dir) {
      // The workspace hint names the project; a session already bound to one
      // of its worktrees keeps working in that checkout (clients send the
      // hint on every turn, not only the binding one). A binding whose
      // checkout vanished refuses here rather than moving the agent into the
      // main tree behind the user's back.
      Some(@worktree.run_dir(dir, session).to_path())
      // A resumed project conversation recovers its registered project from
      // the durable record. Use the throwing resolver here so a retained
      // binding whose checkout vanished names that worktree instead of being
      // flattened into an unspecified missing cwd.
    } else if @session_store.workspace_of(session) is Some(dir) {
      Some(@worktree.run_dir(dir, session).to_path())
    } else {
      @work_dir.of_session(session)
    },
    session,
    session_root: if workspace is Some(dir) {
      Some(@workspaces.store_root(dir))
    } else {
      // A hint-less client resuming an existing workspace conversation must
      // keep using that workspace's store. Only genuinely new sessions fall
      // back to the global root; otherwise one id forks into two histories.
      @session_store.root_of(session)
    },
  }
}

///|
/// Everything that pins a serve process to a config: a prompt whose
/// fingerprint differs (model change, new session, …) must replace the
/// process. The task is deliberately excluded — prompts vary per turn.
fn engine_fingerprint(config : RunConfig) -> String {
  [
    config.engine,
    config.api_key,
    config.api_url.unwrap_or(""),
    config.model,
    config.max_steps.to_string(),
    config.cwd.map(cwd => cwd.to_string()).unwrap_or(""),
    config.session,
    config.session_root.map(root => root.to_string()).unwrap_or(""),
  ].join("\u{0}")
}

///|
test "a different endpoint cannot reuse a live engine process" {
  let base : RunConfig = {
    task: "t",
    api_key: "k",
    api_url: None,
    model: "deepseek-v4-pro",
    max_steps: 1000,
    engine: "openseek",
    cwd: None,
    session: "s-fingerprint",
    session_root: None,
  }
  let custom = {
    ..base,
    api_url: Some("https://proxy.example/chat/completions"),
  }
  assert_true(engine_fingerprint(base) != engine_fingerprint(custom))
  assert_eq(engine_fingerprint(base), engine_fingerprint({ ..base, task: "u" }))
  // cwd is part of the fingerprint: a session bound to a worktree can never
  // reuse a serve process rooted elsewhere (and vice versa).
  assert_true(
    engine_fingerprint(base) !=
    engine_fingerprint({ ..base, cwd: Some(Path("/w/.worktrees/x")) }),
  )
}

///|
test "configured endpoint uses its stored key or the placeholder" {
  assert_eq(
    configured_api_key(
      api_url="https://proxy.example/chat/completions",
      deepseek_env="official-key",
    ),
    PlaceholderApiKey,
  )
  assert_eq(
    configured_api_key(
      stored_key="custom-key",
      api_url="https://proxy.example/chat/completions",
      deepseek_env="official-key",
    ),
    "custom-key",
  )
}

///|
test "DeepSeek endpoint still uses DEEPSEEK env fallback" {
  assert_eq(configured_api_key(deepseek_env="official-key"), "official-key")
  let _ = configured_api_key() catch {
    EngineError(message) => {
      assert_true(message.contains("DeepSeek API key is required"))
      return
    }
  }
  fail("official endpoint accepted a missing key")
}

///|
/// The endpoint comes from the settings store, never the process
/// environment: an `OPENSEEK_API_URL` exported in the launching shell must
/// not redirect the zero-config provider away from the proxy.
async test "run config ignores OPENSEEK_API_URL in favor of the settings" {
  let previous = @sys.get_env_var("OPENSEEK_API_URL")
  @sys.set_env_var("OPENSEEK_API_URL", "https://env.example/chat/completions")
  defer (if previous is Some(value) {
    @sys.set_env_var("OPENSEEK_API_URL", value)
  } else {
    @sys.unset_env_var("OPENSEEK_API_URL")
  })
  // No settings file at all: the default provider is the OpenSeek proxy.
  let manager = new_engine_manager("openseek")
  let config = run_config(manager, {
    task: "hello",
    submission_id: None,
    model: None,
    max_steps: None,
    session: "s-default",
    workspace: None,
  })
  assert_true(config.api_url is Some(OpenseekProxyUrl))
  assert_eq(config.api_key, PlaceholderApiKey)
}

///|
async test "run config rejects a blank session" {
  let manager = new_engine_manager("openseek")
  for session in ["", "   "] {
    let detail = try {
      ignore(
        run_config(manager, {
          task: "hello",
          submission_id: None,
          model: None,
          max_steps: None,
          session,
          workspace: None,
        }),
      )
      "no error"
    } catch {
      EngineError(detail) => detail
      error if @async.is_being_cancelled() => raise error
      error => "\{error}"
    }
    assert_true(detail.contains("session id must not be empty"))
  }
}

///|
async test "host chooses durable placement from workspace state" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  // The registry canonicalizes workspace paths, so build the fixture from
  // the tmpdir's physical spelling (`/tmp` is a symlink on macOS).
  let dir = @fs.realpath(@fs.tmpdir(prefix="openseek-config-workspace-"))
  let global_root = dir + "/global"
  let workspace = dir + "/workspace"
  let workspace_resource = @pathx.Path(workspace).resolve().resource_path()
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", global_root)
  defer (if previous is Some(value) {
    @sys.set_env_var("OPENSEEK_SESSION_ROOT", value)
  } else {
    @sys.unset_env_var("OPENSEEK_SESSION_ROOT")
  })
  @fsx.ensure_dir(Path(global_root))
  @fsx.ensure_dir(Path(workspace + "/.openseek/sessions/s-workspace"))
  @fs.write_file(
    global_root + "/workspaces.json",
    ({ "workspaces": [workspace] } : Json).stringify(),
    create_mode=CreateOrTruncate,
  )
  let manager = new_engine_manager("openseek")
  let config = run_config(manager, {
    task: "resume",
    submission_id: None,
    model: None,
    max_steps: None,
    session: "s-workspace",
    workspace: None,
  })
  assert_eq(
    config.session_root.map(root => root.to_string()),
    Some(workspace + "/.openseek"),
  )
  assert_eq(config.cwd.map(cwd => cwd.to_string()), Some(workspace))
  let fresh = run_config(manager, {
    task: "fresh",
    submission_id: None,
    model: None,
    max_steps: None,
    session: "s-global",
    workspace: None,
  })
  assert_eq(fresh.session_root.map(root => root.to_string()), Some(global_root))
  let attached = run_config(manager, {
    task: "attached",
    submission_id: None,
    model: None,
    max_steps: None,
    session: "s-attached",
    workspace: Some(workspace_resource),
  })
  assert_eq(
    attached.session_root.map(root => root.to_string()),
    Some(workspace + "/.openseek"),
  )
  assert_eq(attached.cwd.map(cwd => cwd.to_string()), Some(workspace))
  @fs.rmdir(dir, recursive=true)
}
