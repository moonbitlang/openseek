// Saved custom models for the Custom URL provider slot.
//
// The endpoint URL and API key live on the Custom provider slot in
// `engine-settings.json`, so each saved model stores only its wire `id`,
// optional display `label`, and `context_window`.

///|
fn parse_model_opt(id : String) -> @deepseek.Model? {
  Some(@deepseek.Model::parse(id)) catch {
    _ => None
  }
}

///|
fn model_ids_match(left : String, right : String) -> Bool {
  left == right ||
  (
    parse_model_opt(left) is Some(parsed) &&
    parse_model_opt(right) == Some(parsed)
  )
}

///|
fn find_custom_model(
  models : Array[@protocol.CustomModel],
  model : String,
) -> @protocol.CustomModel? {
  models
  .search_by(entry => model_ids_match(entry.id, model))
  .map(index => models[index])
}

///|
/// Tolerantly decode saved custom models from `engine-settings.json`. Corrupt
/// or unnamed entries are skipped, and duplicate ids keep their first entry.
fn decode_custom_models(
  raw : Map[String, Json],
) -> Array[@protocol.CustomModel] {
  let entries : Array[@protocol.CustomModel] = []
  guard raw.get("models") is Some(Array(items)) else { return entries }
  for item in items {
    guard item is Object(fields) else { continue }
    guard fields.get("id") is Some(String(raw_id)) else { continue }
    let id = raw_id.trim().to_owned()
    if id.is_empty() ||
      entries.any(existing => model_ids_match(existing.id, id)) {
      continue
    }
    let label = settings_text(fields, "label").map(value => {
      value.trim().to_owned()
    })
    let context_window = match fields.get("context_window") {
      Some(Number(value, ..)) if value > 0.0 => value.to_int()
      _ => @protocol.DefaultCustomModelContextWindow
    }
    entries.push({ id, label, context_window, })
  }
  entries
}

///|
/// Validate and normalize one complete custom-model list before writing it to
/// `engine-settings.json`.
fn normalize_custom_models(
  models : Array[@protocol.CustomModel],
) -> Array[@protocol.CustomModel] raise EngineError {
  guard models.length() <= @protocol.MaxCustomModels else {
    raise EngineError("too many saved models; remove one first")
  }
  let normalized : Array[@protocol.CustomModel] = []
  for entry in models {
    let id = entry.id.trim().to_owned()
    guard !id.is_empty() else { raise EngineError("a model needs a name") }
    guard !normalized.any(existing => model_ids_match(existing.id, id)) else {
      raise EngineError("duplicate model id '\{id}'")
    }
    let label = match entry.label {
      Some(raw) => {
        let trimmed = raw.trim().to_owned()
        guard trimmed.length() <= @protocol.MaxCustomModelLabelChars else {
          raise EngineError("a model name is limited to 64 characters")
        }
        if trimmed.is_empty() {
          None
        } else {
          Some(trimmed)
        }
      }
      None => None
    }
    let window = entry.context_window
    guard window >= @protocol.MinCustomModelContextWindow &&
      window <= @protocol.MaxCustomModelContextWindow else {
      raise EngineError(
        "a model's context window must be between \{@protocol.MinCustomModelContextWindow} and \{@protocol.MaxCustomModelContextWindow} tokens",
      )
    }
    normalized.push({ id, label, context_window: window, })
  }
  normalized
}

///|
test "custom models decode tolerantly with defaults and deduplication" {
  let raw : Map[String, Json] = {
    "models": [
      { "id": "" },
      { "id": "  gemini-4-carbon  ", "label": "  Gemini 4 Carbon  " },
      { "id": "gemini-4-carbon", "context_window": 32_768 },
      { "id": "o3-mini", "context_window": 131_072 },
      "not an entry",
    ],
  }
  assert_eq(decode_custom_models(raw), [
    {
      id: "gemini-4-carbon",
      label: Some("Gemini 4 Carbon"),
      context_window: @protocol.DefaultCustomModelContextWindow,
    },
    { id: "o3-mini", label: None, context_window: 131_072, },
  ])
}

///|
test "custom model normalization enforces bounds, label limit, duplicates, and cap" {
  let err_of = (models : Array[@protocol.CustomModel]) => {
    let _ = normalize_custom_models(models) catch {
      EngineError(message) => return Some(message)
    }
    None
  }
  let valid : @protocol.CustomModel = {
    id: "gemini-4-hydrogen",
    label: None,
    context_window: @protocol.DefaultCustomModelContextWindow,
  }
  assert_true(err_of([{ ..valid, id: "   ", }]) is Some(_))
  assert_true(
    err_of([{ ..valid, label: Some(String::make(65, 'a')), }]) is Some(_),
  )
  assert_true(
    err_of([
      { ..valid, context_window: @protocol.MinCustomModelContextWindow - 1, },
    ])
    is Some(_),
  )
  assert_true(
    err_of([
      { ..valid, context_window: @protocol.MaxCustomModelContextWindow + 1, },
    ])
    is Some(_),
  )
  assert_true(
    err_of([
      { ..valid, id: "deepseek-flash", },
      { ..valid, id: "deepseek-v4-flash", },
    ])
    is Some(_),
  )
  let overflow : Array[@protocol.CustomModel] = []
  for i in 0..<=@protocol.MaxCustomModels {
    overflow.push({ ..valid, id: "m-\{i}", })
  }
  assert_true(err_of(overflow) is Some(_))
}

///|
async test "saved custom models persist and route runs through the custom endpoint" {
  with_settings_dir((dir, manager) => {
    let previous_home = @sys.get_env_var(test_home_env_name())
    defer restore_home_env(previous_home)
    set_test_home(dir.join("global").to_string())
    let workspace = attach_run_workspace(dir)
    let saved = update_settings(
      manager,
      {
        provider: Some("custom"),
        providers: Some({
          "deepseek": { api_url: None, api_key: Some("sk-official"), },
          "custom": {
            api_url: Some("https://gateway.example/v1"),
            api_key: Some("sk-slot"),
          },
        }),
      },
      models=[
        {
          id: "gemini-4-carbon",
          label: Some("Gemini 4 Carbon"),
          context_window: 131_072,
        },
        {
          id: "deepseek-flash",
          label: Some("Custom DS Flash"),
          context_window: 262_144,
        },
        { id: "deepseek-v4-pro", label: None, context_window: 131_072, },
      ],
    )
    assert_eq(saved.models.map(model => model.id), [
      "gemini-4-carbon", "deepseek-flash", "deepseek-v4-pro",
    ])
    assert_eq(settings_status(manager).models, saved.models)

    let custom_run = run_config(manager, {
      system_prompt: None,
      images: [],
      task: "hello",
      submission_id: None,
      model: Some("gemini-4-carbon"),
      thinking: None,
      approval: None,
      max_steps: None,
      session: "s-custom",
      workspace: Some(workspace),
    })
    assert_eq(custom_run.api_key, "sk-slot")
    assert_eq(
      custom_run.api_url,
      Some("https://gateway.example/v1/chat/completions"),
    )
    assert_eq(custom_run.key_env, @deepseek.CustomApiKeyEnv)
    assert_eq(custom_run.context_window, Some(131_072))
    assert_true(custom_run.supports_images())

    // Built-in ids saved under Custom keep their built-in key env and image rules.
    let flash_run = run_config(manager, {
      system_prompt: None,
      images: [],
      task: "hello",
      submission_id: None,
      model: Some("deepseek-flash"),
      thinking: None,
      approval: None,
      max_steps: None,
      session: "s-custom-flash",
      workspace: Some(workspace),
    })
    assert_eq(flash_run.key_env, "DEEPSEEK")
    assert_eq(flash_run.context_window, Some(262_144))
    assert_true(flash_run.supports_images())

    let pro_run = run_config(manager, {
      system_prompt: None,
      images: [],
      task: "hello",
      submission_id: None,
      model: Some("deepseek-v4-pro"),
      thinking: None,
      approval: None,
      max_steps: None,
      session: "s-custom-pro",
      workspace: Some(workspace),
    })
    assert_eq(pro_run.key_env, "DEEPSEEK")
    assert_false(pro_run.supports_images())

    // Switching back to DeepSeek official ignores custom model windows.
    let _ = update_settings(manager, {
      provider: Some("deepseek"),
      providers: None,
    })
    let official_run = run_config(manager, {
      system_prompt: None,
      images: [],
      task: "hello",
      submission_id: None,
      model: Some("deepseek-flash"),
      thinking: None,
      approval: None,
      max_steps: None,
      session: "s-official",
      workspace: Some(workspace),
    })
    assert_eq(official_run.api_key, "sk-official")
    assert_true(official_run.api_url is None)
    assert_true(official_run.context_window is None)

    // Clearing the list removes `models` from settings.
    let cleared = update_settings(
      manager,
      { provider: None, providers: None, },
      models=[],
    )
    assert_true(cleared.models.is_empty())
  })
}
