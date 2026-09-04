// Turning a `start` payload into the validated configuration a serve engine
// is spawned with.

///|
const DefaultModel = "deepseek-v4-flash"

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
  // The environment variable that carries `api_key` to the engine; see
  // `key_env_for`.
  key_env : String
  // Custom chat-completions endpoint; None means the engine's built-in
  // default for the model's provider.
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
  ThinkingHigh
}

///|
fn configured_api_key(
  stored_key? : String,
  api_url? : String,
  env_key? : String,
  missing? : String = "an API key is required; add it in Settings",
) -> String raise EngineError {
  if stored_key is Some(value) {
    return value
  }
  if api_url is Some(_) {
    return PlaceholderApiKey
  }
  if env_key is Some(value) {
    return value
  }
  raise EngineError(missing)
}

///|
/// The model runs fall back to when neither the request nor `OPENSEEK_MODEL`
/// names one: each official provider's flagship, and DeepSeek's for a custom
/// endpoint (any wire name works there, but the engine still needs one).
fn ApiProvider::default_model(self : ApiProvider) -> String {
  match self {
    Glm => "glm-5.3"
    Deepseek | Custom => DefaultModel
  }
}

///|
/// The environment variable the engine resolves for one model wire name.
fn model_key_env(model : String) -> String {
  if model.has_prefix("glm-") {
    "GLM"
  } else if model.has_prefix("kimi-") {
    "KIMI"
  } else {
    "DEEPSEEK"
  }
}

///|
/// The environment variable that carries the run's API key to the engine.
/// The engine resolves its chat key from a provider-specific variable chosen
/// by the model (`Model::api_key`): `DEEPSEEK`, `KIMI`, or `GLM`. Official
/// providers reject a model from another provider before a child process can
/// inherit that model's ambient credential. A custom endpoint's key instead
/// follows the model's variable, or the engine would never find it; the
/// desktop stores the model as an opaque string, so that routing mirrors the
/// engine's wire-name prefixes.
fn key_env_for(
  provider : ApiProvider,
  model : String,
) -> String raise EngineError {
  let model_key = model_key_env(model)
  match provider {
    Deepseek => {
      guard model_key == "DEEPSEEK" else {
        raise EngineError(
          "model \{model} does not belong to the configured DeepSeek provider",
        )
      }
      "DEEPSEEK"
    }
    Glm => {
      guard model_key == "GLM" else {
        raise EngineError(
          "model \{model} does not belong to the configured GLM provider",
        )
      }
      "GLM"
    }
    Custom => model_key
  }
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
    thinking?=payload.thinking,
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
    thinking?=payload.thinking,
    max_steps?=payload.max_steps,
    workspace?=payload.workspace,
  )
}

///|
async fn session_command_config(
  manager : EngineManager,
  session : String,
  model? : String,
  thinking? : @protocol.OpenSeekThinking,
  max_steps? : Int,
  workspace? : String,
) -> RunConfig {
  let session = session.trim().to_owned()
  guard !session.is_empty() else {
    raise EngineError("session id must not be empty")
  }
  serve_config("", manager, model?, thinking?, max_steps?, session~, workspace?)
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
  thinking? : @protocol.OpenSeekThinking,
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
  let model = match model {
    Some(model) => model
    // The engine takes its model from OPENSEEK_MODEL (DEEPSEEK_MODEL is
    // deliberately ignored — see `serve_engine_env`), so the host's
    // fallback must read the same variable.
    None =>
      @env.get("OPENSEEK_MODEL").unwrap_or(settings.provider.default_model())
  }
  {
    task,
    api_key: endpoint.api_key,
    key_env: key_env_for(settings.provider, model),
    api_url: endpoint.api_url,
    model,
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
    // The variable the key travels in is provider identity: the same key
    // under a different variable is a different endpoint configuration.
    config.key_env,
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
    key_env: "DEEPSEEK",
    api_url: None,
    model: "deepseek-v4-pro",
    thinking: ThinkingMax,
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
  assert_true(
    engine_fingerprint(base) !=
    engine_fingerprint({ ..base, thinking: ThinkingHigh, }),
  )
  assert_eq(
    engine_fingerprint(base),
    engine_fingerprint({ ..base, task: "u", }),
  )
  // cwd is part of the fingerprint: a session bound to a worktree can never
  // reuse a serve process rooted elsewhere (and vice versa).
  assert_true(
    engine_fingerprint(base) !=
    engine_fingerprint({ ..base, cwd: Some(Path("/w/.worktrees/x")), }),
  )
}

///|
test "configured endpoint uses its stored key or the placeholder" {
  assert_eq(
    configured_api_key(
      api_url="https://proxy.example/chat/completions",
      env_key="official-key",
    ),
    PlaceholderApiKey,
  )
  assert_eq(
    configured_api_key(
      stored_key="custom-key",
      api_url="https://proxy.example/chat/completions",
      env_key="official-key",
    ),
    "custom-key",
  )
}

///|
test "official endpoints still use their env fallback" {
  assert_eq(configured_api_key(env_key="official-key"), "official-key")
  let _ = configured_api_key(missing="DeepSeek API key is required") catch {
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
  defer @fs.rmdir(root.to_string(), recursive=true)
  set_test_home(root.join("home").to_string())
  let workspace = attach_run_workspace(root)
  let manager = new_engine_manager("openseek", runtime_dir=root)
  // The BYOK configuration: the official provider with its key.
  let _ = update_settings(manager, {
    provider: Some("deepseek"),
    custom_api_url: None,
    deepseek_api_key: Some("sk-official"),
    glm_api_key: None,
    custom_api_key: None,
  })
  let config = run_config(manager, {
    task: "hello",
    submission_id: None,
    model: None,
    thinking: None,
    max_steps: None,
    session: "s-default",
    workspace: Some(workspace),
  })
  assert_true(config.api_url is None)
  assert_eq(config.api_key, "sk-official")
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
  defer @fs.rmdir(dir, recursive=true)
  let home = dir + "/home"
  let global_root = home + "/.openseek"
  let workspace = dir + "/workspace"
  let workspace_resource = @pathx.Path(workspace).resolve().resource_path()
  set_test_home(home)
  defer (if previous_home is Some(value) {
    @sys.set_env_var(test_home_env_name(), value)
  } else {
    @sys.unset_env_var(test_home_env_name())
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
    thinking: None,
    max_steps: None,
    session: "s-workspace",
    workspace: None,
  })
  assert_eq(
    config.session_root.map(root => root.to_string()),
    Some(workspace + "/.openseek"),
  )
  assert_eq(config.cwd.map(cwd => cwd.to_string()), Some(workspace))
  // A hint-less session that no attached workspace claims has nowhere to run.
  // The host refuses instead of inventing a directory and a store for it,
  // which is what would fork one id into two histories.
  let unclaimed = try {
    ignore(
      run_config(manager, {
        task: "fresh",
        submission_id: None,
        model: None,
        thinking: None,
        max_steps: None,
        session: "s-unclaimed",
        workspace: None,
      }),
    )
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(unclaimed.contains("has no workspace"))
  let attached = run_config(manager, {
    task: "attached",
    submission_id: None,
    model: None,
    thinking: None,
    max_steps: None,
    session: "s-attached",
    workspace: Some(workspace_resource),
  })
  assert_eq(
    attached.session_root.map(root => root.to_string()),
    Some(workspace + "/.openseek"),
  )
  assert_eq(attached.cwd.map(cwd => cwd.to_string()), Some(workspace))
}
