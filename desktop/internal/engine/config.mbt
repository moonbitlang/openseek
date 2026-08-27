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
  thinking : @protocol.OpenSeekThinking
  max_steps : Int
  engine : String
  cwd : @pathx.Path?
  session : String
  session_root : @pathx.Absolute?
}

///|
/// A typed request value outranks the inherited process setting. Older clients
/// omit the field and retain the CLI-compatible environment/default behavior.
fn RunConfig::configured_thinking(
  value : @protocol.OpenSeekThinking?,
) -> @protocol.OpenSeekThinking raise EngineError {
  if value is Some(thinking) {
    return thinking
  }
  if @env.get("OPENSEEK_THINKING") is Some(value) {
    guard @protocol.OpenSeekThinking::parse(value.trim().to_owned())
      is Some(thinking) else {
      raise EngineError("OPENSEEK_THINKING must be one of no, high, or max")
    }
    return thinking
  }
  ThinkingMax
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
    thinking?=payload.thinking,
    max_steps?=payload.max_steps,
    session~,
    workspace=payload.workspace,
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
    thinking?=payload.thinking,
    max_steps?=payload.max_steps,
    workspace=payload.workspace,
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
    thinking?=payload.thinking,
    max_steps?=payload.max_steps,
    workspace=payload.workspace,
  )
}

///|
async fn session_command_config(
  manager : EngineManager,
  session : String,
  model? : String,
  thinking? : @protocol.OpenSeekThinking,
  max_steps? : Int,
  workspace~ : String,
) -> RunConfig {
  let session = session.trim().to_owned()
  guard !session.is_empty() else {
    raise EngineError("session id must not be empty")
  }
  serve_config("", manager, model?, thinking?, max_steps?, session~, workspace~)
}

///|
/// The registered project a request names. The registry, not the payload,
/// decides which directories a run may work in, so a path that is not
/// registered — a workspace the user detached, say — is refused by name
/// rather than redirected to whatever else holds the id.
async fn named_workspace(workspace : String) -> @pathx.Absolute {
  guard @pathx.Absolute::from_uri_path(workspace) is Some(absolute) else {
    raise EngineError("workspace is not a supported absolute resource path")
  }
  match @workspaces.registered_dir(absolute) {
    Some(dir) => dir
    None => raise EngineError("\{workspace} is not a registered workspace")
  }
}

///|
/// The store a session command addresses. Every op that spawns an engine
/// resolves it here, and so does every op that must decide whether a live
/// engine is writing the record it names — the two answers have to agree.
async fn requested_store(workspace : String) -> @pathx.Absolute {
  @workspaces.store_root(named_workspace(workspace))
}

///|
/// The validated configuration shared by every op that can spawn a serve
/// engine. The endpoint (provider, key, URL) comes from the host-owned
/// settings store, never from the request — a client carries no credentials
/// (docs/remote-protocol.md).
///
/// A workspace run happens in the project directory itself, with the session's
/// durable record in the in-project store. Only registered workspaces qualify:
/// the registry, not the payload, decides which directories a run may work in.
async fn serve_config(
  task : String,
  manager : EngineManager,
  model? : String,
  thinking? : @protocol.OpenSeekThinking,
  max_steps? : Int,
  session~ : String,
  workspace~ : String,
) -> RunConfig {
  let engine = manager.engine
  let (settings, _) = manager.settings_snapshot()
  let endpoint = resolved_endpoint(settings)
  // A workspace run happens in the project directory itself, with the
  // session's durable record in that project's store. The request names the
  // workspace; nothing here recovers it from the id, so one id can never fork
  // into two histories behind a client that forgot which store it meant.
  let dir = named_workspace(workspace)
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
    thinking: RunConfig::configured_thinking(thinking),
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
    config.thinking.wire(),
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
    thinking: ThinkingMax,
    max_steps: 1000,
    engine: "openseek",
    cwd: None,
    session: "s-fingerprint",
    session_root: Some(@pathx.Path("/sessions").resolve()),
  }
  let custom = {
    ..base,
    api_url: Some("https://proxy.example/chat/completions"),
  }
  assert_true(engine_fingerprint(base) != engine_fingerprint(custom))
  assert_true(
    engine_fingerprint(base) !=
    engine_fingerprint({ ..base, thinking: ThinkingHigh }),
  )
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
/// not redirect the official DeepSeek provider away from its built-in URL.
async test "run config ignores OPENSEEK_API_URL in favor of the settings" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_API_URL")
  @sys.set_env_var("OPENSEEK_API_URL", "https://env.example/chat/completions")
  defer (if previous is Some(value) {
    @sys.set_env_var("OPENSEEK_API_URL", value)
  } else {
    @sys.unset_env_var("OPENSEEK_API_URL")
  })
  let previous_home = @sys.get_env_var(test_home_env_name())
  defer restore_home_env(previous_home)
  // A run needs a workspace before the endpoint matters; attach one so this
  // test fails only for the reason it is named after.
  let root : @pathx.Path = Path(@fs.tmpdir(prefix="openseek-config-endpoint-"))
  set_test_home(root.join("home").to_string())
  let workspace = attach_run_workspace(root)
  let manager = new_engine_manager("openseek", runtime_dir=root)
  // The BYOK configuration: the official provider with its key.
  let _ = update_settings(manager, {
    provider: Some("deepseek"),
    custom_api_url: None,
    deepseek_api_key: Some("sk-official"),
    custom_api_key: None,
  })
  let config = run_config(manager, {
    task: "hello",
    submission_id: None,
    model: None,
    thinking: None,
    max_steps: None,
    session: "s-default",
    workspace,
  })
  assert_true(config.api_url is None)
  assert_eq(config.api_key, "sk-official")
  @fs.rmdir(root.to_string(), recursive=true)
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
          thinking: None,
          max_steps: None,
          session,
          workspace: "",
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
  let previous_home = @sys.get_env_var(test_home_env_name())
  // BYOK: the default provider needs a key. Set one here so placement — not
  // endpoint resolution — is what this test can fail for, regardless of the
  // ambient environment.
  let previous_key = @sys.get_env_var("DEEPSEEK")
  @sys.set_env_var("DEEPSEEK", "sk-placement-test")
  defer (if previous_key is Some(value) {
    @sys.set_env_var("DEEPSEEK", value)
  } else {
    @sys.unset_env_var("DEEPSEEK")
  })
  // The registry canonicalizes workspace paths, so build the fixture from
  // the tmpdir's physical spelling (`/tmp` is a symlink on macOS).
  let dir = @fs.realpath(@fs.tmpdir(prefix="openseek-config-workspace-"))
  let home = dir + "/home"
  let global_root = home + "/.openseek"
  let workspace = dir + "/workspace"
  let other = dir + "/other"
  let workspace_resource = @pathx.Path(workspace).resolve().resource_path()
  let other_resource = @pathx.Path(other).resolve().resource_path()
  set_test_home(home)
  defer (if previous_home is Some(value) {
    @sys.set_env_var(test_home_env_name(), value)
  } else {
    @sys.unset_env_var(test_home_env_name())
  })
  @fsx.ensure_dir(Path(global_root))
  @fsx.ensure_dir(Path(workspace + "/.openseek/sessions/s-workspace"))
  @fsx.ensure_dir(Path(other + "/.openseek"))
  @fs.write_file(
    global_root + "/workspaces.json",
    ({ "workspaces": [workspace, other] } : Json).stringify(),
    create_mode=CreateOrTruncate,
  )
  let manager = new_engine_manager("openseek")
  // The store comes from what the request named, never from which store
  // happens to hold the id: a request that names the other project is that
  // project's request, even for an id this one owns. (`start_run` refuses
  // this particular one — it would open a second record for an id another
  // store owns — but the placement it refuses is decided here.)
  let elsewhere = run_config(manager, {
    task: "resume",
    submission_id: None,
    model: None,
    thinking: None,
    max_steps: None,
    session: "s-workspace",
    workspace: other_resource,
  })
  assert_eq(elsewhere.session_root.unwrap().to_string(), other + "/.openseek")
  let attached = run_config(manager, {
    task: "attached",
    submission_id: None,
    model: None,
    thinking: None,
    max_steps: None,
    session: "s-workspace",
    workspace: workspace_resource,
  })
  assert_eq(
    attached.session_root.unwrap().to_string(),
    workspace + "/.openseek",
  )
  assert_eq(attached.cwd.map(cwd => cwd.to_string()), Some(workspace))
  // An unregistered directory is refused by name. The registry, not the
  // payload, decides which directories a run may work in — and a refusal
  // keeps a stale client from silently filing the record in another store.
  let detail = try {
    ignore(
      run_config(manager, {
        task: "detached",
        submission_id: None,
        model: None,
        thinking: None,
        max_steps: None,
        session: "s-workspace",
        workspace: @pathx.Path(dir + "/elsewhere").resolve().resource_path(),
      }),
    )
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(detail.has_suffix("is not a registered workspace"))
  @fs.rmdir(dir, recursive=true)
}
