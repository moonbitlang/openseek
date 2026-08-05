// Turning a `start` payload into the validated configuration a serve engine
// is spawned with.

///|
const DefaultModel = "deepseek-v4-pro"

///|
const DefaultMaxSteps = 1000

///|
/// Sent as the API key when a custom endpoint is configured without one: the
/// engine refuses to start with an empty key, but an endpoint like the
/// default OpenSeek proxy does not validate it.
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
  cwd : @path.Path?
  session : String?
  session_root : @path.Path?
}

///|
/// The official OpenSeek proxy; must stay a prefix of `OpenseekProxyUrl`.
/// Endpoints under it authenticate with the packaged client token instead
/// of a user API key.
const OpenseekProxyPrefix : String = "https://openseek-api.moonbitlang.cn/"

///|
/// The staging deployment's twin of `OpenseekProxyPrefix`; must stay a
/// prefix of `OpenseekStagingProxyUrl`.
const OpenseekStagingProxyPrefix : String = "https://openseek-api-staging.moonbitlang.cn/"

///|
fn configured_api_key(
  stored_key : String?,
  api_url : String?,
  deepseek_env : String?,
  client_token? : String,
) -> String raise EngineError {
  if stored_key is Some(value) {
    return value
  }
  if api_url is Some(url) {
    // Only the official proxy (and its staging twin) gets the client token;
    // any other endpoint would be handing the credential to a third-party
    // server.
    if (
        url.has_prefix(OpenseekProxyPrefix) ||
        url.has_prefix(OpenseekStagingProxyPrefix)
      ) &&
      client_token is Some(token) {
      return token
    }
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
  serve_config(
    task,
    manager,
    model?=payload.model,
    max_steps?=payload.max_steps,
    session?=payload.session.map(session => session.trim().to_owned()),
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
  let session = payload.session.trim().to_owned()
  guard !session.is_empty() else {
    raise EngineError("session id must not be empty")
  }
  serve_config(
    "",
    manager,
    model?=payload.model,
    max_steps?=payload.max_steps,
    session~,
    workspace?=payload.workspace,
  )
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
  session? : String,
  workspace? : String,
) -> RunConfig {
  let engine = manager.engine
  let (settings, _) = manager.settings_snapshot()
  let endpoint = resolved_endpoint(settings)
  // A workspace run happens in the project directory itself, with the
  // session's durable record in the in-project store. Only registered
  // workspaces qualify — the registry, not the payload, decides which
  // directories a run may work in.
  let workspace : @path.Path? = if workspace is Some(path) {
    match registered_workspace(path) {
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
      Some(dir)
    } else {
      resolved_run_cwd(session)
    },
    session,
    session_root: if workspace is Some(dir) {
      Some(workspace_session_root(dir))
    } else if session is Some(session) {
      // A hint-less client resuming an existing workspace conversation must
      // keep using that workspace's store. Only genuinely new sessions fall
      // back to the global root; otherwise one id forks into two histories.
      session_store_root(session)
    } else {
      None
    },
  }
}

///|
/// Engine working directory for a run. A named conversation gets its own
/// workspace directory derived from its durable session id (created on demand
/// by `start_run`), so the agent's files land somewhere the user can find and
/// resuming the session returns to them. With no session, fall back to the
/// user's home directory: inheriting the host's own cwd would hand the agent
/// whatever directory the app happened to be launched from (`/` under Finder),
/// which is never a sensible place to work in.
async fn resolved_run_cwd(session : String?) -> @path.Path? {
  if session is Some(session) && session_workspace_dir(session) is Some(dir) {
    return Some(dir)
  }
  @home.dir().map(home => home.to_string())
}

///|
/// The manager's map key for a run: its durable session id, or the one shared
/// slot for session-less runs (the desktop client always names a session).
fn session_key(config : RunConfig) -> String {
  config.session.unwrap_or("")
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
    config.session.unwrap_or(""),
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
    session: None,
    session_root: None,
  }
  let custom = {
    ..base,
    api_url: Some("https://proxy.example/chat/completions"),
  }
  assert_true(engine_fingerprint(base) != engine_fingerprint(custom))
  assert_eq(engine_fingerprint(base), engine_fingerprint({ ..base, task: "u" }))
}

///|
test "custom endpoint does not reuse DEEPSEEK env fallback" {
  assert_eq(
    configured_api_key(
      None,
      Some("https://proxy.example/chat/completions"),
      Some("official-key"),
    ),
    PlaceholderApiKey,
  )
  assert_eq(
    configured_api_key(
      Some("custom-key"),
      Some("https://proxy.example/chat/completions"),
      Some("official-key"),
    ),
    "custom-key",
  )
}

///|
test "official OpenSeek proxy authenticates with the client token" {
  assert_eq(
    configured_api_key(
      None,
      Some("https://openseek-api.moonbitlang.cn/chat/completions"),
      Some("official-key"),
      client_token="stamped-token",
    ),
    "stamped-token",
  )
  // A user-provided key always wins over the stamped token.
  assert_eq(
    configured_api_key(
      Some("user-key"),
      Some("https://openseek-api.moonbitlang.cn/chat/completions"),
      None,
      client_token="stamped-token",
    ),
    "user-key",
  )
  // An unstamped build behaves as before.
  assert_eq(
    configured_api_key(
      None,
      Some("https://openseek-api.moonbitlang.cn/chat/completions"),
      None,
    ),
    PlaceholderApiKey,
  )
}

///|
test "other endpoints never see the client token" {
  assert_eq(
    configured_api_key(
      None,
      Some("https://proxy.example/chat/completions"),
      None,
      client_token="stamped-token",
    ),
    PlaceholderApiKey,
  )
  // A lookalike host on another domain does not match the prefix.
  assert_eq(
    configured_api_key(
      None,
      Some("https://openseek-api.moonbitlang.cn.evil.example/chat/completions"),
      None,
      client_token="stamped-token",
    ),
    PlaceholderApiKey,
  )
}

///|
test "official endpoint still uses DEEPSEEK env fallback" {
  assert_eq(
    configured_api_key(None, None, Some("official-key")),
    "official-key",
  )
  let _ = configured_api_key(None, None, None) catch {
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
    session: None,
    workspace: None,
  })
  assert_true(config.api_url is Some(OpenseekProxyUrl))
}

///|
async test "host chooses durable placement from workspace state" {
  archive_env_test_lock.acquire()
  defer archive_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  let dir = @fs.tmpdir(prefix="openseek-config-workspace-")
  let global_root = dir + "/global"
  let workspace = dir + "/workspace"
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
    session: Some("s-workspace"),
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
    session: Some("s-global"),
    workspace: None,
  })
  assert_eq(fresh.session_root.map(root => root.to_string()), Some(global_root))
  let attached = run_config(manager, {
    task: "attached",
    submission_id: None,
    model: None,
    max_steps: None,
    session: Some("s-attached"),
    workspace: Some(workspace),
  })
  assert_eq(
    attached.session_root.map(root => root.to_string()),
    Some(workspace + "/.openseek"),
  )
  assert_eq(attached.cwd.map(cwd => cwd.to_string()), Some(workspace))
  @fs.rmdir(dir, recursive=true)
}
