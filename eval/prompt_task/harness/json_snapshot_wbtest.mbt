///|
/// The JSON these types write, pinned byte for byte: `report.json` and the
/// manifests are read by people and by `read_manifest`, so a change to the
/// encoder must show up here first.
fn snapshot_probe() -> ValidationProbeSpec {
  ValidationProbeSpec(
    name="moon check",
    command=["moon", "check", "--target", "native"],
    stdin="in",
    expect_exit=2,
    stdout_contains="ok",
    stdout_json=true,
  )
}

///|
test "manifest types serialize to their pinned shape" {
  let probe = snapshot_probe()
  let trial = TrialArtifact(
    index=1,
    workspace="ws",
    log_path="log",
    session_id="sid",
    events_path="ev",
    exit_code=0,
  )
  json_inspect(ToJson::to_json(probe), content={
    "name": "moon check",
    "command": ["moon", "check", "--target", "native"],
    "stdin": "in",
    "write_file": "",
    "write_content": "",
    "expect_exit": 2,
    "output_contains": "",
    "stdout_contains": "ok",
    "stderr_contains": "",
    "stdout_json": true,
  })
  json_inspect(ToJson::to_json(trial), content={
    "index": 1,
    "workspace": "ws",
    "log_path": "log",
    "session_id": "sid",
    "events_path": "ev",
    "exit_code": 0,
  })
  let manifest = RunManifest(
    model="m",
    problem_id="p",
    prompt_label="l",
    task_file="t",
    runs=2,
    concurrency=1,
    min_successes=1,
    max_steps=8,
    out_dir="out",
    validation_probes=[probe],
    trials=[trial],
  )
  json_inspect(ToJson::to_json(manifest), content={
    "model": "m",
    "problem_id": "p",
    "prompt_label": "l",
    "task_file": "t",
    "runs": 2,
    "concurrency": 1,
    "min_successes": 1,
    "max_steps": 8,
    "out_dir": "out",
    "validation_probes": [
      {
        "name": "moon check",
        "command": ["moon", "check", "--target", "native"],
        "stdin": "in",
        "write_file": "",
        "write_content": "",
        "expect_exit": 2,
        "output_contains": "",
        "stdout_contains": "ok",
        "stderr_contains": "",
        "stdout_json": true,
      },
    ],
    "trials": [
      {
        "index": 1,
        "workspace": "ws",
        "log_path": "log",
        "session_id": "sid",
        "events_path": "ev",
        "exit_code": 0,
      },
    ],
  })
}

///|
test "suite types serialize to their pinned shape" {
  let probe = snapshot_probe()
  let problem = ProblemSpec(id="p", task_file="t", validation_probes=[probe])
  let combo = ComboRun(
    model="m",
    problem_id="p",
    prompt_label="l",
    task_file="t",
    out_dir="o",
    manifest_path="mp",
  )
  json_inspect(ToJson::to_json(combo), content={
    "model": "m",
    "problem_id": "p",
    "prompt_label": "l",
    "task_file": "t",
    "out_dir": "o",
    "manifest_path": "mp",
  })
  let suite = SuiteManifest(
    name="n",
    out_dir="o",
    runs_per_combo=2,
    concurrency=1,
    min_successes=1,
    max_steps=8,
    models=["m"],
    problems=[problem],
    combos=[combo],
  )
  json_inspect(ToJson::to_json(suite), content={
    "name": "n",
    "out_dir": "o",
    "runs_per_combo": 2,
    "concurrency": 1,
    "min_successes": 1,
    "max_steps": 8,
    "models": ["m"],
    "problems": [
      {
        "id": "p",
        "prompt_label": "p",
        "task_file": "t",
        "validation_probes": [
          {
            "name": "moon check",
            "command": ["moon", "check", "--target", "native"],
            "stdin": "in",
            "write_file": "",
            "write_content": "",
            "expect_exit": 2,
            "output_contains": "",
            "stdout_contains": "ok",
            "stderr_contains": "",
            "stdout_json": true,
          },
        ],
      },
    ],
    "combos": [
      {
        "model": "m",
        "problem_id": "p",
        "prompt_label": "l",
        "task_file": "t",
        "out_dir": "o",
        "manifest_path": "mp",
      },
    ],
  })
}

///|
test "report result types serialize to their pinned shape" {
  let probe = ProbeResult(name="file", passed=true, reason="ok")
  let validation : ValidationResult = {
    ran: true,
    passed: false,
    reason: "r",
    moon_check: true,
    moon_test: false,
    file_probe: true,
    stdin_probe: false,
    duplicate_probe: true,
    probes: [probe],
  }
  let result : EvalResult = {
    index: 3,
    prompt_label: "l",
    success: false,
    reason: "why",
    workspace: "ws",
    log_path: "log",
    session_id: "sid",
    events_path: "ev",
    exit_code: 1,
    steps: 4,
    tool_results: 5,
    tool_errors: 6,
    runtime_notices: 7,
    finished: true,
    finish_message: "done",
    terminal_status: "finished",
    terminal_message: "msg",
    validation,
    parse_errors: 8,
    partial_tail: false,
    moon_check_uses: 9,
    moon_test_uses: 10,
    moon_run_e_mentions: 11,
    moon_run_c_mentions: 12,
    bad_run_e_mentions: 13,
    from_str_mentions: 14,
    parse_int_mentions: 15,
    argparse_mentions: 16,
    old_argparse_mentions: 17,
    c_ffi_mentions: 18,
    env_args_mentions: 19,
    result_style_mentions: 20,
    try_mentions: 21,
    warnings: "w",
  }
  json_inspect(ToJson::to_json(probe), content={
    "name": "file",
    "passed": true,
    "reason": "ok",
  })
  json_inspect(ToJson::to_json(result), content={
    "index": 3,
    "prompt_label": "l",
    "success": false,
    "reason": "why",
    "workspace": "ws",
    "log_path": "log",
    "session_id": "sid",
    "events_path": "ev",
    "exit_code": 1,
    "steps": 4,
    "tool_results": 5,
    "tool_errors": 6,
    "runtime_notices": 7,
    "finished": true,
    "finish_message": "done",
    "terminal_status": "finished",
    "terminal_message": "msg",
    "validation": {
      "ran": true,
      "passed": false,
      "reason": "r",
      "moon_check": true,
      "moon_test": false,
      "file_probe": true,
      "stdin_probe": false,
      "duplicate_probe": true,
      "probes": [{ "name": "file", "passed": true, "reason": "ok" }],
    },
    "parse_errors": 8,
    "partial_tail": false,
    "moon_check_uses": 9,
    "moon_test_uses": 10,
    "moon_run_e_mentions": 11,
    "moon_run_c_mentions": 12,
    "bad_run_e_mentions": 13,
    "from_str_mentions": 14,
    "parse_int_mentions": 15,
    "argparse_mentions": 16,
    "old_argparse_mentions": 17,
    "c_ffi_mentions": 18,
    "env_args_mentions": 19,
    "result_style_mentions": 20,
    "try_mentions": 21,
    "warnings": "w",
  })
}
