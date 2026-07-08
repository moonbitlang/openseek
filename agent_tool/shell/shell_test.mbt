///|
async fn run_shell(arguments : Json) -> @agent_tool.ToolOutput {
  let action = match @shell.definition().execute {
    Async(execute) => execute(arguments)
    Sync(_) => fail("shell tool should be async")
  }
  guard action is Respond(output) else { fail("expected Respond") }
  output
}

///|
/// Run the shell tool wired like the agent: a background runtime, so foreground
/// commands run through the shared ShellExecution model and the background /
/// detach paths are exercised.
#cfg(not(platform="windows"))
async fn run_shell_wired(
  bg : @bgjobs.BgJobRuntime,
  arguments : Json,
) -> @agent_tool.ToolOutput {
  let action = match @shell.definition(bg_runtime=bg).execute {
    Async(execute) => execute(arguments)
    Sync(_) => fail("shell tool should be async")
  }
  guard action is Respond(output) else { fail("expected Respond") }
  output
}

///|
#cfg(not(platform="windows"))
async test "run_in_background starts a job and returns its id" {
  @async.with_task_group(group => {
    let bg = @bgjobs.BgJobRuntime::new(AgentTaskScope(group))
    let output = run_shell_wired(bg, {
      "cmd": "printf hi",
      "run_in_background": true,
    })
    assert_false(output.is_error)
    assert_true(output.content.contains("started background job"))
    assert_true(bg.list().length() == 1)
  })
}

///|
#cfg(not(platform="windows"))
async test "run_in_background rejects timeout_ms" {
  @async.with_task_group(group => {
    let bg = @bgjobs.BgJobRuntime::new(AgentTaskScope(group))
    let output = run_shell_wired(bg, {
      "cmd": "printf hi",
      "run_in_background": true,
      "timeout_ms": 1000,
    })
    assert_true(output.is_error)
    assert_true(output.content.contains("not supported with run_in_background"))
  })
}

///|
#cfg(not(platform="windows"))
async test "foreground runs through the execution model" {
  @async.with_task_group(group => {
    let bg = @bgjobs.BgJobRuntime::new(AgentTaskScope(group))
    let output = run_shell_wired(bg, { "cmd": "printf hi" })
    assert_false(output.is_error)
    assert_true(output.content.contains("hi"))
    assert_true(output.content.contains("exit=0"))
  })
}

///|
#cfg(not(platform="windows"))
async test "wired foreground reports binary output as a tool error" {
  @async.with_task_group(group => {
    let bg = @bgjobs.BgJobRuntime::new(AgentTaskScope(group))
    // The wired path (through ShellExecution) must match the per-call path:
    // non-UTF-8 output is a tool error, not replacement characters as success.
    let output = run_shell_wired(bg, { "cmd": "printf '\\377'" })
    assert_true(output.is_error)
    assert_true(output.content.contains("Malformed"))
  })
}

///|
#cfg(not(platform="windows"))
async test "foreground enforces max_output_chars with an output-limit error" {
  @async.with_task_group(group => {
    let bg = @bgjobs.BgJobRuntime::new(AgentTaskScope(group))
    // `yes` exceeds the tiny budget; the shared foreground path must report the
    // output-limit error, not silently drop output as a success.
    let output = run_shell_wired(bg, { "cmd": "yes", "max_output_chars": 100 })
    assert_true(output.is_error)
    assert_true(output.content.contains("output_limit_reached"))
  })
}

///|
#cfg(not(platform="windows"))
async test "a timed command that floods output is an output-limit error, not detached" {
  @async.with_task_group(group => {
    let dir = @fs.tmpdir(prefix="openseek-test-")
    let bg = @bgjobs.BgJobRuntime::new(AgentTaskScope(group), spill_dir=dir)
    // A long timeout, but the runaway must be killed at the output limit promptly
    // (not run to the timeout and then backgrounded).
    let output = run_shell_wired(bg, {
      "cmd": "yes",
      "timeout_ms": 30000,
      "max_output_chars": 100,
    })
    assert_true(output.is_error)
    assert_true(output.content.contains("output_limit_reached"))
    @fs.rmdir(dir, recursive=true) catch {
      _ => ()
    }
  })
}

///|
#cfg(not(platform="windows"))
async test "a detached foreground job retains full output past the inline cap" {
  @async.with_task_group(group => {
    let dir = @fs.tmpdir(prefix="openseek-test-")
    let bg = @bgjobs.BgJobRuntime::new(AgentTaskScope(group), spill_dir=dir)
    // Under the output limit at the timeout (still sleeping) → cleanly detached;
    // then it floods output, which a detached job retains (the output-limit kill
    // is cleared on detach).
    let output = run_shell_wired(bg, {
      "cmd": "sleep 0.3; seq 1 5000",
      "timeout_ms": 150,
      "max_output_chars": 100,
    })
    assert_true(output.content.contains("moved to the background"))
    // The detached job is file-backed, so its full output is retained, not
    // capped at the foreground budget. Poll until the monitor has flushed it.
    let id = bg.list()[0].id
    let mut seen = false
    for _ in 0..<200 {
      if bg.read_output(id).unwrap_or("").contains("5000") {
        seen = true
        break
      }
      @async.sleep(25)
    }
    assert_true(seen)
    let _ = bg.stop(id)
    @fs.rmdir(dir, recursive=true) catch {
      _ => ()
    }
  })
}

///|
#cfg(not(platform="windows"))
async test "a foreground command that times out is detached to the background" {
  @async.with_task_group(group => {
    let bg = @bgjobs.BgJobRuntime::new(AgentTaskScope(group))
    let output = run_shell_wired(bg, { "cmd": "sleep 2", "timeout_ms": 100 })
    assert_false(output.is_error)
    assert_true(output.content.contains("moved to the background"))
    assert_true(bg.list().length() == 1)
    assert_true(bg.list()[0].status is Running)
  })
}

///|
async fn run_shell_in_workspace(
  workspace_root : String,
  arguments : Json,
) -> @agent_tool.ToolOutput {
  let action = match @shell.definition(workspace_root~).execute {
    Async(execute) => execute(arguments)
    Sync(_) => fail("shell tool should be async")
  }
  guard action is Respond(output) else { fail("expected Respond") }
  output
}

///|
/// The canonical protected source fixture for the masked-write catalog below.
let answer_source : String = "pub fn answer() -> Int { 42 }\n"

///|
/// Write the protected `main.mbt` fixture into `dir`.
async fn write_answer_main(
  dir : String,
  content? : String = answer_source,
) -> Unit {
  @fs.write_file("\{dir}/main.mbt", content, create_mode=CreateOrTruncate)
}

///|
/// Assert the protected `main.mbt` fixture survived untouched.
async fn assert_answer_main_unchanged(
  dir : String,
  content? : String = answer_source,
) -> Unit {
  assert_eq(@fs.read_file("\{dir}/main.mbt").text(), content)
}

///|
/// Assert `result` is the pre-execution source-write refusal: an error
/// Respond carrying the `marker` phrase plus the shared feedback line (and,
/// when `line_anchored`, the edit-tool redirection hint).
fn expect_source_write_blocked(
  output : @agent_tool.ToolOutput,
  marker? : String = "source tree operation is blocked",
  line_anchored? : Bool = false,
) -> Unit raise {
  assert_true(output.is_error)
  assert_true(output.content.contains(marker))
  assert_true(
    output.content.contains("source file writes from shell are blocked"),
  )
  if line_anchored {
    assert_true(output.content.contains("line-anchored"))
  }
}

///|
#cfg(not(platform="windows"))
async fn sandbox_exec_usable_for_test() -> Bool {
  if !@fs.exists("/usr/bin/sandbox-exec") {
    return false
  }
  let probe_dir = @fs.tmpdir(prefix="openseek-shell-sandbox-probe-") catch {
    _ => return false
  }
  // sandbox-exec matches deny rules against the realpath of the write target, so
  // the deny literal must use the resolved temp dir. macOS temp dirs sit under
  // symlinked prefixes (`/tmp`, `$TMPDIR`); without this the deny never matched,
  // the probe reported the sandbox unusable, and every functional sandbox test
  // below silently skipped.
  let probe_dir = @fs.realpath(probe_dir) catch { _ => probe_dir }
  let blocked = "\{probe_dir}/blocked"
  let profile =
    $|(version 1)
    $|(allow default)
    $|(deny file-write* (literal "\{blocked}"))
  let (code, _) = @process.collect_output_merged("/usr/bin/sandbox-exec", [
    "-p", profile, "sh", "-c", ":",
  ]) catch {
    _ => {
      cleanup_sandbox_exec_test_probe(probe_dir, blocked)
      return false
    }
  }
  if code != 0 {
    cleanup_sandbox_exec_test_probe(probe_dir, blocked)
    return false
  }
  let (deny_code, _) = @process.collect_output_merged("/usr/bin/sandbox-exec", [
    "-p",
    profile,
    "sh",
    "-c",
    "printf probe > \{test_shell_quote(blocked)}",
  ]) catch {
    _ => {
      cleanup_sandbox_exec_test_probe(probe_dir, blocked)
      return false
    }
  }
  let denied = deny_code != 0 && !@fs.exists(blocked)
  cleanup_sandbox_exec_test_probe(probe_dir, blocked)
  denied
}

///|
#cfg(not(platform="windows"))
fn test_shell_quote(text : String) -> String {
  "'\{text.replace_all(old="'", new="'\\''")}'"
}

///|
#cfg(not(platform="windows"))
async fn cleanup_sandbox_exec_test_probe(
  dir : String,
  blocked : String,
) -> Unit {
  ignore(@fs.remove(blocked) catch { _ => () })
  ignore(@fs.rmdir(dir) catch { _ => () })
}

///|
#cfg(platform="windows")
test "shell description tells models to use PowerShell on Windows" {
  let description = @shell.definition().description
  assert_true(description.contains("PowerShell"))
  assert_true(description.contains("pwsh -NoProfile -Command"))
  assert_true(description.contains("PowerShell syntax"))
}

///|
#cfg(not(platform="windows"))
test "shell description tells models to use POSIX shell off Windows" {
  let description = @shell.definition().description
  assert_true(description.contains("POSIX shell"))
  assert_true(description.contains("sh -c"))
  assert_true(description.contains("POSIX shell syntax"))
}

///|
#cfg(not(platform="windows"))
async test "shell description teaches background jobs only when a runtime is wired" {
  // Unwired: no runtime means run_in_background does not exist and a timed-out
  // command is killed — the description must not promise otherwise.
  let unwired = @shell.definition().description
  assert_false(unwired.contains("run_in_background"))
  // Wired: guide the model to background long-running work and to rely on the
  // pushed completion notice instead of blocking on sleeps or polling.
  @async.with_task_group(group => {
    let bg = @bgjobs.BgJobRuntime::new(AgentTaskScope(group))
    let wired = @shell.definition(bg_runtime=bg).description
    assert_true(wired.contains("run_in_background"))
    assert_true(wired.contains("notice"))
    assert_true(wired.contains("sleep"))
    assert_true(wired.contains("shell_output"))
    assert_true(wired.contains("shell_stop"))
  })
}

///|
async test "shell runs cmd and returns exit code plus output" {
  let output = run_shell({ "cmd": "echo hello" })
  assert_false(output.is_error)
  assert_true(output.content.contains("exit=0"))
  assert_true(output.content.contains("hello"))
}

///|
async test "shell propagates non-zero exit codes" {
  let output = run_shell({ "cmd": "exit 7" })
  assert_true(output.is_error)
  assert_true(output.content.contains("exit=7"))
}

///|
#cfg(platform="windows")
async test "shell follows PowerShell native Windows exit semantics" {
  let output = run_shell({ "cmd": "cmd /c exit 7" })
  assert_true(output.is_error)
  assert_true(output.content.contains("exit=1"))
}

///|
#cfg(platform="windows")
async test "shell follows final successful PowerShell command on Windows" {
  let output = run_shell({ "cmd": "cmd /c exit 7; Write-Output 'ok'" })
  assert_false(output.is_error)
  assert_true(output.content.contains("exit=0"))
  assert_true(output.content.contains("ok"))
}

///|
async test "shell honors cwd when non-empty" {
  @vfs.with_tmpdir(prefix="openseek-shell-cwd-", dir => {
    let output = run_shell({ "cmd": "echo cwd-ok > marker.txt", "cwd": dir })
    let dir_path : @path.Path = dir
    let marker_path = dir_path.join("marker.txt").normalize().to_string()
    let marker = @fs.read_file(marker_path).text() catch { _ => "" }
    assert_false(output.is_error)
    assert_true(output.content.contains("exit=0"))
    assert_eq(marker.trim(), "cwd-ok")
  })
}

///|
async test "shell uses the workspace root when cwd is omitted" {
  @vfs.with_tmpdir(prefix="openseek-shell-workspace-", dir => {
    @fs.write_file(
      "\{dir}/marker.txt",
      "root-ok\n",
      create_mode=CreateOrTruncate,
    )
    let output = run_shell_in_workspace(dir, { "cmd": "cat marker.txt" })
    assert_false(output.is_error)
    assert_true(output.content.contains("exit=0"))
    assert_true(output.content.contains("root-ok"))
  })
}

///|
async test "shell reads a virtual filesystem fixture from cwd" {
  @vfs.with_tmpdir(prefix="openseek-shell-vfs-", project => {
    @vfs.FileSystem({
      "data/input.txt": (
        #|shell-vfs
        #|
      ),
    }).write_to(project)
    let output = run_shell({ "cmd": "cat data/input.txt", "cwd": project })
    assert_false(output.is_error)
    inspect(
      output.content.trim(),
      content=(
        #|shell-vfs
        #|<system>exit=0</system>
      ),
    )
  })
}

///|
async test "shell treats empty cwd as missing" {
  let output = run_shell({ "cmd": "echo cwdless", "cwd": "" })
  assert_false(output.is_error)
  assert_true(output.content.contains("exit=0"))
  assert_true(output.content.contains("cwdless"))
}

///|
#cfg(platform="windows")
async test "shell leaves output at exact limit as a normal result on Windows" {
  let output = run_shell({
    "cmd": "[Console]::Out.Write('abc')",
    "max_output_chars": 3,
  })
  assert_false(output.is_error)
  assert_eq(output.content, "abc\n<system>exit=0</system>")
}

///|
#cfg(not(platform="windows"))
async test "shell leaves output at exact limit as a normal result on Unix" {
  let output = run_shell({ "cmd": "printf %s 'abc'", "max_output_chars": 3 })
  assert_false(output.is_error)
  assert_eq(output.content, "abc\n<system>exit=0</system>")
}

///|
#cfg(platform="windows")
async test "shell counts output limits in characters for non-ascii text on Windows" {
  let output = run_shell({
    "cmd": "[Console]::Out.Write('中中')",
    "max_output_chars": 2,
  })
  assert_false(output.is_error)
  assert_eq(output.content, "中中\n<system>exit=0</system>")
}

///|
#cfg(not(platform="windows"))
async test "shell counts output limits in characters for non-ascii text on Unix" {
  let output = run_shell({ "cmd": "printf %s '中中'", "max_output_chars": 2 })
  assert_false(output.is_error)
  assert_eq(output.content, "中中\n<system>exit=0</system>")
}

///|
#cfg(platform="windows")
async test "shell leaves four-byte utf8 output at exact character limit on Windows" {
  let output = run_shell({
    "cmd": "[Console]::Out.Write('😀')",
    "max_output_chars": 1,
  })
  assert_false(output.is_error)
  assert_eq(output.content, "😀\n<system>exit=0</system>")
}

///|
#cfg(not(platform="windows"))
async test "shell leaves four-byte utf8 output at exact character limit on Unix" {
  let output = run_shell({ "cmd": "printf %s '😀'", "max_output_chars": 1 })
  assert_false(output.is_error)
  assert_eq(output.content, "😀\n<system>exit=0</system>")
}

///|
#cfg(platform="windows")
async test "shell stops oversized output while the command is still running on Windows" {
  let output = run_shell({
    "cmd": "[Console]::Out.Write('abcdef'); Start-Sleep -Seconds 2",
    "max_output_chars": 3,
    "timeout_ms": 1000,
  })
  assert_true(output.is_error)
  assert_true(
    output.content =~ re"^abc\n<system>exit=cancelled truncated=true output_limit_reached=true shown_chars=3 max_output_chars=3</system>$",
  )
  assert_false(output.content.contains("timed out"))
  assert_false(output.content.contains("abcdef"))
}

///|
#cfg(not(platform="windows"))
async test "shell stops oversized output while the command is still running on Unix" {
  let output = run_shell({
    "cmd": "printf %s 'abcdef'; sleep 2",
    "max_output_chars": 3,
    "timeout_ms": 1000,
  })
  assert_true(output.is_error)
  assert_true(
    output.content =~ re"^abc\n<system>exit=cancelled truncated=true output_limit_reached=true shown_chars=3 max_output_chars=3</system>$",
  )
  assert_false(output.content.contains("timed out"))
  assert_false(output.content.contains("abcdef"))
}

///|
#cfg(platform="windows")
async test "shell does not cut multi-byte utf8 output mid-character on Windows" {
  let output = run_shell({
    "cmd": "[Console]::Out.Write('中中中'); Start-Sleep -Seconds 2",
    "max_output_chars": 2,
    "timeout_ms": 1000,
  })
  assert_true(output.is_error)
  assert_true(
    output.content =~ re"^中中\n<system>exit=cancelled truncated=true output_limit_reached=true shown_chars=2 max_output_chars=2</system>$",
  )
  assert_false(output.content.contains("�"))
  assert_false(output.content.contains("中中中"))
}

///|
#cfg(not(platform="windows"))
async test "shell does not cut multi-byte utf8 output mid-character on Unix" {
  let output = run_shell({
    "cmd": "printf %s '中中中'; sleep 2",
    "max_output_chars": 2,
    "timeout_ms": 1000,
  })
  assert_true(output.is_error)
  assert_true(
    output.content =~ re"^中中\n<system>exit=cancelled truncated=true output_limit_reached=true shown_chars=2 max_output_chars=2</system>$",
  )
  assert_false(output.content.contains("�"))
  assert_false(output.content.contains("中中中"))
}

///|
#cfg(platform="windows")
async test "shell does not split four-byte utf8 characters on Windows" {
  let output = run_shell({
    "cmd": "[Console]::Out.Write('😀😀'); Start-Sleep -Seconds 2",
    "max_output_chars": 1,
    "timeout_ms": 1000,
  })
  assert_true(output.is_error)
  assert_true(
    output.content =~ re"^😀\n<system>exit=cancelled truncated=true output_limit_reached=true shown_chars=1 max_output_chars=1</system>$",
  )
  assert_false(output.content.contains("�"))
  assert_false(output.content.contains("😀😀"))
}

///|
#cfg(not(platform="windows"))
async test "shell does not split four-byte utf8 characters on Unix" {
  let output = run_shell({
    "cmd": "printf %s '😀😀'; sleep 2",
    "max_output_chars": 1,
    "timeout_ms": 1000,
  })
  assert_true(output.is_error)
  assert_true(
    output.content =~ re"^😀\n<system>exit=cancelled truncated=true output_limit_reached=true shown_chars=1 max_output_chars=1</system>$",
  )
  assert_false(output.content.contains("�"))
  assert_false(output.content.contains("😀😀"))
}

///|
#cfg(platform="windows")
async test "shell reports binary output as a tool error on Windows" {
  let output = run_shell({
    "cmd": "[Console]::OpenStandardOutput().WriteByte(255)",
  })
  assert_true(output.is_error)
  assert_true(output.content.contains("error running shell:"))
  assert_true(output.content.contains("Malformed"))
}

///|
#cfg(not(platform="windows"))
async test "shell reports binary output as a tool error on Unix" {
  let output = run_shell({ "cmd": "printf '\\377'" })
  assert_true(output.is_error)
  assert_true(output.content.contains("error running shell:"))
  assert_true(output.content.contains("Malformed"))
}

///|
#cfg(platform="windows")
async test "shell output limit wins over an unbounded producer on Windows" {
  let output = run_shell({
    "cmd": "while ($true) { [Console]::Out.Write('yyyyyyyyyy') }",
    "max_output_chars": 5,
    "timeout_ms": 1000,
  })
  assert_true(output.is_error)
  assert_true(
    output.content =~ re"^yyyyy\n<system>exit=cancelled truncated=true output_limit_reached=true shown_chars=5 max_output_chars=5</system>$",
  )
  assert_false(output.content.contains("timed out"))
}

///|
#cfg(not(platform="windows"))
async test "shell output limit wins over an unbounded producer on Unix" {
  let output = run_shell({
    "cmd": "while :; do printf %s 'yyyyyyyyyy'; done",
    "max_output_chars": 5,
    "timeout_ms": 1000,
  })
  assert_true(output.is_error)
  assert_true(
    output.content =~ re"^yyyyy\n<system>exit=cancelled truncated=true output_limit_reached=true shown_chars=5 max_output_chars=5</system>$",
  )
  assert_false(output.content.contains("timed out"))
}

///|
#cfg(platform="windows")
async test "shell merges stderr into the captured output on Windows" {
  let output = run_shell({ "cmd": "[Console]::Error.WriteLine('oops')" })
  assert_false(output.is_error)
  assert_true(output.content.contains("oops"))
}

///|
#cfg(not(platform="windows"))
async test "shell merges stderr into the captured output on Unix" {
  let output = run_shell({ "cmd": "printf '%s\\n' 'oops' 1>&2" })
  assert_false(output.is_error)
  assert_true(output.content.contains("oops"))
}

///|
#cfg(platform="windows")
async test "shell times out long running commands on Windows" {
  let output = run_shell({ "cmd": "Start-Sleep -Seconds 2", "timeout_ms": 50 })
  assert_true(output.is_error)
  assert_eq(output.content, "error: shell command timed out after 50ms")
}

///|
#cfg(not(platform="windows"))
async test "shell times out long running commands on Unix" {
  let output = run_shell({ "cmd": "sleep 2", "timeout_ms": 50 })
  assert_true(output.is_error)
  assert_eq(output.content, "error: shell command timed out after 50ms")
}

///|
async test "shell rejects moon_cmd as a shell command" {
  // `moon check` now runs through shell (no redirect); the only remaining guard
  // is the bare `moon_cmd` tool name, blocked before execution. We do not
  // exercise `moon check` here: the shell tool would run a nested `moon` under
  // `moon test` and deadlock on the build lock.
  let output = run_shell({ "cmd": "moon_cmd run cmd/main" })
  assert_true(output.is_error)
  assert_true(output.content.contains("moon_cmd is not a shell command"))
}

///|
async test "shell rejects sed -i in-place editing" {
  // Blocked by policy before execution, so no file is touched; the model is
  // redirected to the edit tool.
  let output = run_shell({ "cmd": "sed -i 's/old/new/' main.mbt" })
  assert_true(output.is_error)
  assert_true(output.content.contains("sed -i"))
  assert_true(output.content.contains("edit"))
  assert_true(output.content.contains("line-anchored"))
  assert_false(output.content.contains("`write`"))
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox blocks source writes and points to edit tools" {
  if !sandbox_exec_usable_for_test() {
    return
  }
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-source-", dir => {
    write_answer_main(dir)
    // The redirect target hides behind a variable, so the static preblock cannot
    // see it. The write only fails because the kernel source-write sandbox denies
    // it at runtime, which is exactly the enforcement this test must cover.
    let output = run_shell_in_workspace(dir, {
      "cmd": "dest=main.mbt; printf 'pub fn answer() -> Int { 43 }\\n' > \"$dest\"",
      "cwd": dir,
    })
    assert_true(output.is_error)
    assert_true(
      output.content.contains("Operation not permitted") ||
      output.content.contains("Permission denied"),
    )
    assert_true(
      output.content.contains("source file writes from shell are blocked"),
    )
    assert_true(output.content.contains("edit"))
    assert_true(output.content.contains("line-anchored"))
    assert_false(output.content.contains("`write`"))
    assert_answer_main_unchanged(dir)
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox allows generated source writes under _build" {
  if !sandbox_exec_usable_for_test() {
    return
  }
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-build-carveout-", dir => {
    @fs.mkdir("\{dir}/_build")
    // `_build/main.mbt` matches the source-file shape but lives under a
    // Moon-managed build tree, so the SBPL carve-out must keep it writable.
    let output = run_shell_in_workspace(dir, {
      "cmd": "awk 'BEGIN { print \"pub fn generated() -> Int { 1 }\" > \"_build/main.mbt\" }'",
      "cwd": dir,
    })
    assert_false(output.is_error)
    assert_false(
      output.content.contains("source file writes from shell are blocked"),
    )
    assert_eq(
      @fs.read_file("\{dir}/_build/main.mbt").text(),
      "pub fn generated() -> Int { 1 }\n",
    )
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox reports masked source write denials as errors" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-masked-denial-", dir => {
    write_answer_main(dir)
    let output = run_shell_in_workspace(dir, {
      "cmd": "printf %s changed 2>/dev/null > main.mbt || true",
      "cwd": dir,
    })
    assert_true(output.is_error)
    assert_true(output.content.contains("<system>exit=blocked</system>"))
    assert_true(output.content.contains("blocked before execution"))
    assert_true(
      output.content.contains("source file writes from shell are blocked"),
    )
    assert_true(output.content.contains("line-anchored"))
    assert_false(output.content.contains("`write`"))
    assert_answer_main_unchanged(dir)
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks source write through symlink redirect" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-symlink-redirect-", dir => {
    write_answer_main(dir)
    @fs.symlink(target="main.mbt", "\{dir}/out.log")
    let output = run_shell_in_workspace(dir, {
      "cmd": "moon fmt > out.log",
      "cwd": dir,
    })
    assert_true(output.is_error)
    assert_true(
      output.content.contains("source file write redirect is blocked"),
    )
    assert_true(
      output.content.contains("source file writes from shell are blocked"),
    )
    assert_answer_main_unchanged(dir)
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks copy through symlinked source destination" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-symlink-copy-", dir => {
    write_answer_main(dir)
    @fs.write_file(
      "\{dir}/replacement.txt",
      "pub fn answer() -> Int { 43 }\n",
      create_mode=CreateOrTruncate,
    )
    @fs.symlink(target="main.mbt", "\{dir}/out.log")
    let result = run_shell_in_workspace(dir, {
      "cmd": "cp replacement.txt out.log 2>/dev/null || true",
      "cwd": dir,
    })
    expect_source_write_blocked(result, line_anchored=true)
    assert_answer_main_unchanged(dir)
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks tee through symlinked source destination" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-symlink-tee-", dir => {
    write_answer_main(dir)
    @fs.symlink(target="main.mbt", "\{dir}/out.log")
    let result = run_shell_in_workspace(dir, {
      "cmd": "printf changed | tee out.log >/dev/null",
      "cwd": dir,
    })
    expect_source_write_blocked(result)
    assert_answer_main_unchanged(dir)
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox does not treat unrelated output as source denial" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-unrelated-denial-", dir => {
    let output = run_shell_in_workspace(dir, {
      "cmd": "printf '%s\\n' 'foo: Operation not permitted'",
      "cwd": dir,
    })
    assert_false(output.is_error)
    assert_true(output.content.contains("foo: Operation not permitted"))
    assert_false(
      output.content.contains("source file writes from shell are blocked"),
    )
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks source write after uncertain cd chain" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-cd-chain-", dir => {
    write_answer_main(dir)
    let output = run_shell_in_workspace(dir, {
      "cmd": "cd /definitely-missing-openseek 2>/dev/null && :; printf changed > main.mbt",
      "cwd": dir,
    })
    assert_true(output.is_error)
    assert_true(output.content.contains("blocked before execution"))
    assert_true(
      output.content.contains("source file writes from shell are blocked"),
    )
    assert_answer_main_unchanged(dir)
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks source write after entering workspace from external cwd" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-external-cwd-", dir => {
    write_answer_main(dir)
    let output = run_shell_in_workspace(dir, {
      "cmd": "cd \{dir}; printf changed 2>/dev/null > main.mbt || true",
      "cwd": "/tmp",
    })
    assert_true(output.is_error)
    assert_true(output.content.contains("blocked before execution"))
    assert_answer_main_unchanged(dir)
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks source directory moves" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-mv-source-dir-", dir => {
    @fs.mkdir("\{dir}/pkg")
    @fs.write_file(
      "\{dir}/pkg/main.mbt",
      "pub fn answer() -> Int { 42 }\n",
      create_mode=CreateOrTruncate,
    )
    let output = run_shell_in_workspace(dir, {
      "cmd": "mv pkg pkg.bak",
      "cwd": dir,
    })
    assert_true(output.is_error)
    assert_true(output.content.contains("source tree operation is blocked"))
    assert_true(output.content.contains("line-anchored"))
    assert_true(@fs.exists("\{dir}/pkg/main.mbt"))
    assert_false(@fs.exists("\{dir}/pkg.bak"))
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox tracks static relative cd before source directory move" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-mv-static-cd-", dir => {
    @fs.mkdir("\{dir}/src")
    @fs.mkdir("\{dir}/src/pkg")
    @fs.write_file(
      "\{dir}/src/pkg/main.mbt",
      "pub fn answer() -> Int { 42 }\n",
      create_mode=CreateOrTruncate,
    )
    let result = run_shell_in_workspace(dir, {
      "cmd": "cd src && mv pkg pkg.bak 2>/dev/null || true",
      "cwd": dir,
    })
    expect_source_write_blocked(result)
    assert_true(@fs.exists("\{dir}/src/pkg/main.mbt"))
    assert_false(@fs.exists("\{dir}/src/pkg.bak"))
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks masked cp source writes" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-cp-masked-source-", dir => {
    write_answer_main(dir)
    @fs.write_file(
      "\{dir}/replacement.txt",
      "pub fn answer() -> Int { 43 }\n",
      create_mode=CreateOrTruncate,
    )
    let result = run_shell_in_workspace(dir, {
      "cmd": "cp replacement.txt main.mbt 2>/dev/null || true",
      "cwd": dir,
    })
    expect_source_write_blocked(result, line_anchored=true)
    assert_answer_main_unchanged(dir)
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks masked mv backup source moves" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-mv-backup-source-", dir => {
    write_answer_main(dir)
    let result = run_shell_in_workspace(dir, {
      "cmd": "mv -b main.mbt backup 2>/dev/null || true",
      "cwd": dir,
    })
    expect_source_write_blocked(result)
    assert_true(@fs.exists("\{dir}/main.mbt"))
    assert_false(@fs.exists("\{dir}/backup"))
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks masked git apply" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-git-apply-source-", dir => {
    write_answer_main(dir)
    // `git apply` applies an EXTERNAL patch — arbitrary content — so it stays
    // pre-blocked before execution even when the failure is masked. Recoverable
    // git worktree subcommands (checkout/restore/reset/rm/mv/...) are no longer
    // blocked; they run as trusted source writers.
    let result = run_shell_in_workspace(dir, {
      "cmd": "git apply change.patch 2>/dev/null || true",
      "cwd": dir,
    })
    expect_source_write_blocked(result)
    assert_answer_main_unchanged(dir)
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks masked awk source writes" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-awk-masked-source-", dir => {
    write_answer_main(dir)
    let result = run_shell_in_workspace(dir, {
      "cmd": "awk 'BEGIN { print \"pub fn answer() -> Int { 43 }\" > \"main.mbt\" }' 2>/dev/null || true",
      "cwd": dir,
    })
    expect_source_write_blocked(result, line_anchored=true)
    assert_answer_main_unchanged(dir)
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks masked dynamic source tree renames" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-dynamic-rename-", dir => {
    let result = run_shell_in_workspace(dir, {
      "cmd": "src=_build/gen; mkdir -p \"$src\"; printf 'pub fn generated() -> Int { 1 }\\n' > \"$src/main.mbt\"; mv \"$src\" pkg 2>/dev/null || true",
      "cwd": dir,
    })
    expect_source_write_blocked(result, line_anchored=true)
    assert_false(@fs.exists("\{dir}/pkg"))
    assert_false(@fs.exists("\{dir}/_build"))
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks masked pathlib source writes" {
  let (python_code, _) = @process.collect_output_merged("sh", [
    "-c", "command -v python3 >/dev/null 2>&1",
  ]) catch {
    _ => return
  }
  if python_code != 0 {
    return
  }
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-pathlib-source-", dir => {
    write_answer_main(dir)
    let result = run_shell_in_workspace(dir, {
      "cmd": "python3 -c 'from pathlib import Path; Path(\"main.mbt\").write_text(\"pub fn answer() -> Int { 43 }\\\\n\")' 2>/dev/null || true",
      "cwd": dir,
    })
    expect_source_write_blocked(result, line_anchored=true)
    assert_answer_main_unchanged(dir)
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks masked heredoc source redirects" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-heredoc-source-", dir => {
    write_answer_main(dir)
    let result = run_shell_in_workspace(dir, {
      "cmd": "cat 2>/dev/null > main.mbt <<'EOF' || true\npub fn answer() -> Int { 43 }\nEOF",
      "cwd": dir,
    })
    expect_source_write_blocked(result)
    assert_answer_main_unchanged(dir)
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks masked python heredoc source writes" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-python-heredoc-", dir => {
    write_answer_main(dir)
    let result = run_shell_in_workspace(dir, {
      "cmd": "python3 - <<'PY' 2>/dev/null || true\nopen('main.mbt', 'w').write('pub fn answer() -> Int { 43 }\\n')\nPY",
      "cwd": dir,
    })
    expect_source_write_blocked(result)
    assert_answer_main_unchanged(dir)
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks masked versioned python source writes" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-python-versioned-", dir => {
    write_answer_main(dir)
    let result = run_shell_in_workspace(dir, {
      "cmd": "python3.12 -c 'open(\"main.mbt\", \"w\").write(\"pub fn answer() -> Int { 43 }\\\\n\")' 2>/dev/null || true",
      "cwd": dir,
    })
    expect_source_write_blocked(result)
    assert_answer_main_unchanged(dir)
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks python exe source write modes" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-python-exe-mode-", dir => {
    write_answer_main(dir)
    let result = run_shell_in_workspace(dir, {
      "cmd": "python.exe -c 'open(\"main.mbt\", \"w+\").close()' 2>/dev/null || true",
      "cwd": dir,
    })
    expect_source_write_blocked(result)
    assert_answer_main_unchanged(dir)
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks masked cp into created source directory" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-cp-created-dir-", dir => {
    write_answer_main(dir)
    let result = run_shell_in_workspace(dir, {
      "cmd": "mkdir backup && cp main.mbt backup 2>/dev/null || true",
      "cwd": dir,
    })
    expect_source_write_blocked(result, line_anchored=true)
    assert_true(@fs.exists("\{dir}/main.mbt"))
    assert_false(@fs.exists("\{dir}/backup/main.mbt"))
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preserves mkdir predictions across fallback branches" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-cp-or-created-dir-", dir => {
    @vfs.with_tmpdir(prefix="openseek-shell-sandbox-external-source-", external => {
      write_answer_main(dir)
      @fs.write_file(
        "\{external}/generated.mbt",
        "pub fn generated() -> Int { 1 }\n",
        create_mode=CreateOrTruncate,
      )
      let result = run_shell_in_workspace(dir, {
        "cmd": "mkdir gen || true; cp \{external}/generated.mbt gen 2>/dev/null || true",
        "cwd": dir,
      })
      expect_source_write_blocked(result, line_anchored=true)
      assert_false(@fs.exists("\{dir}/gen/generated.mbt"))
    })
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks nested shell source generation" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-nested-sh-source-", dir => {
    let output = run_shell_in_workspace(dir, {
      "cmd": "sh -c 'mkdir -p _build/gen; printf source > _build/gen/main.mbt; mv _build/gen pkg'",
      "cwd": dir,
    })
    assert_true(output.is_error)
    assert_true(output.content.contains("source tree operation is blocked"))
    assert_true(output.content.contains("line-anchored"))
    assert_false(@fs.exists("\{dir}/pkg/main.mbt"))
    assert_false(@fs.exists("\{dir}/_build/gen/main.mbt"))
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks scripted source directory renames" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-python-rename-source-dir-", dir => {
    @fs.mkdir("\{dir}/pkg")
    @fs.write_file(
      "\{dir}/pkg/main.mbt",
      "pub fn answer() -> Int { 42 }\n",
      create_mode=CreateOrTruncate,
    )
    let result = run_shell_in_workspace(dir, {
      "cmd": "python3 -c 'import os; os.rename(\"pkg\", \"pkg.bak\")' 2>/dev/null || true",
      "cwd": dir,
    })
    expect_source_write_blocked(result, line_anchored=true)
    assert_true(@fs.exists("\{dir}/pkg/main.mbt"))
    assert_false(@fs.exists("\{dir}/pkg.bak/main.mbt"))
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks scripted external source directory imports" {
  @vfs.with_tmpdir(
    prefix="openseek-shell-sandbox-python-external-source-dir-",
    root => {
      let workspace = "\{root}/workspace"
      let generated = "\{root}/generated_pkg"
      let generated_file = "\{root}/generated.mbt"
      @fs.mkdir(workspace)
      @fs.mkdir(generated)
      @fs.write_file(
        "\{generated}/main.mbt",
        "pub fn generated() -> Int { 1 }\n",
        create_mode=CreateOrTruncate,
      )
      @fs.write_file(
        generated_file,
        "pub fn generated_file() -> Int { 1 }\n",
        create_mode=CreateOrTruncate,
      )
      let result = run_shell_in_workspace(workspace, {
        "cmd": "python3 -c 'import shutil; shutil.move(\"\{generated}\", \"pkg\")'",
        "cwd": workspace,
      })
      expect_source_write_blocked(result, line_anchored=true)
      assert_true(@fs.exists("\{generated}/main.mbt"))
      assert_false(@fs.exists("\{workspace}/pkg/main.mbt"))
      let copy_output = run_shell_in_workspace(workspace, {
        "cmd": "python3 -c 'import shutil; shutil.copy(\"\{generated_file}\", \"pkg\")'",
        "cwd": workspace,
      })
      assert_true(copy_output.is_error)
      assert_true(
        copy_output.content.contains("source tree operation is blocked"),
      )
      assert_true(
        copy_output.content.contains(
          "source file writes from shell are blocked",
        ),
      )
      assert_true(@fs.exists(generated_file))
      assert_false(@fs.exists("\{workspace}/pkg"))
    },
  )
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox blocks unrecognized incoming source directory renames" {
  @vfs.with_tmpdir(
    prefix="openseek-shell-sandbox-python-incoming-source-dir-",
    dir => {
      @fs.mkdir("\{dir}/_build")
      let output = run_shell_in_workspace(dir, {
        "cmd": "python3 -c 'import os; os.makedirs(\"_build/gen\", exist_ok=True); open(\"_build/gen/main.mbt\", \"w\").write(\"pub fn generated() -> Int { 1 }\\\\n\"); os.rename(\"_build/gen\", \"pkg\")'",
        "cwd": dir,
      })
      assert_true(output.is_error)
      assert_true(output.content.contains("source tree operation is blocked"))
      assert_true(output.content.contains("line-anchored"))
      assert_false(@fs.exists("\{dir}/_build/gen/main.mbt"))
      assert_false(@fs.exists("\{dir}/pkg/main.mbt"))
    },
  )
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks script rename of generated source directory" {
  @vfs.with_tmpdir(
    prefix="openseek-shell-sandbox-python-generated-dir-rename-",
    dir => {
      let output = run_shell_in_workspace(dir, {
        "cmd": "mkdir -p _build/gen && printf 'pub fn generated() -> Int { 1 }\\n' > _build/gen/main.mbt && python3 -c 'import os; os.rename(\"_build/gen\", \"pkg\")'",
        "cwd": dir,
      })
      assert_true(output.is_error)
      assert_true(output.content.contains("source tree operation is blocked"))
      assert_true(output.content.contains("line-anchored"))
      assert_false(@fs.exists("\{dir}/_build/gen/main.mbt"))
      assert_false(@fs.exists("\{dir}/pkg/main.mbt"))
    },
  )
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox allows non-source directory moves" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-mv-assets-dir-", dir => {
    @fs.mkdir("\{dir}/assets")
    @fs.write_file(
      "\{dir}/assets/logo.txt",
      "not MoonBit source\n",
      create_mode=CreateOrTruncate,
    )
    let output = run_shell_in_workspace(dir, {
      "cmd": "mv assets pkg",
      "cwd": dir,
    })
    assert_false(output.is_error)
    assert_false(output.content.contains("source tree operation is blocked"))
    assert_true(@fs.exists("\{dir}/pkg/logo.txt"))
    assert_false(@fs.exists("\{dir}/assets/logo.txt"))
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks source directory move after uncertain cd chain" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-mv-uncertain-cd-", dir => {
    @fs.mkdir("\{dir}/pkg")
    @fs.write_file(
      "\{dir}/pkg/main.mbt",
      "pub fn answer() -> Int { 42 }\n",
      create_mode=CreateOrTruncate,
    )
    let output = run_shell_in_workspace(dir, {
      "cmd": "cd /definitely-missing-openseek 2>/dev/null && :; mv pkg pkg.bak",
      "cwd": dir,
    })
    assert_true(output.is_error)
    assert_true(output.content.contains("source tree operation is blocked"))
    assert_true(@fs.exists("\{dir}/pkg/main.mbt"))
    assert_false(@fs.exists("\{dir}/pkg.bak"))
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks source directory move after entering workspace from external cwd" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-mv-external-cwd-", dir => {
    @fs.mkdir("\{dir}/pkg")
    @fs.write_file(
      "\{dir}/pkg/main.mbt",
      "pub fn answer() -> Int { 42 }\n",
      create_mode=CreateOrTruncate,
    )
    let output = run_shell_in_workspace(dir, {
      "cmd": "cd \{dir}; mv pkg pkg.bak",
      "cwd": "/tmp",
    })
    assert_true(output.is_error)
    assert_true(output.content.contains("source tree operation is blocked"))
    assert_true(@fs.exists("\{dir}/pkg/main.mbt"))
    assert_false(@fs.exists("\{dir}/pkg.bak"))
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks source directory removals" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-rm-source-dir-", dir => {
    @fs.mkdir("\{dir}/pkg")
    @fs.write_file(
      "\{dir}/pkg/moon.pkg",
      "warnings = \"\"\n",
      create_mode=CreateOrTruncate,
    )
    let output = run_shell_in_workspace(dir, { "cmd": "rm -rf pkg", "cwd": dir })
    assert_true(output.is_error)
    assert_true(output.content.contains("source tree operation is blocked"))
    assert_true(@fs.exists("\{dir}/pkg/moon.pkg"))
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks incoming source directory moves" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-mv-incoming-dir-", root => {
    let workspace = "\{root}/workspace"
    let generated = "\{root}/generated_pkg"
    @fs.mkdir(workspace)
    @fs.mkdir(generated)
    @fs.write_file(
      "\{generated}/main.mbt",
      "pub fn generated() -> Int { 1 }\n",
      create_mode=CreateOrTruncate,
    )
    let output = run_shell_in_workspace(workspace, {
      "cmd": "mv \{generated} pkg",
      "cwd": workspace,
    })
    assert_true(output.is_error)
    assert_true(output.content.contains("source tree operation is blocked"))
    assert_true(output.content.contains("line-anchored"))
    assert_true(@fs.exists("\{generated}/main.mbt"))
    assert_false(@fs.exists("\{workspace}/pkg/main.mbt"))
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks generated source directory moves from build output" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-mv-generated-dir-", workspace => {
    @fs.mkdir("\{workspace}/_build")
    let output = run_shell_in_workspace(workspace, {
      "cmd": "mkdir -p _build/gen && printf 'pub fn generated() -> Int { 1 }\\n' > _build/gen/main.mbt && mv _build/gen pkg",
      "cwd": workspace,
    })
    assert_true(output.is_error)
    assert_true(output.content.contains("source tree operation is blocked"))
    assert_false(@fs.exists("\{workspace}/_build/gen/main.mbt"))
    assert_false(@fs.exists("\{workspace}/pkg/main.mbt"))
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks generated dotted source directory moves from build output" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-mv-generated-dot-dir-", workspace => {
    @fs.mkdir("\{workspace}/_build")
    let output = run_shell_in_workspace(workspace, {
      "cmd": "mkdir -p _build/gen.v1 && printf 'pub fn generated() -> Int { 1 }\\n' > _build/gen.v1/main.mbt && mv _build/gen.v1 pkg",
      "cwd": workspace,
    })
    assert_true(output.is_error)
    assert_true(output.content.contains("source tree operation is blocked"))
    assert_false(@fs.exists("\{workspace}/_build/gen.v1/main.mbt"))
    assert_false(@fs.exists("\{workspace}/pkg/main.mbt"))
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks generated dotted source directory moves into existing directory" {
  @vfs.with_tmpdir(
    prefix="openseek-shell-sandbox-mv-generated-dot-dir-existing-",
    workspace => {
      @fs.mkdir("\{workspace}/_build")
      @fs.mkdir("\{workspace}/pkg")
      let output = run_shell_in_workspace(workspace, {
        "cmd": "mkdir -p _build/gen.v1 && printf 'pub fn generated() -> Int { 1 }\\n' > _build/gen.v1/main.mbt && mv _build/gen.v1 pkg",
        "cwd": workspace,
      })
      assert_true(output.is_error)
      assert_true(output.content.contains("source tree operation is blocked"))
      assert_false(@fs.exists("\{workspace}/_build/gen.v1/main.mbt"))
      assert_false(@fs.exists("\{workspace}/pkg/gen.v1/main.mbt"))
    },
  )
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks generated source directory moves to dotted destinations" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-mv-generated-dir-dot-dest-", workspace => {
    @fs.mkdir("\{workspace}/_build")
    let output = run_shell_in_workspace(workspace, {
      "cmd": "mkdir -p _build/gen && printf 'pub fn generated() -> Int { 1 }\\n' > _build/gen/main.mbt && mv _build/gen pkg.v1",
      "cwd": workspace,
    })
    assert_true(output.is_error)
    assert_true(output.content.contains("source tree operation is blocked"))
    assert_false(@fs.exists("\{workspace}/_build/gen/main.mbt"))
    assert_false(@fs.exists("\{workspace}/pkg.v1/main.mbt"))
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks generated file-like source directory moves to file-like destinations" {
  @vfs.with_tmpdir(
    prefix="openseek-shell-sandbox-mv-generated-file-like-dir-",
    workspace => {
      @fs.mkdir("\{workspace}/_build")
      let output = run_shell_in_workspace(workspace, {
        "cmd": "mkdir -p assets _build/gen.tmp && printf 'pub fn generated() -> Int { 1 }\\n' > _build/gen.tmp/main.mbt && mv _build/gen.tmp assets/pkg.tmp",
        "cwd": workspace,
      })
      assert_true(output.is_error)
      assert_true(output.content.contains("source tree operation is blocked"))
      assert_false(@fs.exists("\{workspace}/_build/gen.tmp/main.mbt"))
      assert_false(@fs.exists("\{workspace}/assets/pkg.tmp/main.mbt"))
    },
  )
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox allows generated non-source file moves from build output" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-mv-generated-file-", workspace => {
    let output = run_shell_in_workspace(workspace, {
      "cmd": "mkdir -p assets _build && printf data > _build/logo.txt && mv _build/logo.txt assets/logo.txt",
      "cwd": workspace,
    })
    assert_false(output.is_error)
    assert_false(output.content.contains("source tree operation is blocked"))
    assert_eq(@fs.read_file("\{workspace}/assets/logo.txt").text(), "data")
    assert_false(@fs.exists("\{workspace}/_build/logo.txt"))
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks incoming source files moved into workspace directories" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-mv-incoming-file-", root => {
    let workspace = "\{root}/workspace"
    @fs.mkdir(workspace)
    @fs.mkdir("\{workspace}/pkg")
    let generated = "\{root}/generated.mbt"
    @fs.write_file(
      generated,
      "pub fn generated() -> Int { 1 }\n",
      create_mode=CreateOrTruncate,
    )
    let output = run_shell_in_workspace(workspace, {
      "cmd": "mv -t pkg \{generated}",
      "cwd": workspace,
    })
    assert_true(output.is_error)
    assert_true(output.content.contains("source tree operation is blocked"))
    assert_true(@fs.exists(generated))
    assert_false(@fs.exists("\{workspace}/pkg/generated.mbt"))
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox blocks moon work writes" {
  if !sandbox_exec_usable_for_test() {
    return
  }
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-moon-work-", dir => {
    @fs.write_file(
      "\{dir}/moon.work",
      "members = []\n",
      create_mode=CreateOrTruncate,
    )
    let output = run_shell_in_workspace(dir, {
      "cmd": "printf 'members = [\".\"]' > moon.work",
      "cwd": dir,
    })
    assert_true(output.is_error)
    assert_true(
      output.content.contains("source file writes from shell are blocked"),
    )
    assert_eq(@fs.read_file("\{dir}/moon.work").text(), "members = []\n")
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox still permits moon check build outputs" {
  if !sandbox_exec_usable_for_test() {
    return
  }
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-moon-check-", dir => {
    @fs.write_file(
      "\{dir}/moon.mod",
      "name = \"tmp/shell_sandbox_moon_check\"\n",
      create_mode=CreateOrTruncate,
    )
    write_answer_main(dir)
    let output = run_shell_in_workspace(dir, { "cmd": "moon check", "cwd": dir })
    assert_false(output.is_error)
    assert_true(output.content.contains("<system>exit=0</system>"))
    assert_false(output.content.contains("source file writes from shell"))
  })
}

///|
#cfg(not(platform="windows"))
async test "shell allows moon check pre-build source outputs" {
  @vfs.with_tmpdir(prefix="openseek-shell-moon-check-prebuild-", dir => {
    @fs.write_file(
      "\{dir}/moon.mod",
      "name = \"tmp/shell_moon_check_prebuild\"\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{dir}/moon.pkg",
      (
        #|options(
        #|  "pre-build": [
        #|    {
        #|      "command": "printf 'pub fn generated() -> Int { 1 }\\n' > generated.mbt",
        #|      "input": [],
        #|      "output": "generated.mbt",
        #|    },
        #|  ],
        #|)
      ),
      create_mode=CreateOrTruncate,
    )
    write_answer_main(dir, content="pub fn answer() -> Int { generated() }\n")
    let output = run_shell_in_workspace(dir, { "cmd": "moon check", "cwd": dir })
    assert_false(output.is_error)
    assert_true(output.content.contains("<system>exit=0</system>"))
    assert_true(@fs.exists("\{dir}/generated.mbt"))
    assert_eq(
      @fs.read_file("\{dir}/generated.mbt").text(),
      "pub fn generated() -> Int { 1 }\n",
    )
  })
}

///|
#cfg(not(platform="windows"))
async test "shell trusts guarded package cd before moon check pre-build output" {
  if !sandbox_exec_usable_for_test() {
    return
  }
  @vfs.with_tmpdir(prefix="openseek-shell-moon-check-cd-prebuild-", dir => {
    @fs.write_file(
      "\{dir}/moon.mod",
      "name = \"tmp/shell_moon_check_cd_prebuild\"\n",
      create_mode=CreateOrTruncate,
    )
    @fs.mkdir("\{dir}/pkg")
    @fs.write_file(
      "\{dir}/pkg/moon.pkg",
      (
        #|options(
        #|  "pre-build": [
        #|    {
        #|      "command": "printf 'pub fn generated() -> Int { 1 }\\n' > generated.mbt",
        #|      "input": [],
        #|      "output": "generated.mbt",
        #|    },
        #|  ],
        #|)
      ),
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{dir}/pkg/main.mbt",
      "pub fn answer() -> Int { generated() }\n",
      create_mode=CreateOrTruncate,
    )
    let output = run_shell_in_workspace(dir, {
      "cmd": "cd pkg && moon check",
      "cwd": dir,
    })
    // `cd pkg && moon check` is a trusted source-write command, so the sandbox
    // must run it unsandboxed and let moon's pre-build write source. We assert
    // only that our guard did not interpose; whether moon's pre-build itself
    // succeeds is moon's concern, not the sandbox's. (If trust regressed and the
    // command were sandboxed, moon's `> generated.mbt` would surface one of these
    // denial markers.)
    assert_false(
      output.content.contains("source file writes from shell are blocked"),
    )
    assert_false(output.content.contains("blocked before execution"))
    assert_false(output.content.contains("Operation not permitted"))
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox blocks too-complex sed source rewrites" {
  if !sandbox_exec_usable_for_test() {
    return
  }
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-sed-glob-", dir => {
    write_answer_main(dir, content="pub fn answer() -> Int { old }\n")
    let output = run_shell_in_workspace(dir, {
      "cmd": "sed -i '' 's/old/new/' *.mbt",
      "cwd": dir,
    })
    assert_true(output.is_error)
    assert_true(
      output.content.contains("source file writes from shell are blocked"),
    )
    assert_true(output.content.contains("line-anchored"))
    assert_false(output.content.contains("`write`"))
    assert_answer_main_unchanged(
      dir,
      content="pub fn answer() -> Int { old }\n",
    )
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox preblocks too-complex fd duplicate source redirect" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-fd-dup-source-", dir => {
    write_answer_main(dir)
    let output = run_shell_in_workspace(dir, {
      "cmd": "printf changed >& main.mbt *.txt 2>/dev/null || true",
      "cwd": dir,
    })
    assert_true(output.is_error)
    assert_true(output.content.contains("source tree operation is blocked"))
    assert_answer_main_unchanged(dir)
  })
}

///|
#cfg(not(platform="windows"))
async test "shell sandbox allows read-only grep of source text" {
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-grep-mv-", dir => {
    @fs.write_file(
      "\{dir}/main.mbt",
      "let mv_marker = 1\n",
      create_mode=CreateOrTruncate,
    )
    let output = run_shell_in_workspace(dir, {
      "cmd": "grep mv *.mbt",
      "cwd": dir,
    })
    assert_false(output.is_error)
    assert_true(output.content.contains("mv_marker"))
    assert_false(output.content.contains("source tree operation is blocked"))
  })
}

///|
#cfg(not(platform="windows"))
async test "shell preblocks env unset sed source rewrites" {
  @vfs.with_tmpdir(prefix="openseek-shell-env-sed-source-", dir => {
    write_answer_main(dir, content="pub fn answer() -> Int { old }\n")
    let output = run_shell_in_workspace(dir, {
      "cmd": "env -u FOO sed -i '' 's/old/new/' *.mbt 2>/dev/null || true",
      "cwd": dir,
    })
    assert_true(output.is_error)
    assert_true(
      output.content.contains("source file writes from shell are blocked"),
    )
    assert_true(output.content.contains("line-anchored"))
    assert_false(output.content.contains("`write`"))
    assert_answer_main_unchanged(
      dir,
      content="pub fn answer() -> Int { old }\n",
    )
  })
}

///|
#cfg(not(platform="windows"))
async test "shell preblocks env assignment sed source rewrites" {
  @vfs.with_tmpdir(prefix="openseek-shell-env-assign-sed-source-", dir => {
    write_answer_main(dir, content="pub fn answer() -> Int { old }\n")
    let output = run_shell_in_workspace(dir, {
      "cmd": "FOO=bar sed -i '' 's/old/new/' *.mbt 2>/dev/null || true",
      "cwd": dir,
    })
    assert_true(output.is_error)
    assert_true(
      output.content.contains("source file writes from shell are blocked"),
    )
    assert_true(output.content.contains("line-anchored"))
    assert_false(output.content.contains("`write`"))
    assert_answer_main_unchanged(
      dir,
      content="pub fn answer() -> Int { old }\n",
    )
  })
}

///|
#cfg(not(platform="windows"))
async test "shell preblocks find exec sed source rewrites" {
  @vfs.with_tmpdir(prefix="openseek-shell-find-sed-source-", dir => {
    write_answer_main(dir, content="pub fn answer() -> Int { old }\n")
    let output = run_shell_in_workspace(dir, {
      "cmd": "find \{dir} -name '*.mbt' -exec env FOO=bar sed -i '' 's/old/new/' {} + 2>/dev/null || true",
      "cwd": dir,
    })
    assert_true(output.is_error)
    assert_true(
      output.content.contains("source file writes from shell are blocked"),
    )
    assert_true(output.content.contains("line-anchored"))
    assert_false(output.content.contains("`write`"))
    assert_answer_main_unchanged(
      dir,
      content="pub fn answer() -> Int { old }\n",
    )
  })
}

///|
#cfg(not(platform="windows"))
async test "shell preblocks looped sed source rewrites through path list" {
  @vfs.with_tmpdir(prefix="openseek-shell-loop-sed-source-", dir => {
    write_answer_main(dir, content="pub fn answer() -> Int { old }\n")
    @fs.write_file(
      "\{dir}/files.txt",
      "\{dir}/main.mbt\n",
      create_mode=CreateOrTruncate,
    )
    let output = run_shell_in_workspace(dir, {
      "cmd": "while IFS= read -r f; do sed -i '' 's/old/new/' \"$f\"; done < files.txt",
      "cwd": dir,
    })
    assert_true(output.is_error)
    assert_true(
      output.content.contains("source file writes from shell are blocked"),
    )
    assert_true(output.content.contains("line-anchored"))
    assert_false(output.content.contains("`write`"))
    assert_answer_main_unchanged(
      dir,
      content="pub fn answer() -> Int { old }\n",
    )
  })
}

///|
#cfg(not(platform="windows"))
async test "shell allows recoverable git worktree rollback" {
  @vfs.with_tmpdir(prefix="openseek-shell-git-rollback-", dir => {
    write_answer_main(dir)
    // Build a tiny repo with a committed main.mbt. init/config/add/commit only
    // touch `.git`, so they run (sandboxed) without being blocked.
    let setup_output = run_shell_in_workspace(dir, {
      "cmd": "git init -q && git config user.email a@b.c && git config user.name t && git add main.mbt && git commit -q -m init",
      "cwd": dir,
    })
    assert_false(
      setup_output.content.contains("source file writes from shell are blocked"),
    )
    // Dirty the tracked source, then discard the change with `git checkout` — a
    // trusted, recoverable worktree write that now runs unsandboxed and succeeds.
    write_answer_main(dir, content="pub fn answer() -> Int { 999 }\n")
    let output = run_shell_in_workspace(dir, {
      "cmd": "git checkout -- main.mbt",
      "cwd": dir,
    })
    assert_false(output.is_error)
    assert_false(
      output.content.contains("source file writes from shell are blocked"),
    )
    assert_answer_main_unchanged(dir)
  })
}

///|
#cfg(not(platform="windows"))
async test "shell allows trusted moon fmt command" {
  if !sandbox_exec_usable_for_test() {
    return
  }
  @vfs.with_tmpdir(prefix="openseek-shell-sandbox-moon-fmt-", dir => {
    @fs.write_file(
      "\{dir}/moon.mod",
      "name = \"tmp/shell_sandbox_moon_fmt\"\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{dir}/main.mbt",
      "pub fn answer()->Int{42}\n",
      create_mode=CreateOrTruncate,
    )
    let output = run_shell_in_workspace(dir, { "cmd": "moon fmt", "cwd": dir })
    assert_false(output.is_error)
    assert_true(output.content.contains("<system>exit=0</system>"))
    assert_false(output.content.contains("source file writes from shell"))
    assert_true(@fs.read_file("\{dir}/main.mbt").text().contains("answer"))
  })
}

///|
#cfg(not(platform="windows"))
async test "shell appends moon check after applied moon ide rename" {
  @vfs.with_tmpdir(prefix="openseek-shell-auto-check-", dir => {
    @fs.write_file(
      "\{dir}/moon.mod",
      "name = \"tmp/shell_auto_check\"\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{dir}/moon.pkg",
      "warnings = \"+unnecessary_annotation\"\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{dir}/main.mbt",
      (
        #|pub fn old_name() -> Int { missing_symbol }
        #|
        #|pub fn call() -> Int { old_name() }
        #|
      ),
      create_mode=CreateOrTruncate,
    )
    let output = run_shell({
      "cmd": "moon ide rename old_name new_name --loc main.mbt:1:8 --apply",
      "cwd": dir,
    })
    assert_false(output.is_error)
    assert_true(output.content.contains("<system>exit=0</system>"))
    assert_true(output.content.contains("Applied 2 edit(s)"))
    assert_true(output.content.contains("\nmoon check:\nexit="))
    assert_true(output.content.contains("missing_symbol"))
    // The `<system>` footer stays the last line even with the moon check block
    // inserted before it.
    assert_true(output.content.has_suffix("<system>exit=0</system>"))
    let renamed = @fs.read_file("\{dir}/main.mbt").text()
    assert_true(renamed.contains("new_name"))
    assert_false(renamed.contains("old_name"))
  })
}

///|
#cfg(not(platform="windows"))
async test "shell appends moon check from moon.work workspace root" {
  @vfs.with_tmpdir(prefix="openseek-shell-auto-check-workspace-", dir => {
    @fs.write_file(
      "\{dir}/moon.work",
      "members = [\"pkg\"]\n",
      create_mode=CreateOrTruncate,
    )
    @fs.mkdir("\{dir}/pkg")
    @fs.write_file(
      "\{dir}/pkg/moon.mod",
      "name = \"tmp/shell_auto_check_workspace\"\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{dir}/pkg/moon.pkg",
      "warnings = \"+unnecessary_annotation\"\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{dir}/pkg/main.mbt",
      "pub fn broken()->Int{missing_from_workspace}\n",
      create_mode=CreateOrTruncate,
    )
    let output = run_shell({ "cmd": "moon fmt", "cwd": dir })
    assert_false(output.is_error)
    assert_true(output.content.contains("<system>exit=0</system>"))
    assert_true(output.content.contains("\nmoon check:\nexit=255"))
    assert_true(output.content.contains("missing_from_workspace"))
  })
}

///|
async test "shell does not append moon check for non-mutating moon shapes" {
  @vfs.with_tmpdir(prefix="openseek-shell-no-auto-check-", dir => {
    @fs.write_file(
      "\{dir}/moon.mod",
      "name = \"tmp/shell_no_auto_check\"\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{dir}/moon.pkg",
      "warnings = \"+unnecessary_annotation\"\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{dir}/main.mbt",
      (
        #|pub fn broken() -> Int { missing_symbol }
        #|
      ),
      create_mode=CreateOrTruncate,
    )
    for cmd in ["echo moon add", "true || moon fmt", "moon fmt --check"] {
      let output = run_shell({ "cmd": cmd, "cwd": dir })
      assert_false(output.content.contains("moon check:"))
    }
    let output = run_shell({
      "cmd": "moon fmt",
      "cwd": dir,
      "timeout_ms": 30000,
    })
    assert_false(output.is_error)
    assert_false(output.content.contains("moon check:"))
  })
}

///|
#cfg(not(platform="windows"))
async test "shell appends moon check from moon command target cwd" {
  @vfs.with_tmpdir(prefix="openseek-shell-auto-check-c-option-", dir => {
    let project = "\{dir}/project"
    @fs.mkdir(project)
    @fs.write_file(
      "\{project}/moon.mod",
      "name = \"tmp/shell_auto_check_c_option\"\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{project}/moon.pkg",
      "warnings = \"+unnecessary_annotation\"\n",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      "\{project}/main.mbt",
      (
        #|pub fn broken() -> Int { missing_symbol }
        #|
      ),
      create_mode=CreateOrTruncate,
    )
    for
      cmd in [
        "moon -C project fmt", "moon -Cproject fmt", "moon -C=project fmt", "cd ./project && moon fmt",
      ] {
      let output = run_shell({ "cmd": cmd, "cwd": dir })
      assert_false(output.is_error)
      assert_true(output.content.contains("<system>exit=0</system>"))
      assert_true(output.content.contains("\nmoon check:\nexit="))
      assert_true(output.content.contains("missing_symbol"))
    }
  })
}

///|
async test "shell rejects missing cmd" {
  let output = run_shell({ "cwd": "unused" })
  assert_true(output.is_error)
  assert_true(output.content.contains("error: shell requires"))
  assert_true(output.content.contains("arguments.cmd"))
}

///|
async test "shell rejects non-object arguments" {
  let output = run_shell(Json::null())
  assert_true(output.is_error)
  assert_eq(output.content, "error: shell requires object arguments")
}

///|
async test "shell rejects non-existent cwd" {
  @vfs.with_tmpdir(prefix="openseek-shell-cwd-", dir => {
    let dir_path : @path.Path = dir
    let path = dir_path.join("does-not-exist").normalize().to_string()
    let output = run_shell({ "cmd": "echo hello", "cwd": path })
    assert_true(output.is_error)
    assert_true(output.content.contains("cwd does not exist"))
  })
}

///|
async test "shell rejects cwd that is a file not a directory" {
  @vfs.with_tmpdir(prefix="openseek-shell-cwd-", dir => {
    let dir_path : @path.Path = dir
    let path = dir_path.join("file.txt").normalize().to_string()
    @fs.write_file(path, "not a directory", create_mode=CreateOrTruncate)
    let output = run_shell({ "cmd": "echo hello", "cwd": path })
    assert_true(output.is_error)
    assert_true(output.content.contains("cwd is not a directory"))
  })
}
