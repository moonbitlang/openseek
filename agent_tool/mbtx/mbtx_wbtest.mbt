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
