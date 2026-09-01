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
/// Pin the probe's per-target evidence table: the runnable artifact decides
/// run-stage, moon's `all_pkgs.json` residue is what a failed build leaves,
/// and a bare tree claims nothing. The wasm row is exercised end to end by
/// the classification tests; the other rows — llvm cannot even be built by
/// this toolchain — and the release-profile fallback are pinned here with
/// fabricated files in the layout moon's own build plan names.
async test "snippet_compiled reads moon's per-target build evidence" {
  @vfs.with_tmpdir(prefix="mbtx-artifact-probe-", dir => {
    async fn plant(parent : String, file : String) -> Unit {
      @fs.mkdir("\{dir}/\{parent}", recursive=true)
      @fs.write_file(
        "\{dir}/\{parent}/\{file}",
        "",
        create_mode=CreateOrTruncate,
      )
    }

    // An empty tree claims nothing: moon can fail before writing anything
    // (a dependency-resolution fault leaves the dir bare), and a wiped tree
    // must not read as "build failed".
    assert_true(snippet_compiled(dir, "wasm") is None)
    // moon's plan file without the artifact is a failed build...
    plant("wasm/debug/build", "all_pkgs.json")
    assert_true(snippet_compiled(dir, "wasm") is Some(false))
    // ...and the artifact decides run-stage.
    plant("wasm/debug/build/single", "single.wasm")
    assert_true(snippet_compiled(dir, "wasm") is Some(true))
    // Target dirs are disjoint: one target's evidence proves nothing about
    // another's.
    assert_true(snippet_compiled(dir, "wasm-gc") is None)
    plant("wasm-gc/debug/build", "all_pkgs.json")
    assert_true(snippet_compiled(dir, "wasm-gc") is Some(false))
    plant("wasm-gc/debug/build/single", "single.wasm")
    assert_true(snippet_compiled(dir, "wasm-gc") is Some(true))
    assert_true(snippet_compiled(dir, "js") is None)
    plant("js/debug/build", "all_pkgs.json")
    assert_true(snippet_compiled(dir, "js") is Some(false))
    plant("js/debug/build/single", "single.js")
    assert_true(snippet_compiled(dir, "js") is Some(true))
    assert_true(snippet_compiled(dir, "llvm") is None)
    plant("llvm/debug/build", "all_pkgs.json")
    assert_true(snippet_compiled(dir, "llvm") is Some(false))
    plant("llvm/debug/build/single", "single.exe")
    assert_true(snippet_compiled(dir, "llvm") is Some(true))
    // The release profile is the fallback for a future moon default flip, so a
    // release-only artifact still counts.
    plant("js/release/build/single", "single.js")
    @fs.rmdir("\{dir}/js/debug", recursive=true)
    assert_true(snippet_compiled(dir, "js") is Some(true))
    // Wiping a target's whole tree UNclassifies it — the sabotage direction
    // can only remove a label, never flip one stage's label to the other's.
    @fs.rmdir("\{dir}/wasm", recursive=true)
    assert_true(snippet_compiled(dir, "wasm") is None)
  })
}

///|
/// The body/brief framing names the failure stage. A build failure drops the
/// exit code — moon's is always 1 there and says nothing the diagnostics do
/// not — while a runtime failure keeps the program's own code, and an unknown
/// probe result keeps the pre-classification wording, claiming nothing.
test "finished_body and finished_brief name the failure stage" {
  assert_eq(finished_body("out\n", 0, compiled=Some(true)), "out\n")
  assert_true(
    finished_body("", 0, compiled=Some(true)).contains(
      "exited 0 with no output",
    ),
  )
  // The build's exit status is preserved: moon is NOT always 1 here (a
  // dependency-cache fault exits 255), and distinct codes are diagnostic.
  let build_failed = finished_body("diagnostics", 1, compiled=Some(false))
  assert_true(build_failed.contains("BUILD failed (exit 1)"))
  assert_true(build_failed.contains("never ran"))
  assert_true(build_failed.contains("diagnostics"))
  assert_true(
    finished_body("lock fault", 255, compiled=Some(false)).contains(
      "BUILD failed (exit 255)",
    ),
  )
  // The run-side wording claims exactly what presence proves: the build
  // completed — not that the program itself launched (a missing runner also
  // lands here, and is likewise not a `source` problem).
  let runtime_failure = finished_body("trace", 3, compiled=Some(true))
  assert_true(runtime_failure.contains("exited 3 at RUNTIME"))
  assert_true(runtime_failure.contains("from the run, not the build"))
  assert_true(runtime_failure.contains("trace"))
  // The blank-output corners still name the stage.
  assert_true(
    finished_body("", 1, compiled=Some(false)).contains("BUILD failed"),
  )
  assert_true(finished_body("", 3, compiled=Some(true)).contains("exited 3"))
  // An unknown probe result claims no stage in either direction.
  let unknown = finished_body("out", 3, compiled=None)
  assert_true(unknown.contains("exited 3"))
  assert_false(unknown.contains("BUILD failed"))
  assert_false(unknown.contains("RUNTIME"))
  assert_eq(
    finished_brief(1, compiled=Some(false)),
    "mbtx (build failed, exit=1)",
  )
  assert_eq(
    finished_brief(255, compiled=Some(false)),
    "mbtx (build failed, exit=255)",
  )
  assert_eq(finished_brief(3, compiled=Some(true)), "mbtx (exit=3)")
  assert_eq(finished_brief(3, compiled=None), "mbtx (exit=3)")
  assert_eq(finished_brief(0, compiled=Some(true)), "mbtx (exit=0)")
}

///|
test "timeout_head says which half of the run never finished" {
  let program_hung = timeout_head(5_000, compiled=Some(true))
  assert_true(
    program_hung.contains("BUILD completed but the run did not finish"),
  )
  let build_hung = timeout_head(5_000, compiled=Some(false))
  assert_true(build_hung.contains("BUILD never completed"))
  assert_true(build_hung.contains("never ran"))
  // The probe failing keeps the original both-ways hedge.
  let unknown = timeout_head(5_000, compiled=None)
  assert_true(unknown.contains("a build that never completed"))
}

///|
/// Proton CLI is admitted one subcommand at a time. In particular, there is no
/// bare rule and no global working-directory prefix: callers set the child
/// process cwd instead of letting the command redirect itself elsewhere.
test "the spawn policy admits Proton subcommands but not global cwd options" {
  let proton_prefixes : Array[Array[String]] = []
  for entry in spawnable_commands {
    let (program, args_prefix) = entry
    if program == "proton_cli" {
      proton_prefixes.push(args_prefix)
    }
  }
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
  let codex_prefixes : Array[Array[String]] = []
  for entry in spawnable_commands {
    let (program, args_prefix) = entry
    if program == "codex" {
      codex_prefixes.push(args_prefix)
    }
  }
  assert_eq(codex_prefixes.length(), 1)
  assert_eq(codex_prefixes[0], ["review"])
  assert_false(codex_prefixes.contains([]))
  assert_false(codex_prefixes.contains(["exec"]))
  assert_false(codex_prefixes.contains(["install"]))
}
