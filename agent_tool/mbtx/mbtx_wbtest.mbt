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

///|
/// The prose that teaches the spawn allowlist is RENDERED from it, so a
/// command admitted to `spawnable_commands` reaches the model without a
/// second edit. This pins that: every program and every verb in the table has
/// to appear in the rendered list, which is the property the old hand-written
/// prose could not hold — `moon --version` and `moonx` had both drifted out
/// of a copy by the time it was replaced.
///
/// The wording around the list is deliberately not asserted; that only breaks
/// on rewrites.
test "the rendered spawn list covers every admitted command" {
  for entry in spawnable_commands {
    let (program, args_prefix) = entry
    let bullet = spawn_bullet(program)
    match args_prefix {
      // A program admitted with no prefix takes any arguments; there is no
      // verb to look for.
      [] => assert_true(bullet.contains("any arguments"))
      // Checked inside this program's OWN bullet and delimited, so a dropped
      // `moon add` cannot be covered by the `add` in `worktree list|add|prune`.
      [single] => assert_true(bullet_lists_verb(bullet, single))
      // Longer prefixes are grouped under their first token, so the whole
      // prefix is never one substring: check the group the parts land in.
      [head, .. rest] =>
        assert_true(
          bullet.contains("`\{head} ") && bullet.contains(rest.join("|")),
        )
    }
  }
}

///|
/// The rendered bullet for `program`, whitespace flattened so a wrap cannot
/// split a verb list, and with the following bullets cut off so a check reads
/// only this program's grant. Fails the test when the program has no bullet
/// at all, which is the coverage gap worth reporting by name.
fn spawn_bullet(program : String) -> String raise {
  let flattened = {
    let builder = StringBuilder()
    let mut in_space = false
    for char in spawn_list_markdown() {
      if char is (' ' | '\n') {
        if !in_space {
          builder.write_char(' ')
          in_space = true
        }
      } else {
        builder.write_char(char)
        in_space = false
      }
    }
    builder.to_string()
  }
  let opening = "- `\{program}` — "
  guard flattened.find(opening) is Some(start) else {
    fail("the rendered spawn list has no bullet for \{program}")
  }
  let body = flattened[start + opening.length():]
  match body.find(" - `") {
    Some(next) => body[:next].to_owned()
    None => body.to_owned()
  }
}

///|
/// Whether `bullet` offers `verb` as a whole entry of its comma-separated verb
/// list, rather than as a fragment of a longer word or of a grouped prefix.
/// Flags render as code, so both spellings count.
fn bullet_lists_verb(bullet : String, verb : String) -> Bool {
  let verbs = spawn_verbs(bullet)
  verbs.contains(verb) || verbs.contains("`\{verb}`")
}

///|
/// The single-token verbs a bullet lists, split back out of the rendered
/// prose. The verb list runs to whichever comes first: the `, plus ` that
/// introduces the grouped multi-token prefixes, or the `. ` that ends the
/// sentence and starts the note — so neither a grouped prefix nor a note's
/// own commas can be mistaken for a verb.
fn spawn_verbs(bullet : String) -> Array[String] {
  let mut cut = bullet.length()
  for marker in [", plus ", ". "] {
    if bullet.find(marker) is Some(index) && index < cut {
      cut = index
    }
  }
  [
    for part in bullet[:cut].split(", ").collect() => part.to_owned()
  ]
}

///|
/// Grouping is what lets one bullet describe several two-token prefixes, and
/// getting it wrong would silently narrow what the model believes it may run.
test "the rendered spawn list groups multi-token prefixes under one verb" {
  let rendered = spawn_list_markdown()
  assert_true(rendered.contains("`worktree list|add|prune`"))
  assert_true(rendered.contains("`submodule update|status`"))
  assert_true(rendered.contains("`stash list|show`"))
  assert_true(rendered.contains("`publish --dry-run`"))
  // `git stash` with no verb is a push, and stays out along with `pop`.
  assert_false(rendered.contains("stash list|show|pop"))
}

///|
/// The description is the one place the model reads the list, so the render
/// has to actually reach it — under the heading the system prompt now cites
/// by name instead of restating the list itself.
test "the mbtx description carries the rendered spawn list" {
  let text = description(
    background=true,
    escalation=false,
    hosting=false,
    auto_background_after_ms=5_000,
    foreground_timeout_ms=120_000,
    build_timeout_ms=20_000,
  )
  assert_true(text.contains("## Which programs a snippet may start"))
  assert_true(text.contains(spawn_list_markdown()))
}

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
