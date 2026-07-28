// The topbar's branch chip: report the git branch of a conversation's
// working directory. Display only — a missing repository (or a machine
// without git) simply reads as "no branch", never an error.

///|
async fn git_branch_op(payload : GitBranchPayload) -> GitBranchReply {
  // A live run hands us its cwd; a resumed conversation has none, so fall
  // back to the directory the session's engine runs in (mirrors
  // `host.open_path`).
  let base = match payload.cwd {
    Some(cwd) => cwd
    None => @engine.session_cwd(payload.session)
  }
  guard !base.is_empty() else { return { branch: None } }
  { branch: git_branch(base) }
}

///|
/// The branch checked out at `dir` (`git rev-parse --abbrev-ref HEAD`), with
/// a detached HEAD named by its short hash instead of the literal "HEAD".
/// None when `dir` is not a git repository or git is unavailable.
async fn git_branch(dir : String) -> String? {
  let name = git_output(dir, ["rev-parse", "--abbrev-ref", "HEAD"])
  let name = if name == "HEAD" {
    git_output(dir, ["rev-parse", "--short", "HEAD"])
  } else {
    name
  }
  if name.is_empty() {
    None
  } else {
    Some(name)
  }
}

///|
async fn git_output(dir : String, args : Array[String]) -> String {
  let (code, stdout, _) = @process.collect_output("git", args, cwd=dir) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return ""
  }
  guard code == 0 else { return "" }
  (stdout.text() catch { _ => "" }).trim().to_owned()
}
