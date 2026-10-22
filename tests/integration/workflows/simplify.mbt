///|
/// The simplify sweep's scripted children. Scouts cite candidates, some of
/// which the script must drop; each package's worker ends a different way;
/// reviewers accept, reject or hedge.
fn FakeHost::simplify_child(
  self : FakeHost,
  job : String,
  arguments : Json,
) -> Result[Json, String] raise {
  guard arguments
    is { "kind": String(kind), "label": String(label), "input": input, .. } else {
    fail("unexpected start: \{arguments.stringify()}")
  }
  let cite = (file : String, line : Int32, note : String) => {
    ({ "file": file, "line": line, "note": note } : Json)
  }
  match kind {
    "explore" if label.has_prefix("simplify:scout-") => {
      assert_true(arguments is { "max_steps": 80, .. }, msg=label)
      guard input is { "query": String(query), "hints": String(hints), .. } else {
        fail("scout input: \{input.stringify()}")
      }
      assert_true(hints.contains("# Simplifying MoonBit safely"), msg=hints)
      if self.mode == "simplify-publish" {
        assert_true(query.contains("pattern matching"), msg=query)
      }
      // Every scout cites everything; the script keeps a citation only from
      // the scout whose packages own its file.
      Ok({
        "answer": "candidates by package",
        "citations": [
          cite("alpha/a.mbt", 1, "pattern: bind the parts"),
          cite("alpha/a.mbt", 1, "pattern: bind the parts"),
          cite("./alpha/b.mbt", 2, "range loop: for i in 0..<n"),
          cite("alpha/generated_x.mbt", 1, "generated"),
          cite("alpha/nested/n.mbt", 1, "comprehension"),
          cite("beta/b.mbt", 1, "interpolation"),
          cite("delta/d.mbt", 1, "slice"),
          cite("gamma/g.mbt", 1, "inline the helper"),
          cite("missing.mbt", 1, "not a file"),
          { "file": "README.md" },
        ],
      })
    }
    "explore" => {
      assert_true(label.has_prefix("simplify:review-"), msg=label)
      assert_true(arguments is { "max_steps": 60, .. }, msg=label)
      guard input is { "query": String(query), .. } &&
        query
        .split("\n")
        .filter_map(line => line.strip_prefix("Package: "))
        .head()
        is Some(dir) else {
        fail("review input: \{input.stringify()}")
      }
      let dir = dir.to_owned()
      assert_true(
        query.contains("Commit: \{self.fixture[dir]}") &&
        query.contains("Base: \{self.fixture["head"]}"),
        msg=query,
      )
      match dir {
        "alpha" =>
          Ok({
            "answer": if self.mode == "simplify-limit" {
              "VERDICT: ACCEPT probably\nlooks fine"
            } else {
              "VERDICT: ACCEPT.\nbehavior unchanged"
            },
            "citations": [],
          })
        "beta" =>
          Ok({
            "answer": "VERDICT: REJECT\nloosens an invariant",
            "citations": [cite("beta/b.mbt", 1, "adds mut")],
          })
        _ => Err("unexpected review of \{dir}")
      }
    }
    "worker" => {
      guard label.strip_prefix("simplify:") is Some(dir) &&
        arguments
        is {
          "worktree": {
            "name": String(name),
            "allowed_paths": Array(paths),
            ..
          },
          ..
        } &&
        input is { "task": String(task), "context": String(context), .. } else {
        fail("worker start: \{arguments.stringify()}")
      }
      let dir = dir.to_owned()
      assert_true(
        name.length() <= 40 &&
        name.has_prefix("simp-") &&
        name
        .iter()
        .all(char => {
          (char >= 'a' && char <= 'z') ||
          (char >= '0' && char <= '9') ||
          char == '-'
        }),
        msg=name,
      )
      assert_true(context.contains("# Simplifying MoonBit safely"))
      assert_true(task.contains("AGENTS.md"), msg=task)
      // Only the package's own source: no generated file, no nested package.
      if dir == "alpha" {
        assert_eq(Json::array(paths), ["alpha/a.mbt", "alpha/b.mbt"])
      }
      if self.mode == "simplify-incomplete" {
        return Err("failed: step limit")
      }
      let head = self.fixture["head"]
      let (state, base) : (Json, String) = match dir {
        "delta" => ({ "kind": "no_changes" }, head)
        // HEAD moved under this worker: its base is another commit.
        "gamma" =>
          (
            { "kind": "committed", "commit": self.fixture["gamma"] },
            self.fixture["beta"],
          )
        _ => ({ "kind": "committed", "commit": self.fixture[dir] }, head)
      }
      self.workspaces[job] = {
        "kind": "worktree",
        "worktree": {
          "name": name,
          "path": "/tmp/\{name}",
          "branch": "openseek/\{name}--1a2b3c4d-sr-1",
          "base": base,
          "allowed_paths": Json::array(paths),
          "state": state,
        },
      }
      Ok({
        "schema_version": 1,
        "status": if dir == "alpha/nested" {
          "partial"
        } else {
          "done"
        },
        "summary": "simplified \{dir}",
        "verification": "moon check: pass; moon test: pass",
      })
    }
    _ => fail("unexpected start: \{arguments.stringify()}")
  }
}

///|
/// The stub `gh` the sweep calls: it records each call and answers the three
/// it makes.
async fn gh_child(dir : String) -> Unit {
  let args = @env.args()
  append(
    dir + "/gh.jsonl",
    Json::array([ for arg in args[1:] => Json::string(arg) ]).stringify(),
  )
  match args {
    [_, "repo", "view", ..] => println("example/repo")
    [_, "auth", "status", ..] => ()
    [_, "pr", "create", ..] => println("https://github.com/example/repo/pull/7")
    _ => fail("unexpected gh call: \{args.join(" ")}")
  }
}

///|
/// Run git in `cwd` with a fixed identity and return its output.
async fn git(cwd : String, args : Array[String]) -> String {
  let output = @shell.Cmd(
    "git",
    [
      "-c", "user.name=fixture", "-c", "user.email=fixture@example.com", "-c", "commit.gpgsign=false",
      ..args,
    ],
    cwd~,
  ).output(timeout_ms=60000)
  output.check()
  output.stdout()
}

///|
/// The sweep against the fake host, in a real repository whose `origin` is a
/// local bare repository and whose `gh` is the stub above.
async fn verify_simplify(root : String, temp : String, exe : String) -> Unit {
  let artifact = compile(root, temp, "simplify")
  let repo = temp + "/simplify-repo"
  let origin = temp + "/simplify-origin.git"
  for dir in ["alpha/nested", "beta", "delta", "gamma", "empty"] {
    @fs.mkdir(repo + "/" + dir, recursive=true)
  }
  write(repo + "/README.md", "fixture\n")
  write(repo + "/alpha/moon.pkg", "")
  write(repo + "/alpha/a.mbt", "fn a() -> Int {\n  1\n}\n")
  write(repo + "/alpha/b.mbt", "fn b() -> Int {\n  2\n}\n")
  write(repo + "/alpha/generated_x.mbt", "fn x() -> Int {\n  3\n}\n")
  write(repo + "/alpha/pkg.generated.mbti", "package \"alpha\"\n")
  write(repo + "/alpha/nested/moon.pkg", "")
  write(repo + "/alpha/nested/n.mbt", "fn n() -> Int {\n  4\n}\n")
  write(repo + "/beta/moon.pkg", "")
  write(repo + "/beta/b.mbt", "fn b() -> Int {\n  5\n}\n")
  write(repo + "/delta/moon.pkg", "")
  write(repo + "/delta/d.mbt", "fn d() -> Int {\n  6\n}\n")
  write(repo + "/gamma/moon.pkg.json", "{}\n")
  write(repo + "/gamma/g.mbt", "fn g() -> Int {\n  7\n}\n")
  write(repo + "/empty/moon.pkg", "")
  ignore(git(repo, ["init", "-q", "-b", "main"]))
  ignore(git(repo, ["add", "-A"]))
  ignore(git(repo, ["commit", "-q", "-m", "fixture"]))
  ignore(git(temp, ["init", "-q", "--bare", origin]))
  ignore(git(repo, ["remote", "add", "origin", origin]))
  ignore(git(repo, ["push", "-q", "origin", "main"]))
  ignore(git(repo, ["remote", "set-head", "origin", "main"]))
  let head = git(repo, ["rev-parse", "HEAD"]).trim().to_owned()
  // The commits the scripted workers report, one per package, off HEAD.
  let commits : Map[String, String] = Map([])
  for index, dir in ["alpha", "alpha/nested", "beta", "gamma"] {
    ignore(git(repo, ["checkout", "-q", "-b", "work-\{index}", head]))
    let file = match dir {
      "alpha" => "alpha/a.mbt"
      "alpha/nested" => "alpha/nested/n.mbt"
      "beta" => "beta/b.mbt"
      _ => "gamma/g.mbt"
    }
    append(repo + "/" + file, "// simplified")
    ignore(git(repo, ["commit", "-q", "-am", "simplify \{dir}"]))
    commits[dir] = git(repo, ["rev-parse", "HEAD"]).trim().to_owned()
    ignore(git(repo, ["checkout", "-q", "main"]))
  }
  let bin = temp + "/simplify-bin"
  let calls = temp + "/simplify-gh"
  @fs.mkdir(bin)
  @fs.mkdir(calls)
  @fs.symlink(target=exe, bin + "/gh")
  guard @env.get_env_var("PATH") is Some(path) else {
    fail("Test runner needs PATH for moonrun")
  }
  let extra_env : Map[String, String] = {
    "PATH": bin + ":" + path,
    "OPENSEEK_GH_FIXTURE": calls,
  }
  for
    mode in [
      "simplify-publish", "simplify-limit", "simplify-incomplete", "simplify-bad-number",
      "simplify-subdir", "simplify-dirty", "simplify-ahead",
    ] {
    let host = fake_host("simplify", mode)
    host.fixture["head"] = head
    for dir, commit in commits {
      host.fixture[dir] = commit
    }
    if @fs.exists(calls + "/gh.jsonl") {
      @fs.remove(calls + "/gh.jsonl")
    }
    match mode {
      "simplify-dirty" => append(repo + "/alpha/a.mbt", "// local edit")
      "simplify-ahead" => {
        append(repo + "/README.md", "local")
        ignore(git(repo, ["commit", "-q", "-am", "local commit"]))
      }
      _ => ()
    }
    let args = match mode {
      "simplify-publish" =>
        ["--scouts", "2", "--max-prs", "8", "--", "pattern", "matching"]
      "simplify-limit" => ["--no-pr", "--max-prs", "2"]
      "simplify-incomplete" => ["--no-pr", "--path", "beta"]
      "simplify-bad-number" => ["--max-prs", "9"]
      _ => []
    }
    let cwd = if mode == "simplify-subdir" { repo + "/alpha" } else { repo }
    let (code, output) = run_against(
      Some(host),
      artifact,
      args,
      cwd~,
      extra_env~,
    )
    match mode {
      "simplify-dirty" => ignore(git(repo, ["checkout", "--", "alpha/a.mbt"]))
      "simplify-ahead" => ignore(git(repo, ["reset", "-q", "--hard", head]))
      _ => ()
    }
    let labels = host.starts.map(start => {
      match start {
        { "label": String(label), .. } => label
        _ => ""
      }
    })
    let gh_calls = read_calls(calls + "/gh.jsonl")
    let (succeeds, expected) : (Bool, Array[String]) = match mode {
      "simplify-publish" => {
        assert_eq(labels, [
          "simplify:scout-1", "simplify:scout-2", "simplify:alpha", "simplify:alpha/nested",
          "simplify:beta", "simplify:delta", "simplify:review-1", "simplify:gamma",
          "simplify:review-3",
        ])
        guard host.starts.filter_map(start => {
            match start {
              {
                "label": "simplify:alpha",
                "worktree": { "name": String(name), .. },
                ..
              } => Some(name)
              _ => None
            }
          })
          is [name] else {
          fail("no alpha worker")
        }
        // The accepted change is on origin, and its PR targets the default
        // branch by name in the named repository.
        assert_eq(
          git(origin, ["rev-parse", "refs/heads/simplify/\{name}"]).trim(),
          commits["alpha"],
        )
        assert_eq(gh_calls.length(), 3, msg=output)
        assert_true(
          gh_calls[2]
          is [
            "pr",
            "create",
            "--repo",
            "example/repo",
            "--base",
            "main",
            "--head",
            String(branch),
            "--title",
            "refactor(alpha): simplify",
            ..,
          ] &&
          branch == "simplify/\{name}",
          msg=gh_calls[2].stringify(),
        )
        (
          true,
          [
            "alpha: candidates=2 worker=committed \{commits["alpha"][:10]} review=accepted pr=https://github.com/example/repo/pull/7",
            "alpha/nested: candidates=1 worker=reported partial: simplified alpha/nested review=- pr=-",
            "beta: candidates=1 worker=committed",
            "review=rejected",
            "  rejected: loosens an invariant\n  - beta/b.mbt:1: adds mut",
            "kept locally: openseek/",
            "delta: candidates=1 worker=nothing changed",
            "gamma: candidates=1 worker=started from",
            "packages=5 chosen=5 prs=1 accepted=1 rejected=1 skipped=3 tokens=108",
          ],
        )
      }
      "simplify-limit" => {
        assert_eq(
          labels.filter(label => !label.has_prefix("simplify:scout-")),
          ["simplify:alpha", "simplify:alpha/nested", "simplify:review-1"],
        )
        assert_eq(gh_calls.length(), 0, msg=output)
        (
          true,
          [
            "review=unreviewed: no verdict line", "packages=5 chosen=2 prs=0 accepted=0 rejected=0 skipped=1",
          ],
        )
      }
      "simplify-incomplete" => {
        assert_eq(labels, ["simplify:scout-1", "simplify:beta"])
        (
          false,
          [
            "beta: candidates=1 worker=no worktree (failed: step limit)", "packages=1 chosen=1",
            "the sweep is incomplete: the worker for beta did not report",
          ],
        )
      }
      "simplify-bad-number" => (false, ["--max-prs takes a number from 1 to 8"])
      "simplify-subdir" =>
        (false, ["run this from the repository root, not alpha/"])
      "simplify-dirty" =>
        (false, ["commit or stash the changes to tracked files first"])
      _ => (false, ["HEAD is not on origin/main"])
    }
    if mode
      is ("simplify-bad-number"
      | "simplify-subdir"
      | "simplify-dirty"
      | "simplify-ahead") {
      // Preflight stops the run before any child starts.
      assert_eq(labels, [], msg=output)
    }
    assert_eq(code == 0, succeeds, msg=output)
    for part in expected {
      assert_true(
        output.contains(part),
        msg="\{mode}: missing \{part}\n\{output}",
      )
    }
    println("simplify: \{mode} passed")
  }
}
