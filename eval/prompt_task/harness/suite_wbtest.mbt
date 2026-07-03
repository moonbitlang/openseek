///|
fn simple_probe(name : String) -> ValidationProbeSpec {
  ValidationProbeSpec(name~, command=["moon", "--version"])
}

///|
fn suite_config_json() -> Json {
  {
    "name": "mini-suite",
    "models": ["deepseek-v4-flash", "deepseek-v4-pro"],
    "runs_per_combo": 3,
    "concurrency": 5,
    "min_successes": 0,
    "max_steps": 20,
    "problems": [
      {
        "id": "alpha",
        "task_file": "tasks/alpha.md",
        "validation_probes": [
          { "name": "moon check", "command": ["moon", "--version"] },
        ],
      },
      {
        "id": "beta",
        "prompt_label": "Beta Problem",
        "task_file": "tasks/beta.md",
        "validation_probes": [
          { "name": "moon test", "command": ["moon", "--version"] },
        ],
      },
    ],
  }
}

///|
async test "suite config parses relative task paths and flattens jobs" {
  @vfs.with_tmpdir(prefix="openseek-prompt-suite-config", root => {
    @fs.mkdir(root + "/suite", recursive=true)
    let suite_file = root + "/suite/suite.json"
    @fs.write_file(
      suite_file,
      suite_config_json().stringify(),
      create_mode=CreateOrTruncate,
    )
    let config = suite_config_from_file(
      suite_file,
      api_key="key",
      out_dir=root + "/runs",
      repo_root=".",
      engine="",
      system_prompt_file="",
      system_prompt_addendum_file="",
    )
    assert_eq(config.name, "mini-suite")
    assert_eq(config.models.length(), 2)
    assert_eq(config.problems.length(), 2)
    assert_eq(config.problems[0].task_file, root + "/suite/tasks/alpha.md")
    assert_eq(config.problems[1].prompt_label, "Beta Problem")
    let jobs = suite_jobs(config)
    assert_eq(jobs.length(), 12)
    assert_eq(jobs[0].model.to_string(), "deepseek-v4-flash")
    assert_eq(jobs[0].problem.id, "alpha")
    assert_eq(jobs[0].repeat_index, 0)
    assert_eq(jobs[3].problem.id, "beta")
    assert_eq(jobs[6].model.to_string(), "deepseek-v4-pro")
  })
}

///|
async test "suite manifest round trips combos" {
  @vfs.with_tmpdir(prefix="openseek-prompt-suite-manifest", root => {
    let manifest = SuiteManifest(
      name="mini-suite",
      out_dir=root,
      runs_per_combo=1,
      concurrency=1,
      min_successes=0,
      max_steps=20,
      models=["deepseek-v4-flash"],
      problems=[
        ProblemSpec(id="alpha", task_file="tasks/alpha.md", validation_probes=[
          simple_probe("moon check"),
        ]),
      ],
      combos=[
        ComboRun(
          model="deepseek-v4-flash",
          problem_id="alpha",
          prompt_label="alpha:deepseek-v4-flash",
          task_file="tasks/alpha.md",
          out_dir=root + "/combos/deepseek-v4-flash/alpha",
          manifest_path=root +
            "/combos/deepseek-v4-flash/alpha/run_manifest.json",
        ),
      ],
    )
    write_suite_manifest(manifest)
    let loaded = read_suite_manifest(root)
    assert_eq(loaded.name, "mini-suite")
    assert_eq(loaded.combos.length(), 1)
    assert_eq(loaded.combos[0].problem_id, "alpha")
    assert_eq(loaded.problems[0].validation_probes[0].name, "moon check")
  })
}

///|
test "suite manifest relocates combo paths to caller output dir" {
  let manifest = SuiteManifest(
    name="mini-suite",
    out_dir="/old/suite",
    runs_per_combo=1,
    concurrency=1,
    min_successes=0,
    max_steps=20,
    models=["deepseek-v4-flash"],
    problems=[
      ProblemSpec(id="alpha", task_file="tasks/alpha.md", validation_probes=[
        simple_probe("moon check"),
      ]),
    ],
    combos=[
      ComboRun(
        model="deepseek-v4-flash",
        problem_id="alpha",
        prompt_label="alpha:deepseek-v4-flash",
        task_file="tasks/alpha.md",
        out_dir="/old/suite/combos/deepseek-v4-flash/alpha",
        manifest_path="/old/suite/combos/deepseek-v4-flash/alpha/run_manifest.json",
      ),
    ],
  )
  let relocated = suite_manifest_for_output_dir(manifest, "/new/suite")
  assert_eq(relocated.out_dir, "/new/suite")
  assert_eq(
    relocated.combos[0].out_dir,
    "/new/suite/combos/deepseek-v4-flash/alpha",
  )
  assert_eq(
    relocated.combos[0].manifest_path,
    "/new/suite/combos/deepseek-v4-flash/alpha/run_manifest.json",
  )
}

///|
fn validation_for_suite_test(passed : Bool) -> ValidationResult {
  {
    ran: true,
    passed,
    reason: if passed {
      "ok"
    } else {
      "moon check: failed"
    },
    moon_check: passed,
    moon_test: false,
    file_probe: false,
    stdin_probe: false,
    duplicate_probe: false,
    probes: [ProbeResult(name="moon check", passed~, reason="ok")],
  }
}

///|
fn eval_result_for_suite_test(index : Int, success : Bool) -> EvalResult {
  {
    index,
    prompt_label: "alpha:deepseek-v4-flash",
    success,
    reason: if success {
      "ok"
    } else {
      "validation failed"
    },
    workspace: "out/workspaces/" + padded_index(index),
    log_path: "out/logs/" + padded_index(index) + ".log",
    session_id: "trial-" + padded_index(index),
    events_path: "out/workspaces/" +
    padded_index(index) +
    "/.openseek/sessions/trial-" +
    padded_index(index) +
    "/openseek_session-trial-" +
    padded_index(index) +
    ".jsonl",
    exit_code: 0,
    steps: index * 2,
    tool_results: index,
    tool_errors: if success {
      0
    } else {
      1
    },
    shell_uses: index,
    shell_failures: if success {
      0
    } else {
      1
    },
    runtime_notices: 0,
    finished: success,
    finish_message: if success {
      "done"
    } else {
      ""
    },
    terminal_status: if success {
      "finished"
    } else {
      "failed"
    },
    terminal_message: if success {
      "done"
    } else {
      "failed"
    },
    validation: validation_for_suite_test(success),
    parse_errors: 0,
    partial_tail: false,
    moon_check_uses: 1,
    moon_test_uses: 0,
    moon_run_e_mentions: 0,
    moon_run_c_mentions: 0,
    bad_run_e_mentions: 0,
    from_str_mentions: 0,
    parse_int_mentions: 0,
    argparse_mentions: 0,
    old_argparse_mentions: 0,
    c_ffi_mentions: 0,
    env_args_mentions: 0,
    result_style_mentions: 0,
    try_mentions: 0,
    warnings: "",
  }
}

///|
test "suite report renders markdown and html from shared report frontend" {
  let combo = {
    model: "deepseek-v4-flash",
    prompt_label: "alpha:deepseek-v4-flash",
    task_file: "tasks/alpha.md",
    runs: 2,
    concurrency: 5,
    min_successes: 1,
    successes: 1,
    out_dir: "suite/combos/deepseek-v4-flash/alpha",
    results: [
      eval_result_for_suite_test(1, true),
      eval_result_for_suite_test(2, false),
    ],
  }
  let suite = SuiteReport(
    name="mini-suite",
    out_dir="suite",
    runs_per_combo=2,
    concurrency=5,
    reports=[combo],
  )
  assert_true(suite.passed())
  let markdown = suite.markdown()
  assert_true(markdown.contains("Prompt Task Suite Eval"))
  assert_true(markdown.contains("alpha"))
  assert_true(markdown.contains("Avg Steps"))
  let html = suite.html()
  assert_true(html.contains("<html"))
  assert_true(html.contains("trial-card"))
}
