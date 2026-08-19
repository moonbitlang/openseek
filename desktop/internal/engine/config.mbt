// Turning a `start` payload into the validated configuration a serve engine
// is spawned with.

///|
const DefaultModel = "deepseek-v4-pro"

///|
const DefaultMaxSteps = 1000

///|
/// Sent as the API key when a custom endpoint has no stored key: the
/// engine refuses to start with an empty key, so this preserves the request
/// shape for endpoints that need no credential (e.g. a local Ollama or
/// LM Studio server).
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
  let hinted : @pathx.Absolute? = if workspace is Some(path) {
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
  // Every run belongs to a workspace. The hint names one; a hint-less client
  // resuming an existing conversation recovers the workspace that already
  // owns the durable record, so one id can never fork into two histories.
  // With neither, there is nowhere to run — the client must attach a project
  // rather than have the host invent a directory.
  let dir = if hinted is Some(dir) {
    dir
  } else if @session_store.workspace_of(session) is Some(dir) {
    dir
  } else {
    raise EngineError(
      "this conversation has no workspace; attach a project first",
    )
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
    // A run happens in the workspace directory itself, unless the session is
    // bound to one of its worktrees — then it works in that checkout, on
    // every turn and not only the binding one. A binding whose checkout
    // vanished refuses here rather than moving the agent into the main tree
    // behind the user's back.
    cwd: Some(@worktree.run_dir(dir, session).to_path()),
    session,
    session_root: Some(@workspaces.store_root(dir)),
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
