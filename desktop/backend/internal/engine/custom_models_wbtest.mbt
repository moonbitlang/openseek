// The custom-model list end to end on the host: how a `settings.set` stores
// it, what a hand-edited store reads back as, and what a run built from it
// carries to the engine.

///|
/// One settings patch carrying just a custom-model list, so a test says only
/// what it is about.
fn custom_models_patch(models : Array[CustomModel]) -> SettingsPatch {
  {
    provider: None,
    custom_api_url: None,
    deepseek_api_key: None,
    glm_api_key: None,
    custom_api_key: None,
    custom_models: Some(models),
  }
}

///|
async test "custom models round-trip with their optional names" {
  with_settings_dir((dir, manager) => {
    let status = update_settings(
      manager,
      custom_models_patch([
        { id: "  qwen3-coder  ", label: Some("  Qwen3 Coder  "), },
        { id: "local-llama", label: None, },
        // A blank name is the absence of one, not an empty label.
        { id: "local-mistral", label: Some("   "), },
      ]),
    )
    json_inspect(status.custom_models, content=[
      { "id": "qwen3-coder", "label": "Qwen3 Coder" },
      { "id": "local-llama" },
      { "id": "local-mistral" },
    ])
    // The durable file keeps the same shape: trimmed, and an absent name is
    // omitted rather than written as null or "".
    guard @json.parse(@fsx.read_text(settings_file(dir))) is Object(fields) &&
      fields.get("custom_models") is Some(stored) else {
      fail("the settings file carries no custom_models")
    }
    json_inspect(stored, content=[
      { "id": "qwen3-coder", "label": "Qwen3 Coder" },
      { "id": "local-llama" },
      { "id": "local-mistral" },
    ])
    let reloaded = load_engine_settings(manager.runtime_dir)
    assert_eq(reloaded.custom_models, [
      { id: "qwen3-coder", label: Some("Qwen3 Coder"), },
      { id: "local-llama", label: None, },
      { id: "local-mistral", label: None, },
    ])
  })
}

///|
async test "an absent list is kept and an empty one clears it" {
  with_settings_dir((dir, manager) => {
    let _ = update_settings(
      manager,
      custom_models_patch([{ id: "qwen3-coder", label: None, }]),
    )
    // A patch that says nothing about the list leaves it alone.
    let kept = update_settings(manager, {
      provider: None,
      custom_api_url: None,
      deepseek_api_key: None,
      glm_api_key: None,
      custom_api_key: None,
      custom_models: None,
    })
    assert_eq(kept.custom_models.length(), 1)
    // An empty list is the instruction to clear it, and the key leaves the
    // file rather than lingering as an empty array.
    let cleared = update_settings(manager, custom_models_patch([]))
    assert_eq(cleared.custom_models.length(), 0)
    assert_false(@fsx.read_text(settings_file(dir)).contains("custom_models"))
  })
}

///|
async test "an unusable custom-model list is refused whole" {
  with_settings_dir((_dir, manager) => {
    // Each case names the reason; none of them may be stored, and a patch
    // that mixes a good entry with a bad one stores neither.
    let cases : Array[(Array[CustomModel], String)] = [
      ([{ id: "  ", label: None, }], "must be one word"),
      ([{ id: "qwen 3", label: None, }], "must be one word"),
      ([{ id: "glm-5.3", label: None, }], "is already in the model menu"),
      (
        [{ id: "qwen3", label: None, }, { id: "qwen3", label: None, }],
        "is listed twice",
      ),
      (
        [{ id: "qwen3", label: Some("x".repeat(129)), }],
        "longer than 128 characters",
      ),
      // A good entry beside a bad one does not survive on its own: the patch
      // is one instruction, so it is stored whole or not at all.
      (
        [{ id: "good-model", label: None, }, { id: "qwen 3", label: None, }],
        "must be one word",
      ),
    ]
    for (models, expected) in cases {
      let detail = try {
        ignore(update_settings(manager, custom_models_patch(models)))
        ""
      } catch {
        EngineError(message) => message
        _ => ""
      } noraise {
        _ => ""
      }
      assert_true(detail.contains(expected))
    }
    // One entry too many is refused as well.
    let too_many : Array[CustomModel] = []
    for index in 0..<(CustomModelsLimit + 1) {
      too_many.push({ id: "model-\{index}", label: None, })
    }
    let detail = try {
      ignore(update_settings(manager, custom_models_patch(too_many)))
      ""
    } catch {
      EngineError(message) => message
      _ => ""
    } noraise {
      _ => ""
    }
    assert_true(detail.contains("at most 32 custom models"))
    // Nothing above reached the store.
    assert_eq(
      load_engine_settings(manager.runtime_dir).custom_models.length(),
      0,
    )
  })
}

///|
async test "a hand-edited store keeps only the entries it can use" {
  with_settings_dir((dir, manager) => {
    let entries = [
      "{\"id\": \"qwen3-coder\", \"label\": \"Qwen3 Coder\"}", "{\"id\": \"qwen3-coder\", \"label\": \"Duplicate\"}",
      "{\"id\": \"\"}", "{\"id\": \"qwen 3\"}", "{\"id\": \"glm-5.3\"}", "{\"id\": \"kimi-k2.7-code\"}",
      "\"not-an-object\"", "{\"label\": \"no id\"}",
    ]
    @fsx.write_text(
      settings_file(dir),
      "{\"version\": 3, \"provider\": \"custom\", \"custom_models\": [" +
      entries.join(",") +
      "]}",
    )
    let models = load_engine_settings(manager.runtime_dir).custom_models
    // The first spelling of a duplicate wins, an id that is not a wire name
    // is dropped, and a model the composer's menu already lists is not a
    // custom one — while a Kimi id the menu has no entry for is kept.
    assert_eq(models, [
      { id: "qwen3-coder", label: Some("Qwen3 Coder"), },
      { id: "kimi-k2.7-code", label: None, },
    ])
  })
}

///|
#cfg(not(platform="windows"))
async test "a run carries a configured custom model and refuses a stray id" {
  ambient_env_test_lock.acquire()
  defer ambient_env_test_lock.release()
  let previous_home = @sys.get_env_var(test_home_env_name())
  let root : @pathx.Path = Path(@fs.tmpdir(prefix="openseek-custom-model-"))
  defer @fs.rmdir(root.to_string(), recursive=true)
  set_test_home(root.join("home").to_string())
  defer restore_home_env(previous_home)
  let workspace = attach_run_workspace(root)
  let manager = new_engine_manager("openseek", runtime_dir=root)
  let _ = update_settings(manager, {
    provider: Some("custom"),
    custom_api_url: Some("https://proxy.example/chat/completions"),
    deepseek_api_key: None,
    glm_api_key: None,
    custom_api_key: Some("sk-proxy"),
    custom_models: Some([{ id: "qwen3-coder", label: None, }]),
  })
  let config = run_config(manager, {
    task: "hello",
    submission_id: None,
    model: Some("qwen3-coder"),
    thinking: None,
    max_steps: None,
    session: "s-custom-model",
    workspace: Some(workspace),
  })
  assert_eq(config.model, "qwen3-coder")
  assert_eq(config.api_url, Some("https://proxy.example/chat/completions"))
  assert_eq(config.api_key, "sk-proxy")
  // An unknown id travels in the DeepSeek variable, which is where the
  // engine's own lookup reads a model it does not know.
  assert_eq(config.key_env, "DEEPSEEK")
  // A run that names no model takes the endpoint's first configured one, not
  // DeepSeek's tier — which this endpoint may not serve.
  let previous_model = @sys.get_env_var("OPENSEEK_MODEL")
  @sys.unset_env_var("OPENSEEK_MODEL")
  defer (match previous_model {
    Some(value) => @sys.set_env_var("OPENSEEK_MODEL", value)
    None => @sys.unset_env_var("OPENSEEK_MODEL")
  })
  let defaulted = run_config(manager, {
    task: "hello",
    submission_id: None,
    model: None,
    thinking: None,
    max_steps: None,
    session: "s-custom-default",
    workspace: Some(workspace),
  })
  assert_eq(defaulted.model, "qwen3-coder")
  // A model nobody configured is refused while the host can still name the
  // fix, instead of failing inside the engine with "unknown model".
  let refused = try {
    ignore(
      run_config(manager, {
        task: "hello",
        submission_id: None,
        model: Some("ghost-model"),
        thinking: None,
        max_steps: None,
        session: "s-ghost-model",
        workspace: Some(workspace),
      }),
    )
    ""
  } catch {
    EngineError(message) => message
    _ => ""
  } noraise {
    _ => ""
  }
  assert_true(refused.contains("is not configured for this endpoint"))
}
