///|
/// Run `source` in a fresh, auto-cleaned workspace, which is also the default
/// working directory the program runs in.
async fn run(source : String) -> @agent_tool.ToolOutput {
  @vfs.with_tmpdir(prefix="mbtx-ws-", ws => run_in(ws, { "source": source }))
}

///|
/// Run with an explicit `workspace_root` and raw arguments (for cwd / target /
/// decode-failure cases).
async fn run_in(
  workspace_root : String,
  arguments : Json,
) -> @agent_tool.ToolOutput {
  let action = match @mbtx.definition(workspace_root~).execute {
    Async(execute) => execute(arguments)
    Sync(_) => fail("mbtx should be async")
  }
  guard action is Respond(output) else { fail("expected Respond") }
  output
}

///|
async test "runs a pure-core program and returns its output" {
  let out = run("fn main { println(6 * 7) }")
  assert_false(out.is_error)
  assert_true(out.content.contains("42"))
}

///|
async test "surfaces a compile error via moon's own diagnostics" {
  let out = run("fn main { let _x : Int = \"nope\" }")
  assert_true(out.is_error)
  assert_true(
    out.content.to_lower().contains("type") || out.content.contains("String"),
  )
  // ...and labeled as the BUILD phase failing: the synchronous build phase
  // returned nonzero, so the program never started — by construction, not by
  // probing artifacts or parsing diagnostics.
  assert_true(out.content.contains("BUILD failed"))
  assert_true(out.content.contains("never ran"))
  assert_true(out.brief is Some("mbtx (build failed, exit=1)"))
}

///|
/// The stage labels are structural (which phase's process failed), so program
/// OUTPUT cannot sway them: compiler-diagnostic-shaped text is routinely a
/// snippet's legitimate output — a child `moon check` run prints exactly that
/// — and must not turn a runtime trap into a build failure or taint a clean
/// exit.
async test "a runtime trap is labeled as the run, whatever the output says" {
  let out = run(
    "fn main { println(\"Error: [4014] fake diagnostic\"); panic() }",
  )
  assert_true(out.is_error)
  assert_true(out.content.contains("at RUNTIME"))
  assert_true(out.content.contains("from the run, not the build"))
  assert_false(out.content.contains("BUILD failed"))
}

///|
async test "diagnostic-shaped output with a clean exit stays unlabeled" {
  let out = run("fn main { println(\"Error: [4014] fake diagnostic\") }")
  assert_false(out.is_error)
  assert_false(out.content.contains("BUILD failed"))
  assert_false(out.content.contains("at RUNTIME"))
}

///|
/// The build phase has its own bound, and hitting it is reported as the build
/// never finishing — the program is never blamed, because it never existed.
/// The 1ms bound is a physical impossibility, not a latency guess: `moon`
/// cannot even be spawned and waited on within it.
async test "a build that outlives its bound is reported as the build's" {
  @vfs.with_tmpdir(prefix="mbtx-build-bound-", ws => {
    let definition = @mbtx.definition(workspace_root=ws, build_timeout_ms=1)
    let action = match definition.execute {
      Async(execute) => execute({ "source": "fn main { println(1) }" })
      Sync(_) => fail("mbtx should be async")
    }
    guard action is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(output.content.contains("BUILD did not finish"))
    assert_true(output.content.contains("never ran"))
    assert_true(output.brief is Some("mbtx (build timeout)"))
  })
}

///|
/// A run that never finishes still carries the build phase's warnings: they
/// exist only in the build capture, and the timeout report is their one ride
/// to the model — alongside the staged wording that only the PROGRAM can be
/// what hung, since the build had already succeeded.
async test "a run timeout carries build warnings and blames only the program" {
  @vfs.with_tmpdir(prefix="mbtx-timeout-warn-", ws => {
    let definition = @mbtx.definition(
      workspace_root=ws,
      foreground_timeout_ms=500,
    )
    let source =
      #|import { "moonbitlang/async" }
      #|
      #|async fn main {
      #|  let unused = 1
      #|  @async.sleep(60_000)
      #|}
    let action = match definition.execute {
      Async(execute) => execute({ "source": source, "warning": "on" })
      Sync(_) => fail("mbtx should be async")
    }
    guard action is Respond(output) else { fail("expected Respond") }
    assert_true(output.is_error)
    assert_true(output.content.contains("timed out"))
    assert_true(output.content.contains("the PROGRAM that did not finish"))
    assert_true(output.content.contains("Unused variable"))
  })
}

///|
/// Only the wasm target is staged; a single-shot target's one exit code
/// covers both phases and its report deliberately claims neither.
async test "a non-wasm failure carries no stage label" {
  let out = run_in(".", {
    "source": "fn main { println(\"before\"); panic() }",
    "target": "js",
  })
  assert_true(out.is_error)
  assert_true(out.content.contains("exited"))
  assert_false(out.content.contains("at RUNTIME"))
  assert_false(out.content.contains("BUILD failed"))
}

///|
async test "reads a workspace file by a RELATIVE path (default cwd = workspace)" {
  @vfs.with_tmpdir(ws => {
    @fs.write_file("\{ws}/note.txt", "one\ntwo\n", create_mode=CreateOrTruncate)
    let out = run_in(ws, {
      "source": (
        #|import { "moonbitlang/async", "moonbitlang/async/fs", "moonbitlang/async/stdio" }
        #|
        #|async fn main {
        #|  let text = @fs.read_file("note.txt").text()
        #|  @stdio.stdout.write("lines=\{[..text.split("\n")].filter(l => !l.is_empty()).length()}\n")
        #|}
      ),
    })
    assert_false(out.is_error)
    assert_true(out.content.contains("lines=2"))
  })
}

///|
async test "cwd argument overrides the working directory" {
  @vfs.with_tmpdir(elsewhere => {
    @vfs.with_tmpdir(target => {
      @fs.write_file(
        "\{target}/marker.txt",
        "CWD-OK\n",
        create_mode=CreateOrTruncate,
      )
      // workspace_root is `elsewhere` (no marker), but cwd points at `target`.
      let out = run_in(elsewhere, {
        "source": (
          #|import { "moonbitlang/async", "moonbitlang/async/fs", "moonbitlang/async/stdio" }
          #|
          #|async fn main {
          #|  @stdio.stdout.write(@fs.read_file("marker.txt").text())
          #|}
        ),
        "cwd": target,
      })
      assert_false(out.is_error)
      assert_true(out.content.contains("CWD-OK"))
    })
  })
}

///|
async test "a non-existent cwd is reported, not run" {
  let out = run_in(".", {
    "source": "fn main { println(1) }",
    "cwd": "/no/such/mbtx/dir",
  })
  assert_true(out.is_error)
  assert_true(out.content.contains("does not exist"))
}

///|
/// Gate on the same preparation `execute` performs — skip where enforcement is
/// unavailable (not macOS, or a nested sandbox). Probed against a throwaway
/// root so no real workspace is scanned.
async fn sandbox_enforcement_available() -> Bool {
  // A host where even tmpdir fails must skip (as the old probe did), not raise.
  let dir = @fs.tmpdir(prefix="openseek-mbtx-gate-") catch { _ => return false }
  let available = @sandbox.SandboxedCommand::create_if_available(
      dir,
      Shell(":"),
    )
    is Some(_)
  @fs.rmdir(dir, recursive=true) catch {
    _ => ()
  }
  available
}

///|
/// A snippet needs somewhere to put scratch files, and `@fs.tmpdir()` is where
/// it will look. Under a policy moonrun takes that base path from the POLICY's
/// `TMPDIR`, so the run points it at its own build directory: the call has to
/// succeed without the host's temp directory ever being granted.
async test "a snippet's temp directory lands somewhere it may write" {
  let out = run(
    (
      #|import { "moonbitlang/async", "moonbitlang/async/fs", "moonbitlang/async/stdio" }
      #|
      #|async fn main {
      #|  let dir = @fs.tmpdir(prefix="probe-")
      #|  @fs.write_file("\{dir}/x.txt", "hi", create_mode=CreateOrTruncate)
      #|  @stdio.stdout.write("ok=\{@fs.exists("\{dir}/x.txt")}\n")
      #|  @fs.rmdir(dir, recursive=true)
      #|}
    ),
  )
  assert_false(out.is_error)
  assert_true(out.content.contains("ok=true"))
}

///|
/// The FFI refusal keys on the syntax, not the word: a snippet that merely
/// MENTIONS `extern` — in a commit message, a comment, any string — has done
/// nothing wrong, and refusing it cost a real turn a retry.
async test "the FFI refusal reads syntax, not the word extern" {
  let mentions = run(
    (
      #|fn main {
      #|  let message = "docs: explain how extern bindings are reviewed"
      #|  println(message)
      #|}
    ),
  )
  assert_false(mentions.is_error)
  assert_true(mentions.content.contains("docs: explain"))
}

///|
/// A refused spawn carries the same OS wording as a blocked write, and the
/// guidance used to assert it WAS a blocked write — so a run that never touched
/// a file was told to reason about paths. The message must name the rule that
/// actually fired.
#cfg(not(platform="windows"))
async test "a refused spawn gets guidance that fits a refused spawn" {
  let out = run(
    (
      #|import { "bobzhang/myshell", "moonbitlang/async" }
      #|
      #|async fn main {
      #|  @myshell.Cmd("curl", ["--version"]).output() |> ignore
      #|}
    ),
  )
  assert_true(out.is_error)
  assert_true(out.content.contains("spawn allowlist"))
  // And it must not claim, as it once did, that a write was what failed.
  assert_false(out.content.contains("denying a write OUTSIDE"))
}

///|
/// A snippet writes NOTHING in the workspace — the file's kind does not enter
/// into it. Its own temp directory is where it may write, and everything that
/// changes a workspace file goes through the file tools or through a child
/// process, which no `fs` rule of this policy reaches.
///
/// Deletion is the case that matters: moonrun gates `remove`, `rename` and
/// `rmdir` on `fs.write` too, so granting the workspace was a documented way
/// around `remove`'s refusal to delete a file it did not create.
///
/// Ungated: this is the policy's own `fs.write` rule, which moonrun applies on
/// every platform, so there is no host where it may be skipped.
async test "a snippet writes only its own temp dir, never the workspace" {
  @vfs.with_tmpdir(ws => {
    @vfs.with_tmpdir(outside => {
      @fs.write_file(
        "\{ws}/keep.mbt",
        "fn main {  }\n",
        create_mode=CreateOrTruncate,
      )
      @fs.write_file(
        "\{ws}/notes.txt",
        "keep me\n",
        create_mode=CreateOrTruncate,
      )
      let source = (
        #|import { "moonbitlang/async", "moonbitlang/async/fs", "moonbitlang/async/stdio" }
        #|
        #|async fn main {
        #|  let source_write = try {
        #|    @fs.write_file("keep.mbt", "// REWRITTEN\n", create_mode=CreateOrTruncate)
        #|    true
        #|  } catch { _ => false }
        #|  let data_write = try {
        #|    @fs.write_file("fresh.txt", "x", create_mode=CreateOrTruncate)
        #|    true
        #|  } catch { _ => false }
        #|  let delete = try {
        #|    @fs.remove("notes.txt")
        #|    true
        #|  } catch { _ => false }
        #|  let outside = try {
        #|    @fs.write_file("OUTSIDE/escape.txt", "x", create_mode=CreateOrTruncate)
        #|    true
        #|  } catch { _ => false }
        #|  let scratch = try {
        #|    let dir = @fs.tmpdir(prefix="probe-")
        #|    @fs.write_file("\{dir}/ok.txt", "x", create_mode=CreateOrTruncate)
        #|    true
        #|  } catch { _ => false }
        #|  @stdio.stdout.write("source=\{source_write} data=\{data_write} delete=\{delete} outside=\{outside} scratch=\{scratch}\n")
        #|}
      ).replace_all(old="OUTSIDE", new=outside)
      let out = run_in(ws, { "source": source })
      assert_true(out.content.contains("source=false"))
      assert_true(out.content.contains("data=false"))
      assert_true(out.content.contains("delete=false"))
      assert_true(out.content.contains("outside=false"))
      // Its own scratch space still works, or a snippet could not stage anything.
      assert_true(out.content.contains("scratch=true"))
      // Reported as denied AND untouched on disk — including the deletion.
      assert_true(@fs.read_file("\{ws}/keep.mbt").text().contains("fn main"))
      assert_true(@fs.exists("\{ws}/notes.txt"))
      assert_false(@fs.exists("\{ws}/fresh.txt"))
      assert_false(@fs.exists("\{outside}/escape.txt"))
    })
  })
}

///|
/// Reads are NOT bounded the way writes are, and that asymmetry is deliberate:
/// the `read` tool takes any absolute path with no scope, so a read root list
/// buys no confidentiality — it only turns a wrong guess at where the toolchain
/// lives into a refusal that reads like a broken environment, which live runs
/// spent steps on. Pinned against a file the workspace cannot reach so it can
/// only pass if the policy really is open.
async test "a snippet may read outside the workspace, though it may not write" {
  @vfs.with_tmpdir(ws => {
    @vfs.with_tmpdir(outside => {
      @fs.write_file(
        "\{outside}/note.txt",
        "READABLE\n",
        create_mode=CreateOrTruncate,
      )
      let source = (
        #|import { "moonbitlang/async", "moonbitlang/async/fs", "moonbitlang/async/stdio" }
        #|
        #|async fn main {
        #|  let text = try {
        #|    @fs.read_file("OUTSIDE/note.txt").text()
        #|  } catch { _ => "refused" }
        #|  @stdio.stdout.write("read=\{text.trim()}\n")
        #|}
      ).replace_all(old="OUTSIDE", new=outside)
      let out = run_in(ws, { "source": source })
      assert_true(out.content.contains("read=READABLE"))
    })
  })
}

///|
/// The generated moonrun policy is deny-by-default, so a program NOT on the
/// spawn allowlist must be refused at the host boundary — on every platform,
/// unlike the `sandbox-exec` profile. Uses a program that certainly exists and
/// is certainly not listed, so a pass cannot come from the command being
/// missing.
#cfg(not(platform="windows"))
async test "a command outside the spawn allowlist is denied by the policy" {
  let out = run(
    (
      #|import { "bobzhang/myshell", "moonbitlang/async" }
      #|
      #|async fn main {
      #|  let refused = try {
      #|    let result = @myshell.Cmd("chmod", ["644", "/tmp"]).output()
      #|    "ran exit=\{result.exit_code}"
      #|  } catch { _ => "refused" }
      #|  println("chmod: \{refused}")
      #|}
    ),
  )
  assert_true(out.content.contains("chmod: refused"))
}

///|
/// The allowlist keys on the argument prefix, not just the program, so one
/// subcommand of a program can be admitted while another is not. This is what
/// keeps `moon` — a general-purpose runner — from making the list decorative.
#cfg(not(platform="windows"))
async test "the spawn allowlist discriminates between subcommands" {
  let out = run(
    (
      #|import { "bobzhang/myshell", "moonbitlang/async" }
      #|
      #|async fn main {
      #|  // A refusal must be the POLICY refusing, not the command failing, so
      #|  // make the repo first: every probe below then exits 0 if it is allowed
      #|  // to start at all.
      #|  @myshell.Cmd("git", ["init", "-q", "."]).output() |> ignore
      #|  async fn probe(program : String, args : Array[String]) -> String {
      #|    try {
      #|      @myshell.Cmd(program, args).output() |> ignore
      #|      "ran"
      #|    } catch { _ => "refused" }
      #|  }
      #|  println("status: \{probe("git", ["status", "--short"])}")
      #|  println("clean: \{probe("git", ["clean", "-n"])}")
      #|  println("stash-list: \{probe("git", ["stash", "list"])}")
      #|  println("stash-pop: \{probe("git", ["stash", "pop"])}")
      #|  println("reconfigured: \{probe("git", ["-c", "core.pager=cat", "status"])}")
      #|  println("moon-version-flag: \{probe("moon", ["--version"])}")
      #|  println("moon-package: \{probe("moon", ["package"])}")
      #|  println("moon-search: \{probe("moon", ["search", "--help"])}")
      #|  println("moon-bench: \{probe("moon", ["bench"])}")
      #|  println("moon-publish-dry-run: \{probe("moon", ["publish", "--dry-run"])}")
      #|  println("moon-publish: \{probe("moon", ["publish"])}")
      #|  println("just: \{probe("just", ["--version"])}")
      #|  println("curl: \{probe("curl", ["--version"])}")
      #|  println("codex-exec: \{probe("codex", ["exec", "run ls"])}")
      #|}
    ),
  )
  // A listed git subcommand runs; one left off the list does not — the rules
  // are per subcommand, so `git` as such is not a capability.
  assert_true(out.content.contains("status: ran"))
  assert_true(out.content.contains("clean: refused"))
  // A two-token prefix reaches one verb deep, so a subcommand can be split:
  // reading the stash is allowed while mutating the shared stack is not.
  assert_true(out.content.contains("stash-list: ran"))
  assert_true(out.content.contains("stash-pop: refused"))
  // A reconfiguring global option precedes the subcommand, so the argument
  // vector starts with `-c` and matches no prefix. This is what makes the
  // shell tool's `global_option_reconfigures` guard unnecessary here.
  assert_true(out.content.contains("reconfigured: refused"))
  // A prefix gates whole tokens, so the FLAG spelling of a subcommand is a
  // separate rule from the subcommand. Listing only `version` refused
  // `moon --version`, which a live run then spent three attempts working
  // around; both spellings are listed now.
  assert_true(out.content.contains("moon-version-flag: ran"))
  // `package` and the non-publishing validation form may start, while plain
  // `publish` still matches no prefix. `just` has likewise left the surface.
  assert_true(out.content.contains("moon-package: ran"))
  // Registry search is admitted; `--help` keeps the probe off the network,
  // since only starting the process is under test.
  assert_true(out.content.contains("moon-search: ran"))
  assert_true(out.content.contains("moon-bench: ran"))
  assert_true(out.content.contains("moon-publish-dry-run: ran"))
  assert_true(out.content.contains("moon-publish: refused"))
  assert_true(out.content.contains("just: refused"))
  assert_true(out.content.contains("curl: refused"))
  // The same prefix gating admits exactly one verb of the Codex CLI: the
  // read-only `review`. The policy refusal fires before the binary resolves,
  // so `exec` is refused whether or not codex is installed; asserting that
  // `review` runs would depend on the machine having it, so only the negative
  // side is portable.
  assert_true(out.content.contains("codex-exec: refused"))
}

///|
/// The snippet may use network clients and localhost servers, but it must not
/// expose a listener on every interface. The denied wildcard bind is caught by
/// the snippet so both sides of the boundary are visible in one run.
async test "network allows outbound use and localhost-only binds" {
  let out = run(
    (
      #|import { "moonbitlang/async", "moonbitlang/async/socket" }
      #|
      #|async fn main {
      #|  let localhost = try {
      #|    let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
      #|    defer server.close()
      #|    let client = @socket.Tcp::connect(server.addr())
      #|    client.close()
      #|    "allowed"
      #|  } catch {
      #|    error if @async.is_being_cancelled() => raise error
      #|    _ => "refused"
      #|  }
      #|  let wildcard = try {
      #|    let server = @socket.TcpServer(@socket.Addr::parse("0.0.0.0:0"))
      #|    server.close()
      #|    "allowed"
      #|  } catch {
      #|    error if @async.is_being_cancelled() => raise error
      #|    _ => "refused"
      #|  }
      #|  println("localhost=\{localhost} wildcard=\{wildcard}")
      #|}
    ),
  )
  assert_true(out.content.contains("localhost=allowed"))
  assert_true(out.content.contains("wildcard=refused"))
}

///|
/// The profile follows `read_only`, not the presence of a lab. A caller that
/// forgets `scratch_dir` should lose the lab and keep the sandbox — the review
/// CLI shipped one revision without the lab and silently ran unconfined, which
/// is the shape this pins against.
async test "read_only denies source writes with no scratch lab wired" {
  guard sandbox_enforcement_available() else { return }
  @vfs.with_tmpdir(prefix="mbtx-ro-", ws => {
    @fs.write_file(
      "\{ws}/keep.mbt",
      "fn main {  }\n",
      create_mode=CreateOrTruncate,
    )
    let definition = @mbtx.definition(workspace_root=ws, read_only=true)
    let action = match definition.execute {
      Async(execute) =>
        execute({
          "source": (
            #|import { "moonbitlang/async", "moonbitlang/async/fs", "moonbitlang/async/stdio" }
            #|
            #|async fn main {
            #|  let wrote = try {
            #|    @fs.write_file("keep.mbt", "// CORRUPTED\n", create_mode=CreateOrTruncate)
            #|    true
            #|  } catch { _ => false }
            #|  @stdio.stdout.write("workspace=\{wrote}\n")
            #|}
          ),
        })
      Sync(_) => fail("mbtx should be async")
    }
    guard action is Respond(output) else { fail("expected Respond") }
    assert_true(output.content.contains("workspace=false"))
    assert_true(@fs.read_file("\{ws}/keep.mbt").text().contains("fn main {  }"))
  })
}

///|
/// A read-only subagent gets a scratch lab: the one place it MAY fabricate and
/// rewrite source to verify a claim empirically. The lab must be writable while
/// the workspace's own sources stay denied — otherwise the lab either does not
/// work or is a hole in the read-only posture.
async test "a scratch lab is writable while workspace source stays denied" {
  guard sandbox_enforcement_available() else { return }
  @vfs.with_tmpdir(prefix="mbtx-lab-ws-", ws => {
    @vfs.with_tmpdir(prefix="mbtx-lab-", lab => {
      @fs.write_file(
        "\{ws}/keep.mbt",
        "fn main {  }\n",
        create_mode=CreateOrTruncate,
      )
      let definition = @mbtx.definition(
        workspace_root=ws,
        read_only=true,
        scratch_dir=lab,
      )
      // The lab path is substituted rather than interpolated: the snippet has
      // `\{...}` of its own, which an interpolated outer string would consume.
      let source = (
        #|import { "moonbitlang/async", "moonbitlang/async/fs", "moonbitlang/async/stdio" }
        #|
        #|async fn main {
        #|  let in_lab = try {
        #|    @fs.write_file("LAB_DIR/probe.mbt", "fn probe() -> Int { 1 }\n", create_mode=CreateOrTruncate)
        #|    true
        #|  } catch { _ => false }
        #|  let in_workspace = try {
        #|    @fs.write_file("keep.mbt", "// CORRUPTED\n", create_mode=CreateOrTruncate)
        #|    true
        #|  } catch { _ => false }
        #|  @stdio.stdout.write("lab=\{in_lab} workspace=\{in_workspace}\n")
        #|}
      ).replace_all(old="LAB_DIR", new=lab)
      let action = match definition.execute {
        Async(execute) => execute({ "source": source })
        Sync(_) => fail("mbtx should be async")
      }
      guard action is Respond(output) else { fail("expected Respond") }
      assert_true(output.content.contains("lab=true"))
      assert_true(output.content.contains("workspace=false"))
      assert_true(
        @fs.read_file("\{ws}/keep.mbt").text().contains("fn main {  }"),
      )
    })
  })
}

///|
/// A worker's SNIPPET is bound like every other: it writes nothing in the tree,
/// its own worktree included. A worker does write source — through `edit` and
/// `write`, and through the moon commands it spawns, which are children and so
/// outside this policy. `moon fmt` on its own files keeps working.
///
/// The sibling denial is the half that is load-bearing here, and it now holds
/// on every platform rather than only where `sandbox-exec` does. The kernel
/// profile still governs what those CHILD processes may touch; that is pinned
/// in `internal/sandbox/worker_profile_test.mbt`.
async test "a worker's snippet writes neither its own tree nor a sibling's" {
  @vfs.with_tmpdir(prefix="mbtx-worker-repo-", repo => {
    let common_git = "\{repo}/.git"
    let worker = "\{repo}/wt-1"
    let sibling = "\{repo}/wt-2"
    @fs.mkdir("\{common_git}/worktrees/wt-1", recursive=true)
    @fs.mkdir(worker, recursive=true)
    @fs.mkdir(sibling, recursive=true)
    @fs.write_file(
      "\{worker}/mine.mbt",
      "fn mine() -> Int { 1 }\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{sibling}/theirs.mbt",
      "fn theirs() -> Int { 2 }\n",
      create_mode=CreateOrTruncate,
    )
    let definition = @mbtx.definition(
      workspace_root=worker,
      // The real geometry the subtask controller computes: the repository's
      // shared surfaces are denied wholesale and the worker's own tree is
      // carved back out of them, so `worker_root` sits below a denied root.
      worker_sandbox={
        deny_roots: [@fs.realpath(repo)],
        worker_root: @fs.realpath(worker),
        worker_admin_dir: @fs.realpath("\{common_git}/worktrees/wt-1"),
      },
    )
    let source = (
      #|import { "moonbitlang/async", "moonbitlang/async/fs", "moonbitlang/async/stdio" }
      #|
      #|async fn main {
      #|  let mine = try {
      #|    @fs.write_file("mine.mbt", "fn mine() -> Int { 11 }\n", create_mode=CreateOrTruncate)
      #|    true
      #|  } catch { _ => false }
      #|  let theirs = try {
      #|    @fs.write_file("SIBLING/theirs.mbt", "// CLOBBERED\n", create_mode=CreateOrTruncate)
      #|    true
      #|  } catch { _ => false }
      #|  @stdio.stdout.write("mine=\{mine} theirs=\{theirs}\n")
      #|}
    ).replace_all(old="SIBLING", new=sibling)
    let action = match definition.execute {
      Async(execute) => execute({ "source": source })
      Sync(_) => fail("mbtx should be async")
    }
    guard action is Respond(output) else { fail("expected Respond") }
    assert_true(output.content.contains("mine=false"))
    assert_true(output.content.contains("theirs=false"))
    // Untouched on disk, not merely reported as denied — both trees.
    assert_true(
      @fs.read_file("\{sibling}/theirs.mbt").text().contains("fn theirs"),
    )
    assert_true(
      @fs.read_file("\{worker}/mine.mbt").text().contains("-> Int { 1 }"),
    )
  })
}

///|
/// Without a job runtime the description names the longer cancelling timeout;
/// the schema never asks the model to choose foreground versus background.
test "a definition without a job runtime describes its hard timeout" {
  let definition = @mbtx.definition(workspace_root=".")
  assert_false(definition.description.contains("run_in_background"))
  assert_true(definition.description.contains("no background-job runtime"))
  assert_true(definition.description.contains("up to 300s"))
  let injected = @mbtx.definition(
    workspace_root=".",
    foreground_timeout_ms=12_345,
  )
  assert_true(injected.description.contains("up to 12345ms"))
  let JsonSchema(schema) = definition.schema
  assert_false(schema.stringify().contains("run_in_background"))
  // Both execution-time variants teach the staged wasm contract: the build
  // runs first, synchronously, on its own bound.
  assert_true(definition.description.contains("BUILT first, synchronously"))
  let staged_bound = @mbtx.definition(workspace_root=".", build_timeout_ms=777)
  assert_true(staged_bound.description.contains("777ms"))
}

///|
/// The command policy and its model-facing description are maintained
/// separately, so pin the Proton entry at the public definition boundary too.
test "the description advertises the Proton CLI command surface" {
  let description = @mbtx.definition(workspace_root=".").description
  assert_true(description.contains("`proton_cli`"))
  assert_true(description.contains("doctor"))
  assert_true(description.contains("cef"))
  assert_true(
    description.contains(
      "`-C`/`--cwd` options before the subcommand are refused",
    ),
  )
}

///|
/// The schema is the model-facing argument contract, so pin its shape: the
/// arguments the tool decodes are all present, and only `source` is required.
test "the schema advertises every decoded argument" {
  let JsonSchema(schema) = @mbtx.definition(workspace_root=".").schema
  guard schema is { "properties": Object(properties), "required": required, .. } else {
    fail("expected an object schema with properties and required")
  }
  // Order-independent: `Map` iteration order is not the declaration order, and
  // MoonBit's String ordering is by length first, so a sorted expectation would
  // encode neither what this test means nor what a reader expects.
  let names = properties.keys().collect()
  assert_eq(names.length(), 4)
  for name in ["source", "target", "cwd", "warning"] {
    assert_true(names.contains(name))
  }
  assert_eq(required, (["source"] : Json))
}

///|
/// The removed argument is rejected below JSON Schema enforcement, and its
/// migration guidance must still read correctly through execute's shared
/// "mbtx requires ..." decode-error wrapper.
async test "the removed background field has grammatical migration guidance" {
  let out = run_in(".", { "source": "fn main {  }", "run_in_background": true })
  assert_true(out.is_error)
  assert_true(out.content.contains("mbtx requires arguments without"))
  assert_true(out.content.contains("field was removed"))
  assert_true(out.content.contains("handoff is automatic"))
}

// The EDSL guidance the description carries — how a snippet is shaped, the
// warning off `@myshell.Pipeline`, batching probes into one turn — is not
// re-pinned by phrase here: an assertion that a text contains its own words
// breaks on every rewrite and catches no real gap.

///|
async test "an uncaught sandbox denial is explained, not left as a bare EPERM" {
  @vfs.with_tmpdir(ws => {
    @vfs.with_tmpdir(outside => {
      // Unlike the test above, the snippet does NOT catch the write failure, so
      // the run dies with the raw OS error — the case where the model previously
      // saw only `Operation not permitted` with no idea the sandbox caused it.
      let source = (
        #|import { "moonbitlang/async", "moonbitlang/async/fs" }
        #|
        #|async fn main {
        #|  @fs.write_file("OUTSIDE/escape.txt", "x", create_mode=CreateOrTruncate)
        #|}
      ).replace_all(old="OUTSIDE", new=outside)
      let out = run_in(ws, { "source": source })
      assert_true(out.is_error)
      // The raw failure stays visible, and it is the moonrun policy's own
      // wording — the phrase the guidance is recognized by. Assert what is
      // actually printed: an earlier version of this test looked for
      // "Operation not permitted", which only ever matched because the guidance
      // text quoted that phrase, so it verified nothing about the real error.
      assert_true(out.content.contains("Sandbox policy blocked file write"))
      assert_true(out.content.contains("Permission denied"))
      // ...now followed by the sandbox explanation
      assert_true(out.content.contains("mbtx sandbox"))
      // The guidance describes the policy's rules — the snippet's own roots and
      // the spawn allowlist — not the source-write rule this run does not carry.
      assert_true(out.content.contains("write outside its own"))
      assert_false(out.content.contains("`edit`"))
      assert_false(@fs.exists("\{outside}/escape.txt"))
    })
  })
}

///|
async test "warnings are suppressed by default and shown with warning=on" {
  @vfs.with_tmpdir(ws => {
    // `x` is unused (id 2) and `{}` is ambiguous_braces (id 82, in the
    // 80..83 block a stale ceiling once missed): both warn under
    // `warning: "on"`, both silent by default.
    let source = "fn main {\n  let x = 1\n  let y = {}\n  ignore(y)\n  println(2)\n}"
    let quiet = run_in(ws, { "source": source })
    assert_false(quiet.is_error)
    assert_true(quiet.content.contains("2"))
    assert_false(quiet.content.contains("Warning"))
    let loud = run_in(ws, { "source": source, "warning": "on" })
    assert_false(loud.is_error)
    assert_true(loud.content.contains("Warning"))
    assert_true(loud.content.contains("Unused variable"))
    // warning diagnostics get the same source:LINE:COL rewrite as errors
    assert_true(loud.content.contains("source:"))
  })
}

///|
async test "a denial past the display cap is still detected and explained" {
  @vfs.with_tmpdir(ws => {
    @vfs.with_tmpdir(outside => {
      // ~200KB of flood BEFORE the uncaught denied write: the OSError line lands
      // beyond the 48KB display cap (and beyond one 64KB scan chunk), so only
      // the full-log scan can see it.
      let source = (
        #|import { "moonbitlang/async", "moonbitlang/async/fs", "moonbitlang/async/stdio" }
        #|
        #|async fn main {
        #|  let filler = String::make(1000, 'x')
        #|  for _i in 0..<200 {
        #|    @stdio.stdout.write("\{filler}\n")
        #|  }
        #|  @fs.write_file("OUTSIDE/escape.txt", "x", create_mode=CreateOrTruncate)
        #|}
      ).replace_all(old="OUTSIDE", new=outside)
      let out = run_in(ws, { "source": source })
      assert_true(out.is_error)
      // the displayed prefix is the truncated flood, not the denial line —
      // pinned on `OSError`, a token the guidance text does not contain, so
      // the assertion cannot be satisfied by the guidance instead...
      assert_true(out.content.contains("output truncated"))
      assert_false(out.content.contains("OSError"))
      // ...yet the guidance still lands, from the full-log scan
      assert_true(out.content.contains("mbtx sandbox"))
      assert_false(@fs.exists("\{outside}/escape.txt"))
    })
  })
}

///|
async test "warning off keeps error-state diagnostics failing (partial_match)" {
  @vfs.with_tmpdir(ws => {
    // partial_match (warning 11) defaults to the `error` state: with warnings
    // off it must STILL fail compilation, not compile into a runtime panic.
    let out = run_in(ws, {
      "source": "fn f(x : Int?) -> Int {\n  match x {\n    Some(v) => v\n  }\n}\n\nfn main {\n  println(f(None))\n}",
    })
    assert_true(out.is_error)
    assert_true(out.content.contains("partial_match"))
    assert_false(out.content.contains("PanicError"))
  })
}

///|
async test "rejects an unknown warning value" {
  let out = run_in(".", { "source": "fn main {  }", "warning": "loud" })
  assert_true(out.is_error)
  assert_true(out.content.contains("mbtx requires"))
}

///|
async test "rejects non-string source arguments" {
  let out = run_in(".", { "code": "x" })
  assert_true(out.is_error)
  assert_true(out.content.contains("mbtx requires"))
}

///|
async test "runs a pure snippet on a non-native target" {
  @vfs.with_tmpdir(ws => {
    let out = run_in(ws, {
      "source": "fn main { println(6 * 7) }",
      "target": "js",
    })
    assert_false(out.is_error)
    assert_true(out.content.contains("42"))
  })
}

///|
async test "error diagnostics name `source`, not the throwaway temp path" {
  let out = run("fn main {\n  let _x : Int = \"nope\"\n}")
  assert_true(out.is_error)
  // the model reads a path about its own input, not /tmp/openseek-mbtx-*
  assert_true(out.content.contains("source:"))
  assert_false(out.content.contains("openseek-mbtx-"))
  assert_false(out.content.contains("snippet.mbt"))
}

///|
/// The system prompt's minimal shell example exercises the library without
/// spawning a child process: glob expansion itself is useful MoonBit IO.
async test "moonbitlang/async/shell glob lists workspace paths" {
  @vfs.with_tmpdir(prefix="mbtx-glob-", ws => {
    @fs.write_file("\{ws}/main.mbt", "fn main {}", create_mode=CreateOrTruncate)
    let out = run_in(ws, {
      "source": (
        #|import { "moonbitlang/async", "moonbitlang/async/fs", "moonbitlang/async/shell", "moonbitlang/core/env" }
        #|
        #|async fn main {
        #|  for path in @shell.glob("*.mbt") {
        #|    println(path)
        #|  }
        #|  for name in @fs.readdir(".") {
        #|    println(name)
        #|  }
        #|  guard @env.get_env_var("HOME") is Some(home) else {
        #|    println("HOME is not set")
        #|    return
        #|  }
        #|  println("\{home}/.moon exists: \{@fs.exists("\{home}/.moon")}")
        #|}
      ),
    })
    assert_false(out.is_error)
    assert_true(out.content.contains("main.mbt"))
  })
}

///|
/// The system prompt's plain command example reads a captured run back through
/// `Output`'s accessor methods: the type is opaque, so field access does not
/// compile, and a non-zero exit is reported rather than raised.
#cfg(not(platform="windows"))
async test "reads a captured command through Output accessors" {
  let out = run(
    (
      #|import { "moonbitlang/async", "moonbitlang/async/shell" }
      #|
      #|async fn main {
      #|  let out = @shell.Cmd("git", ["--version"]).output()
      #|  println(out.stdout())
      #|  println(out.stderr())
      #|  println("exit=\{out.exit_code()}")
      #|  let missing = @shell.Cmd("git", ["rev-parse", "--verify", "no-such-ref"]).output()
      #|  println("missing exit=\{missing.exit_code()}")
      #|}
    ),
  )
  assert_false(out.is_error)
  assert_true(out.content.contains("git version"))
  assert_true(out.content.contains("exit=0"))
  assert_true(out.content.contains("missing exit=128"))
}

///|
/// The system prompt's compiler example combines structured diagnostics with
/// incremental stdout handling instead of teaching two `moon check` shapes.
#cfg(not(platform="windows"))
async test "streams structured moon check diagnostics with async shell" {
  @vfs.with_tmpdir(prefix="mbtx-json-check-", ws => {
    @fs.write_file(
      "\{ws}/moon.mod",
      "name = \"tmp/mbtx_json_check\"\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{ws}/main.mbt",
      "pub fn broken() -> Int { \"not an int\" }\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file("\{ws}/moon.pkg", "", create_mode=CreateOrTruncate)
    let out = run_in(ws, {
      "source": (
        #|import { "moonbitlang/async", "moonbitlang/async/shell", "moonbitlang/core/json" }
        #|
        #|async fn main {
        #|  let mut errors = 0
        #|  let exit_code = @shell.Cmd(
        #|    "moon",
        #|    ["check", "--output-json", "--diagnostic-limit", "5"],
        #|    env={ "NO_COLOR": "1" },
        #|  ).each_line() <| line => {
        #|    let diagnostic = @json.parse(line) catch { _ => return }
        #|    if diagnostic is {
        #|      "level": String("error"),
        #|      "path": String(path),
        #|      "loc": String(loc),
        #|      "message": String(message),
        #|      ..
        #|    } {
        #|      errors += 1
        #|      println("\{path}:\{loc}  \{message}")
        #|    }
        #|  }
        #|  println("exit=\{exit_code} errors=\{errors}")
        #|}
      ),
    })
    assert_false(out.is_error)
    assert_true(out.content.contains("main.mbt:"))
    assert_true(out.content.contains("errors=1"))
  })
}

///|
async test "refuses native FFI (extern can bind libc system)" {
  // `extern` sidesteps the @process import check, so it is refused too — the
  // static boundary is best-effort until the wasm sandbox lands.
  let out = run(
    (
      #|extern "c" fn c_system(cmd : Bytes) -> Int = "system"
      #|
      #|fn main { c_system("true") |> ignore }
    ),
  )
  assert_true(out.is_error)
  assert_true(out.content.contains("native FFI"))
}

///|
/// A compute-only backend has no moonrun policy. Text resembling its refusal
/// marker is ordinary program output even in a runtime-less definition.
async test "a runtime-less non-wasm run does not invent a policy refusal" {
  let out = run_in(".", {
    "source": "fn main { println(\"Sandbox policy blocked file write: example\") }",
    "target": "js",
  })
  assert_false(out.is_error)
  assert_true(out.content.contains("Sandbox policy blocked"))
  assert_false(out.content.contains("mbtx sandbox:"))
}

///|
async test "snippet stdin is an empty file (EOF), not the engine's inherited fd 0" {
  // A snippet that reads stdin must get immediate EOF, not block on (or steal
  // from) the parent's fd 0 — which under serve/TUI is the control channel.
  let out = run(
    (
      #|import { "moonbitlang/async", "moonbitlang/async/stdio" }
      #|
      #|async fn main {
      #|  let line = @stdio.stdin.read_until("\n")
      #|  @stdio.stdout.write("got=\{line is Some(_)}\n")
      #|}
    ),
  )
  assert_false(out.is_error)
  assert_true(out.content.contains("got=false"))
}

///|
async test "a non-zero exit shows the exit code in the content, not just the brief" {
  // prints, then aborts: the model must see the failure in what it reads
  let out = run("fn main { println(\"before\"); panic() }")
  assert_true(out.is_error)
  assert_true(out.content.contains("before"))
  assert_true(out.content.contains("exited"))
}

///|
/// The short handoff grace belongs only to a runtime-backed definition. A
/// foreground-only subrun has no job owner, so it keeps its independent hard
/// timeout instead of being cancelled at the handoff boundary.
async test "a runtime-less run uses its foreground timeout, not the handoff grace" {
  @vfs.with_tmpdir(prefix="mbtx-foreground-timeout-", ws => {
    let definition = @mbtx.definition(
      workspace_root=ws,
      auto_background_after_ms=1,
      foreground_timeout_ms=300_000,
    )
    let source =
      #|import { "moonbitlang/async" }
      #|
      #|async fn main {
      #|  @async.sleep(100)
      #|  println("finished inline")
      #|}
    let action = match definition.execute {
      Async(execute) => execute({ "source": source })
      Sync(_) => fail("mbtx should be async")
    }
    guard action is Respond(output) else { fail("expected Respond") }
    assert_false(output.is_error)
    assert_true(output.content.contains("finished inline"))
    assert_false(output.content.contains("moved to the background"))
  })
}

///|
/// Run with an approval channel wired, so the `escalated` argument exists and
/// `answer` decides what it resolves to.
async fn run_escalating(
  source : String,
  answer : @agent_runtime.ApprovalOutcome,
  asked~ : Array[@agent_runtime.ApprovalAsk],
) -> @agent_tool.ToolOutput {
  @vfs.with_tmpdir(prefix="mbtx-escalate-", ws => {
    let definition = @mbtx.definition(
      workspace_root=ws,
      approval=ApprovalChannel(ask => {
        asked.push(ask)
        answer
      }),
    )
    let action = match definition.execute {
      Async(execute) => execute({ "source": source, "escalated": true })
      Sync(_) => fail("mbtx should be async")
    }
    guard action is Respond(output) else { fail("expected Respond") }
    output
  })
}

///|
/// The argument exists only where something can answer it, keeping a headless
/// run from spending a call on a field whose every use is refused.
test "the escalated argument is offered only with an approval channel" {
  let plain = @mbtx.definition(workspace_root=".")
  let JsonSchema(plain_schema) = plain.schema
  guard plain_schema is { "properties": Object(plain_properties), .. } else {
    fail("expected an object schema")
  }
  assert_false(plain_properties.contains("escalated"))
  assert_false(plain.description.contains("escalated=true"))
  let asking = @mbtx.definition(
    workspace_root=".",
    approval=ApprovalChannel(_ => Rejected),
  )
  let JsonSchema(asking_schema) = asking.schema
  guard asking_schema is { "properties": Object(asking_properties), .. } else {
    fail("expected an object schema")
  }
  assert_true(asking_properties.contains("escalated"))
  // The description has to carry it too: the refusal advice above it tells the
  // model to say so rather than work around a refusal, which is wrong wherever
  // asking is a sanctioned move.
  assert_true(asking.description.contains("escalated=true"))
}

///|
/// A granted escalation is what the policy file not being passed looks like:
/// a program the allowlist refuses runs normally.
#cfg(not(platform="windows"))
async test "an approved escalation runs outside the spawn allowlist" {
  let asked : Array[@agent_runtime.ApprovalAsk] = []
  let out = run_escalating(
    (
      #|import { "bobzhang/myshell", "moonbitlang/async" }
      #|
      #|async fn main {
      #|  let ran = try {
      #|    let result = @myshell.Cmd("chmod", ["644", "/tmp"]).output()
      #|    "ran exit=\{result.exit_code}"
      #|  } catch { _ => "refused" }
      #|  println("chmod: \{ran}")
      #|}
    ),
    AllowedOnce,
    asked~,
  )
  assert_false(out.is_error)
  assert_true(out.content.contains("chmod: ran"))
  // The question names the tool, states what would be granted, and carries the
  // program itself — the thing the user is actually deciding about.
  assert_eq(asked.length(), 1)
  assert_eq(asked[0].tool_name, "mbtx")
  assert_true(asked[0].detail.contains("no sandbox policy"))
}

///|
/// The refusal path never reaches the program at all.
#cfg(not(platform="windows"))
async test "a refused escalation does not run at all" {
  let asked : Array[@agent_runtime.ApprovalAsk] = []
  let out = run_escalating(
    (
      #|import { "moonbitlang/async" }
      #|
      #|async fn main {
      #|  println("this must not run")
      #|}
    ),
    Rejected,
    asked~,
  )
  assert_true(out.is_error)
  assert_false(out.content.contains("this must not run"))
  assert_eq(asked.length(), 1)
}

///|
/// Each refusal says something different, because what the model should do
/// next differs: a person's no is final for the task, a withdrawn request
/// decided nothing, and an absent channel means retry without the argument.
/// A single shared text would make all three read as the same wall.
async test "each way of not being granted says a different thing" {
  let refused = run_escalating("fn main {  }", Rejected, asked=[])
  assert_true(refused.content.contains("declined"))
  assert_true(refused.content.contains("do not ask again"))
  let withdrawn = run_escalating("fn main {  }", Cancelled, asked=[])
  assert_true(withdrawn.content.contains("NOTHING RAN"))
  assert_true(withdrawn.content.contains("not a refusal"))
  // Asking where the argument was never advertised: the model sent a field it
  // was not offered, and is told to drop it rather than to try again.
  let unavailable = @vfs.with_tmpdir(prefix="mbtx-unasked-", ws => {
    run_in(ws, { "source": "fn main {  }", "escalated": true })
  })
  assert_true(unavailable.content.contains("no approval channel"))
  assert_true(unavailable.content.contains("without `escalated`"))
  // No two of them are the same sentence.
  assert_false(refused.content == withdrawn.content)
  assert_false(withdrawn.content == unavailable.content)
  assert_false(refused.content == unavailable.content)
}

///|
/// A call that does not ask never reaches the channel: approval is not a
/// per-call toll, and a snippet that stays inside the sandbox must not cost
/// anyone a prompt.
async test "an ordinary call never asks for approval" {
  let asked : Array[@agent_runtime.ApprovalAsk] = []
  @vfs.with_tmpdir(prefix="mbtx-noask-", ws => {
    let definition = @mbtx.definition(
      workspace_root=ws,
      approval=ApprovalChannel(ask => {
        asked.push(ask)
        AllowedOnce
      }),
    )
    let action = match definition.execute {
      Async(execute) => execute({ "source": "fn main { println(6 * 7) }" })
      Sync(_) => fail("mbtx should be async")
    }
    guard action is Respond(output) else { fail("expected Respond") }
    assert_true(output.content.contains("42"))
  })
  assert_eq(asked.length(), 0)
}

///|
/// The refusal a model actually hits has to name the sanctioned answer, or the
/// answer only exists in a description read once at the top of the session.
/// This is the whole path: a real refused spawn, a real run, the real guidance
/// appended to the real output.
#cfg(not(platform="windows"))
async test "a refusal names escalation when a channel is wired" {
  let source =
    #|import { "bobzhang/myshell", "moonbitlang/async" }
    #|
    #|async fn main {
    #|  @myshell.Cmd("chmod", ["644", "/tmp"]).output() |> ignore
    #|}
  let asking = @vfs.with_tmpdir(prefix="mbtx-hint-", ws => {
    let definition = @mbtx.definition(
      workspace_root=ws,
      approval=ApprovalChannel(_ => Rejected),
    )
    let action = match definition.execute {
      Async(execute) => execute({ "source": source })
      Sync(_) => fail("mbtx should be async")
    }
    guard action is Respond(output) else { fail("expected Respond") }
    output
  })
  assert_true(asking.is_error)
  assert_true(asking.content.contains("spawn allowlist"))
  assert_true(asking.content.contains("`escalated: true`"))
  // Nothing was asked: the refusal teaches, it does not itself prompt.
  assert_true(asking.content.contains("this exact snippet ONCE"))
  // The same refusal without a channel must not advertise a field the schema
  // does not carry — that would cost a whole call to discover.
  let plain = @vfs.with_tmpdir(prefix="mbtx-hint-plain-", ws => {
    run_in(ws, { "source": source })
  })
  assert_true(plain.is_error)
  assert_true(plain.content.contains("spawn allowlist"))
  assert_false(plain.content.contains("escalated"))
}

///|
/// The allowlist section of the description carries the same fork, because the
/// case that motivated this never reached a refusal at all: asked to run `just
/// check`, the model read the justfile and quietly ran the three `moon`
/// commands it expands to, never mentioning that asking was possible.
test "the description offers asking as an answer where it exists" {
  let plain = @mbtx.definition(workspace_root=".").description
  assert_true(plain.contains("say so rather than working around it"))
  let asking = @mbtx.definition(
      workspace_root=".",
      approval=ApprovalChannel(_ => Rejected),
    ).description
  assert_true(asking.contains("two answers are legitimate"))
  assert_true(asking.contains("retry that one snippet with escalated=true"))
  // The stance survives the fork: reconstructing the command out of allowed
  // parts without saying so is still the answer that is not.
  assert_true(asking.contains("Reconstructing the refused command"))
}

///|
/// Escalation only means something on the backend the policy binds. The
/// compute-only targets never had `--wasm-policy` passed to them, so a grant
/// there would change nothing about the run — and the prompt behind it costs a
/// person's attention. Refused before anyone is asked.
async test "escalation is refused on a target that carries no policy" {
  let asked : Array[@agent_runtime.ApprovalAsk] = []
  let out = @vfs.with_tmpdir(prefix="mbtx-target-", ws => {
    let definition = @mbtx.definition(
      workspace_root=ws,
      approval=ApprovalChannel(ask => {
        asked.push(ask)
        AllowedOnce
      }),
    )
    let action = match definition.execute {
      Async(execute) =>
        execute({
          "source": "fn main { println(1) }",
          "target": "js",
          "escalated": true,
        })
      Sync(_) => fail("mbtx should be async")
    }
    guard action is Respond(output) else { fail("expected Respond") }
    output
  })
  assert_true(out.is_error)
  assert_true(out.content.contains("applies to the wasm target"))
  // Nobody was interrupted for a grant that would have done nothing.
  assert_eq(asked.length(), 0)
}

///|
/// An approved escalation runs with no policy, so the marker the refusal scan
/// keys on cannot mean what it means elsewhere: `@process.spawn(): Permission
/// denied` is the guest's own `EPERM` text, which an unsandboxed child raises
/// for its own reasons. Scanning anyway reported a successful run as an error
/// and told the model to ask for the escalation it had just been granted.
#cfg(not(platform="windows"))
async test "an escalated run is not read as a policy refusal" {
  let out = @vfs.with_tmpdir(prefix="mbtx-escalated-scan-", ws => {
    let definition = @mbtx.definition(
      workspace_root=ws,
      approval=ApprovalChannel(_ => AllowedOnce),
    )
    // Spawning something that exists but cannot be executed raises exactly the
    // text the scan looks for — from the OS, not from any policy.
    let source =
      #|import { "bobzhang/myshell", "moonbitlang/async", "moonbitlang/async/fs" }
      #|
      #|async fn main {
      #|  let dir = @fs.tmpdir(prefix="probe-")
      #|  let path = dir + "/not-executable"
      #|  @fs.write_file(path, "not a program", create_mode=CreateOrTruncate)
      #|  let refused = try {
      #|    @myshell.Cmd(path, []).output() |> ignore
      #|    "ran"
      #|  } catch { error => "\{error}" }
      #|  println("child: \{refused}")
      #|}
    let action = match definition.execute {
      Async(execute) => execute({ "source": source, "escalated": true })
      Sync(_) => fail("mbtx should be async")
    }
    guard action is Respond(output) else { fail("expected Respond") }
    output
  })
  // Whatever the child did, this tool must not claim its own sandbox refused
  // something, nor tell the model to escalate again.
  // The marker really is in the output — otherwise this test would pass by
  // having nothing for the scan to trip on.
  assert_true(out.content.contains("@process.spawn(): Permission denied"))
  // And this tool must not claim its own sandbox refused something, nor tell
  // the model to escalate again.
  assert_false(out.content.contains("this tool's policy refusing"))
  assert_false(out.content.contains("escalated: true"))
}

///|
/// Run `source` as a HOSTED snippet: one whose conversation has a durable
/// session, so mbtx reserves child ordinals and a run directory and hands
/// them to the guest as `WORKFLOW_HOST`. `store` stands in for the session
/// store; ordinals come from a local counter, as the CLI's shared one would.
async fn run_hosted(
  workspace_root : String,
  store : String,
  source : String,
) -> @agent_tool.ToolOutput {
  let issued = Ref(0)
  let subrun = @host.SubrunInjection(
    exe="/unused/openseek",
    session_root=store,
    parent="run7",
    workspace_root~,
    reserve_ordinals=count => {
      let base = issued.val + 1
      issued.val += count
      base
    },
  )
  let action = match @mbtx.definition(workspace_root~, subrun~).execute {
    Async(execute) => execute({ "source": source, "subrun": true })
    Sync(_) => fail("mbtx should be async")
  }
  guard action is Respond(output) else { fail("expected Respond") }
  output
}

///|
async test "a hosted snippet may write its own run directory" {
  @vfs.with_tmpdir(prefix="mbtx-ws-", ws => {
    @vfs.with_tmpdir(prefix="mbtx-store-", store => {
      // The guest reads the handoff the policy set and appends to the two
      // paths it names. Under mbtx's REAL policy the session store is not a
      // write root, so this passes only because the run's own directory was
      // created before the policy named it and granted as one — the case a
      // hand-written policy in an earlier end-to-end check silently hid.
      let out = run_hosted(
        ws,
        store,
        (
          #|import { "moonbitlang/async", "moonbitlang/async/fs", "moonbitlang/core/env", "moonbitlang/core/json" }
          #|
          #|async fn main {
          #|  guard @env.get_env_var("WORKFLOW_HOST") is Some(raw) else { println("NO HANDOFF"); return }
          #|  guard @json.parse(raw) is { "journal": String(journal), "events": String(events), .. } else { println("BAD HANDOFF"); return }
          #|  @fs.write_file(journal, "{\"e\":1}\n", append=true, create_mode=OpenOrCreate)
          #|  @fs.write_file(events, "{\"event\":\"agent_started\"}\n", append=true, create_mode=OpenOrCreate)
          #|  println("wrote")
          #|}
        ),
      )
      if out.is_error {
        fail("hosted snippet failed:\n\{out.content}")
      }
      assert_true(out.content.contains("wrote"))
      let journal = @fs.read_file("\{store}/run7-wf-1/journal.jsonl").text()
      assert_true(journal.contains("{\"e\":1}"))
      let events = @fs.read_file("\{store}/run7-wf-1/events.jsonl").text()
      assert_true(events.contains("agent_started"))
    })
  })
}

///|
async test "a hosted snippet may NOT write the rest of the session store" {
  @vfs.with_tmpdir(prefix="mbtx-ws-", ws => {
    @vfs.with_tmpdir(prefix="mbtx-store-", store => {
      // Only the run's directory was granted. Writing beside another session's
      // transcript in the store root is refused by the policy — and mbtx
      // reports a refusal as an error, with its own advice, which is the
      // contract this test also pins: a snippet that overreaches is TOLD so.
      let out = run_hosted(
        ws,
        store,
        (
          #|import { "moonbitlang/async", "moonbitlang/async/fs", "moonbitlang/core/env", "moonbitlang/core/json" }
          #|
          #|async fn main {
          #|  guard @env.get_env_var("WORKFLOW_HOST") is Some(raw) else { println("NO HANDOFF"); return }
          #|  guard @json.parse(raw) is { "journal": String(journal), .. } else { println("BAD HANDOFF"); return }
          #|  let dir = journal.rev_find("/").map(i => journal[:i].to_string()).unwrap_or("?")
          #|  let store = dir.rev_find("/").map(i => dir[:i].to_string()).unwrap_or("?")
          #|  @fs.write_file("\{store}/other-session.jsonl", "x", create_mode=OpenOrCreate) catch { _ => { println("store refused"); return } }
          #|  println("STORE WRITABLE")
          #|}
        ),
      )
      assert_true(out.is_error)
      assert_true(out.content.contains("store refused"))
      assert_true(out.content.contains("Sandbox policy blocked"))
      assert_false(out.content.contains("STORE WRITABLE"))
      assert_false(@fs.exists("\{store}/other-session.jsonl"))
    })
  })
}

///|
async test "an unhosted snippet sees no handoff, even one its host inherited" {
  // The guest copies the host's environment, and this process may itself be
  // a child of a hosted snippet. The policy therefore always DECIDES
  // `WORKFLOW_HOST`: to the reservation when there is one, to nothing when
  // there is not. A snippet with no durable session must never find a
  // grandparent's handoff and mint child ids from a block that is not its own.
  let out = run(
    (
      #|import { "moonbitlang/core/env" }
      #|
      #|fn main {
      #|  match @env.get_env_var("WORKFLOW_HOST") {
      #|    Some(v) if !v.is_empty() => println("LEAKED: \{v}")
      #|    _ => println("clear")
      #|  }
      #|}
    ),
  )
  assert_false(out.is_error)
  assert_true(out.content.contains("clear"))
  assert_false(out.content.contains("LEAKED"))
}

///|
async test "asking to delegate on a session that cannot host is refused, and says why" {
  // The capability is absent (no `subrun` injection); the model asks anyway.
  // Running the snippet without the coordinates it expects would let its
  // subagents vanish, so the answer is a refusal the model can act on.
  let out = run_in(".", { "source": "fn main { println(1) }", "subrun": true })
  assert_true(out.is_error)
  assert_true(out.content.contains("no durable session"))
  assert_true(out.content.contains("Retry without `subrun`"))
}

///|
async test "a hosted session reserves nothing unless the snippet asks" {
  @vfs.with_tmpdir(prefix="mbtx-ws-", ws => {
    @vfs.with_tmpdir(prefix="mbtx-store-", store => {
      // Same capability as `run_hosted`, but the snippet does not set the
      // flag: no ordinals are reserved, no run directory is created, no
      // handoff is written, and no engine enters the command vocabulary.
      // Reserving children a script never starts would waste ids and announce
      // a workflow that does not exist.
      let issued = Ref(0)
      let subrun = @host.SubrunInjection(
        exe="/unused/openseek",
        session_root=store,
        parent="run7",
        workspace_root=ws,
        reserve_ordinals=count => {
          let base = issued.val + 1
          issued.val += count
          base
        },
      )
      let action = match @mbtx.definition(workspace_root=ws, subrun~).execute {
        Async(execute) =>
          execute({
            "source": (
              #|import { "moonbitlang/core/env" }
              #|
              #|fn main {
              #|  match @env.get_env_var("WORKFLOW_HOST") {
              #|    Some(v) if !v.is_empty() => println("HANDOFF PRESENT")
              #|    _ => println("no handoff")
              #|  }
              #|}
            ),
          })
        Sync(_) => fail("mbtx should be async")
      }
      guard action is Respond(out) else { fail("expected Respond") }
      assert_false(out.is_error)
      assert_true(out.content.contains("no handoff"))
      assert_eq(issued.val, 0)
      assert_false(@fs.exists("\{store}/run7-wf-1"))
    })
  })
}

///|
/// An injection over a local counter that starts at `first`, so a test can
/// pick the ordinal block — and therefore the run id, `wf-<first>` — its
/// lines will carry. The protocol sink is shared by every test in the
/// process, so a test that reads it must be able to tell its own run apart.
fn hosted_injection(
  store : String,
  workspace_root : String,
  first~ : Int,
) -> (@host.SubrunInjection, Ref[Int]) {
  let issued = Ref(first - 1)
  let injection = @host.SubrunInjection(
    exe="/unused/openseek",
    session_root=store,
    parent="run7",
    workspace_root~,
    reserve_ordinals=count => {
      let base = issued.val + 1
      issued.val += count
      base
    },
  )
  (injection, issued)
}

///|
async fn run_hosted_with(
  workspace_root : String,
  store : String,
  arguments : Json,
  first? : Int = 1,
) -> (@agent_tool.ToolOutput, Int) {
  let (subrun, issued) = hosted_injection(store, workspace_root, first~)
  let action = match @mbtx.definition(workspace_root~, subrun~).execute {
    Async(execute) => execute(arguments)
    Sync(_) => fail("mbtx should be async")
  }
  guard action is Respond(output) else { fail("expected Respond") }
  (output, issued.val - (first - 1))
}

///|
async test "delegation is refused off the wasm target, before anything is reserved" {
  @vfs.with_tmpdir(prefix="mbtx-ws-", ws => {
    @vfs.with_tmpdir(prefix="mbtx-store-", store => {
      // The handoff lives in the wasm policy; a js run has none to carry it.
      let (out, issued) = run_hosted_with(ws, store, {
        "source": "fn main { println(1) }",
        "target": "js",
        "subrun": true,
      })
      assert_true(out.is_error)
      assert_true(out.content.contains("applies to the wasm target"))
      assert_eq(issued, 0)
      // Escalation lifts the policy the handoff is delivered through.
      let (out, issued) = run_hosted_with(ws, store, {
        "source": "fn main { println(1) }",
        "subrun": true,
        "escalated": true,
      })
      assert_true(out.is_error)
      assert_true(out.content.contains("exclude each other"))
      assert_eq(issued, 0)
      // Neither refusal created a run directory: the desktop must never be
      // told about a workflow that was refused.
      assert_false(@fs.exists("\{store}/run7-wf-1"))
    })
  })
}

///|
async test "the run directory is created even when the store root is not there yet" {
  @vfs.with_tmpdir(prefix="mbtx-ws-", ws => {
    @vfs.with_tmpdir(prefix="mbtx-store-", store => {
      // The store creates its directories lazily, so a reservation may be the
      // first thing to touch the root. A policy naming a root that failed to
      // appear is refused whole; the mkdir must not depend on the root.
      let root = "\{store}/not-yet"
      let (out, issued) = run_hosted_with(ws, root, {
        "source": "fn main { println(\"hosted\") }",
        "subrun": true,
      })
      assert_false(out.is_error, msg=out.content)
      assert_eq(issued, @host.block_size)
      assert_true(@fs.exists("\{root}/run7-wf-1"))
    })
  })
}

///|
/// The workflow bracket lines for run `id` that the in-process protocol sink
/// is holding, in order. Everything else queued is discarded: other tests'
/// hosted runs announce runs of their own into the same sink.
fn workflow_lines(id : String) -> Array[Json] raise {
  let lines = []
  while @emit.poll_line() is Some(line) {
    let entry = @json.parse(line)
    if entry is { "event": String(event), "id": String(entry_id), .. } &&
      event.has_prefix("workflow_") &&
      entry_id == id {
      lines.push(entry)
    }
  }
  lines
}

///|
/// One test, not four: the protocol sink is process-global and a drain takes
/// every queued line, so two tests reading it concurrently would steal each
/// other's brackets. The sink is opened and left open — closing it while
/// another test's hosted run is announcing would drop that run's lines.
async test "a hosted run is announced before it runs and closed on every exit" {
  @vfs.with_tmpdir(prefix="mbtx-ws-", ws => {
    @vfs.with_tmpdir(prefix="mbtx-store-", store => {
      @emit.open()
      ignore(workflow_lines(""))
      // A run that completes: one open, one close, the coordinates a reader
      // needs — where to tail, and which child ordinals are this run's.
      let (out, _) = run_hosted_with(
        ws,
        store,
        { "source": "fn main { println(\"hosted\") }", "subrun": true },
        first=700,
      )
      assert_false(out.is_error, msg=out.content)
      guard workflow_lines("wf-700")
        is [
          {
            "event": String("workflow_started"),
            "journal": String(journal),
            "events": String(events),
            "first_child": Number(700, ..),
            "child_count": Number(32, ..),
            ..
          },
          { "event": String("workflow_finished"), .. },
        ] else {
        fail("expected one open and one close for wf-700")
      }
      assert_eq(journal, "\{store}/run7-wf-700/journal.jsonl")
      assert_eq(events, "\{store}/run7-wf-700/events.jsonl")
      // A run that never starts — the build fails — still closes its bracket,
      // or a reader would show a workflow running forever.
      let (out, _) = run_hosted_with(
        ws,
        store,
        { "source": "fn main { let _x : Int = \"nope\" }", "subrun": true },
        first=800,
      )
      assert_true(out.is_error)
      guard workflow_lines("wf-800")
        is [
          { "event": String("workflow_started"), .. },
          { "event": String("workflow_finished"), .. },
        ] else {
        fail("a failed build must still close wf-800")
      }
      // A run adopted into the background returns from the call while the
      // snippet is STILL RUNNING. Its bracket must stay open until the job
      // ends, not close at adoption.
      @async.with_task_group() <| group => {
        let bg = @bgjobs.BgJobRuntime(AgentTaskScope(group))
        let (subrun, _) = hosted_injection(store, ws, first=900)
        let definition = @mbtx.definition(
          workspace_root=ws,
          bg_runtime=bg,
          auto_background_after_ms=1,
          subrun~,
        )
        let source =
          #|import { "moonbitlang/async" }
          #|
          #|async fn main {
          #|  @async.sleep(400)
          #|  println("late")
          #|}
        let action = match definition.execute {
          Async(execute) => execute({ "source": source, "subrun": true })
          Sync(_) => fail("mbtx should be async")
        }
        guard action is Respond(output) else { fail("expected Respond") }
        assert_false(output.is_error, msg=output.content)
        assert_true(output.content.contains("moved to the background"))
        guard workflow_lines("wf-900")
          is [{ "event": String("workflow_started"), .. }] else {
          fail("at adoption the run is announced and still open")
        }
        let mut closed = false
        for _ in 0..<200 {
          if workflow_lines("wf-900")
            is [{ "event": String("workflow_finished"), .. }] {
            closed = true
            break
          }
          @async.sleep(50)
        }
        assert_true(closed, msg="the job's terminal must close wf-900")
      }
      // A run that does not delegate announces nothing.
      let (out, _) = run_hosted_with(
        ws,
        store,
        { "source": "fn main { println(1) }" },
        first=950,
      )
      assert_false(out.is_error)
      assert_eq(workflow_lines("wf-950").length(), 0)
    })
  })
}
