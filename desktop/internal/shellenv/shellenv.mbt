// Login-shell environment resolution for the desktop host.
//
// A GUI app launched from Finder/Dock inherits only launchd's minimal
// environment (PATH=/usr/bin:/bin:...), so anything the user configured in
// their shell rc files — Homebrew, moon, node, custom variables — is
// invisible to the engine and every tool it spawns. Resolve it the way
// VS Code does: run the user's interactive login shell once at startup and
// have it re-exec this executable with `--print-env-json <mark>`, which
// prints the environment the shell built up as marker-wrapped JSON. The
// markers let the parent ignore whatever the rc files write to stdout, and
// JSON handles multi-line values and escaping. The resolved variables are
// written back into this process, so the engine, LSP servers, and the shell
// tool all inherit them for free.

///|
/// Set while probing so rc files can detect the probe (and skip slow work),
/// and so a probe can never recurse into another probe.
const ResolvingGuardVar : String = "OPENSEEK_RESOLVING_ENVIRONMENT"

///|
/// Interactive shells can hang on rc files that wait for input; give up and
/// keep the inherited environment after this long.
const ProbeTimeoutMs : Int = 10_000

///|
/// Target of the hidden `--print-env-json <mark>` flag: print this process's
/// environment as `<mark>{json}<mark>` for the probing parent to extract.
pub fn print_env_json(mark : String) -> Unit {
  println(mark + @sys.get_env_vars().to_json().stringify() + mark)
}

///|
/// Windows GUI processes inherit the user's registry environment, so there
/// is nothing to resolve.
#cfg(platform="windows")
pub async fn apply_login_shell_env(
  _executable : String,
  _log : @xlog.Logger,
) -> Unit {

}

///|
/// Probe the user's interactive login shell for the environment it builds
/// up and graft the result onto this process. Best-effort: any failure —
/// timeout, nonzero exit, unparsable output — keeps the inherited
/// environment and only leaves a log line behind.
#cfg(not(platform="windows"))
pub async fn apply_login_shell_env(
  executable : String,
  log : @xlog.Logger,
) -> Unit {
  guard @sys.get_env_var(ResolvingGuardVar) is None else { return }
  let shell = match @sys.get_env_var("SHELL") {
    Some(shell) if !shell.trim().is_empty() => shell
    _ => "/bin/sh"
  }
  let mark = "__openseek_env_\{@sys.now()}__"
  let command = "\{shell_quote(executable)} --print-env-json \{mark}"
  // csh/tcsh reject the separate `-l` flag; every other shell in practice
  // (bash, zsh, fish, dash) takes interactive+login+command this way.
  let shell_name = match shell.rev_find("/") {
    Some(index) => shell[index + 1:].to_owned()
    None => shell
  }
  let args : Array[String] = if shell_name is ("csh" | "tcsh") {
    ["-ic", command]
  } else {
    ["-i", "-l", "-c", command]
  }
  log.info() <? { "message": "shell env probe", "shell": shell }
  let probe_env : Map[String, String] = {}
  probe_env[ResolvingGuardVar] = "1"
  let result = @async.with_timeout_opt(ProbeTimeoutMs, () => {
    @process.collect_stdout(shell, args, extra_env=probe_env)
  }) catch {
    error if @async.is_being_cancelled() => raise error
    error => {
      log.warn() <? { "message": "shell env probe failed", "error": "\{error}" }
      return
    }
  }
  guard result is Some((code, stdout)) else {
    log.warn() <? { "message": "shell env probe timed out" }
    return
  }
  guard code == 0 else {
    log.warn() <? { "message": "shell env probe exit", "code": code }
    return
  }
  let text = stdout.text() catch {
    error => {
      log.warn() <? { "message": "shell env probe output", "error": "\{error}" }
      return
    }
  }
  guard parse_probe_output(text, mark) is Some(env) else {
    log.warn() <? { "message": "shell env probe output unrecognized" }
    return
  }
  let mut applied = 0
  for key, value in env {
    if session_local(key) {
      continue
    }
    @sys.set_env_var(key, value)
    applied += 1
  }
  log.info() <? { "message": "shell env applied", "count": applied }
}

///|
/// Extract the marker-wrapped JSON environment from the probe's stdout. rc
/// files may print arbitrary noise before and after the payload, and the
/// payload itself can contain the mark (zsh exports `_` as the last argument
/// of the command line), so take everything between the FIRST and LAST
/// occurrence of the mark — the greedy match VS Code's regex relies on too.
fn parse_probe_output(text : String, mark : String) -> Map[String, String]? {
  guard text.find(mark) is Some(first) else { return None }
  let start = first + mark.length()
  guard text.rev_find(mark) is Some(last) && last >= start else { return None }
  let json = @json.parse(text[start:last]) catch { _ => return None }
  guard json is Object(entries) else { return None }
  let env : Map[String, String] = {}
  for key, value in entries {
    if value is String(value) {
      env[key] = value
    }
  }
  Some(env)
}

///|
/// Shell-session bookkeeping that would be wrong to graft onto this process.
fn session_local(key : String) -> Bool {
  key == ResolvingGuardVar || key is ("_" | "SHLVL" | "PWD" | "OLDPWD")
}

///|
/// Single-quote `text` for a POSIX shell command line, escaping embedded
/// single quotes as `'\''`.
fn shell_quote(text : String) -> String {
  "'" + text.replace_all(old="'", new="'\\''") + "'"
}
