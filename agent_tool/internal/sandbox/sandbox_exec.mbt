///|
/// The standard absolute path of the macOS `sandbox-exec` binary. Its
/// presence alone does not mean sandboxing works in the current process;
/// `sandbox_exec_available` probes that.
const SandboxExecPath : String = "/usr/bin/sandbox-exec"

///|
let sandbox_exec_available_cache : Ref[Bool?] = { val: None }

///|
/// Build the argument vector passed to `SandboxExecPath` to interpret `cmd`
/// under an inline SBPL `profile`.
///
/// The returned vector has the shape
/// `[-p, profile, @platform_shell.program, ..@platform_shell.args(cmd)]`.
/// Therefore `cmd` is shell text, not an executable path or a pre-tokenized
/// argument vector. This function does not validate the profile or probe
/// availability.
fn sandbox_exec_args(profile : String, cmd : String) -> Array[String] {
  ["-p", profile, @platform_shell.program(), ..@platform_shell.args(cmd)]
}

///|
/// Return whether `sandbox-exec` can apply and enforce a profile in this
/// process.
///
/// On the first call, the probe runs an allowed no-op and a denied temporary
/// file write. It returns `true` only when the former succeeds and the latter
/// is actually blocked. Missing binaries, spawn failures, and environments
/// that forbid nested sandboxing produce `false`; cancellation still
/// propagates. The result is cached process-wide, so later calls do not probe
/// again.
async fn sandbox_exec_available() -> Bool {
  match sandbox_exec_available_cache.val {
    Some(value) => value
    None => {
      let value = probe_sandbox_exec_available()
      sandbox_exec_available_cache.val = Some(value)
      value
    }
  }
}

///|
async fn probe_sandbox_exec_available() -> Bool {
  if !@fs.exists(SandboxExecPath) {
    return false
  }
  let probe_dir = @fs.tmpdir(prefix="openseek-sandbox-probe-") catch {
    error if @async.is_being_cancelled() => raise error
    _ => return false
  }
  // sandbox-exec matches `file-write*` rules against the *realpath* of the
  // target. Temp dirs live under symlinked prefixes on macOS (`/tmp` ->
  // `/private/tmp`, `$TMPDIR` under `/private/var/...`), so a deny rule built
  // from the unresolved path never matches the resolved write. That made the
  // probe believe the sandbox was unenforced and disabled it process-wide.
  // Resolve the dir first, exactly like the real source-write profile does for
  // the workspace root.
  let probe_dir = @fs.realpath(probe_dir) catch {
    error if @async.is_being_cancelled() => raise error
    _ => probe_dir
  }
  let blocked_path = @path.Path(probe_dir)
    .join(Path("blocked"))
    .normalize()
    .to_string()
  let probe_profile =
    $|(version 1)
    $|(allow default)
    $|(deny file-write* (literal "\{sbpl_string_escape(blocked_path)}"))
  let noop_exit = run_probe_exit(
    SandboxExecPath,
    sandbox_exec_args(probe_profile, PlatformNoopCommand),
  )
  if noop_exit != Some(0) {
    cleanup_sandbox_probe(probe_dir, blocked_path)
    return false
  }
  let write_exit = run_probe_exit(
    SandboxExecPath,
    sandbox_exec_args(
      probe_profile,
      "printf probe > \{shell_quote(blocked_path)}",
    ),
  )
  let denied = write_exit != Some(0) && !@fs.exists(blocked_path)
  cleanup_sandbox_probe(probe_dir, blocked_path)
  denied
}

///|
/// Exit code of `program args`, or `None` when the spawn (or an unexpected IO
/// error) fails; a cancellation still propagates. A thin wrapper over
/// `@process.collect_output_merged`, which already drains merged stdout+stderr
/// before waiting, so a child that fills the pipe buffer cannot deadlock
/// against `wait`. The sandbox-availability probe only needs the exit status
/// plus a follow-up `@fs.exists` check, so the collected bytes are discarded.
async fn run_probe_exit(program : String, args : Array[String]) -> Int? {
  let (exit_code, _) = @process.collect_output_merged(program, args) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  Some(exit_code)
}

///|
#cfg(platform="windows")
const PlatformNoopCommand : String = "exit 0"

///|
#cfg(not(platform="windows"))
const PlatformNoopCommand : String = ":"

///|
fn shell_quote(text : String) -> String {
  "'\{text.replace_all(old="'", new="'\\''")}'"
}

///|
async fn cleanup_sandbox_probe(
  probe_dir : String,
  blocked_path : String,
) -> Unit {
  ignore(@fs.remove(blocked_path) catch { _ => () })
  ignore(@fs.rmdir(probe_dir) catch { _ => () })
}
