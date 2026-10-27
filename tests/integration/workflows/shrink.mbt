///|
/// The shrink rounds' scripted children. Each package's worker ends a
/// different way, and a package's worker in a later round reports the commit
/// made for that round.
fn FakeHost::shrink_child(
  self : FakeHost,
  job : String,
  arguments : Json,
) -> Result[Json, String] raise {
  guard arguments
    is { "kind": String(kind), "label": String(label), "input": input, .. } else {
    fail("unexpected start: \{arguments.stringify()}")
  }
  match kind {
    "explore" => {
      guard label.strip_prefix("shrink:review-") is Some(dir) else {
        fail("unexpected explore start: \{label}")
      }
      assert_true(arguments is { "max_steps": 60, .. }, msg=label)
      guard input is { "query": String(query), "hints": String(hints), .. } else {
        fail("review input: \{input.stringify()}")
      }
      let dir = dir.to_owned()
      let round = self.fixture["round:\{dir}"]
      assert_true(hints.contains("# Shrinking a MoonBit package's public API"))
      assert_true(
        query.contains("Package: \{dir}") &&
        query.contains("Commit: \{self.fixture["\{dir}#\{round}"]}") &&
        query.contains("Base: \{self.fixture["base#\{round}"]}") &&
        query.contains("## The candidates it had to resolve\n- `pub fn"),
        msg=query,
      )
      match dir {
        "alpha" =>
          Ok({
            "answer": "VERDICT: ACCEPT\nevery demoted item is unused\nthe seam names its users",
            "citations": [],
          })
        "gamma" =>
          Ok({ "answer": "VERDICT: ACCEPT\ndeleted dead code", "citations": [] })
        "beta" =>
          Ok({
            "answer": "VERDICT: REJECT\nblessed without a reason",
            "citations": [
              { "file": "beta/exports.mbt", "line": 1, "note": "no reason" },
            ],
          })
        _ => Err("unexpected review of \{dir}")
      }
    }
    "worker" => {
      guard label.strip_prefix("shrink:") is Some(dir) &&
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
        name.has_prefix("shrink-") &&
        name
        .iter()
        .all(char => {
          (char >= 'a' && char <= 'z') ||
          (char >= '0' && char <= '9') ||
          char == '-'
        }),
        msg=name,
      )
      assert_true(context.contains("exports.mbt"), msg=context)
      assert_true(task.contains("AGENTS.md"), msg=task)
      let round = match self.fixture.get("round:\{dir}") {
        Some("1") => "2"
        Some(_) => "3"
        None => "1"
      }
      self.fixture["round:\{dir}"] = round
      let continuing = self.mode == "shrink-continue"
      if dir == "alpha" && round == "1" && !continuing {
        // The package's own source, its interface and its exports.mbt: no
        // generated file, no nested package.
        assert_eq(Json::array(paths), [
          "alpha/a.mbt", "alpha/a_test.mbt", "alpha/reexport.mbt", "alpha/moon.pkg",
          "alpha/moon.pkg.json", "alpha/exports.mbt", "alpha/alpha_wbtest.mbt", "alpha/pkg.generated.mbti",
        ])
        // Only the candidates: no blessed export, no used item, no member,
        // no trait implementation.
        for
          row in [
            "`pub fn dead() -> Int  // usage: 0 (0 in test)`", "`pub fn seam() -> Int  // usage: 3 (3 in test)`",
            "`pub(all) struct Wide {  // (all) or (open) can be removed`",
          ] {
          assert_true(task.contains(row), msg=task)
        }
        for
          row in [
            "kept", "Url", "used", "impl Show", "x : Int", "Wide::equal", "type Model",
            "pub using", "Origin", "other_name", "Seed::make",
          ] {
          assert_true(!task.contains(row), msg="\{row} in \{task}")
        }
      }
      // A test kit's test-only items are its purpose; its unused one is not.
      if dir == "kit" {
        assert_true(task.contains("pub fn stray()") && !task.contains("seed"))
      }
      if dir == "alpha" && (round == "2" || continuing) {
        assert_true(task.contains("pub fn cascade() -> Int"), msg=task)
      }
      let base = self.fixture["base#\{round}"]
      let state : Json = match self.fixture.get("\{dir}#\{round}") {
        Some(commit) => { "kind": "committed", "commit": commit }
        None => { "kind": "no_changes" }
      }
      let workspace = (state : Json) => {
        (
          {
            "kind": "worktree",
            "worktree": {
              "name": name,
              "path": "/tmp/\{name}",
              "branch": "work-\{dir.replace_all(old="/", new="-")}-\{round}",
              "base": base,
              "allowed_paths": Json::array(paths),
              "state": state,
            },
          } : Json)
      }
      self.workspaces[job] = workspace(state)
      // Beta's first read races its capture.
      if dir == "beta" {
        self.workspaces[job] = workspace({ "kind": "working" })
        self.fixture["capture:\{job}"] = workspace(state).stringify()
      }
      Ok({
        "schema_version": 1,
        "status": "done",
        "summary": WorkerSummary,
        "verification": "moon check --deny-warn: pass; moon test: pass",
      })
    }
    _ => fail("unexpected start: \{arguments.stringify()}")
  }
}

///|
/// What every scripted worker reports having done.
const WorkerSummary : String = "dead: deleted; seam: exports.mbt (tests of beta use it); Wide: narrowed"

///|
/// The stub `moon` the rounds call: `ide analyze` prints the canned analysis
/// for its turn (none once they run out), and `check` passes unless told to
/// fail. Each call is recorded with the commit it ran at.
async fn moon_child(dir : String) -> Unit {
  let args = @env.args()[1:].to_owned()
  let head = @shell.Cmd("git", ["rev-parse", "HEAD"]).output(timeout_ms=30000)
  head.check()
  let calls = read_calls(dir + "/moon.jsonl")
  append(
    dir + "/moon.jsonl",
    (
      {
        "args": Json::array(args.map(Json::string)),
        "head": head.stdout().trim(),
        "in_sub": @fs.realpath(".").has_suffix("/sub"),
      } : Json).stringify(),
  )
  match args {
    ["ide", "analyze"] => {
      let turn = calls
        .filter(call => call is { "args": ["ide", ..], .. })
        .length() +
        1
      let canned = dir + "/analyze-\{turn}.txt"
      if @fs.exists(canned) {
        println(@fs.read_file(canned).text())
      }
    }
    ["check", ..] if @fs.exists(dir + "/fail-check") =>
      fail("error: unused function `dead`")
    ["check", ..] => ()
    _ => fail("unexpected moon call: \{args.join(" ")}")
  }
}

///|
/// What `moon ide analyze` prints in the fixture's rounds: padded rows, a
/// `//` inside a value, a blessed export, a member row, a trait
/// implementation, a nested module, and a package with no directory.
const FirstAnalysis : String =
  #|package "fx/app/alpha"
  #|
  #|// Values
  #|pub const Url : String = "https://a//b"          // usage: 1 (0 in test)
  #|pub fn used() -> Int                             // usage: 2 (1 in test)
  #|pub fn dead() -> Int                             // usage: 0 (0 in test)
  #|pub fn seam() -> Int                             // usage: 3 (3 in test)
  #|pub fn kept() -> Int                             // usage: 0 (0 in test), in exports.mbt
  #|pub using @kit {type Seed}                       // usage: 0 (0 in test)
  #|pub const Origin : String = "https://a//b"       // usage: 0 (0 in test)
  #|pub fn other_name() -> Int                       // usage: 0 (0 in test)
  #|pub fn Seed::make() -> Seed                      // usage: 0 (0 in test)
  #|
  #|// Types and methods
  #|pub(all) struct Wide {                           // (all) or (open) can be removed
  #|  x : Int                                        // usage: 0 (0 in test)
  #|} derive(Eq)
  #|pub fn Wide::equal(Self, Self) -> Bool
  #|pub impl Show for Wide                           // usage: 0 (0 in test)
  #|
  #|type Model derive(Eq)
  #|
  #|package "fx/app/alpha/nested"
  #|
  #|pub fn n() -> Int                                // usage: 1 (0 in test)
  #|
  #|package "fx/app/beta"
  #|
  #|pub fn b() -> Int                                // usage: 0 (0 in test)
  #|
  #|package "fx/app/gamma"
  #|
  #|pub fn g() -> Int                                // usage: 0 (0 in test)
  #|
  #|package "fx/app/kit"
  #|
  #|pub fn seed() -> Int                             // usage: 2 (2 in test)
  #|pub fn stray() -> Int                            // usage: 0 (0 in test)
  #|
  #|package "fx/sub/delta"
  #|
  #|pub fn d() -> Int                                // usage: 0 (0 in test)
  #|
  #|package "fx/app/ghost"
  #|
  #|pub fn g() -> Int                                // usage: 0 (0 in test)

///|
/// Round 1 deleted `dead`, which was the only user of `cascade`.
const SecondAnalysis : String =
  #|package "fx/app/alpha"
  #|
  #|pub fn cascade() -> Int                          // usage: 0 (0 in test)
  #|
  #|package "fx/app/beta"
  #|
  #|pub fn b() -> Int                                // usage: 0 (0 in test)
  #|
  #|package "fx/app/kit"
  #|
  #|pub fn stray() -> Int                            // usage: 0 (0 in test)
  #|
  #|package "fx/sub/delta"
  #|
  #|pub fn d() -> Int                                // usage: 0 (0 in test)

///|
/// What the run gave up on is left, and so is the item alpha's second
/// change was given and did not resolve.
const ThirdAnalysis : String =
  #|package "fx/app/alpha"
  #|
  #|pub fn cascade() -> Int                          // usage: 0 (0 in test)
  #|
  #|package "fx/app/beta"
  #|
  #|pub fn b() -> Int                                // usage: 0 (0 in test)
  #|
  #|package "fx/app/kit"
  #|
  #|pub fn stray() -> Int                            // usage: 0 (0 in test)
  #|
  #|package "fx/sub/delta"
  #|
  #|pub fn d() -> Int                                // usage: 0 (0 in test)

///|
/// A parent package skipped by name, with an eligible package nested in it.
const NestedAnalysis : String =
  #|package "fx/app/alpha"
  #|
  #|pub fn dead() -> Int                             // usage: 0 (0 in test)
  #|
  #|package "fx/app/alpha/nested"
  #|
  #|pub fn n() -> Int                                // usage: 0 (0 in test)

///|
/// Git with a fixed committer, so the script's cherry-pick and the test's
/// prediction of it make the same commit.
async fn pinned_git(cwd : String, args : Array[String]) -> String {
  let output = @shell.Cmd(
    "git",
    args,
    cwd~,
    env=pinned_env(),
    inherit_env=false,
  ).output(timeout_ms=60000)
  output.check()
  output.stdout()
}

///|
fn pinned_env() -> Map[String, String] {
  let env = clean_env()
  env["GIT_COMMITTER_NAME"] = "fixture"
  env["GIT_COMMITTER_EMAIL"] = "fixture@example.com"
  env["GIT_COMMITTER_DATE"] = "2026-01-01T00:00:00Z"
  env
}

///|
/// The rounds against the fake host, in a real repository whose `origin` is
/// a local bare repository and whose `gh` and `moon` are stubs.
async fn verify_shrink(root : String, temp : String, exe : String) -> Unit {
  let artifact = compile(root, temp, "shrink")
  let repo = temp + "/shrink-repo"
  let origin = temp + "/shrink-origin.git"
  for dir in ["alpha/nested", "beta", "gamma", "kit", "sub/src/delta"] {
    @fs.mkdir(repo + "/" + dir, recursive=true)
  }
  write(repo + "/README.md", "fixture\n")
  write(repo + "/moon.mod", "name = \"fx/app\"\n\nversion = \"0.1.0\"\n")
  // A module whose packages live under its `source` directory.
  write(
    repo + "/sub/moon.mod.json",
    "{\n  \"name\": \"fx/sub\",\n  \"source\": \"src/\"\n}\n",
  )
  write(
    repo + "/alpha/moon.pkg",
    "import {\n  \"fx/app/kit\",\n} for \"test\"\n",
  )
  write(repo + "/kit/moon.pkg", "")
  write(repo + "/gamma/moon.pkg", "")
  write(repo + "/gamma/g.mbt", "pub fn g() -> Int {\n  8\n}\n")
  write(repo + "/kit/k.mbt", "pub fn stray() -> Int {\n  7\n}\n")
  write(repo + "/alpha/a.mbt", "pub fn dead() -> Int {\n  1\n}\n")
  write(repo + "/alpha/a_test.mbt", "test {\n  ignore(@alpha.dead())\n}\n")
  // Re-exports: the analyzer lists the value and the renamed function as
  // plain declarations, and counts no use that goes through them.
  write(
    repo + "/alpha/reexport.mbt",
    "///|\npub using @kit {\n  Origin,\n  type Seed,\n  stray as other_name,\n}\n",
  )
  write(repo + "/alpha/generated_x.mbt", "fn x() -> Int {\n  3\n}\n")
  write(
    repo + "/alpha/pkg.generated.mbti",
    "package \"fx/app/alpha\"\n\npub fn dead() -> Int\npub fn seam() -> Int\n",
  )
  write(repo + "/alpha/nested/moon.pkg", "")
  write(repo + "/alpha/nested/n.mbt", "pub fn n() -> Int {\n  4\n}\n")
  write(repo + "/beta/moon.pkg", "")
  write(repo + "/beta/b.mbt", "pub fn b() -> Int {\n  5\n}\n")
  write(repo + "/sub/src/delta/moon.pkg", "")
  write(repo + "/sub/src/delta/d.mbt", "pub fn d() -> Int {\n  6\n}\n")
  ignore(git(repo, ["init", "-q", "-b", "main"]))
  ignore(git(repo, ["config", "user.name", "fixture"]))
  ignore(git(repo, ["config", "user.email", "fixture@example.com"]))
  ignore(git(repo, ["config", "commit.gpgsign", "false"]))
  ignore(git(repo, ["add", "-A"]))
  ignore(git(repo, ["commit", "-q", "-m", "fixture"]))
  ignore(git(temp, ["init", "-q", "--bare", origin]))
  ignore(git(repo, ["remote", "add", "origin", origin]))
  ignore(git(repo, ["push", "-q", "origin", "main"]))
  ignore(git(repo, ["remote", "set-head", "origin", "main"]))
  let head = git(repo, ["rev-parse", "HEAD"]).trim().to_owned()
  // The commits the scripted workers report, each on its round's base: the
  // first round's off HEAD, the second's off the first round's tip, which
  // the test predicts by making the script's cherry-pick itself.
  let commit = async fn(
    branch : String,
    base : String,
    files : Array[(String, String)],
  ) {
    ignore(git(repo, ["checkout", "-q", "-b", branch, base]))
    for file in files {
      write(repo + "/" + file.0, file.1)
    }
    ignore(git(repo, ["add", "-A"]))
    ignore(git(repo, ["commit", "-q", "-m", "shrink \{branch}"]))
    let made = git(repo, ["rev-parse", "HEAD"]).trim().to_owned()
    ignore(git(repo, ["checkout", "-q", "main"]))
    made
  }
  // Alpha's first change drops `dead` from its interface and keeps `seam`
  // in exports.mbt.
  let alpha1 = commit("work-alpha-1", head, [
    ("alpha/a.mbt", "fn dead() -> Int {\n  1\n}\n"),
    (
      "alpha/pkg.generated.mbti", "package \"fx/app/alpha\"\n\npub fn seam() -> Int\n",
    ),
    (
      "alpha/exports.mbt", "///|\n/// Test seam for beta's tests.\npub fn seam() -> Int {\n  2\n}\n",
    ),
    // Its blackbox test moved to a whitebox file; the worker could only
    // empty it.
    ("alpha/a_test.mbt", "///|\n// Moved to alpha_wbtest.mbt.\n"),
  ])
  let beta1 = commit("work-beta-1", head, [
    ("beta/b.mbt", "fn b() -> Int {\n  5\n}\n"),
  ])
  let gamma1 = commit("work-gamma-1", head, [
    ("gamma/g.mbt", "fn g() -> Int {\n  8\n}\n"),
  ])
  // A change that cannot be combined with alpha's: it edits alpha's file.
  let clash = commit("work-clash", head, [("alpha/a.mbt", "clash\n")])
  ignore(git(repo, ["checkout", "-q", "--detach", head]))
  // Each pick is amended into a commit named for its package, with the
  // worker's summary as the body.
  let reword = (dir : String) => {
    [
      "commit",
      "-q",
      "--amend",
      "-m",
      "refactor(\{dir}): shrink public API",
      "-m",
      WorkerSummary,
    ]
  }
  ignore(pinned_git(repo, ["cherry-pick", alpha1]))
  ignore(pinned_git(repo, ["rm", "-q", "--", "alpha/a_test.mbt"]))
  ignore(pinned_git(repo, reword("alpha")))
  ignore(pinned_git(repo, ["cherry-pick", gamma1]))
  ignore(pinned_git(repo, reword("gamma")))
  let tip1 = git(repo, ["rev-parse", "HEAD"]).trim().to_owned()
  ignore(git(repo, ["checkout", "-q", "main"]))
  let alpha2 = commit("work-alpha-2", tip1, [
    ("alpha/a.mbt", "fn dead() -> Int {\n  2\n}\n"),
  ])
  ignore(git(repo, ["checkout", "-q", "--detach", tip1]))
  ignore(pinned_git(repo, ["cherry-pick", alpha2]))
  ignore(pinned_git(repo, reword("alpha")))
  let tip2 = git(repo, ["rev-parse", "HEAD"]).trim().to_owned()
  ignore(git(repo, ["checkout", "-q", "main"]))
  let bin = temp + "/shrink-bin"
  let calls = temp + "/shrink-calls"
  @fs.mkdir(bin)
  @fs.mkdir(calls)
  @fs.symlink(target=exe, bin + "/gh")
  @fs.symlink(target=exe, bin + "/moon")
  write(calls + "/analyze-1.txt", FirstAnalysis)
  write(calls + "/analyze-2.txt", SecondAnalysis)
  write(calls + "/analyze-3.txt", ThirdAnalysis)
  guard @env.get_env_var("PATH") is Some(path) else {
    fail("Test runner needs PATH for moonrun")
  }
  let extra_env = pinned_env()
  extra_env["PATH"] = bin + ":" + path
  extra_env["OPENSEEK_GH_FIXTURE"] = calls
  extra_env["OPENSEEK_MOON_FIXTURE"] = calls
  // The arguments the bounded run prints, which the next mode runs.
  let mut continued = ""
  let branch1 = "shrink/r1-\{tip1[:8]}"
  let branch2 = "shrink/r2-\{tip2[:8]}"
  for
    mode in [
      "shrink-publish", "shrink-check-fails", "shrink-conflict", "shrink-rounds",
      "shrink-continue", "shrink-none", "shrink-skip", "shrink-fixed", "shrink-bad-number",
      "shrink-subdir", "shrink-dirty", "shrink-ahead", "shrink-stack-on",
    ] {
    let host = fake_host("shrink", mode)
    host.fixture["base#1"] = head
    host.fixture["base#2"] = tip1
    host.fixture["alpha#1"] = alpha1
    host.fixture["beta#1"] = beta1
    host.fixture["alpha#2"] = alpha2
    host.fixture["gamma#1"] = if mode == "shrink-conflict" {
      clash
    } else {
      gamma1
    }
    let start = if mode == "shrink-continue" { branch1 } else { "main" }
    if mode == "shrink-continue" {
      // The continuation starts from round 1's branch, where the analysis is
      // the second one and alpha's change is made on round 1's tip.
      host.fixture["base#1"] = tip1
      host.fixture["alpha#1"] = alpha2
      write(calls + "/analyze-1.txt", SecondAnalysis)
      ignore(git(repo, ["checkout", "-q", branch1]))
    }
    if mode == "shrink-skip" {
      write(calls + "/analyze-1.txt", NestedAnalysis)
    }
    for file in ["gh.jsonl", "moon.jsonl"] {
      if @fs.exists(calls + "/" + file) {
        @fs.remove(calls + "/" + file)
      }
    }
    match mode {
      "shrink-dirty" => append(repo + "/alpha/a.mbt", "// local edit")
      "shrink-check-fails" => write(calls + "/fail-check", "")
      "shrink-ahead" => {
        append(repo + "/README.md", "local")
        ignore(git(repo, ["commit", "-q", "-am", "local commit"]))
      }
      // A branch on origin whose tip is not HEAD.
      "shrink-stack-on" =>
        ignore(git(repo, ["push", "-q", "origin", "\{beta1}:refs/heads/other"]))
      _ => ()
    }
    let args = match mode {
      "shrink-publish" =>
        [
          "--check-target", "native", "--check-target", "js", "--check-in", "sub",
          "--exclude", "sub", "--", "keep", "the", "protocol",
        ]
      // Exactly what the bounded run printed.
      "shrink-continue" =>
        continued.split(" ").map(arg => arg.to_owned()).collect()
      "shrink-check-fails" | "shrink-conflict" => ["--no-pr"]
      "shrink-rounds" => ["--no-pr", "--rounds", "1"]
      "shrink-none" => ["--no-pr", "--path", "beta"]
      "shrink-skip" => ["--no-pr", "--rounds", "1", "--skip", "alpha"]
      "shrink-stack-on" => ["--stack-on", "other"]
      "shrink-fixed" => ["--no-pr", "--path", "nowhere"]
      "shrink-bad-number" => ["--max-packages", "17"]
      _ => []
    }
    let cwd = if mode == "shrink-subdir" { repo + "/alpha" } else { repo }
    let (code, output) = run_against(
      Some(host),
      artifact,
      args,
      cwd~,
      extra_env~,
    )
    match mode {
      "shrink-dirty" => ignore(git(repo, ["checkout", "--", "alpha/a.mbt"]))
      "shrink-check-fails" => @fs.remove(calls + "/fail-check")
      "shrink-ahead" => ignore(git(repo, ["reset", "-q", "--hard", head]))
      _ => ()
    }
    // Whatever happened, the checkout is back where it was, with no pick
    // left half done.
    assert_eq(
      git(repo, ["rev-parse", "--abbrev-ref", "HEAD"]).trim(),
      start,
      msg=output,
    )
    assert_true(!@fs.exists(repo + "/.git/CHERRY_PICK_HEAD"), msg=output)
    assert_eq(git(repo, ["status", "--porcelain"]).trim(), "", msg=output)
    if mode == "shrink-skip" {
      write(calls + "/analyze-1.txt", FirstAnalysis)
    }
    if mode == "shrink-continue" {
      write(calls + "/analyze-1.txt", FirstAnalysis)
      ignore(git(repo, ["checkout", "-q", "main"]))
      ignore(git(repo, ["branch", "-D", branch1, "shrink/r1-\{tip2[:8]}"]))
    }
    assert_eq(git(repo, ["rev-parse", "HEAD"]).trim(), head)
    let labels = host.starts.map(start => {
      match start {
        { "label": String(label), .. } => label
        _ => ""
      }
    })
    let gh_calls = read_calls(calls + "/gh.jsonl")
    let moon_calls = read_calls(calls + "/moon.jsonl").map(call => {
      guard call is { "args": Array(args), "head": String(at), .. } else {
        fail("moon call: \{call.stringify()}")
      }
      let at = if at == head {
        "head"
      } else if at == tip1 {
        "tip1"
      } else if at == tip2 {
        "tip2"
      } else {
        at
      }
      let words = [ for arg in args if arg is String(word) => word ]
      let place = if call is { "in_sub": True, .. } { " in sub" } else { "" }
      "\{words.join(" ")} @\{at}\{place}"
    })
    let (succeeds, expected) : (Bool, Array[String]) = match mode {
      "shrink-publish" => {
        assert_eq(
          labels,
          [
            "shrink:alpha", "shrink:beta", "shrink:gamma", "shrink:kit", "shrink:review-alpha",
            "shrink:review-beta", "shrink:review-gamma", "shrink:alpha", "shrink:review-alpha",
          ],
          msg=output,
        )
        // Each round is analyzed at its base and checked once per target
        // at its tip.
        assert_eq(moon_calls, [
          "ide analyze @head", "check --deny-warn --no-mbti --target native @tip1",
          "check --deny-warn --no-mbti --target js @tip1", "check --deny-warn --no-mbti @tip1 in sub",
          "ide analyze @tip1", "check --deny-warn --no-mbti --target native @tip2",
          "check --deny-warn --no-mbti --target js @tip2", "check --deny-warn --no-mbti @tip2 in sub",
          "ide analyze @tip2",
        ])
        // Both rounds are on origin, and the second PR is stacked on the
        // first's branch.
        assert_eq(
          git(origin, ["rev-parse", "refs/heads/\{branch1}"]).trim(),
          tip1,
        )
        assert_eq(
          git(origin, ["rev-parse", "refs/heads/\{branch2}"]).trim(),
          tip2,
        )
        assert_eq(gh_calls.length(), 4, msg=output)
        assert_true(
          gh_calls[0] is ["repo", "view", String(url), ..] && url == origin,
          msg=gh_calls[0].stringify(),
        )
        for
          index, (base, head_branch, title) in [
            ("main", branch1, "refactor: shrink public API (round 1)"),
            (branch1, branch2, "refactor: shrink public API (round 2)"),
          ] {
          assert_true(
            gh_calls[index + 2]
            is [
              "pr",
              "create",
              "--repo",
              "example/repo",
              "--base",
              String(got_base),
              "--head",
              String(got_head),
              "--title",
              String(got_title),
              "--body",
              String(body),
            ] &&
            got_base == base &&
            got_head == head_branch &&
            got_title == title &&
            body.contains("### `alpha`") &&
            (index == 1 || body.contains("### `gamma`")) &&
            body.contains("the seam names its users") &&
            !body.contains("### `beta`"),
            msg=gh_calls[index + 2].stringify(),
          )
        }
        // The test file alpha's worker emptied is gone, in alpha's commit:
        // round 1 is one commit per package.
        assert_eq(
          git(repo, ["ls-tree", "--name-only", tip1, "alpha/a_test.mbt"]).trim(),
          "",
        )
        assert_eq(git(repo, ["rev-parse", "\{tip1}~2"]).trim(), head)
        assert_eq(
          git(repo, ["log", "--format=%s", "\{head}..\{tip1}"]).trim(),
          "refactor(gamma): shrink public API\nrefactor(alpha): shrink public API",
        )
        // Each round keeps a local branch to continue from.
        assert_eq(git(repo, ["rev-parse", branch1]).trim(), tip1)
        assert_eq(git(repo, ["rev-parse", branch2]).trim(), tip2)
        ignore(git(repo, ["branch", "-D", branch1, branch2]))
        // The combined workers' branches are gone; the rejected one's stays.
        assert_eq(git(repo, ["branch", "--list", "work-alpha-1"]).trim(), "")
        assert_eq(
          git(repo, ["branch", "--list", "work-beta-1"]).trim(),
          "work-beta-1",
        )
        (
          true,
          [
            "round 1: packages=4 chosen=4",
            "  alpha: candidates=3 worker=committed \{alpha1[:10]} review=accepted",
            "  beta: candidates=1 worker=committed",
            "    rejected: blessed without a reason\n  - beta/exports.mbt:1: no reason",
            "    kept locally: work-beta-1",
            "  gamma: candidates=1 worker=committed \{gamma1[:10]} review=accepted",
            "  kit: candidates=1 worker=nothing changed review=-",
            "round 1: accepted=2 tip=\{tip1[:10]} api: pkg.generated.mbti -1 +0, exports.mbt +5 pr=https://github.com/example/repo/pull/7",
            "round 2: packages=1 chosen=1",
            "  alpha: candidates=1 worker=committed \{alpha2[:10]} review=accepted",
            "round 2: accepted=1 tip=\{tip2[:10]}",
            "stack: \{branch1} https://github.com/example/repo/pull/7",
            "  alpha: unresolved after its change: pub fn cascade() -> Int",
            "fixed point except alpha beta kit sub/src/delta: rounds=2 starts=9 tokens=108",
            "continue from \{branch2}: --check-target native --check-target js --check-in sub --stack-on \{branch2} --exclude sub --skip beta --skip kit --skip alpha -- keep the protocol",
          ],
        )
      }
      "shrink-check-fails" => {
        assert_eq(moon_calls, [
          "ide analyze @head", "check --deny-warn --no-mbti @tip1",
        ])
        // The round that failed its check stays on a local branch.
        assert_eq(git(repo, ["rev-parse", branch1]).trim(), tip1)
        ignore(git(repo, ["branch", "-D", branch1]))
        (
          false,
          [
            "round 1 (\{branch1}) fails its check: moon check --deny-warn --no-mbti:\n",
            "error: unused function `dead`",
            "stopped: round 1 fails its check: rounds=1",
          ],
        )
      }
      "shrink-conflict" => {
        assert_eq(moon_calls, ["ide analyze @head"])
        (false, ["round 1: the accepted changes do not combine: "])
      }
      "shrink-rounds" => {
        assert_eq(gh_calls.length(), 0, msg=output)
        // Round 1's branch stays for the next mode, which continues from it.
        assert_eq(git(repo, ["rev-parse", branch1]).trim(), tip1)
        let prefix = "continue from \{branch1}: "
        guard output
          .split("\n")
          .filter_map(line => line.strip_prefix(prefix))
          .head()
          is Some(rest) else {
          fail("no continuation line\n\{output}")
        }
        continued = rest.to_owned()
        (
          true,
          [
            "round 1: accepted=2 tip=\{tip1[:10]} api: pkg.generated.mbti -1 +0, exports.mbt +5 pr=branch \{branch1}",
            "stopped: --rounds 1: rounds=1",
            "\{prefix}--no-pr --rounds 1 --skip beta --skip kit --skip sub/src/delta",
          ],
        )
      }
      "shrink-continue" => {
        // The given-up packages stay given up, and the limit holds: one
        // round, from round 1's tip, for alpha alone.
        assert_eq(labels, ["shrink:alpha", "shrink:review-alpha"], msg=output)
        assert_eq(moon_calls, [
          "ide analyze @tip1", "check --deny-warn --no-mbti @tip2",
        ])
        (
          true,
          [
            "round 1: packages=1 chosen=1",
            "round 1: accepted=1 tip=\{tip2[:10]}",
            "stopped: --rounds 1: rounds=1",
          ],
        )
      }
      "shrink-none" => {
        // A round with nothing accepted publishes nothing, and its package
        // is not offered again.
        assert_eq(labels, ["shrink:beta", "shrink:review-beta"], msg=output)
        assert_eq(moon_calls, ["ide analyze @head", "ide analyze @head"])
        (
          true,
          [
            "round 1: nothing accepted", "fixed point except beta: rounds=1 starts=2",
            "continue from main: --path beta --no-pr --skip beta",
          ],
        )
      }
      "shrink-skip" => {
        // --skip names one package: the package nested in it is still
        // offered.
        assert_eq(labels, ["shrink:alpha/nested"], msg=output)
        (
          true,
          [
            "round 1: packages=1 chosen=1", "stopped: --rounds 1", "continue from main: --no-pr --rounds 1 --skip alpha --skip alpha/nested",
          ],
        )
      }
      "shrink-fixed" => {
        assert_eq(labels, [])
        (true, ["fixed point: rounds=0 starts=0 tokens=0"])
      }
      "shrink-bad-number" =>
        (false, ["--max-packages takes a number from 1 to 16"])
      "shrink-subdir" =>
        (false, ["run this from the repository root, not alpha/"])
      "shrink-dirty" =>
        (false, ["commit or stash the changes to tracked files first"])
      "shrink-stack-on" =>
        (false, ["HEAD is not origin/other: check out the last round's branch"])
      _ => (false, ["HEAD is not on origin/main"])
    }
    if mode
      is ("shrink-bad-number"
      | "shrink-subdir"
      | "shrink-dirty"
      | "shrink-ahead"
      | "shrink-stack-on") {
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
    println("shrink: \{mode} passed")
  }
}
