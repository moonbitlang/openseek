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
/// Probe the user's interactive login shell for the environment it builds
/// up and graft the result onto this process. Best-effort: any failure —
/// timeout, nonzero exit, unparsable output — keeps the inherited
/// environment and only leaves a log line behind. Windows GUI processes
/// already inherit the user's registry environment, so they return before
/// starting a probe.
pub async fn apply_login_shell_env(executable : String) -> Unit {
  if @platform.win32 || @platform.win64 {
    return
  }
  guard @sys.get_env_var(ResolvingGuardVar) is None else { return }
  let shell = match @sys.get_env_var("SHELL") {
    Some(shell) if !shell.is_blank() => shell
    _ => "/bin/sh"
  }
  let mark = "__openseek_env_\{@sys.now()}__"
  let command = "\{shell_quote(executable)} --print-env-json \{mark}"
  // csh/tcsh reject the separate `-l` flag; every other shell in practice
  // (bash, zsh, fish, dash) takes interactive+login+command this way.
  let shell_name = match shell.rev_after("/") {
    Some(name) => name.to_owned()
    None => shell
  }
  let args : Array[String] = if shell_name is ("csh" | "tcsh") {
    ["-ic", command]
  } else {
    ["-i", "-l", "-c", command]
  }
  @xlog.info() <? { "message": "shell env probe", "shell": shell }
  let probe_env : Map[String, String] = Map([])
  probe_env[ResolvingGuardVar] = "1"
  let result = @async.with_timeout_opt(ProbeTimeoutMs, () => {
    @processx.collect_output_no_stdin(shell, args, extra_env=probe_env)
  }) catch {
    error if @async.is_being_cancelled() => raise error
    error => {
      @xlog.warn() <?
        { "message": "shell env probe failed", "error": "\{error}" }
      return
    }
  }
  guard result is Some((code, stdout, _)) else {
    @xlog.warn() <? { "message": "shell env probe timed out" }
    return
  }
  guard code == 0 else {
    @xlog.warn() <? { "message": "shell env probe exit", "code": code }
    return
  }
  let text = stdout.text() catch {
    error => {
      @xlog.warn() <?
        { "message": "shell env probe output", "error": "\{error}" }
      return
    }
  }
  guard parse_probe_output(text, mark) is Some(env) else {
    @xlog.warn() <? { "message": "shell env probe output unrecognized" }
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
  @xlog.info() <? { "message": "shell env applied", "count": applied }
}

///|
/// Build the command an interactive terminal runs after its shell startup
/// files have loaded, putting bin_dirs first on that session's path in the
/// supplied order. One command carries the whole prefix so the terminal does
/// not echo a separate environment update for every packaged tool directory.
/// The command is shell-specific because changing the already-running desktop
/// process cannot update a live prompt. Unknown shells return None instead of
/// receiving syntax they may reject. A carriage return matches xterm's Enter
/// key and works for both PTYs and Windows ConPTY.
pub fn path_prepend_command(
  shell_command : String,
  bin_dirs : Array[String],
  windows~ : Bool,
) -> String? {
  if bin_dirs.is_empty() {
    return None
  }
  let shell = shell_command.to_lower()
  let shell_name = match shell.rev_after("/") {
    Some(name) => name.to_owned()
    None => shell.rev_after("\\").map(name => name.to_owned()).unwrap_or(shell)
  }
  if shell_name is ("pwsh" | "pwsh.exe" | "powershell" | "powershell.exe") {
    let separator = if windows { ";" } else { ":" }
    let quoted = (bin_dirs.join(separator) + separator).replace_all(
      old="'",
      new="''",
    )
    // Environment names are case-sensitive outside Windows, where executable
    // lookup reads PATH rather than the separate Path variable.
    let path_name = if windows { "Path" } else { "PATH" }
    return Some("$env:\{path_name} = '\{quoted}' + $env:\{path_name}\r")
  }
  if windows {
    if shell_name is ("cmd" | "cmd.exe") {
      return Some("set \"Path=\{bin_dirs.join(";")};%Path%\"\r")
    }
    return None
  }
  if shell_name == "fish" {
    let quoted_dirs = [
      for bin_dir in bin_dirs => {
        let quoted = bin_dir
          .replace_all(old="\\", new="\\\\")
          .replace_all(old="'", new="\\'")
        "'\{quoted}'"
      }
    ]
    return Some("set -gx PATH \{quoted_dirs.join(" ")} $PATH\r")
  }
  let quoted_dirs = [
    for bin_dir in bin_dirs => "'\{bin_dir.replace_all(old="'", new="'\\''")}'"
  ]
  if shell_name is ("csh" | "tcsh") {
    return Some("setenv PATH \{quoted_dirs.join(":")}:\"$PATH\"\r")
  }
  if shell_name
    is ("sh" | "bash" | "zsh" | "dash" | "ash" | "ksh" | "mksh" | "yash") {
    return Some("export PATH=\{quoted_dirs.join(":")}:\"$PATH\"\r")
  }
  None
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
  let env : Map[String, String] = Map([])
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
  "'\{text.replace_all(old="'", new="'\\''")}'"
}

///|
test "parse_probe_output extracts the marker-wrapped environment" {
  let mark = "__openseek_env_42__"
  let text = "p10k: warning\n\{mark}{\"PATH\":\"/opt/homebrew/bin:/usr/bin\",\"FOO\":\"a\\nb\"}\{mark}\ngoodbye\n"
  guard parse_probe_output(text, mark) is Some(env) else {
    fail("expected an environment")
  }
  assert_true(env.get("PATH") is Some("/opt/homebrew/bin:/usr/bin"))
  assert_true(env.get("FOO") is Some("a\nb"))
}

///|
test "parse_probe_output survives the mark leaking into the payload" {
  // zsh exports `_` as the last argument of the command line — the mark
  // itself — so the JSON payload can contain the mark. The greedy
  // first-to-last extraction must still capture the whole object.
  let mark = "__openseek_env_42__"
  let text = "\{mark}{\"_\":\"\{mark}\",\"PATH\":\"/usr/bin\"}\{mark}"
  guard parse_probe_output(text, mark) is Some(env) else {
    fail("expected an environment")
  }
  assert_true(env.get("PATH") is Some("/usr/bin"))
}

///|
test "parse_probe_output rejects noise without markers" {
  assert_true(parse_probe_output("no marks here", "__mark__") is None)
  assert_true(parse_probe_output("__mark__ only one", "__mark__") is None)
  assert_true(
    parse_probe_output("__mark__not json__mark__", "__mark__") is None,
  )
}

///|
test "session-local variables are not grafted" {
  assert_true(session_local("OPENSEEK_RESOLVING_ENVIRONMENT"))
  assert_true(session_local("_"))
  assert_true(session_local("SHLVL"))
  assert_true(session_local("PWD"))
  assert_true(session_local("OLDPWD"))
  assert_false(session_local("PATH"))
}

///|
test "shell_quote escapes embedded single quotes" {
  assert_eq(
    shell_quote("/Applications/My App.app/host"),
    "'/Applications/My App.app/host'",
  )
  assert_eq(shell_quote("it's"), "'it'\\''s'")
}
