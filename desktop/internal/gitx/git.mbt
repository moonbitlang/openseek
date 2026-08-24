// Running git as a subprocess: the four call shapes the host needs, and the
// repository question every caller asks first.
//
// A git call fails in exactly two useful ways — the command could not run, or
// it ran and refused — and the refusal text is written for a person. Every
// shape here therefore keeps git's own message rather than summarizing it.

///|
/// Debug is what the host boundary logs: proton renders a failed handler's
/// error through `Repr`, which prints only an opaque `<...: ...>` placeholder
/// for types without it — swallowing the one string that says what failed.
pub suberror GitError {
  GitError(String)
} derive(Debug)

///|
impl Show for GitError with fn output(self, logger) {
  match self {
    GitError(message) => logger.write_string(message)
  }
}

///|
/// Run git in `dir` and return its stdout exactly. Porcelain `-z` callers need
/// the leading status-space and NUL separators intact; ordinary callers trim
/// this value in `run` below.
pub async fn output(dir : @pathx.Absolute, args : Array[String]) -> String {
  let (code, stdout, stderr) = @processx.collect_output_no_stdin(
    "git",
    args,
    cwd=dir.to_string(),
    no_console_window=true,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise GitError("failed to run git: \{error}")
  }
  guard code == 0 else {
    let detail = (stderr.text() catch { _ => "" }).trim().to_owned()
    raise GitError(
      if detail.is_empty() {
        "git \{args.join(" ")} exited with code \{code}"
      } else {
        detail
      },
    )
  }
  stdout.text() catch {
    _ => raise GitError("git produced non-text output")
  }
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
  let (code, stdout, _) = @processx.collect_output_no_stdin(
    "git",
    args,
    cwd=dir.to_string(),
    no_console_window=true,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  guard code == 0 else { return None }
  let text = stdout.text() catch { _ => return None }
  Some(text.trim().to_owned())
}

///|
/// Fire-and-forget git call for shielded rollback. Every failure is
/// swallowed, which is only safe because callers run it inside
/// `@async.protect_from_cancel` — no cancellation error can surface there —
/// and are already propagating the failure that triggered the rollback.
pub async fn rollback(dir : @pathx.Absolute, args : Array[String]) -> Unit {
  let _ = @processx.collect_output_no_stdin(
    "git",
    args,
    cwd=dir.to_string(),
    no_console_window=true,
  ) catch {
    _ => return
  }
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
