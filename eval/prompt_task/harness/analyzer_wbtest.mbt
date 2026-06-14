///|
fn session_events(session : @agent_session.Session) -> String {
  let out = StringBuilder::new()
  for event in session.events() {
    out.write_string(event.to_json().stringify())
    out.write_char('\n')
  }
  out.to_string()
}

///|
fn sample_events() -> String {
  let session = @agent_session.Session(SessionId("trial-01"), system_prompt="")
    .append(User(UserMessage("build a toml cli")))
    .append(
      Assistant(
        AssistantMessage("I will run moon check", tool_calls=[
          ToolCall(
            id="call_1",
            name="moon_cmd",
            arguments="{\"command\":\"moon check\"}",
          ),
        ]),
      ),
    )
    .append(
      Tool(
        ToolResult(
          tool_call_id="call_1",
          tool_name="moon_cmd",
          content="moon check passed",
        ),
      ),
    )
    .append(Terminal(Finished("done")))
  session_events(session)
}

///|
fn assistant_events(session_id : String, content : String) -> String {
  let session = @agent_session.Session(SessionId(session_id), system_prompt="")
    .append(User(UserMessage("run moon check and moon test before finishing")))
    .append(Assistant(AssistantMessage(content)))
    .append(Terminal(Finished("done")))
  session_events(session)
}

///|
fn eval_session_for_test(session : @agent_session.Session) -> EvalResult {
  eval_session_with_context(session, {
    index: 0,
    prompt_label: "",
    workspace: "",
    log_path: "",
    events_path: "",
    exit_code: 0,
    validation: {
      ran: false,
      passed: true,
      reason: "not run",
      moon_check: false,
      moon_test: false,
      file_probe: false,
      stdin_probe: false,
      duplicate_probe: false,
    },
    parse_errors: 0,
    partial_tail: false,
    extra_reasons: [],
    extra_warnings: [],
  })
}

///|
test "session summary counts typed events" {
  let parsed = @session_log.parse_events(sample_events())
  let session = @session_log.session_from_parse(
    parsed,
    id="trial-01",
    system_prompt="",
  )
  let result = eval_session_for_test(session)
  assert_true(result.finished)
  assert_eq(result.steps, 2)
  assert_eq(result.tool_results, 1)
  assert_eq(result.tool_errors, 0)
  assert_eq(result.shell_uses, 0)
  assert_eq(result.runtime_notices, 0)
  assert_eq(result.moon_check_uses, 3)
}

///|
test "eval session produces standalone result" {
  let parsed = @session_log.parse_events(sample_events())
  let session = @session_log.session_from_parse(
    parsed,
    id="trial-01",
    system_prompt="",
  )
  let result = eval_session_for_test(session)
  assert_true(result.success)
  assert_eq(result.session_id, "trial-01")
  assert_eq(result.steps, 2)
  assert_false(result.validation.ran)
  assert_true(result.markdown().contains("Prompt Task Eval Result"))
  assert_true(result.html().contains("<html"))
}

///|
test "behavior counters ignore user task prompt" {
  let session = @agent_session.Session(
      SessionId("prompt-only"),
      system_prompt="",
    )
    .append(
      User(
        UserMessage(
          "run moon check and moon test with @string.from_str and @argparse.command try?",
        ),
      ),
    )
    .append(Terminal(Finished("done")))
  let result = eval_session_for_test(session)
  assert_true(result.success)
  assert_eq(result.moon_check_uses, 0)
  assert_eq(result.moon_test_uses, 0)
  assert_eq(result.from_str_mentions, 0)
  assert_eq(result.old_argparse_mentions, 0)
  assert_eq(result.try_mentions, 0)
}

///|
test "latest non-finished terminal determines success" {
  let session = @agent_session.Session(
      SessionId("multi-turn"),
      system_prompt="",
    )
    .append(User(UserMessage("first")))
    .append(Terminal(Finished("done")))
    .append(User(UserMessage("second")))
    .append(Terminal(Failed("agent failed")))
  let result = eval_session_for_test(session)
  assert_false(result.success)
  assert_false(result.finished)
  assert_eq(result.terminal_status, "failed")
  assert_true(result.reason.contains("agent terminal failed"))
}

///|
test "finish tool terminal does not double count a model step" {
  let session = @agent_session.Session(
      SessionId("trial-finish"),
      system_prompt="",
    )
    .append(User(UserMessage("finish")))
    .append(
      Assistant(
        AssistantMessage("", tool_calls=[
          ToolCall(
            id="call_finish",
            name="finish",
            arguments="{\"answer\":\"done\"}",
          ),
        ]),
      ),
    )
    .append(
      Tool(
        ToolResult(
          tool_call_id="call_finish",
          tool_name="finish",
          content="finished: done",
        ),
      ),
    )
    .append(Terminal(Finished("done")))
  let result = eval_session_for_test(session)
  assert_eq(result.steps, 1)
  assert_eq(result.tool_results, 1)
  assert_true(result.finished)
}

///|
test "same output dir preserves absolute workspace paths" {
  let manifest = RunManifest(
    model="deepseek-v4-flash",
    prompt_label="flash",
    task_file="eval/prompt_tasks/toml_parser_cli.md",
    runs=1,
    concurrency=1,
    min_successes=1,
    max_steps=160,
    out_dir=".moonagent/eval_runs/default",
    trials=[
      TrialArtifact(
        index=1,
        workspace="/tmp/openseek/.moonagent/eval_runs/default/workspaces/01",
        log_path=".moonagent/eval_runs/default/logs/01.log",
        session_id="trial-01",
        events_path="/tmp/openseek/.moonagent/eval_runs/default/workspaces/01/.openseek/sessions/trial-01/events.jsonl",
        exit_code=0,
      ),
    ],
  )
  let relocated = manifest_for_output_dir(
    manifest, ".moonagent/eval_runs/default",
  )
  assert_eq(
    relocated.trials[0].workspace,
    "/tmp/openseek/.moonagent/eval_runs/default/workspaces/01",
  )
}

///|
async test "analyze run writes reports to caller output directory" {
  let root = @fs.tmpdir(prefix="openseek-prompt-analyze-out")
  let out_dir = root + "/actual"
  let stale_dir = root + "/stale"
  @fs.mkdir(out_dir, recursive=true)
  let actual_events_path = out_dir +
    "/workspaces/01/.openseek/sessions/trial-01/events.jsonl"
  let stale_events_path = stale_dir +
    "/workspaces/01/.openseek/sessions/trial-01/events.jsonl"
  @fs.mkdir(
    out_dir + "/workspaces/01/.openseek/sessions/trial-01",
    recursive=true,
  )
  @fs.mkdir(
    stale_dir + "/workspaces/01/.openseek/sessions/trial-01",
    recursive=true,
  )
  @fs.write_file(
    actual_events_path,
    assistant_events("trial-01", "I used @string.parse_int"),
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    stale_events_path,
    assistant_events("trial-01", "I only used moon test"),
    create_mode=CreateOrTruncate,
  )
  let manifest_json : Json = {
    "model": "deepseek-v4-flash",
    "prompt_label": "flash",
    "task_file": "eval/prompt_tasks/toml_parser_cli.md",
    "runs": 0,
    "concurrency": 1,
    "min_successes": 0,
    "max_steps": 160,
    "out_dir": stale_dir,
    "trials": (
      [
        {
          "index": 1,
          "workspace": stale_dir + "/workspaces/01",
          "log_path": stale_dir + "/logs/01.log",
          "session_id": "trial-01",
          "events_path": stale_events_path,
          "exit_code": 0,
        },
      ] : Json),
  }
  @fs.write_file(
    manifest_path(out_dir),
    manifest_json.stringify(),
    create_mode=CreateOrTruncate,
  )
  let report = analyze_run(out_dir)
  assert_eq(report.out_dir, out_dir)
  assert_eq(report.results[0].workspace, out_dir + "/workspaces/01")
  assert_eq(report.results[0].events_path, actual_events_path)
  assert_false(report.results[0].workspace.contains(stale_dir))
  assert_eq(report.results[0].parse_int_mentions, 1)
  assert_eq(report.results[0].moon_test_uses, 0)
  assert_true(@fs.exists(out_dir + "/report.md"))
  assert_true(@fs.exists(out_dir + "/report.html"))
  assert_false(@fs.exists(stale_dir + "/report.md"))
  @fs.rmdir(root, recursive=true)
}

///|
test "json stdout probe accepts valid json only" {
  assert_true(json_stdout_probe(0, "{\"a\":1}\n", "").passed)
  let invalid = json_stdout_probe(0, "not-json\n", "")
  assert_false(invalid.passed)
  assert_true(invalid.reason.contains("stdout is not JSON"))
}

///|
test "markdown report includes prompt label and parser metrics" {
  let report : EvalReport = {
    model: "deepseek-v4-flash",
    prompt_label: "flash",
    task_file: "eval/prompt_tasks/toml_parser_cli.md",
    runs: 1,
    concurrency: 1,
    min_successes: 1,
    successes: 1,
    out_dir: "out",
    results: [
      {
        index: 1,
        prompt_label: "flash",
        success: true,
        reason: "ok",
        workspace: "ws",
        log_path: "log",
        session_id: "trial-01",
        events_path: "events",
        exit_code: 0,
        steps: 1,
        tool_results: 1,
        tool_errors: 0,
        shell_uses: 0,
        shell_failures: 0,
        runtime_notices: 0,
        finished: true,
        finish_message: "done",
        terminal_status: "finished",
        terminal_message: "done",
        validation: {
          ran: true,
          passed: true,
          reason: "ok",
          moon_check: true,
          moon_test: true,
          file_probe: true,
          stdin_probe: true,
          duplicate_probe: true,
        },
        parse_errors: 0,
        partial_tail: false,
        moon_check_uses: 1,
        moon_test_uses: 1,
        moon_run_e_mentions: 1,
        moon_run_c_mentions: 0,
        bad_run_e_mentions: 0,
        from_str_mentions: 1,
        parse_int_mentions: 0,
        argparse_mentions: 1,
        old_argparse_mentions: 0,
        c_ffi_mentions: 0,
        env_args_mentions: 0,
        result_style_mentions: 0,
        try_mentions: 0,
        warnings: "",
      },
    ],
  }
  let text = report.markdown()
  assert_true(text.contains("flash"))
  assert_true(text.contains("Parse Errors"))
  assert_true(text.contains("## Trial Details"))
  assert_true(report.html().contains("<html"))
  assert_true(report.html().contains("trial-card"))
}
