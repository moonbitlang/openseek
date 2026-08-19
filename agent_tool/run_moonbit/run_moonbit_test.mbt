///|
/// Run `source` in a fresh, auto-cleaned workspace, which is also the default
/// working directory the program runs in.
async fn run(source : String) -> @agent_tool.ToolOutput {
  @vfs.with_tmpdir(prefix="run-moonbit-ws-", ws => {
    run_in(ws, { "source": source })
  })
}

///|
/// Run with an explicit `workspace_root` and raw arguments (for cwd / target /
/// decode-failure cases).
async fn run_in(
  workspace_root : String,
  arguments : Json,
) -> @agent_tool.ToolOutput {
  let action = match @run_moonbit.definition(workspace_root~).execute {
    Async(execute) => execute(arguments)
    Sync(_) => fail("run_moonbit should be async")
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
    "cwd": "/no/such/run-moonbit/dir",
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
  let dir = @fs.tmpdir(prefix="openseek-run-moonbit-gate-") catch {
    _ => return false
  }
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
async test "sandbox blocks overwriting a protected source file in the workspace" {
  // Only meaningful where the sandbox can actually enforce (macOS, not nested);
  // gate on the SAME probe `execute` uses so a host where sandbox-exec exists but
  // cannot apply a nested profile (production runs unsandboxed there) skips
  // rather than fails. The wasm backend carries this policy cross-platform.
  guard sandbox_enforcement_available() else { return }
  @vfs.with_tmpdir(ws => {
    @fs.write_file(
      "\{ws}/keep.mbt",
      "fn main {  }\n",
      create_mode=CreateOrTruncate,
    )
    let out = run_in(ws, {
      "source": (
        #|import { "moonbitlang/async", "moonbitlang/async/fs", "moonbitlang/async/stdio" }
        #|
        #|async fn main {
        #|  let blocked = try {
        #|    @fs.write_file("keep.mbt", "// CORRUPTED\n", create_mode=CreateOrTruncate)
        #|    false
        #|  } catch { _ => true }
        #|  // a non-source output is still allowed
        #|  @fs.write_file("out.txt", "ok\n", create_mode=CreateOrTruncate)
        #|  @stdio.stdout.write("blocked=\{blocked}\n")
        #|}
      ),
    })
    assert_false(out.is_error)
    assert_true(out.content.contains("blocked=true"))
    // the protected source file is untouched; the non-source output landed
    assert_true(@fs.read_file("\{ws}/keep.mbt").text().contains("fn main {  }"))
    assert_true(@fs.exists("\{ws}/out.txt"))
  })
}

///|
/// A read-only subagent gets a scratch lab: the one place it MAY fabricate and
/// rewrite source to verify a claim empirically. The lab must be writable while
/// the workspace's own sources stay denied — otherwise the lab either does not
/// work or is a hole in the read-only posture.
async test "a scratch lab is writable while workspace source stays denied" {
  guard sandbox_enforcement_available() else { return }
  @vfs.with_tmpdir(prefix="run-moonbit-lab-ws-", ws => {
    @vfs.with_tmpdir(prefix="run-moonbit-lab-", lab => {
      @fs.write_file(
        "\{ws}/keep.mbt",
        "fn main {  }\n",
        create_mode=CreateOrTruncate,
      )
      let definition = @run_moonbit.definition(
        workspace_root=ws,
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
        Sync(_) => fail("run_moonbit should be async")
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
/// Worker mode replaces the workspace profile instead of adding to it: a worker
/// is supposed to write source, just only its own. Pin both halves — its own
/// tree is writable (a worker that cannot run `moon fmt` on its own files is
/// useless), and a sibling worktree is not.
async test "worker mode allows the worker's own source and denies a sibling's" {
  guard sandbox_enforcement_available() else { return }
  @vfs.with_tmpdir(prefix="run-moonbit-worker-repo-", repo => {
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
    let definition = @run_moonbit.definition(
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
      Sync(_) => fail("run_moonbit should be async")
    }
    guard action is Respond(output) else { fail("expected Respond") }
    assert_true(output.content.contains("mine=true"))
    assert_true(output.content.contains("theirs=false"))
    // The sibling's file is untouched on disk, not merely reported as denied.
    assert_true(
      @fs.read_file("\{sibling}/theirs.mbt").text().contains("fn theirs"),
    )
  })
}

///|
test "the description encourages batched same-turn probing" {
  // The batching guidance lives in the tool description (and the default
  // prompt): several independent probes in ONE assistant turn, not serial
  // single-probe turns.
  // The description is a wrapped `#|` block, so newlines fall mid-phrase;
  // normalize them to spaces before matching the guidance phrases.
  let description = @run_moonbit.definition(workspace_root=".").description.replace_all(
    old="\n",
    new=" ",
  )
  assert_true(description.contains("SAME assistant turn"))
  assert_true(description.contains("come back together"))
}

///|
/// Without a job runtime the tool cannot execute a background run, so neither
/// the description nor the schema may advertise one — the model would only get
/// an error. (The wired half of this contract is asserted in the `agent`
/// package, which builds a registry with a real runtime.)
test "a definition without a job runtime does not advertise background runs" {
  let definition = @run_moonbit.definition(workspace_root=".")
  assert_false(definition.description.contains("run_in_background"))
  assert_true(definition.description.contains("bobzhang/myshell"))
  let JsonSchema(schema) = definition.schema
  assert_false(schema.stringify().contains("run_in_background"))
}

///|
/// The schema is the model-facing argument contract, so pin its shape: the
/// arguments the tool decodes are all present, and only `source` is required.
test "the schema advertises every decoded argument" {
  let JsonSchema(schema) = @run_moonbit.definition(workspace_root=".").schema
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
test "the description teaches the process EDSL, since there is no shell tool" {
  let description = @run_moonbit.definition(workspace_root=".").description.replace_all(
    old="\n",
    new=" ",
  )
  assert_true(description.contains("bobzhang/myshell"))
  assert_true(description.contains("@myshell.Cmd"))
  // The pipeline stage is unreliable with slow producers upstream, so the
  // description must steer to capture-and-filter-in-MoonBit instead.
  assert_true(description.contains("Do NOT use"))
  assert_true(description.contains("Pipeline"))
}

///|
async test "an uncaught sandbox denial is explained, not left as a bare EPERM" {
  guard sandbox_enforcement_available() else { return }
  @vfs.with_tmpdir(ws => {
    @fs.write_file(
      "\{ws}/keep.mbt",
      "fn main {  }\n",
      create_mode=CreateOrTruncate,
    )
    // Unlike the test above, the snippet does NOT catch the write failure, so
    // the run dies with the raw OS error — the case where the model previously
    // saw only `Operation not permitted` with no idea the sandbox caused it.
    let out = run_in(ws, {
      "source": (
        #|import { "moonbitlang/async", "moonbitlang/async/fs" }
        #|
        #|async fn main {
        #|  @fs.write_file("keep.mbt", "// CORRUPTED\n", create_mode=CreateOrTruncate)
        #|}
      ),
    })
    assert_true(out.is_error)
    // the raw OS error stays visible...
    assert_true(out.content.contains("Operation not permitted"))
    // ...now followed by the sandbox explanation and anti-workaround guidance
    assert_true(out.content.contains("run_moonbit sandbox"))
    assert_true(out.content.contains("Do NOT try to work around"))
    assert_true(out.content.contains("`edit`"))
    // the protected source file is untouched
    assert_true(@fs.read_file("\{ws}/keep.mbt").text().contains("fn main {  }"))
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
  guard sandbox_enforcement_available() else { return }
  @vfs.with_tmpdir(ws => {
    @fs.write_file(
      "\{ws}/keep.mbt",
      "fn main {  }\n",
      create_mode=CreateOrTruncate,
    )
    // ~200KB of flood BEFORE the uncaught denied write: the OSError line lands
    // beyond the 48KB display cap (and beyond one 64KB scan chunk), so only
    // the full-log scan can see it.
    let out = run_in(ws, {
      "source": (
        #|import { "moonbitlang/async", "moonbitlang/async/fs", "moonbitlang/async/stdio" }
        #|
        #|async fn main {
        #|  let filler = String::make(1000, 'x')
        #|  for _i in 0..<200 {
        #|    @stdio.stdout.write("\{filler}\n")
        #|  }
        #|  @fs.write_file("keep.mbt", "// CORRUPTED\n", create_mode=CreateOrTruncate)
        #|}
      ),
    })
    assert_true(out.is_error)
    // the displayed prefix is the truncated flood, not the denial line (the
    // feedback itself quotes "Operation not permitted", so pin on OSError)...
    assert_true(out.content.contains("output truncated"))
    assert_false(out.content.contains("OSError"))
    // ...yet the guidance still lands, from the full-log scan
    assert_true(out.content.contains("run_moonbit sandbox"))
    assert_true(@fs.read_file("\{ws}/keep.mbt").text().contains("fn main {  }"))
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
  assert_true(out.content.contains("run_moonbit requires"))
}

///|
async test "rejects non-string source arguments" {
  let out = run_in(".", { "code": "x" })
  assert_true(out.is_error)
  assert_true(out.content.contains("run_moonbit requires"))
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
  // the model reads a path about its own input, not /tmp/openseek-run-moonbit-*
  assert_true(out.content.contains("source:"))
  assert_false(out.content.contains("openseek-run-moonbit-"))
  assert_false(out.content.contains("snippet.mbt"))
}

///|
/// Spawning processes is what this tool is for now — the refusal that used to
/// send commands to the shell tool would make the registry unable to run any.
#cfg(not(platform="windows"))
async test "runs a command through the myshell EDSL" {
  let out = run(
    (
      #|import { "bobzhang/myshell", "moonbitlang/async" }
      #|
      #|async fn main {
      #|  let result = @myshell.Cmd("printf", ["alpha"]).output()
      #|  println("out=\{result.stdout} exit=\{result.exit_code}")
      #|}
    ),
  )
  assert_false(out.is_error)
  assert_true(out.content.contains("out=alpha exit=0"))
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
