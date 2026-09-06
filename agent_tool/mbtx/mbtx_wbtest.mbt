///|
/// The denial scan runs after the run's deadline has expired, so its work must
/// stay bounded however hard a snippet flooded: an over-budget log is scanned
/// at its head and tail only. With a tiny test budget, a denial in either
/// scanned region is found; one buried in the skipped middle is (by design)
/// not; a log within budget is scanned whole.
async test "denial scan is bounded to the log's head and tail" {
  @vfs.with_tmpdir(prefix="mbtx-denial-scan-", dir => {
    let denial = "sh: main.mbt: Operation not permitted\n"
    let filler_line = "\{String::make(63, 'x')}\n"
    fn filler(lines : Int) -> String {
      let out = StringBuilder()
      for _ in 0..<lines {
        out.write_string(filler_line)
      }
      out.to_string()
    }

    async fn scan(name : String, content : String) -> Bool {
      let path = "\{dir}/\{name}.log"
      @fs.write_file(path, content, create_mode=CreateOrTruncate)
      log_shows_denial(
        path,
        text => text.contains("main.mbt: Operation not permitted"),
        budget_bytes=1024,
      )
    }

    // within budget (<= 2KB): scanned whole, wherever the denial sits
    assert_true(scan("small", filler(10) + denial + filler(10)))
    // over budget: the head region sees a leading denial
    assert_true(scan("head", denial + filler(64)))
    // over budget: the tail region sees a trailing denial
    assert_true(scan("tail", filler(64) + denial))
    // over budget with the denial only in the skipped middle: missed by design
    assert_false(scan("middle", filler(20) + denial + filler(20)))
    // no denial at all
    assert_false(scan("clean", filler(64)))
  })
}

///|
/// The build phase's artifact report is moon's own `{"artifacts_path":[…]}`
/// line: the tool takes the LAST well-formed one (a child moon invocation
/// cannot print into the build phase's dedicated log, so lines here are the
/// outer build's) and assumes no target-dir layout when it is present.
test "parse_artifacts_path reads moon's report line" {
  assert_true(
    parse_artifacts_path(
      "Downloading x@1.0\n{\"artifacts_path\":[\"/tmp/b/wasm/debug/build/single/single.wasm\"]}\n",
    )
    is Some("/tmp/b/wasm/debug/build/single/single.wasm"),
  )
  // The last report wins; malformed candidates are skipped, not fatal.
  let two = "{\"artifacts_path\":[\"/old\"]}\n{\"artifacts_path\":\"garbage\"\n{\"artifacts_path\":[\"/new\"]}"
  assert_true(parse_artifacts_path(two) is Some("/new"))
  assert_true(parse_artifacts_path("no report here\n") is None)
  assert_true(parse_artifacts_path("{\"artifacts_path\":[]}") is None)
}

///|
test "strip_artifact_report keeps only the human-facing build output" {
  let mixed = "Warning: [0002] unused\n{\"artifacts_path\":[\"/x\"]}\n"
  assert_eq(strip_artifact_report(mixed), "Warning: [0002] unused")
  assert_eq(strip_artifact_report("{\"artifacts_path\":[\"/x\"]}\n"), "")
}

///|
/// Build notes are bounded so the prepend cannot spend the margin between the
/// run's 48KB output cap and the agent loop's 60k tail-cutting clamp — the
/// margin that keeps the trailing stop/retry and sandbox guidance readable.
test "cap_build_notes bounds a warning flood and marks the cut" {
  assert_eq(cap_build_notes("short"), "short")
  let flood = String::make(20_000, 'w')
  let capped = cap_build_notes(flood)
  assert_true(capped.length() < 9_000)
  assert_true(capped.contains("build warnings truncated"))
}

///|
/// The run-phase framing: on the staged wasm path a failure is from the run
/// by construction and says so; single-shot targets keep the plain wording
/// that claims neither stage.
test "finished_body and timeout_head are stage-aware only when staged" {
  assert_eq(finished_body("out\n", 0, staged=true), "out\n")
  let staged_failure = finished_body("trace", 3, staged=true)
  assert_true(staged_failure.contains("exited 3 at RUNTIME"))
  assert_true(staged_failure.contains("from the run, not the build"))
  assert_true(
    finished_body("", 3, staged=true).contains(
      "the build succeeded, then the run exited 3",
    ),
  )
  let plain_failure = finished_body("trace", 3, staged=false)
  assert_true(plain_failure.contains("exited 3"))
  assert_false(plain_failure.contains("RUNTIME"))
  assert_true(
    timeout_head(5_000, staged=true).contains("the PROGRAM that did not finish"),
  )
  assert_true(
    timeout_head(5_000, staged=false).contains("a build that never completed"),
  )
  assert_eq(with_build_notes("", "body"), "body")
  assert_eq(with_build_notes("warn", "body"), "warn\nbody")
}

///|
/// The argument prefixes the spawn allowlist admits for `program`, in the
/// order `spawnable_commands` lists them.
fn spawn_prefixes(program : String) -> Array[Array[String]] {
  [
    for entry in spawnable_commands if entry.0 == program => entry.1
  ]
}

///|
/// Proton CLI is admitted one subcommand at a time. In particular, there is no
/// bare rule and no global working-directory prefix: callers set the child
/// process cwd instead of letting the command redirect itself elsewhere.
test "the spawn policy admits Proton subcommands but not global cwd options" {
  let proton_prefixes = spawn_prefixes("proton_cli")
  assert_eq(proton_prefixes.length(), 9)
  for
    args_prefix in [
      ["--version"],
      ["--help"],
      ["new"],
      ["dev"],
      ["build"],
      ["package"],
      ["doctor"],
      ["cef"],
      ["updater"],
    ] {
    assert_true(proton_prefixes.contains(args_prefix))
  }
  assert_false(proton_prefixes.contains([]))
  assert_false(proton_prefixes.contains(["-C"]))
  assert_false(proton_prefixes.contains(["--cwd"]))
}

// The spawn allowlist is taught by each role's system prompt now, and that
// prose is NOT pinned by a test: asserting a prompt contains particular words
// only breaks on rewrites. Keeping the list and the prompts in step is a
// review-time job, not a test-time one.

///|
/// Codex CLI is admitted one verb only: the read-only `review`. There is no
/// bare rule and no verb that runs or installs an agent (`exec`, `install`),
/// so the prefix gating keeps the agentic binary's surface to review.
test "the spawn policy admits only the codex review verb" {
  let codex_prefixes = spawn_prefixes("codex")
  assert_eq(codex_prefixes.length(), 1)
  assert_eq(codex_prefixes[0], ["review"])
  assert_false(codex_prefixes.contains([]))
  assert_false(codex_prefixes.contains(["exec"]))
  assert_false(codex_prefixes.contains(["install"]))
}
