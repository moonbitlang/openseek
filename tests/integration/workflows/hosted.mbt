///|
async fn hosted_child(
  name : String,
  mode : String,
  calls : String,
  child : String,
) -> Unit {
  guard @stdio.stdin.read_until("\n") is Some(line) else {
    fail("Missing child request")
  }
  let request = @json.parse(line)
  if name == "de-slop" {
    return de_slop_child(request, mode, calls, child)
  }
  if name == "review" {
    return review_child(request, mode, calls)
  }
  let steps = if name == "repo-map" { 12 } else { 16 }
  assert_true(request is { "kind": String("explore"), .. })
  assert_true(
    request is { "max_steps": Number(value, ..), .. } &&
    value == steps.to_double(),
  )
  if name == "repo-map" {
    guard request is { "input": { "query": String(query), .. }, .. } else {
      fail("Missing query")
    }
    for
      expected in [
        "1 | orientation fixture", "[Excerpt truncated; read the file for the remainder.]",
        "sample/:", "real_implementation.mbt", "pkg.generated.mbti", "moon.pkg",
        "cmd/main/:", "main.mbt",
      ] {
      assert_true(query.contains(expected), msg=expected)
    }
    assert_false(query.contains("excluded tail"))
  }
  append(calls, request.stringify())
  if mode == "partial" && child == "test-2" {
    fail("scripted child failure")
  }
  let file = match mode {
    "missing-file" => "absent.mbt"
    "directory" => "sample"
    "escape" => "escape.md"
    "traversal" => "../outside.md"
    _ => "cmd/main/main.mbt"
  }
  let line : Json = match mode {
    "bad-line" => 2
    "fractional-line" => 1.5
    _ => 1
  }
  let citations : Array[Json] = if mode == "no-citations" {
    []
  } else {
    [{ "file": file, "line": line }]
  }
  let report : Json = {
    "subrun_report": {
      // Deliberately malformed empty answer tests the workflow's rejection.
      "answer": if mode == "empty" && child == "test-2" {
        ""
      } else {
        "offline evidence " + child
      },
      "citations": citations,
    },
  }
  println(report.stringify())
}

///|
/// The review child: one `review` request carrying the criteria the script
/// resolved (its arguments, the engine's standing goal, or both) and a
/// baseline only when one was given, answered with a report in the review
/// contract's shape.
async fn review_child(request : Json, mode : String, calls : String) -> Unit {
  guard request is { "kind": "review", "max_steps": 100, "input": input, .. } else {
    fail("unexpected review request: \{request.stringify()}")
  }
  let (goal, baseline) : (String, (String, Bool)?) = match mode {
    "baseline" => ("Check CSV CRLF handling", Some(("abc", true)))
    "standing" => ("Standing goal", Some(("def", false)))
    "focus" => ("Standing goal\n\nAudit focus:\nCheck CSV CRLF handling", None)
    "override" => ("Standing goal", Some(("abc", true)))
    _ => ("Check CSV CRLF handling", None)
  }
  guard input is { "goal": String(actual), .. } && actual == goal else {
    fail("unexpected criteria: \{input.stringify()}")
  }
  match baseline {
    Some((sha, dirty)) =>
      assert_true(
        input is { "sha": String(actual_sha), "dirty": actual_dirty, .. } &&
        actual_sha == sha &&
        actual_dirty == dirty.to_json(),
        msg=input.stringify(),
      )
    None => assert_false(input is { "sha": _, .. }, msg=input.stringify())
  }
  append(calls, request.stringify())
  let finding : (String, String) -> Json = (severity, title) => {
    "file": "cmd/main/main.mbt",
    "line": 1,
    "severity": severity,
    "category": "correctness",
    "title": title,
    "detail": "offline fixture finding",
    "suggestion": null,
  }
  let findings : Array[Json] = if mode == "blockers" {
    [finding("blocker", "claim does not hold"), finding("high", "also this")]
  } else {
    []
  }
  let report : Json = {
    "subrun_report": {
      "schema_version": 1,
      "scope": { "base": "abc", "head": "WORKTREE", "files": [] },
      "findings": findings,
      "summary": "offline fixture report",
      "stats": {
        "files_reviewed": 0,
        "findings": findings.length(),
        "build": "skipped",
        "tests": "skipped",
      },
    },
  }
  println(report.stringify())
}

///|
async fn verify_review(root : String, temp : String, exe : String) -> Unit {
  let repo = temp + "/review-repository"
  @fs.mkdir(repo)
  let artifact = compile(root, temp, "review")
  for
    mode in [
      "success", "baseline", "blockers", "standing", "focus", "override", "missing",
      "no-criteria", "dirty-without-sha", "help",
    ] {
    let calls = temp + "/review-" + mode + ".jsonl"
    let env = clean_env()
    if mode != "missing" {
      let handoff : Json = {
        "v": 1,
        "exe": exe,
        "child_args": ["hosted-child", "review", mode, calls, "{child}"],
        "child_id": "test-{n}",
        "ids": [1, 1],
        "cwd": repo,
        "deadline_ms": 10000,
      }
      env["WORKFLOW_HOST"] = handoff.stringify()
    }
    // The engine's standing goal, as the host hands it over.
    match mode {
      "standing" | "override" => {
        env["OPENSEEK_GOAL"] = "Standing goal"
        env["OPENSEEK_GOAL_SHA"] = "def"
        env["OPENSEEK_GOAL_DIRTY"] = "false"
      }
      "focus" => env["OPENSEEK_GOAL"] = "Standing goal"
      _ => ()
    }
    let args = match mode {
      "baseline" =>
        ["--sha", "abc", "--dirty", "--", "Check", "CSV", "CRLF", "handling"]
      "override" => ["--sha", "abc", "--dirty"]
      "standing" | "no-criteria" => []
      "dirty-without-sha" => ["--dirty", "Check CSV CRLF handling"]
      "help" => ["--help"]
      _ => ["Check CSV CRLF handling"]
    }
    let result = @shell.Cmd(
      "moonrun",
      [artifact, "--", ..args],
      cwd=repo,
      env~,
      inherit_env=false,
    ).output(timeout_ms=60000)
    let output = result.stdout() + result.stderr()
    let launched = read_calls(calls)
    let succeeds = match mode {
      "success" | "baseline" | "standing" | "focus" | "override" | "help" =>
        true
      _ => false
    }
    assert_eq(result.exit_code() == 0, succeeds, msg=output)
    let reviewed = match mode {
      "success" | "baseline" | "blockers" | "standing" | "focus" | "override" =>
        1
      _ => 0
    }
    assert_eq(launched.length(), reviewed, msg=output)
    let expected = match mode {
      "blockers" => "does not hold yet"
      "missing" => "subrun=true"
      "no-criteria" => "no criteria given"
      "dirty-without-sha" => "--dirty needs --sha"
      "help" => "usage:"
      _ => "findings=0 blockers=0"
    }
    assert_true(output.contains(expected), msg=output)
    assert_eq(
      output.contains("offline fixture report"),
      reviewed == 1,
      msg=output,
    )
    // The report is printed BEFORE the blocker exit, so the caller reads it.
    assert_eq(
      output.contains("findings=2 blockers=1"),
      mode == "blockers",
      msg=output,
    )
    println("review: \{mode} passed")
  }
}

///|
async fn verify_hosted(root : String, temp : String, exe : String) -> Unit {
  let repo = temp + "/repository"
  @fs.mkdir(repo)
  @fs.mkdir(repo + "/sample")
  @fs.mkdir(repo + "/cmd/main", recursive=true)
  write(repo + "/justfile", "check:\n    moon check\n")
  write(
    repo + "/README.md",
    "orientation fixture\n" + String::make(5000, 'x') + "excluded tail",
  )
  write(repo + "/sample/moon.pkg", "")
  write(repo + "/sample/real_implementation.mbt", "")
  write(repo + "/sample/pkg.generated.mbti", "package \"sample\"\n")
  write(repo + "/cmd/main/moon.pkg", "")
  write(repo + "/cmd/main/main.mbt", "fn main {}\n")
  write(temp + "/outside.md", "outside\n")
  @fs.symlink(target=temp + "/outside.md", repo + "/escape.md")
  for name in ["change-review", "repo-map"] {
    let artifact = compile(root, temp, name)
    let expected_calls = if name == "repo-map" { 2 } else { 3 }
    let modes = ["success", "partial", "missing", "capacity"]
    if name == "repo-map" {
      modes.append([
        "empty", "bad-line", "fractional-line", "missing-file", "directory", "escape",
        "traversal", "no-citations", "no-recipes",
      ])
    }
    for mode in modes {
      if mode == "no-recipes" {
        @fs.remove(repo + "/justfile")
      }
      let calls = temp + "/" + name + "-" + mode + ".jsonl"
      let env = clean_env()
      if mode != "missing" {
        let handoff : Json = {
          "v": 1,
          "exe": exe,
          "child_args": ["hosted-child", name, mode, calls, "{child}"],
          "child_id": "test-{n}",
          "ids": [
            1,
            if mode == "capacity" {
              expected_calls - 1
            } else {
              expected_calls
            },
          ],
          "cwd": repo,
          "deadline_ms": 10000,
        }
        env["WORKFLOW_HOST"] = handoff.stringify()
      }
      let result = @shell.Cmd(
        "moonrun",
        [artifact],
        cwd=repo,
        env~,
        inherit_env=false,
      ).output(timeout_ms=60000)
      let output = result.stdout() + result.stderr()
      let launched = read_calls(calls)
      assert_eq(
        result.exit_code() == 0,
        mode == "success" || mode == "no-recipes",
        msg=output,
      )
      assert_eq(
        launched.length(),
        if mode == "missing" || mode == "capacity" {
          0
        } else {
          expected_calls
        },
        msg=output,
      )
      if mode != "missing" && mode != "capacity" {
        let ids : Map[String, Unit] = Map([])
        for call in launched {
          guard call is { "id": String(id), .. } else {
            fail("Missing child id")
          }
          ids[id] = ()
        }
        assert_eq(ids.length(), expected_calls)
        assert_true(output.contains("scouts=\{expected_calls}"), msg=output)
        assert_eq(
          occurrences(output, "offline evidence"),
          if mode == "partial" || mode == "empty" {
            expected_calls - 1
          } else {
            expected_calls
          },
          msg=output,
        )
        if name == "repo-map" {
          assert_true(
            output.contains("Validation recipes (not executed)"),
            msg=output,
          )
          assert_true(
            output.contains(
              if mode == "no-recipes" {
                "No root justfile found"
              } else {
                "check:\n    moon check"
              },
            ),
            msg=output,
          )
        }
      }
      match mode {
        "partial" | "empty" =>
          assert_true(output.contains("INCOMPLETE:"), msg=output)
        "missing" => assert_true(output.contains("subrun=true"), msg=output)
        "capacity" =>
          assert_true(output.contains("no scouts were launched"), msg=output)
        "bad-line"
        | "fractional-line"
        | "missing-file"
        | "directory"
        | "escape"
        | "traversal" => assert_true(output.contains("UNVERIFIED:"), msg=output)
        "success" if name == "repo-map" =>
          assert_eq(occurrences(output, "CHECKED:"), 2, msg=output)
        _ => ()
      }
      println("\{name}: \{mode} passed")
    }
  }
}
