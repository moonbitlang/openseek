///|
async fn ci_child(dir : String) -> Unit {
  let args = @env.args()
  assert_true(args is [_, "pr", "view", ..])
  assert_true(args.contains("--json") && args.contains("--repo"))
  let calls = dir + "/calls.jsonl"
  let previous = read_calls(calls)
  if !previous.is_empty() {
    assert_eq(args[3], "https://github.com/example/repo/pull/42")
  }
  append(calls, args.to_json().stringify())
  guard @json.parse(@fs.read_file(dir + "/fixture.json").text())
    is Array(sequence) &&
    !sequence.is_empty() else {
    fail("Missing fixture sequence")
  }
  let entry = sequence[Int::min(previous.length(), sequence.length() - 1)]
  match entry {
    { "raw": String(raw), .. } => println(raw)
    { "snapshot": snapshot, .. } => println(snapshot.stringify())
    _ => fail("Invalid fixture response")
  }
  if entry is { "error": True, .. } {
    fail("authentication failed")
  }
}

///|
fn check(
  state : Json,
  status? : String = "COMPLETED",
  name? : String = "build",
) -> Json {
  {
    "__typename": "CheckRun",
    "name": name,
    "status": status,
    "conclusion": state,
    "workflowName": "CI",
    "detailsUrl": "https://github.com/example/repo/actions/runs/123/job/456",
  }
}

///|
fn snapshot(
  checks : Json,
  head? : String = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
) -> Json {
  {
    "number": 42,
    "url": "https://github.com/example/repo/pull/42",
    "headRefOid": head,
    "statusCheckRollup": checks,
  }
}

///|
async fn verify_ci(root : String, temp : String, exe : String) -> Unit {
  let artifact = compile(root, temp, "ci-watch")
  let bin = temp + "/bin"
  @fs.mkdir(bin)
  @fs.symlink(target=exe, bin + "/gh")
  guard @env.get_env_var("PATH") is Some(path) else {
    fail("Test runner needs PATH for moonrun")
  }
  let passed = snapshot([check("SUCCESS")])
  let pending = snapshot([check("", status="IN_PROGRESS")])
  let context : Json = {
    "__typename": "StatusContext",
    "context": "external",
    "state": "SUCCESS",
    "targetUrl": null,
  }
  let cases : Array[(String, Array[Json], Bool, String, Bool)] = [
    ("success", [passed], true, "CI PASSED", false),
    ("current-branch", [passed], true, "CI PASSED", false),
    ("legacy-status", [snapshot([context])], true, "CI PASSED", false),
    (
      "mixed-skip",
      [snapshot([check("SUCCESS"), check("SKIPPED", name="optional")])],
      true,
      "skip=1",
      false,
    ),
    ("pending", [pending], false, "CI INCOMPLETE", false),
    ("no-checks", [snapshot([])], false, "NO CHECKS", false),
    (
      "only-skipped",
      [snapshot([check("NEUTRAL")])],
      false,
      "ONLY SKIPPED",
      false,
    ),
    (
      "unknown-state",
      [snapshot([check("NEW_STATE")])],
      false,
      "PENDING/UNKNOWN",
      false,
    ),
    ("missing-conclusion", [snapshot([check(null)])], false, "UNKNOWN", false),
    ("bad-check", [snapshot([{}])], false, "Unrecognized", false),
    ("null-rollup", [snapshot(null)], false, "Invalid CI snapshot", false),
    ("settles", [pending, passed, passed], true, "CI PASSED", true),
    (
      "late-registration",
      [snapshot([]), passed, passed],
      true,
      "CI PASSED",
      true,
    ),
    (
      "late-failure",
      [passed, snapshot([check("FAILURE")])],
      false,
      "CI FAILED",
      true,
    ),
    (
      "head-changed",
      [
        passed,
        snapshot(
          [check("SUCCESS")],
          head="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        ),
      ],
      false,
      "SUPERSEDED",
      true,
    ),
  ]
  for
    state in [
      "FAILURE", "ERROR", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE",
      "STALE",
    ] {
    cases.push(
      (state, [snapshot([check(state.to_json())])], false, "CI FAILED", false),
    )
  }
  cases.append([
    (
      "api-error",
      [{ "error": true, "snapshot": passed }],
      false,
      "CI query failed",
      false,
    ),
    (
      "bad-json",
      [{ "raw": "not json" }],
      false,
      "without a verified successful result",
      false,
    ),
    ("timeout", [pending], false, "without a verified successful result", true),
  ])
  for case in cases {
    let (name, sequence, success, expected, watch) = case
    let dir = temp + "/ci-" + name
    @fs.mkdir(dir)
    let fixture : Array[Json] = sequence.map(value => {
      if value is { "error": _, .. } || value is { "raw": _, .. } {
        value
      } else {
        { "snapshot": value }
      }
    })
    write(dir + "/fixture.json", fixture.to_json().stringify())
    let env = clean_env()
    env["PATH"] = bin + ":" + path
    env["OPENSEEK_CI_FIXTURE"] = dir
    let args = [artifact, "--"]
    if name != "current-branch" {
      args.push("42")
    }
    args.append(["--repo", "example/repo"])
    if watch {
      args.append([
        "--interval-seconds",
        "1",
        "--timeout-seconds",
        if name == "timeout" {
          "1"
        } else {
          "10"
        },
      ])
    } else {
      args.push("--once")
    }
    let result = @shell.Cmd("moonrun", args, cwd=dir, env~, inherit_env=false).output(
      timeout_ms=15000,
    )
    let output = result.stdout() + result.stderr()
    assert_eq(result.exit_code() == 0, success, msg=name + "\n" + output)
    assert_true(output.contains(expected), msg=name + "\n" + output)
    for line in result.stdout().split("\n") {
      if !line.has_prefix("{\"result\"") {
        continue
      }
      let row = @json.parse(line)
      assert_true(
        row is { "url": Null | String(_), "workflow": Null | String(_), .. },
        msg=line.to_owned(),
      )
      if row is { "result": String("FAIL"), .. } {
        assert_true(
          row
          is {
            "failure_logs_argv": [
              String("gh"),
              String("run"),
              String("view"),
              String("123"),
              String("--repo"),
              String("github.com/example/repo"),
              String("--log-failed"),
            ],
            ..
          },
          msg=line.to_owned(),
        )
      }
    }
    let count = read_calls(dir + "/calls.jsonl").length()
    match name {
      "settles" | "late-registration" => assert_eq(count, 3)
      "head-changed" => assert_eq(count, 2)
      "timeout" =>
        assert_eq(
          occurrences(output, "pass=0 skip=0 pending=1 fail=0"),
          1,
          msg=output,
        )
      _ if !watch => assert_eq(count, 1)
      _ => ()
    }
    println("ci-watch: \{name} passed")
  }
  for
    index, options in [
      ["--timeout-seconds", "0"],
      ["--interval-seconds", "9999"],
      ["--repo"],
      ["--unknown"],
    ] {
    let dir = temp + "/invalid-\{index}"
    @fs.mkdir(dir)
    let env = clean_env()
    env["PATH"] = bin + ":" + path
    env["OPENSEEK_CI_FIXTURE"] = dir
    let result = @shell.Cmd(
      "moonrun",
      [artifact, "--", ..options],
      cwd=dir,
      env~,
      inherit_env=false,
    ).output(timeout_ms=15000)
    assert_true(result.exit_code() != 0, msg=result.stdout())
    assert_false(@fs.exists(dir + "/calls.jsonl"))
  }
  println("ci-watch: invalid arguments rejected before gh")
}
