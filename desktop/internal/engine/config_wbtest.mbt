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
  let previous_session_root = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  defer restore_session_root_env(previous_session_root)
  // A run needs a workspace before the endpoint matters; attach one so this
  // test fails only for the reason it is named after.
  let root : @pathx.Path = Path(@fs.tmpdir(prefix="openseek-config-endpoint-"))
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", root.join("global").to_string())
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
    max_steps: None,
    session: "s-default",
    workspace: Some(workspace),
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
  // A hint-less session that no attached workspace claims has nowhere to run.
  // The host refuses instead of inventing a directory and a store for it,
  // which is what would fork one id into two histories.
  let unclaimed = try {
    ignore(
      run_config(manager, {
        task: "fresh",
        submission_id: None,
        model: None,
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
