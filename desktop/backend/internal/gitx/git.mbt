// Running git as a subprocess: the call shapes the backend needs, and the
// repository questions callers ask first. This is the backend's one git
// runner, so its environment policy applies to every git it starts.
//
// A git call fails in exactly two useful ways — the command could not run, or
// it ran and refused — and the refusal text is written for a person. Every
// shape here therefore keeps git's own message rather than summarizing it.

///|
/// Debug is what the host boundary logs: proton renders a failed handler's
/// error through `Repr`, which prints only an opaque `<...: ...>` placeholder
/// for types without it — swallowing the one string that says what failed.
#derive(Debug)
pub suberror GitError {
  GitError(String)
}

///|
impl Show for GitError with fn output(self, logger) {
  match self {
    GitError(message) => logger.write_string(message)
  }
}

///|
/// Remove Git subprocess overrides while retaining PATH, identity, locale, and
/// the user's ordinary Git configuration through HOME/XDG_CONFIG_HOME. Hooks
/// and nested Git commands export repository-local variables, and explicit
/// config/quarantine overrides can redirect object and hook lookup too. The
/// backend must instead discover everything from the validated `cwd` it runs
/// git in. Matching is case-insensitive because Windows preserves arbitrary
/// key casing; removing the whole namespace also covers future Git overrides.
fn sanitize_environment(env : Map[String, String]) -> Unit {
  let remove = [
    for name, _ in env if name.to_upper().has_prefix("GIT_") => name
  ]
  for name in remove {
    env.remove(name)
  }
}

///|
/// The complete environment every git child runs with: this process's
/// environment minus the `GIT_*` namespace. Exposed for tools that run git on
/// their own (gh), which must not be redirected either; pass it with
/// `inherit_env=false`.
pub fn environment() -> Map[String, String] {
  let env = @sys.get_env_vars()
  sanitize_environment(env)
  env
}

///|
/// Start git in `dir` with the sanitized environment and collect its exit
/// status and both streams. Only a failure to run git raises.
async fn collect(
  dir : @pathx.Absolute,
  args : Array[String],
) -> @process.ProcessResult {
  @processx.collect_output_no_stdin(
    "git",
    args,
    cwd=dir.to_string(),
    extra_env=environment(),
    inherit_env=false,
  ) catch {
    error => raise GitError("failed to run git: \{error}")
  }
}

///|
/// The refusal for a git command that exited with `code`: git's own stderr,
/// or the command and status when git said nothing.
fn refusal(args : Array[String], result : @process.ProcessResult) -> GitError {
  let code = result.exit_code
  let detail = (result.stderr_text() catch { _ => "" }).trim().to_owned()
  GitError(
    if detail.is_empty() {
      "git \{args.join(" ")} exited with code \{code}"
    } else {
      detail
    },
  )
}

///|
/// Run git in `dir` and return its stdout bytes exactly, for object content
/// (`cat-file -p`) that need not be text.
pub async fn output_bytes(dir : @pathx.Absolute, args : Array[String]) -> Bytes {
  let result = collect(dir, args)
  let code = result.exit_code
  guard code == 0 else { raise refusal(args, result) }
  result.stdout_binary()
}

///|
/// Run git in `dir` and return its stdout exactly. Porcelain `-z` callers need
/// the leading status-space and NUL separators intact; ordinary callers trim
/// this value in `run` below.
pub async fn output(dir : @pathx.Absolute, args : Array[String]) -> String {
  let result = collect(dir, args)
  let code = result.exit_code
  guard code == 0 else { raise refusal(args, result) }
  result.stdout_text() catch {
    _ => raise GitError("git produced non-text output")
  }
}

///|
/// Run git for a command whose exit status 1 is an answer rather than a
/// failure — `config --get` with no such key, `merge-base --is-ancestor`
/// saying no, `symbolic-ref --quiet` on a detached HEAD, `diff --no-index`
/// finding differences — and return that status with the exact stdout. Any
/// other nonzero status raises with git's own message, like `output`.
pub async fn output_with_status(
  dir : @pathx.Absolute,
  args : Array[String],
) -> (Int32, String) {
  let result = collect(dir, args)
  let code = result.exit_code
  guard code == 0 || code == 1 else { raise refusal(args, result) }
  let text = result.stdout_text() catch {
    _ => raise GitError("git produced non-text output")
  }
  (code, text)
}

///|
/// Run git in `dir` and return its trimmed stdout; a failure raises with
/// git's own message so refusals ("branch already exists", a checkout
/// conflict) reach the user verbatim.
pub async fn run(dir : @pathx.Absolute, args : Array[String]) -> String {
  output(dir, args).trim().to_owned()
}

///|
/// Probe variant of `run`: `None` when git is unavailable or the command
/// fails, for questions where failure itself is the answer (is this a
/// repository? does this branch exist?).
pub async fn probe(dir : @pathx.Absolute, args : Array[String]) -> String? {
  let result = collect(dir, args) catch { _ => return None }
  let code = result.exit_code
  guard code == 0 else { return None }
  let text = result.stdout_text() catch { _ => return None }
  Some(text.trim().to_owned())
}

///|
/// Fire-and-forget git call for shielded rollback. Every failure is
/// swallowed, which is only safe because callers run it inside
/// `@async.protect_from_cancel` — no cancellation error can surface there —
/// and are already propagating the failure that triggered the rollback.
pub async fn rollback(dir : @pathx.Absolute, args : Array[String]) -> Unit {
  let _ = collect(dir, args) catch { _ => return }
}

///|
/// Whether `dir` is inside a git working tree. A plain directory, a `.git`
/// directory itself, and a machine without git all answer false.
pub async fn is_work_tree(dir : @pathx.Absolute) -> Bool {
  probe(dir, ["rev-parse", "--is-inside-work-tree"]) is Some("true")
}

///|
/// The absolute `--git-dir` / `--git-common-dir` pair for `dir`; `None` when
/// `dir` is not inside a git repository or git is unavailable. The two
/// differ exactly for linked worktrees — a submodule checkout keeps them
/// equal, which is why detection is never "`.git` is a file".
pub async fn dir_pair(dir : @pathx.Absolute) -> (String, String)? {
  guard probe(dir, [
      "rev-parse", "--path-format=absolute", "--git-dir", "--git-common-dir",
    ])
    is Some(output) else {
    return None
  }
  let lines : Array[String] = []
  for line in output.split("\n") {
    let line = line.trim().to_owned()
    if !line.is_empty() {
      lines.push(line)
    }
  }
  guard lines is [git_dir, common_dir] else { return None }
  Some((git_dir, common_dir))
}

///|
/// Whether `dir` is a linked git worktree. A main checkout, a submodule
/// checkout, a plain directory, and a machine without git all answer false.
pub async fn is_linked_worktree(dir : @pathx.Absolute) -> Bool {
  guard dir_pair(dir) is Some((git_dir, common_dir)) else { return false }
  git_dir != common_dir
}

///|
pub extend GitError with Debug::{to_repr}
