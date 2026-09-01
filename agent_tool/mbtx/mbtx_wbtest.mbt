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
/// Pin the probe's per-target artifact table. The wasm row is exercised end to
/// end by the classification tests; the other rows — llvm cannot even be built
/// by this toolchain — and the release-profile fallback are pinned here with
/// fabricated artifacts in the layout moon's own build plan names.
async test "snippet_compiled reads moon's per-target runnable artifact" {
  @vfs.with_tmpdir(prefix="mbtx-artifact-probe-", dir => {
    async fn plant(parent : String, file : String) -> Unit {
      @fs.mkdir("\{dir}/\{parent}", recursive=true)
      @fs.write_file(
        "\{dir}/\{parent}/\{file}",
        "",
        create_mode=CreateOrTruncate,
      )
    }

    // A failed build's leftovers (moon writes all_pkgs.json before compiling
    // anything) are not a runnable artifact.
    plant("wasm/debug/build", "all_pkgs.json")
    assert_false(snippet_compiled(dir, "wasm"))
    plant("wasm/debug/build/single", "single.wasm")
    assert_true(snippet_compiled(dir, "wasm"))
    // Target dirs are disjoint: one target's artifact proves nothing about
    // another's.
    assert_false(snippet_compiled(dir, "wasm-gc"))
    plant("wasm-gc/debug/build/single", "single.wasm")
    assert_true(snippet_compiled(dir, "wasm-gc"))
    assert_false(snippet_compiled(dir, "js"))
    plant("js/debug/build/single", "single.js")
    assert_true(snippet_compiled(dir, "js"))
    assert_false(snippet_compiled(dir, "llvm"))
    plant("llvm/debug/build/single", "single.exe")
    assert_true(snippet_compiled(dir, "llvm"))
    // The release profile is the fallback for a future moon default flip, so a
    // release-only artifact still counts.
    plant("js/release/build/single", "single.js")
    @fs.rmdir("\{dir}/js/debug", recursive=true)
    assert_true(snippet_compiled(dir, "js"))
  })
}

///|
/// The body/brief framing names the failure stage. A compile error drops the
/// exit code — moon's is always 1 there and says nothing the diagnostics do
/// not — while a runtime failure keeps the program's own code.
test "finished_body and finished_brief name the failure stage" {
  assert_eq(finished_body("out\n", 0, compiled=true), "out\n")
  assert_true(
    finished_body("", 0, compiled=true).contains("exited 0 with no output"),
  )
  let compile_error = finished_body("diagnostics", 1, compiled=false)
  assert_true(compile_error.contains("COMPILE error"))
  assert_true(compile_error.contains("never ran"))
  assert_true(compile_error.contains("diagnostics"))
  let runtime_failure = finished_body("trace", 3, compiled=true)
  assert_true(runtime_failure.contains("exited 3 at RUNTIME"))
  assert_true(runtime_failure.contains("trace"))
  // The blank-output corners still name the stage.
  assert_true(finished_body("", 1, compiled=false).contains("COMPILE error"))
  assert_true(finished_body("", 3, compiled=true).contains("exited 3"))
  assert_eq(finished_brief(1, compiled=false), "mbtx (compile error)")
  assert_eq(finished_brief(3, compiled=true), "mbtx (exit=3)")
  assert_eq(finished_brief(0, compiled=true), "mbtx (exit=0)")
}

///|
test "timeout_head says which half of the run never finished" {
  let program_hung = timeout_head(5_000, compiled=true)
  assert_true(program_hung.contains("compiled but did not finish"))
  let build_hung = timeout_head(5_000, compiled=false)
  assert_true(build_hung.contains("BUILD never completed"))
  assert_true(build_hung.contains("never ran"))
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
