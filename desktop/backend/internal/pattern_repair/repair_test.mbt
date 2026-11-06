///|
fn request(root : String) -> @protocol.PatternRepairPayload {
  {
    root,
    generation: 7,
    pattern: "foo($x",
    instruction: "Repair this pattern.",
    model: "fixture-model",
    thinking: Some(ThinkingHigh),
  }
}

///|
async test "repair preserves unavailable and invalid-root outcomes" {
  let provider = @search.SemanticProvider(
    engine="unused",
    runtime_dir=None,
    source=External,
  )
  // Engine availability precedes root validation, as in the host operation.
  let payload = request("relative")
  assert_eq(@pattern_repair.repair("", provider, {}, payload), {
    root: payload.root,
    generation: payload.generation,
    candidate_pattern: None,
    validation_status: Unavailable,
    message: "Pattern Repair Agent is unavailable.",
    trace: [],
  })
  try @pattern_repair.repair("unused", provider, {}, payload) catch {
    error => assert_eq(error.to_string(), "path is not absolute")
  } noraise {
    _ => fail("an invalid root must fail the request")
  }
}

///|
async test "repair reports provider preparation failure in the reply" {
  let dir = @pathx.Path(@fs.tmpdir(prefix="openseek-repair-provider-")).resolve()
  defer @fs.rmdir(dir.to_string(), recursive=true)
  let provider = @search.SemanticProvider(
    engine="unused",
    runtime_dir=None,
    source=Bundled(platform="fixture", seed_dir=dir),
  )
  let payload = request(dir.resource_path())
  let reply = @pattern_repair.repair("unused", provider, {}, payload)
  assert_eq(reply.root, payload.root)
  assert_eq(reply.generation, payload.generation)
  assert_true(reply.validation_status is Failed)
  assert_eq(reply.candidate_pattern, None)
  assert_true(
    reply.message.has_prefix("Cannot prepare semantic-search provider: "),
  )
  assert_eq(reply.trace, [])
}

///|
// These executable fixtures exercise the public operation without a model,
// registry access, or mutations to the test process's environment.
#cfg(not(platform="windows"))
async fn with_repair_fixture(
  body : async (
    String,
    @search.SemanticProvider,
    Map[String, String],
    @protocol.PatternRepairPayload,
    String,
  ) -> Unit,
) -> Unit {
  let dir = @fs.realpath(@fs.tmpdir(prefix="openseek-repair-fixture-"))
  defer @fs.rmdir(dir, recursive=true)
  let seed = "\{dir}/seed"
  @fs.mkdir("\{seed}/bin", recursive=true)
  @fs.mkdir("\{seed}/lib/core", recursive=true)
  @fs.write_file("\{seed}/.openseek-moonbit-seed-version", "fixture")
  // The fixture's moon only handles the resolver's bundle preparation.
  @fs.write_file("\{seed}/bin/moon", "#!/bin/sh\nexit 0\n", permission=0o755)
  @fs.write_file("\{seed}/bin/moonc", "", permission=0o755)
  @fs.write_file(
    "\{seed}/bin/moonx",
    (
      #|#!/bin/sh
      #|set -eu
      #|printf '%s\n' "$@" > "$REPAIR_TEST_DIR/validation-args"
      #|printf '%s\n' "$PWD" > "$REPAIR_TEST_DIR/validation-cwd"
      #|printf '%s' "$REPAIR_TEST_DIAGNOSTIC" >&2
      #|exit "$REPAIR_TEST_VALIDATION_EXIT"
    ),
    permission=0o755,
  )
  let engine = "\{dir}/engine"
  @fs.write_file(
    engine,
    (
      #|#!/bin/sh
      #|set -eu
      #|printf '%s\n' "$@" > "$REPAIR_TEST_DIR/agent-args"
      #|printf '%s\n' "$PWD" > "$REPAIR_TEST_DIR/agent-cwd"
      #|printf '%s' "$OPENSEEK_PATTERN_REPAIR_VALIDATOR" > "$REPAIR_TEST_DIR/validator"
      #|printf '%s' "$PATH" > "$REPAIR_TEST_DIR/agent-path"
      #|IFS= read -r request
      #|printf '%s' "$request" > "$REPAIR_TEST_DIR/request"
      #|while [ "$#" -gt 0 ]; do
      #|  case "$1" in
      #|    --result-file) shift; result="$1" ;;
      #|  esac
      #|  shift
      #|done
      #|printf '%s' "$result" > "$REPAIR_TEST_DIR/result-path"
      #|case "$REPAIR_TEST_RESULT_KIND" in
      #|  file) printf '%s' "$REPAIR_TEST_RESULT" > "$result" ;;
      #|  directory) mkdir "$result" ;;
      #|esac
      #|printf '%s' "$REPAIR_TEST_STDERR" >&2
      #|exit "$REPAIR_TEST_EXIT"
    ),
    permission=0o755,
  )
  let provider = @search.SemanticProvider(
    engine~,
    runtime_dir=Some(Path("\{dir}/runtime")),
    source=Bundled(platform="fixture", seed_dir=@pathx.Path(seed).resolve()),
  )
  let env = {
    "PATH": "/usr/bin:/bin",
    "REPAIR_TEST_DIR": dir,
    "REPAIR_TEST_RESULT_KIND": "file",
    "REPAIR_TEST_RESULT": (
      #|{"version":1,"status":"completed","output":{"candidate_pattern":"foo($x)","message":"Repaired."}}
    ),
    "REPAIR_TEST_STDERR": "",
    "REPAIR_TEST_EXIT": "0",
    "REPAIR_TEST_DIAGNOSTIC": "",
    "REPAIR_TEST_VALIDATION_EXIT": "0",
  }
  body(
    engine,
    provider,
    env,
    request(@pathx.Path(dir).resolve().resource_path()),
    dir,
  )
}

///|
#cfg(not(platform="windows"))
async test "repair runs the agent and validates its candidate through the selected provider" {
  with_repair_fixture((engine, provider, env, payload, dir) => {
    let reply = @pattern_repair.repair(engine, provider, env, payload)
    assert_eq(reply, {
      root: payload.root,
      generation: payload.generation,
      candidate_pattern: Some("foo($x)"),
      validation_status: Passed,
      message: "Repaired.",
      trace: ["Candidate submitted"],
    })
    let result_path = @fs.read_file("\{dir}/result-path").text()
    assert_true(!@fs.exists(@pathx.Path(result_path).dirname().to_string()))
    assert_eq(
      @fs.read_file("\{dir}/agent-args").text(),
      [
        "run",
        "--input-format",
        "json",
        "--cancel-on-stdin-eof",
        "--kind",
        "pattern-repair",
        "--result-file",
        result_path,
        "--session",
        "pattern-repair",
        "--session-root",
        @pathx.Path(result_path).dirname().join("sessions").to_string(),
        "--model",
        "fixture-model",
        "--thinking",
        "high",
        "",
      ].join("\n"),
    )
    let input = @json.parse(@fs.read_file("\{dir}/request").text())
    let run = @openseek_protocol.parse_run_request(input)
    assert_eq(run.kind, Some("pattern-repair"))
    assert_eq(run.input, {
      "pattern": payload.pattern,
      "instruction": payload.instruction,
    })
    assert_eq(@fs.read_file("\{dir}/agent-cwd").text(), "\{dir}\n")
    assert_eq(@fs.read_file("\{dir}/validation-cwd").text(), "\{dir}\n")
    let bin = "\{dir}/runtime/toolchains/moonbit/fixture/bin"
    assert_eq(@fs.read_file("\{dir}/agent-path").text(), "\{bin}:/usr/bin:/bin")
    assert_eq(@json.parse(@fs.read_file("\{dir}/validator").text()), {
      "command": "\{bin}/moonx",
      "prefix_args": [@search.MoongrepPackageCoordinate, "--"],
    })
    assert_eq(
      @fs.read_file("\{dir}/validation-args").text(),
      [
        @search.MoongrepPackageCoordinate,
        "--",
        "dump",
        "--expr",
        "foo($x)",
        "--strict-check",
        "--exit-code",
        "",
      ].join("\n"),
    )
    env["REPAIR_TEST_VALIDATION_EXIT"] = "1"
    env["REPAIR_TEST_DIAGNOSTIC"] = "  invalid candidate\n"
    let refused = @pattern_repair.repair(engine, provider, env, payload)
    assert_true(refused.validation_status is Failed)
    assert_eq(refused.candidate_pattern, Some("foo($x)"))
    assert_eq(refused.message, "invalid candidate")
    assert_eq(refused.trace, [
      "Candidate submitted", "Host validation: failed — invalid candidate",
    ])
  })
}

///|
#cfg(not(platform="windows"))
async test "repair distinguishes absent unreadable malformed and unsuccessful results" {
  with_repair_fixture((engine, provider, env, payload, dir) => {
    for
      (kind, result, stderr, code, message) in [
        (
          "absent", "", "", "0", "Pattern Repair Agent did not produce a result.",
        ),
        (
          "absent", "", "", "7", "Pattern Repair Agent process exited with code 7.",
        ),
        ("absent", "", " provider failed\n", "7", "provider failed"),
        (
          "file", "not json", "ignored", "7", "The Pattern Repair Agent's result is malformed:",
        ),
        (
          "directory", "", "ignored", "7", "The Pattern Repair Agent's result is unreadable:",
        ),
        (
          "file", "{\"version\":1,\"status\":\"no_report\"}", "ignored", "0", "Pattern Repair Agent finished without a submission.",
        ),
        (
          "file", "{\"version\":1,\"status\":\"failed\",\"reason\":\"model refused\"}",
          "ignored", "0", "model refused",
        ),
      ] {
      env["REPAIR_TEST_RESULT_KIND"] = kind
      env["REPAIR_TEST_RESULT"] = result
      env["REPAIR_TEST_STDERR"] = stderr
      env["REPAIR_TEST_EXIT"] = code
      let reply = @pattern_repair.repair(engine, provider, env, payload)
      assert_eq(reply.root, payload.root)
      assert_eq(reply.generation, payload.generation)
      assert_true(reply.validation_status is Failed)
      assert_eq(reply.candidate_pattern, None)
      assert_true(reply.message.has_prefix(message))
      assert_eq(reply.trace, [])
      let result_path = @fs.read_file("\{dir}/result-path").text()
      assert_true(!@fs.exists(@pathx.Path(result_path).dirname().to_string()))
      assert_true(!@fs.exists("\{dir}/validation-args"))
    }
  })
}
