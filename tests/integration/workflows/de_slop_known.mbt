///|
async fn verify_de_slop_known(
  root : String,
  temp : String,
  exe : String,
) -> Unit {
  let work = temp + "/known-fixture"
  @fs.mkdir(work)
  let artifact = compile(root, work, "de-slop")
  let repo = work + "/repo"
  @fs.mkdir(repo + "/sample space", recursive=true)
  let source = "fn present() -> Bool { true }\n"
  write(repo + "/sample space/source.mbt", source)
  for
    args in [
      ["init", "--quiet"],
      ["add", "."],
      [
        "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit",
        "--quiet", "-m", "fixture",
      ],
    ] {
    @shell.Cmd("git", args, cwd=repo).output().check()
  }
  let head_result = @shell.Cmd("git", ["rev-parse", "HEAD"], cwd=repo).output()
  head_result.check()
  let head = head_result.stdout().trim().to_owned()
  for
    mode in [
      "known", "wide-known", "stale", "dirty", "malformed", "oversized", "outside",
      "missing", "blank-decisions", "long-decisions", "non-json",
    ] {
    let calls = work + "/" + mode + ".jsonl"
    let journal = work + "/" + mode + ".journal"
    let file = if mode == "outside" {
      work + "/outside.json"
    } else {
      repo + "/.git/known.json"
    }
    let data : Json = {
      "head": if mode == "stale" {
        "stale"
      } else {
        head
      },
      "decisions": match mode {
        "blank-decisions" => " \t "
        "long-decisions" => "x".repeat(6001)
        _ => "source.mbt:1 already handled"
      },
      "padding": if mode == "oversized" {
        "x".repeat(8001)
      } else {
        ""
      },
    }
    write(
      file,
      if mode == "malformed" {
        "{}"
      } else if mode == "non-json" {
        "{"
      } else {
        data.stringify()
      },
    )
    if mode == "dirty" {
      write(repo + "/sample space/source.mbt", source + "// edit\n")
    }
    let env = clean_env()
    env["WORKFLOW_HOST"] = (
      {
        "v": 1,
        "exe": exe,
        "child_args": [
          "hosted-child",
          "de-slop",
          if mode == "wide-known" {
            "wide-known"
          } else {
            "known"
          },
          calls,
          "{child}",
        ],
        "child_id": "test-{n}",
        "ids": [1, 32],
        "cwd": repo,
        "journal": journal,
        "deadline_ms": 10000,
      } : Json).stringify()
    let result = @shell.Cmd(
      "moonrun",
      [
        artifact,
        "--",
        "--known",
        if mode == "missing" {
          repo + "/absent.json"
        } else {
          file
        },
        if mode == "wide-known" {
          "."
        } else {
          "sample space"
        },
      ],
      cwd=repo,
      env~,
      inherit_env=false,
    ).output(timeout_ms=60000)
    let output = result.stdout() + result.stderr()
    let succeeds = mode is ("known" | "wide-known")
    assert_eq(result.exit_code() == 0, succeeds, msg=output)
    assert_eq(
      read_calls(calls).length(),
      if succeeds {
        2
      } else {
        0
      },
      msg=output,
    )
    if mode == "oversized" {
      assert_true(
        output.contains("--known exceeds 8000 characters"),
        msg=output,
      )
    }
    if mode is ("blank-decisions" | "long-decisions" | "malformed") {
      assert_true(
        output.contains(
          "--known needs head and 1–6000 characters of decisions",
        ),
        msg=output,
      )
    }
    if mode == "outside" {
      assert_true(
        output.contains("--known must resolve inside the workspace"),
        msg=output,
      )
    }
    if mode == "stale" {
      assert_true(output.contains("HEAD is stale"), msg=output)
    }
    if mode == "dirty" {
      assert_true(output.contains("requires a clean worktree"), msg=output)
    }
    if mode == "wide-known" {
      let manifest = @json.parse(
        @fs.read_file(journal + ".inventory.json").text(),
      )
      assert_true(
        manifest
        is {
          "source_files": 1,
          "known_decisions": {
            "head": String(actual),
            "decisions": "source.mbt:1 already handled",
            ..
          },
          ..
        } &&
        actual == head,
        msg=manifest.stringify(),
      )
    }
    write(repo + "/sample space/source.mbt", source)
    println("de-slop: known-\{mode} passed")
  }
}
