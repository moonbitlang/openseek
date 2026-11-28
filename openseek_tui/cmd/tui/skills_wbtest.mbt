///|
fn skills_test_state() -> State {
  State({
    api_key: "k",
    api_url: Some("https://proxy.example/v1/chat/completions"),
    model: Deepseek(V4Pro),
    cwd: ".",
    max_steps: Some(10),
    retry_attempts: None,
    retry_backoff_ms: None,
    thinking: Max,
    session_id: SessionId("skills-test"),
    session_root: ".openseek",
    system_prompt_file: None,
    system_prompt_addendum_file: None,
    engine: "openseek",
    engine_args_prefix: [],
  })
}

///|
fn skills_error_count(cmds : Array[Cmd]) -> Int32 {
  [ for cmd in cmds if cmd is AppendItem(Error(_)) => cmd ].length()
}

///|
test "/skills slash command parses list, enable, disable (including spaces and quotes), and rejects bad args" {
  let state = skills_test_state()
  guard update(state, UiInput(SlashCommand(name="skills", arguments="")))
    is [ListSkills] else {
    fail("expected bare /skills to emit ListSkills")
  }
  guard update(
      state,
      UiInput(SlashCommand(name="skills", arguments="enable moonbitlang-typst")),
    )
    is [SetSkillEnabled(id="moonbitlang-typst", enabled=true)] else {
    fail("expected /skills enable to emit SetSkillEnabled(enabled=true)")
  }
  guard update(
      state,
      UiInput(
        SlashCommand(name="skills", arguments="disable moonbitlang-office-cli"),
      ),
    )
    is [SetSkillEnabled(id="moonbitlang-office-cli", enabled=false)] else {
    fail("expected /skills disable to emit SetSkillEnabled(enabled=false)")
  }
  guard update(
      state,
      UiInput(SlashCommand(name="skills", arguments="disable My notes")),
    )
    is [SetSkillEnabled(id="My notes", enabled=false)] else {
    fail("expected /skills disable to accept IDs with spaces")
  }
  guard update(
      state,
      UiInput(SlashCommand(name="skills", arguments="enable \"Release Notes\"")),
    )
    is [SetSkillEnabled(id="Release Notes", enabled=true)] else {
    fail("expected /skills enable to accept quoted IDs")
  }
  for bad in ["sync", "enable", "disable  ", "enable \"\"", "unknown"] {
    let cmds = update(
      state,
      UiInput(SlashCommand(name="skills", arguments=bad)),
    )
    assert_eq(skills_error_count(cmds), 1)
  }
}

///|
test "startup built-in sync records and clears errors silently without transcript noise" {
  let state = skills_test_state()
  let err : @skill_library.BuiltinSkillError = {
    registry: { module_name: "moonbitlang/typst", package_path: "", },
    message: "offline",
  }
  assert_true(update(state, SkillsSynced([err])).is_empty())
  assert_eq(state.builtin_skill_errors.length(), 1)
  assert_true(update(state, SkillsSynced([])).is_empty())
  assert_true(state.builtin_skill_errors.is_empty())
}

///|
test "skill toggles report clear status and session caveat" {
  let state = skills_test_state()
  guard update(
      state,
      SkillToggled(id="moonbitlang-typst", enabled=false, Ok(())),
    )
    is [AppendItem(Notice(disabled))] else {
    fail("expected disable notice")
  }
  let disabled_text = @debug.to_string(disabled)
  assert_true(disabled_text.contains("disabled"))
  assert_false(disabled_text.contains("new sessions"))
  state.session_created = true
  guard update(
      state,
      SkillToggled(id="moonbitlang-typst", enabled=true, Ok(())),
    )
    is [AppendItem(Notice(enabled))] else {
    fail("expected enable notice")
  }
  let enabled_text = @debug.to_string(enabled)
  assert_true(enabled_text.contains("enabled"))
  assert_true(enabled_text.contains("new sessions"))
}

///|
async test "format_skills_summary renders workspace, global, built-in, disabled, and errors" {
  let root = @fs.tmpdir(prefix="tui-skills-summary-")
  defer @fs.remove(root, recursive=true)
  let ws = "\{root}/ws"
  let lib = "\{root}/global"
  @fs.mkdir("\{ws}/.openseek/skills", recursive=true)
  @fs.write_text(
    "\{ws}/.openseek/skills/deploy.md",
    "---\nname: deploy\ndescription: Release workflow.\n---\nbody",
    create_mode=CreateOrTruncate,
  )
  @fs.mkdir("\{lib}/moonbitlang-typst", recursive=true)
  @fs.write_text(
    "\{lib}/moonbitlang-typst/SKILL.md",
    "---\nname: typst\ndescription: Typeset PDFs.\n---\nbody",
    create_mode=CreateOrTruncate,
  )
  @fs.write_text(
    "\{lib}/moonbitlang-typst/.mooncakes.json",
    "{\"kind\":\"standalone\",\"module\":\"moonbitlang/typst\",\"version\":\"1.0.0\",\"package\":\"\"}",
    create_mode=CreateOrTruncate,
  )
  @skill_library.set_skill_enabled(
    "moonbitlang-typst",
    enabled=false,
    library_dir=lib,
  )
  let summary = format_skills_summary(
    cwd=ws,
    library_dir=Some(lib),
    syncing=true,
    builtin_errors=[
      {
        registry: { module_name: "moonbitlang/office-cli", package_path: "", },
        message: "network unreachable",
      },
    ],
  )
  assert_true(summary.contains("Workspace skills"))
  assert_true(summary.contains("deploy — Release workflow."))
  assert_true(summary.contains("Global skills"))
  assert_true(
    summary.contains(
      "typst [built-in, disabled, id: moonbitlang-typst] — Typeset PDFs.",
    ),
  )
  assert_true(summary.contains("Built-in skills sync in progress…"))
  assert_true(summary.contains("moonbitlang/office-cli: network unreachable"))
}
