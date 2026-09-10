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
