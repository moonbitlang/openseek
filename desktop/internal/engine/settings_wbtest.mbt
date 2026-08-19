///|
async test "missing settings read as the BYOK defaults" {
  with_settings_dir(async fn(_dir, manager) {
    let settings = load_engine_settings(manager.runtime_dir)
    assert_true(settings.provider is Deepseek)
    assert_true(settings.deepseek_api_key is None)
    json_inspect(settings_status(manager), content={
      "revision": 0,
      "provider": "deepseek",
      "has_deepseek_key": false,
      "has_custom_key": false,
    })
  })
}

///|
async test "the DEEPSEEK env fallback reads as a usable key" {
  with_settings_dir(async fn(_dir, manager) {
    // The engine resolves DEEPSEEK when no key is stored; the status must
    // agree, or the frontend blocks Send on an endpoint that runs fine.
    @sys.set_env_var("DEEPSEEK", "sk-env")
    defer @sys.unset_env_var("DEEPSEEK")
    json_inspect(settings_status(manager), content={
      "revision": 0,
      "provider": "deepseek",
      "has_deepseek_key": true,
      "has_custom_key": false,
    })
  })
}

///|
async test "a saved key round-trips as presence, never as text" {
  with_settings_dir(async fn(dir, manager) {
    let status = update_settings(manager, {
      provider: Some("deepseek"),
      custom_api_url: None,
      deepseek_api_key: Some("  sk-secret  "),
      custom_api_key: None,
    })
    json_inspect(status, content={
      "revision": 1,
      "provider": "deepseek",
      "has_deepseek_key": true,
      "has_custom_key": false,
    })
    // The status never carries the key; the file carries it trimmed.
    assert_false(status.to_json().stringify().contains("sk-secret"))
    let text = @fsx.read_text(settings_file(dir))
    assert_true(text.contains("\"sk-secret\""))
    let reloaded = load_engine_settings(manager.runtime_dir)
    assert_true(reloaded.deepseek_api_key is Some("sk-secret"))
    assert_true(reloaded.provider is Deepseek)
  })
}

///|
async test "retired hosted providers converge on the DeepSeek default" {
  with_settings_dir(async fn(dir, manager) {
    // A store left behind by a hosted-API build must not wedge: it reads
    // as the BYOK default, which needs a key and therefore routes to
    // Settings.
    @fsx.write_text(settings_file(dir), "{\"provider\": \"openseek\"}")
    assert_true(load_engine_settings(manager.runtime_dir).provider is Deepseek)
    // A write carrying a retired name (e.g. a legacy client's migration)
    // is accepted and persisted as the default it means now.
    let status = update_settings(manager, {
      provider: Some("openseek-staging"),
      custom_api_url: None,
      deepseek_api_key: None,
      custom_api_key: None,
    })
    json_inspect(status, content={
      "revision": 1,
      "provider": "deepseek",
      "has_deepseek_key": false,
      "has_custom_key": false,
    })
    let text = @fsx.read_text(settings_file(dir))
    assert_true(text.contains("\"provider\": \"deepseek\""))
    // Remote access is a SeekMoon relay service and no longer depends on
    // the chat provider, so it stays on the production origin.
    debug_inspect(
      remote_server_base(manager),
      content="Some(\"https://openseek-api.moonbitlang.cn\")",
    )
  })
}

///|
async test "a present-but-blank field clears the stored value" {
  with_settings_dir(async fn(_dir, manager) {
    let _ = update_settings(manager, {
      provider: Some("custom"),
      custom_api_url: Some("https://proxy.example/chat/completions"),
      deepseek_api_key: None,
      custom_api_key: Some("sk-custom"),
    })
    let status = update_settings(manager, {
      provider: None,
      custom_api_url: Some("   "),
      deepseek_api_key: None,
      custom_api_key: Some(""),
    })
    json_inspect(status, content={
      "revision": 2,
      "provider": "custom",
      "has_deepseek_key": false,
      "has_custom_key": false,
    })
  })
}

///|
async test "a save removes the retired WSL settings group" {
  with_settings_dir(async fn(dir, manager) {
    @fsx.write_text(
      settings_file(dir),
      "{\"version\": 1, \"provider\": \"deepseek\", \"wsl\": {\"enabled\": true, \"distro\": \"Ubuntu\"}}",
    )
    let _ = update_settings(manager, {
      provider: None,
      custom_api_url: None,
      deepseek_api_key: Some("sk-kept"),
      custom_api_key: None,
    })
    guard @json.parse(@fsx.read_text(settings_file(dir))) is Object(fields) else {
      fail("settings file is not valid JSON")
    }
    assert_true(fields.get("wsl") is None)
    assert_true(
      fields.get("version") is Some(Number(version, ..)) &&
      version.to_int() == 2,
    )
  })
}

///|
async test "legacy migration cannot replay over a newer settings write" {
  with_settings_dir(async fn(_dir, manager) {
    let migrated = update_settings(
      manager,
      {
        provider: Some("deepseek"),
        custom_api_url: None,
        deepseek_api_key: Some("sk-old"),
        custom_api_key: None,
      },
      legacy_migration=true,
    )
    assert_eq(migrated.revision, 1)
    let modern = update_settings(manager, {
      provider: Some("custom"),
      custom_api_url: Some("https://new.example/chat"),
      deepseek_api_key: Some(""),
      custom_api_key: Some("sk-new"),
    })
    assert_eq(modern.revision, 2)
    // This is the desktop retry after the first migration's reply was lost.
    // It gets the current status so the client can clear localStorage, but
    // neither advances the revision nor restores the stale values.
    let replay = update_settings(
      manager,
      {
        provider: Some("deepseek"),
        custom_api_url: None,
        deepseek_api_key: Some("sk-old"),
        custom_api_key: None,
      },
      legacy_migration=true,
    )
    assert_eq(replay.revision, 2)
    let current = load_engine_settings(manager.runtime_dir)
    assert_true(current.provider is Custom)
    assert_true(current.deepseek_api_key is None)
    assert_true(current.custom_api_key is Some("sk-new"))
  })
}

///|
async test "concurrent disjoint settings patches merge and publish in revision order" {
  with_settings_dir(async fn(dir, manager) {
    let committed : Array[Int] = []
    let ready : @async.Queue[Unit] = Queue(kind=Blocking(2))
    // Queue both callers behind the manager lock so the test exercises the
    // same contended path as two remote clients instead of relying on I/O
    // scheduling to happen to overlap them.
    manager.settings_lock.acquire()
    @async.with_task_group(group => {
      let endpoint = group.spawn(() => {
        ready.put(())
        update_settings(
          manager,
          {
            provider: Some("deepseek"),
            custom_api_url: None,
            deepseek_api_key: Some("sk-concurrent"),
            custom_api_key: None,
          },
          on_committed=fn(status) { committed.push(status.revision) },
        )
      })
      let custom = group.spawn(() => {
        ready.put(())
        update_settings(
          manager,
          {
            provider: None,
            custom_api_url: Some("https://custom.example/chat"),
            deepseek_api_key: None,
            custom_api_key: Some("sk-custom"),
          },
          on_committed=fn(status) { committed.push(status.revision) },
        )
      })
      ready.get()
      ready.get()
      manager.settings_lock.release()
      let endpoint_status = endpoint.wait()
      let custom_status = custom.wait()
      let revisions = [endpoint_status.revision, custom_status.revision]
      revisions.sort()
      assert_eq(revisions, [1, 2])
    })
    assert_eq(committed, [1, 2])
    let text = @fsx.read_text(settings_file(dir))
    guard @json.parse(text) is Object(fields) else {
      fail("settings file is not valid JSON")
    }
    assert_true(fields.get("provider") is Some(String("deepseek")))
    assert_true(fields.get("deepseek_api_key") is Some(String("sk-concurrent")))
    assert_true(
      fields.get("custom_api_url")
      is Some(String("https://custom.example/chat")),
    )
    assert_true(fields.get("custom_api_key") is Some(String("sk-custom")))
    // Revision is a host-process epoch, not a persistence-format change.
    assert_true(fields.get("revision") is None)
    assert_eq(settings_status(manager).revision, 2)
  })
}

///|
async test "saves preserve fields a newer build added" {
  with_settings_dir(async fn(dir, manager) {
    @fsx.write_text(
      settings_file(dir),
      "{\"version\": 1, \"future_field\": \"kept\", \"provider\": \"deepseek\"}",
    )
    let _ = update_settings(manager, {
      provider: None,
      custom_api_url: None,
      deepseek_api_key: Some("sk-new"),
      custom_api_key: None,
    })
    let text = @fsx.read_text(settings_file(dir))
    assert_true(text.contains("\"future_field\""))
    assert_true(text.contains("\"kept\""))
    // The untouched provider survives the patch too.
    let reloaded = load_engine_settings(manager.runtime_dir)
    assert_true(reloaded.provider is Deepseek)
    assert_true(reloaded.deepseek_api_key is Some("sk-new"))
  })
}

///|
async test "a newer-version file is read best-effort but never rewritten" {
  with_settings_dir(async fn(dir, manager) {
    @fsx.write_text(
      settings_file(dir),
      "{\"version\": 99, \"provider\": \"deepseek\", \"deepseek_api_key\": \"sk-kept\"}",
    )
    // Reads still surface what this build understands.
    let settings = load_engine_settings(manager.runtime_dir)
    assert_true(settings.provider is Deepseek)
    assert_true(settings.deepseek_api_key is Some("sk-kept"))
    // Writes are refused so a downgrade cannot eat the newer schema.
    let refused = try
      update_settings(manager, {
        provider: Some("openseek"),
        custom_api_url: None,
        deepseek_api_key: None,
        custom_api_key: None,
      })
    catch {
      EngineError(message) => message
      _ => ""
    } noraise {
      _ => ""
    }
    assert_true(refused.contains("newer"))
    let text = @fsx.read_text(settings_file(dir))
    assert_true(text.contains("\"version\": 99"))
  })
}

///|
async test "an unknown provider is refused on write, defaulted on read" {
  with_settings_dir(async fn(dir, manager) {
    let refused = try
      update_settings(manager, {
        provider: Some("acme"),
        custom_api_url: None,
        deepseek_api_key: None,
        custom_api_key: None,
      })
    catch {
      EngineError(message) => message
      _ => ""
    } noraise {
      _ => ""
    }
    assert_true(refused.contains("unknown API provider"))
    // A corrupted store degrades to the BYOK default.
    @fsx.write_text(settings_file(dir), "{\"provider\": \"acme\"}")
    assert_true(load_engine_settings(manager.runtime_dir).provider is Deepseek)
  })
}

///|
async test "a corrupt file reads as defaults and survives until a save" {
  with_settings_dir(async fn(dir, manager) {
    @fsx.write_text(settings_file(dir), "{ not json")
    let settings = load_engine_settings(manager.runtime_dir)
    assert_true(settings.provider is Deepseek)
    // Nothing rewrote the broken file behind the user's back.
    assert_eq(@fsx.read_text(settings_file(dir)), "{ not json")
  })
}

///|
async test "run config resolves the endpoint from the stored provider" {
  // `with_settings_dir` holds the ambient-env lock, so the session-root
  // save/restore belongs inside its body — acquiring the lock here first
  // would self-deadlock, and restoring after its release would write the
  // ambient environment outside the lock.
  with_settings_dir(async fn(dir, manager) {
    let previous_session_root = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
    defer restore_session_root_env(previous_session_root)
    // A run needs a workspace before it can resolve anything else. This test
    // is about the endpoint the stored provider yields, so any attached
    // directory serves; the env root only locates the registry.
    @sys.set_env_var("OPENSEEK_SESSION_ROOT", dir.join("global").to_string())
    let workspace = attach_run_workspace(dir)
    let _ = update_settings(manager, {
      provider: Some("deepseek"),
      custom_api_url: None,
      deepseek_api_key: Some("sk-stored"),
      custom_api_key: None,
    })
    let config = run_config(manager, {
      task: "hello",
      submission_id: None,
      model: None,
      max_steps: None,
      session: "s-settings-default",
      workspace: Some(workspace),
    })
    // The official endpoint is the engine default: no URL override.
    assert_true(config.api_url is None)
    assert_eq(config.api_key, "sk-stored")
    let _ = update_settings(manager, {
      provider: Some("custom"),
      custom_api_url: Some("https://proxy.example/chat/completions"),
      deepseek_api_key: None,
      custom_api_key: None,
    })
    let custom = run_config(manager, {
      task: "hello",
      submission_id: None,
      model: None,
      max_steps: None,
      session: "s-settings-custom",
      workspace: Some(workspace),
    })
    assert_true(
      custom.api_url is Some("https://proxy.example/chat/completions"),
    )
    // A custom endpoint without a key gets the placeholder, never the
    // stored DeepSeek key.
    assert_eq(custom.api_key, PlaceholderApiKey)
  })
}

///|
async test "a custom provider without a URL refuses to start" {
  with_settings_dir(async fn(_dir, manager) {
    let _ = update_settings(manager, {
      provider: Some("custom"),
      custom_api_url: None,
      deepseek_api_key: None,
      custom_api_key: None,
    })
    let refused = try
      run_config(manager, {
        task: "hello",
        submission_id: None,
        model: None,
        max_steps: None,
        session: "s-settings-missing-url",
        workspace: None,
      })
    catch {
      EngineError(message) => message
      _ => ""
    } noraise {
      _ => ""
    }
    assert_true(refused.contains("custom endpoint URL is required"))
  })
}
