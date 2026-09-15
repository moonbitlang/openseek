///|
test "cli parses env backed options and task" {
  let parsed = run_matches(argv=["write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
    "OPENSEEK_MODEL": "deepseek-v4-pro",
    "OPENSEEK_API_URL": "https://proxy.example/v1/chat/completions",
    "OPENSEEK_MAX_STEPS": "120",
    "OPENSEEK_SYSTEM_PROMPT_FILE": "/tmp/prompt-a.md",
    "OPENSEEK_SYSTEM_PROMPT_ADDENDUM_FILE": "/tmp/prompt-b.md",
    "OPENSEEK_RETRY_ATTEMPTS": "4",
    "OPENSEEK_RETRY_BACKOFF_MS": "25",
  })
  let (model, _, api_url) = @options.agent_settings(parsed)
  assert_true(model is Deepseek(V4Pro))
  assert_eq(model.api_key(parsed.values), Some("test-key"))
  guard api_url is Some(url) else { fail("expected api url") }
  assert_eq(url, "https://proxy.example/v1/chat/completions")
  assert_eq(@cli.value(parsed, "dir"), ".")
  assert_true(@options.max_steps(parsed) is Some(120))
  assert_eq(@cli.value(parsed, "system-prompt-file"), "/tmp/prompt-a.md")
  assert_eq(
    @cli.value(parsed, "system-prompt-addendum-file"),
    "/tmp/prompt-b.md",
  )
  assert_false(parsed is { values: { "session": [_, ..], .. }, .. })
  assert_eq(session_root(parsed), ".openseek")
  assert_eq(@options.task_text(parsed), "write MoonBit")
  assert_eq(@options.retry_overrides(parsed), (Some(4), Some(25)))
}

///|
test "cli defaults model and max steps" {
  let parsed = run_matches(argv=["write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
  })
  let (model, thinking, api_url) = @options.agent_settings(parsed)
  assert_true(model is Deepseek(V4Flash))
  assert_true(thinking is High)
  assert_eq(model.api_key(parsed.values), Some("test-key"))
  assert_true(api_url is None)
  assert_eq(@cli.value(parsed, "dir"), ".")
  assert_true(@options.max_steps(parsed) is None)
  assert_true(parsed is { values: { "session"? : None, .. }, .. })
  assert_eq(session_root(parsed), ".openseek")
  // Absent on both halves: the DeepSeek client keeps its own defaults, which
  // the CLI never restates.
  assert_eq(@options.retry_overrides(parsed), (None, None))
}

///|
async test "one-shot runs record to a generated salted cli session by default" {
  let parsed = run_matches(argv=["write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
  })
  guard resolved_session_id(parsed) is Some(id) else {
    fail("expected a generated session id")
  }
  assert_true(id.value().has_prefix("cli-"))
  // cli- + YYYYMMDD-HHMMSS-mmm is 23 chars; anything beyond is the random
  // salt that keeps two same-millisecond launches under one session root
  // apart (mkdtemp-arbitrated, so its exact length is platform-defined).
  assert_true(id.value().length() > 24)
}

///|
async test "--no-session restores the ephemeral one-shot" {
  let parsed = run_matches(argv=["--no-session", "write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
  })
  assert_true(resolved_session_id(parsed) is None)
}

///|
async test "an explicit --session id is used verbatim" {
  let parsed = run_matches(argv=["--session", "demo", "write", "MoonBit"], env={
    "DEEPSEEK": "test-key",
  })
  guard resolved_session_id(parsed) is Some(id) else {
    fail("expected the explicit id")
  }
  assert_eq(id.value(), "demo")
}

///|
async test "--session with --no-session is a contradiction" {
  let parsed = run_matches(
    argv=["--session", "demo", "--no-session", "write", "MoonBit"],
    env={ "DEEPSEEK": "test-key" },
  )
  let _ = resolved_session_id(parsed) catch {
    error => {
      assert_true("\{error}".contains("--no-session contradicts --session"))
      return
    }
  }
  fail("expected a contradiction failure")
}

///|
async test "load_or_new_session defers first durable write until append" {
  @vfs.with_tmpdir(prefix="openseek-cli-session-", root => {
    let store = @store.SessionStore(root)
    let id : @agent_session.SessionId = SessionId("cli-test")
    let prompt_path = "\{root}/prompt.md"
    @fs.write_file(prompt_path, "system", create_mode=CreateOrTruncate)
    let parsed = run_matches(
      argv=[
        "--session-root", root, "--session", "cli-test", "--system-prompt-file",
        prompt_path, "write", "MoonBit",
      ],
      // Pinned so the exact-prompt assertions stay machine-independent.
      env={
        "DEEPSEEK": "test-key",
        "OPENSEEK_GLOBAL_SKILLS_DIR": "\{root}/no-global-skills",
      },
    )
    let created = load_or_new_session(store, id, parsed, Deepseek(V4Pro))
    // The environment block is pinned by the environment-section tests above;
    // what this test owns is that the block reaches the stored prompt behind
    // the `--system-prompt-file` base.
    let grounded_prompt = configured_system_prompt(parsed, Deepseek(V4Pro))
    assert_true(grounded_prompt.has_prefix("system\n\n## Environment"))
    assert_eq(created.system_prompt(), grounded_prompt)
    assert_eq(created.events().length(), 0)
    assert_false(store.exists(id))
    let with_event = store.append(created, User(UserMessage("hello")))
    assert_eq(with_event.events().length(), 1)
    @fs.remove(prompt_path)
    let loaded = load_or_new_session(store, id, parsed, Deepseek(V4Pro))
    assert_eq(loaded.system_prompt(), grounded_prompt)
    assert_eq(loaded.events().length(), 1)
  })
}

///|
async test "new durable session header persists project layout" {
  @vfs.with_tmpdir(prefix="openseek-cli-session-layout-", root => {
    let workspace = "\{root}/workspace"
    @vfs.FileSystem::from_pairs([
      ("cmd/tool/main.mbt", "x"),
      ("toml/parser.mbt", "x"),
      (".openseek/ignored", "x"),
      ("_build/out/x", "x"),
    ]).write_to(workspace)
    @fs.write_file(
      "\{workspace}/prompt.md",
      "system",
      create_mode=CreateOrTruncate,
    )
    let real_workspace = @fs.realpath(workspace)
    let store = @store.SessionStore("\{real_workspace}/.openseek")
    let id : @agent_session.SessionId = SessionId("cli-test")
    let parsed = run_matches(
      argv=[
        "--dir",
        workspace,
        "--session-root",
        ".openseek",
        "--session",
        id.value(),
        "--system-prompt-file",
        "prompt.md",
        "write",
        "MoonBit",
      ],
      env={
        "DEEPSEEK": "test-key",
        "OPENSEEK_GLOBAL_SKILLS_DIR": "\{workspace}/no-global-skills",
      },
    )
    let created = load_or_new_session(
      store,
      id,
      parsed,
      Deepseek(V4Pro),
      workspace_root=real_workspace,
    )
    let _ = store.append(created, User(UserMessage("hello")))
    let loaded = store.load(id)
    let prompt = loaded.system_prompt()
    assert_true(prompt.contains("Working directory: \{real_workspace}"))
    assert_true(prompt.contains("Project layout"))
    assert_true(prompt.contains("cmd/\n  tool/\ntoml/"))
    assert_false(prompt.contains(".openseek/ignored"))
    assert_false(prompt.contains("_build/"))
  })
}

///|
async test "load_or_new_session recovers empty interrupted session directory" {
  @vfs.with_tmpdir(prefix="openseek-cli-session-empty-dir-", root => {
    let id : @agent_session.SessionId = SessionId("cli-test")
    @fs.mkdir("\{root}/sessions/\{id.value()}", recursive=true)
    let prompt_path = "\{root}/prompt.md"
    @fs.write_file(prompt_path, "system", create_mode=CreateOrTruncate)
    let parsed = run_matches(
      argv=[
        "--session-root",
        root,
        "--session",
        id.value(),
        "--system-prompt-file",
        prompt_path,
        "write",
        "MoonBit",
      ],
      // Pinned so the exact-prompt assertion stays machine-independent.
      env={
        "DEEPSEEK": "test-key",
        "OPENSEEK_GLOBAL_SKILLS_DIR": "\{root}/no-global-skills",
      },
    )
    let store = @store.SessionStore(root)
    let session = load_or_new_session(store, id, parsed, Deepseek(V4Pro))
    // The environment block is pinned by the environment-section tests above;
    // what this test owns is that the block reaches the stored prompt behind
    // the `--system-prompt-file` base.
    let grounded_prompt = configured_system_prompt(parsed, Deepseek(V4Pro))
    assert_true(grounded_prompt.has_prefix("system\n\n## Environment"))
    assert_eq(session.system_prompt(), grounded_prompt)
    assert_eq(session.events().length(), 0)
    let with_event = store.append(session, User(UserMessage("hello")))
    assert_eq(with_event.events().length(), 1)
  })
}
