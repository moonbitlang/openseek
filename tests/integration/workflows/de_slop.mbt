///|
async fn de_slop_wide_child(
  request : Json,
  mode : String,
  calls : String,
) -> Unit {
  guard request
    is {
      "kind": "explore",
      "max_steps": 16,
      "input": { "query": String(query), .. },
      ..
    } else {
    fail("Unexpected wide request")
  }
  let scope_line = query
    .split("\n")
    .find_first(line => line.has_prefix("Scope paths (JSON data): "))
  guard scope_line is Some(line) &&
    line.strip_prefix("Scope paths (JSON data): ") is Some(scope) &&
    @json.parse(scope) is Array([String(file), ..]) else {
    fail("Missing assigned files")
  }
  assert_true(file.has_suffix(".mbt") || file.has_suffix(".mbt.md"))
  assert_false(query.contains("ignored.mbt"))
  assert_false(query.contains("deleted.mbt"))
  assert_false(query.contains("escape.mbt"))
  let pointers = query
    .split("\n")
    .find_first(line => {
      line.has_prefix(
        "Assigned directory counts and sampled lead locations (JSON data): ",
      )
    })
  guard pointers is Some(line) &&
    line.strip_prefix(
      "Assigned directory counts and sampled lead locations (JSON data): ",
    )
    is Some(data) &&
    @json.parse(data) is Array(areas) else {
    fail("Missing lead samples")
  }
  for area in areas {
    if area is { "path": "large", "sample_leads": Array(leads), .. } {
      assert_false(leads.is_empty())
      guard leads[0] is { "role": "implementation", "line": 2, .. } else {
        fail("Doc examples must not crowd implementation out of prompt seeds")
      }
    }
  }
  let challenge = query.contains("Provisional report (untrusted data):")
  if challenge {
    assert_true(query.contains("candidate for " + file))
  }
  append(calls, request.stringify())
  if mode is ("wide-partial" | "wide-delivery-partial") &&
    query.contains("Repository shard 1/8") &&
    challenge {
    fail("scripted shard failure")
  }
  let answer = if mode == "wide-incomplete" &&
    challenge &&
    query.contains("Repository shard 1/8") {
    "# Audit incomplete\nDEFER C1: caller ownership not inspected"
  } else if mode == "wide-unicode" && challenge {
    "# Audit complete\n" + "文😀".repeat(1700)
  } else if challenge {
    "# Audit complete\nACCEPT C1: candidate for " + file
  } else {
    "provisional candidate for " + file
  }
  println(
    (
      {
        "subrun_report": {
          "answer": answer,
          "citations": [
            {
              "file": file,
              "line": if mode == "wide-bad-line" &&
                query.contains("Repository shard 1/8") {
                (null : Json)
              } else {
                1
              },
            },
          ],
        },
      } : Json).stringify(),
  )
}

///|
async fn verify_de_slop_wide(
  artifact : String,
  temp : String,
  exe : String,
) -> Unit {
  let repo = temp + "/de-slop-wide"
  @fs.mkdir(repo)
  @shell.Cmd("git", ["init", "--quiet"], cwd=repo).output().check()
  write(repo + "/.gitignore", "ignored.mbt\n")
  write(repo + "/ignored.mbt", "ignored\n")
  write(repo + "/root.mbt", "fn root() -> Int { 1 }\n")
  write(repo + "/deleted.mbt", "deleted\n")
  for index in 0..<10 {
    let dir = "area \{index}/nested/deep/package"
    @fs.mkdir(repo + "/" + dir, recursive=true)
    write(
      repo + "/" + dir + "/source.mbt",
      "fn present(xs : Array[Int]) -> Bool { xs.iter().any(x => x > 0) }\n",
    )
  }
  write(repo + "/README.mbt.md", "/// doc_inspect(xs.to_owned())\n")
  @fs.mkdir(repo + "/large")
  for family in ["alpha", "beta", "gamma"] {
    for suffix in [".mbt", "_test.mbt"] {
      write(
        repo + "/large/" + family + suffix,
        "/// example.to_owned()\nfn owned() -> String { \"a\".to_owned() }\n" +
        "\n".repeat(80),
      )
    }
  }
  let policy = "fn policy(x : Int) -> Int {\n  let mut value = x\n  if value < 0 {\n    value = 0\n  }\n  value + 1\n}\n"
  write(repo + "/policy_a.mbt", policy)
  write(
    repo + "/policy_b.mbt",
    policy.replace_all(old="fn policy(", new="fn other("),
  )
  write(
    repo + "/policy_near.mbt",
    policy.replace_all(old="value + 1", new="value + 2"),
  )
  write(repo + "/policy_test.mbt", policy)
  write(
    repo + "/defaults.mbt",
    "fn normal(s : String) -> String { s.trim(chars=\"\\r\\n \\t\").to_owned() }\n" +
    "fn spaces(s : String) -> String { s.trim(chars=\" \").to_owned() }\n",
  )
  @shell.Cmd("git", ["add", "."], cwd=repo).output().check()
  @fs.remove(repo + "/deleted.mbt")
  write(
    repo + "/untracked.mbt",
    "fn keep() -> String { \"a\".to_owned() }\n".repeat(5),
  )
  @fs.symlink(target=temp + "/outside.md", repo + "/escape.mbt")
  let all_leads : Set[String] = Set([])
  let sampled : Set[String] = Set([])
  for
    mode in [
      "wide-success", "wide-partial", "wide-resume", "wide-unicode", "wide-capacity",
      "wide-invalid", "wide-no-journal", "wide-bad-line", "wide-incomplete", "wide-delivery",
      "wide-delivery-partial", "wide-round-two", "wide-round-three", "wide-round-zero",
      "wide-round-overflow", "wide-round-text", "wide-round-resume",
    ] {
    let calls = temp + "/" + mode + ".calls"
    let journal = temp + "/" + mode + ".journal"
    let handoff : Map[String, Json] = {
      "v": 1,
      "exe": exe,
      "child_args": ["hosted-child", "de-slop", mode, calls, "{child}"],
      "child_id": "test-{n}",
      "ids": [1, if mode == "wide-capacity" { 2 } else { 16 }],
      "cwd": repo,
      "deadline_ms": 10000,
    }
    if mode != "wide-no-journal" {
      handoff["journal"] = journal.to_json()
    }
    let env = clean_env()
    env["WORKFLOW_HOST"] = handoff.to_json().stringify()
    let args = match mode {
      "wide-round-two" => ["--round", "2", "."]
      "wide-round-resume" => ["--round", "2", "--shard", "1", "."]
      "wide-round-three" => ["--round", "3", "."]
      "wide-round-zero" => ["--round", "0", "."]
      "wide-round-overflow" => ["--round", "1000001", "."]
      "wide-round-text" => ["--round", "two", "."]
      "wide-resume" => ["--shard", "1", "."]
      "wide-invalid" => ["--shard", "0", "."]
      "wide-delivery" | "wide-delivery-partial" => ["--deliver", "."]
      _ => ["."]
    }
    let result = @shell.Cmd(
      "moonrun",
      [artifact, "--", ..args],
      cwd=repo,
      env~,
      inherit_env=false,
    ).output(timeout_ms=60000)
    let output = result.stdout() + result.stderr()
    assert_eq(
      result.exit_code() == 0,
      mode
      is ("wide-success"
      | "wide-resume"
      | "wide-unicode"
      | "wide-delivery"
      | "wide-round-two"
      | "wide-round-three"
      | "wide-round-resume"),
      msg=output,
    )
    assert_true(
      result.stdout_bytes().length() < 40000,
      msg="Combined UTF-8 output exceeds transport budget",
    )
    let launched = read_calls(calls)
    let expected = match mode {
      "wide-success"
      | "wide-partial"
      | "wide-unicode"
      | "wide-incomplete"
      | "wide-delivery"
      | "wide-delivery-partial"
      | "wide-round-two"
      | "wide-round-three" => 16
      "wide-bad-line" => 15
      "wide-resume" | "wide-round-resume" => 2
      _ => 0
    }
    assert_eq(launched.length(), expected, msg=output)
    if !(mode
      is ("wide-no-journal"
      | "wide-round-zero"
      | "wide-round-overflow"
      | "wide-round-text")) {
      guard @json.parse(@fs.read_file(journal + ".inventory.json").text())
        is {
          "version": 4,
          "round": Number(round, ..),
          "source_files": 24,
          "lexical_leads": 32,
          "shards": Array(shards),
          ..
        } else {
        fail("Inventory must include every current source exactly once")
      }
      assert_eq(
        round.to_int(),
        if mode is ("wide-round-two" | "wide-round-resume") {
          2
        } else if mode == "wide-round-three" {
          3
        } else {
          1
        },
      )
      assert_eq(shards.length(), 8)
      let assigned : Array[String] = []
      let defaults : Array[String] = []
      let repeated : Array[String] = []
      let file_shards : Map[String, Int] = Map([])
      let large_shards : Set[Int] = Set([])
      for index, shard in shards {
        guard shard is { "areas": Array(areas), .. } else {
          fail("Missing areas")
        }
        for area in areas {
          guard area
            is {
              "files": Array(files),
              "leads": Array(leads),
              "sample_leads": Array(samples),
              ..
            } else {
            fail("Missing files")
          }
          assert_true(samples.length() <= 4)
          for sample in samples {
            assert_true(
              leads.contains(sample),
              msg="Samples must come from the complete inventory",
            )
            if mode is ("wide-success" | "wide-round-two" | "wide-round-three") {
              sampled.add(sample.stringify())
            }
          }
          for lead in leads {
            if mode == "wide-success" {
              all_leads.add(lead.stringify())
            }
            match lead {
              { "kind": "explicit-trim-characters", "file": String(path), .. } =>
                defaults.push(path)
              {
                "kind": "repeated-function-body",
                "file": String(path),
                "related": { "file": String(peer), "line": 1, .. },
                ..
              } => {
                assert_true(path != peer)
                assert_true(peer is ("policy_a.mbt" | "policy_b.mbt"))
                repeated.push(path)
              }
              _ => ()
            }
          }
          for file in files {
            guard file is String(file) else { fail("Invalid file") }
            assert_false(assigned.contains(file), msg=file)
            assigned.push(file)
            file_shards[file] = index
            if file.has_prefix("large/") {
              large_shards.add(index)
            }
          }
        }
      }
      assert_eq(assigned.length(), 24)
      assert_eq(defaults, ["defaults.mbt", "defaults.mbt"])
      repeated.sort()
      assert_eq(repeated, ["policy_a.mbt", "policy_b.mbt"])
      assert_true(assigned.contains("README.mbt.md"))
      assert_true(
        large_shards.length() > 1,
        msg="Oversized package must span shards",
      )
      for family in ["alpha", "beta", "gamma"] {
        assert_eq(
          file_shards.get("large/" + family + ".mbt"),
          file_shards.get("large/" + family + "_test.mbt"),
        )
      }
      assert_true(assigned.contains("untracked.mbt"))
      assert_true(assigned.contains("area 9/nested/deep/package/source.mbt"))
    }
    if expected > 0 {
      let report = @fs.read_file(journal + ".report.json").text()
      assert_eq(
        occurrences(report, "\"status\":\"reviewed\""),
        if mode
          is ("wide-partial"
          | "wide-bad-line"
          | "wide-incomplete"
          | "wide-delivery-partial") {
          7
        } else if mode is ("wide-resume" | "wide-round-resume") {
          1
        } else {
          8
        },
      )
      assert_eq(
        occurrences(report, "\"status\":\"incomplete\""),
        if mode
          is ("wide-partial"
          | "wide-bad-line"
          | "wide-incomplete"
          | "wide-delivery-partial") {
          1
        } else {
          0
        },
      )
    }
    assert_eq(output.contains("# Delivery handoff"), mode == "wide-delivery")
    println("de-slop: \{mode} passed")
  }
  assert_eq(
    sampled.length(),
    all_leads.length(),
    msg="Three rounds must reach every fixture lead, including later hits in the same file",
  )
  assert_true(all_leads.iter().all(lead => sampled.contains(lead)))
}

///|
async fn de_slop_child(
  request : Json,
  mode : String,
  calls : String,
  child : String,
) -> Unit {
  if mode.has_prefix("wide-") {
    return de_slop_wide_child(request, mode, calls)
  }
  guard request
    is {
      "kind": "explore",
      "max_steps": 24,
      "input": { "query": String(query), .. },
      ..
    } else {
    fail("Unexpected de-slop request: \{request.stringify()}")
  }
  assert_true(query.contains("[\"sample space\"]"), msg=query)
  if mode == "focus" {
    assert_true(
      query.contains(
        "candidate with spaces: symmetric_difference -> difference",
      ),
      msg=query,
    )
  }
  // The second call must consume the first report, not repeat discovery.
  if child == "test-2" {
    assert_eq(read_calls(calls).length(), 1)
    assert_true(query.contains("provisional candidate C1"), msg=query)
    assert_true(query.contains("Do not discover additional candidates"))
  }
  append(calls, request.stringify())
  if mode == "delivery-mutated" && child == "test-2" {
    write("sample space/source.mbt", "fn present() -> Bool { true }\n")
  }
  if mode == "partial" && child == "test-2" {
    fail("scripted challenger failure")
  }
  if mode == "no-report" && child == "test-2" {
    println("# Audit complete\nUncaptured final text is not a submission")
    return
  }
  let answer = match (mode, child) {
    ("empty-discovery", "test-1") | ("empty-challenge", "test-2") => " "
    ("oversized", _) => "x".repeat(8001)
    (_, "test-1") => "provisional candidate C1"
    ("incomplete" | "delivery-incomplete", _) =>
      "# Audit incomplete\nDEFER C1: caller ownership not inspected"
    ("missing-status", _) => "ACCEPT C1: no status heading"
    ("no-changes" | "delivery-no-changes", _) =>
      "# Audit complete\nREJECT C1: ownership is required; no supported changes"
    _ => "# Audit complete\nACCEPT C1: direct predicate; pending validation"
  }
  let file = match mode {
    "missing-file" => "absent.mbt"
    "escape-citation" => "escape.mbt"
    "traversal" => "../outside.md"
    _ => "sample space/source.mbt"
  }
  let line : Json = match mode {
    "bad-line" => 2
    "fractional-line" => 1.5
    "zero-line" => 0
    _ => 1
  }
  let citations : Array[Json] = if mode == "no-citations" {
    []
  } else {
    [{ "file": file, "line": line }]
  }
  if mode
    is ("many-citations"
    | "citation-limit"
    | "too-many-citations"
    | "extra-invalid-citation") {
    citations.clear()
    let count = if mode == "citation-limit" {
      16
    } else if mode == "too-many-citations" {
      17
    } else {
      10
    }
    for index in 0..<count {
      citations.push({
        "file": "sample space/evidence-\{index}.mbt",
        "line": if mode == "extra-invalid-citation" && index == 9 {
          2
        } else {
          1
        },
      })
    }
  }
  if mode == "external-only" {
    citations.clear()
  }
  if mode is ("external-reference" | "external-only") {
    citations.push({
      "file": "~/.moon/lib/core/builtin/array.mbt",
      "line": null,
    })
  }
  let unresolved : Json = match (mode, child) {
    ("incomplete", "test-2") | ("resolved-gap", "test-1") =>
      "caller ownership not inspected"
    ("malformed-gaps", "test-2") => false
    ("validation-pending", "test-2") =>
      "Compiler/tests still need to run; source inspection is complete"
    _ => null
  }
  let report : Json = {
    "subrun_report": {
      "answer": answer,
      "citations": citations,
      "unresolved": unresolved,
    },
  }
  println(report.stringify())
}

///|
async fn verify_de_slop(root : String, temp : String, exe : String) -> Unit {
  let artifact = compile(root, temp, "de-slop")
  let repo = temp + "/de-slop-repository"
  @fs.mkdir(repo + "/sample space", recursive=true)
  @shell.Cmd("git", ["init", "--quiet"], cwd=repo).output().check()
  let source = "fn present(xs : Array[Int]) -> Bool { xs.iter().any(x => x > 0) }\n"
  write(repo + "/sample space/source.mbt", source)
  for index in 0..<16 {
    write(
      repo + "/sample space/evidence-\{index}.mbt",
      "fn evidence_\{index}() -> Int { \{index} }\n",
    )
  }
  @fs.symlink(target=temp + "/outside.md", repo + "/escape.mbt")
  for
    mode in [
      "success", "no-changes", "resolved-gap", "partial", "empty-discovery", "empty-challenge",
      "oversized", "no-citations", "bad-line", "fractional-line", "zero-line", "missing-file",
      "escape-citation", "traversal", "incomplete", "malformed-gaps", "missing",
      "capacity", "help", "no-scope", "unknown-option", "absent-scope", "outside-scope",
      "symlink-scope", "missing-status", "validation-pending", "external-reference",
      "external-only", "no-report", "delivery", "delivery-no-changes", "delivery-incomplete",
      "delivery-mutated", "focus", "empty-focus", "oversized-focus", "wide-focus",
      "explicit-round", "many-citations", "citation-limit", "too-many-citations",
      "extra-invalid-citation",
    ] {
    let calls = temp + "/de-slop-" + mode + ".jsonl"
    let env = clean_env()
    if mode != "missing" {
      let handoff : Json = {
        "v": 1,
        "exe": exe,
        "child_args": ["hosted-child", "de-slop", mode, calls, "{child}"],
        "child_id": "test-{n}",
        "ids": [1, if mode == "capacity" { 1 } else { 2 }],
        "cwd": repo,
        "deadline_ms": 10000,
      }
      env["WORKFLOW_HOST"] = handoff.stringify()
    }
    let args = match mode {
      "focus" =>
        [
          "--focus", "candidate with spaces: symmetric_difference -> difference",
          "sample space",
        ]
      "empty-focus" => ["--focus", " ", "sample space"]
      "oversized-focus" => ["--focus", "x".repeat(2001), "sample space"]
      "wide-focus" => ["--focus", "candidate", "."]
      "explicit-round" => ["--round", "2", "sample space"]
      "help" => ["--help"]
      "no-scope" => []
      "unknown-option" => ["--unknown"]
      "absent-scope" => ["absent"]
      "outside-scope" => [".."]
      "symlink-scope" => ["escape.mbt"]
      "delivery"
      | "delivery-no-changes"
      | "delivery-incomplete"
      | "delivery-mutated" => ["--deliver", "sample space"]
      _ => ["sample space"]
    }
    let result = @shell.Cmd(
      "moonrun",
      [artifact, "--", ..args],
      cwd=repo,
      env~,
      inherit_env=false,
    ).output(timeout_ms=60000)
    let output = result.stdout() + result.stderr()
    let succeeds = mode
      is ("success"
      | "no-changes"
      | "resolved-gap"
      | "help"
      | "external-reference"
      | "validation-pending"
      | "delivery"
      | "delivery-no-changes"
      | "focus"
      | "many-citations"
      | "citation-limit")
    assert_eq(result.exit_code() == 0, succeeds, msg="\{mode}: \{output}")
    let launched = read_calls(calls)
    let expected = match mode {
      "missing"
      | "capacity"
      | "help"
      | "no-scope"
      | "unknown-option"
      | "absent-scope"
      | "outside-scope"
      | "symlink-scope"
      | "empty-focus"
      | "oversized-focus"
      | "wide-focus"
      | "explicit-round" => 0
      "empty-discovery"
      | "oversized"
      | "no-citations"
      | "bad-line"
      | "fractional-line"
      | "zero-line"
      | "missing-file"
      | "escape-citation"
      | "external-only"
      | "too-many-citations"
      | "extra-invalid-citation"
      | "traversal" => 1
      _ => 2
    }
    assert_eq(launched.length(), expected, msg="\{mode}: \{output}")
    if expected == 2 {
      assert_true(output.contains("provisional candidate C1"), msg=output)
    }
    if succeeds && mode != "help" {
      assert_true(output.contains("scouts=2"), msg=output)
      assert_true(
        output.contains("A successful audit is not a passing test result"),
      )
    }
    if mode is ("many-citations" | "citation-limit") {
      assert_eq(
        occurrences(output, "Reference location checked"),
        if mode == "many-citations" {
          20
        } else {
          32
        },
        msg=output,
      )
    }
    if mode == "too-many-citations" {
      assert_true(output.contains("17 citations; expected 1–16"), msg=output)
    }
    if mode == "extra-invalid-citation" {
      assert_true(
        output.contains("citation line exceeds file length"),
        msg=output,
      )
    }
    if mode == "oversized" {
      assert_true(output.contains("8001 answer characters"), msg=output)
    }
    if mode == "no-changes" {
      assert_true(output.contains("no supported changes"), msg=output)
    }
    if mode == "external-reference" {
      assert_true(output.contains("External API reference (not checked):"))
    }
    if mode == "incomplete" {
      assert_true(
        output.contains(
          "INCOMPLETE: the challenger needs more inspection evidence",
        ),
      )
    }
    assert_eq(
      output.contains("# Delivery handoff"),
      mode is ("delivery" | "delivery-no-changes"),
    )
    if mode == "delivery-mutated" {
      assert_true(
        output.contains("scoped source changed during audit"),
        msg=output,
      )
      write(repo + "/sample space/source.mbt", source)
    }
    // Other fixture phases must preserve content.
    assert_eq(@fs.read_file(repo + "/sample space/source.mbt").text(), source)
    println("de-slop: \{mode} passed")
  }
  verify_de_slop_wide(artifact, temp, exe)
}
