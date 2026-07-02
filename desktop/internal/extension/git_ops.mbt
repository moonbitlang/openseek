// The topbar's branch chip: report the git branch of a conversation's
// working directory. Display only — a missing repository (or a machine
// without git) simply reads as "no branch", never an error.

///|
async fn workspace_branch_op(
  payload : WorkspaceBranchPayload,
) -> WorkspaceBranchReply {
  // A live run hands us its cwd; a resumed conversation has none, so fall
  // back to the directory the session's engine runs in (mirrors `open_path`).
  let base = if payload.cwd.is_empty() {
    @engine.session_cwd(payload.session)
  } else {
    payload.cwd
  }
  guard !base.is_empty() else { return { branch: "" } }
  { branch: git_branch(base) }
}

///|
/// The branch checked out at `dir` (`git rev-parse --abbrev-ref HEAD`), with
/// a detached HEAD named by its short hash instead of the literal "HEAD".
/// `""` when `dir` is not a git repository or git is unavailable.
async fn git_branch(dir : String) -> String {
  let name = git_output(dir, ["rev-parse", "--abbrev-ref", "HEAD"])
  if name == "HEAD" {
    git_output(dir, ["rev-parse", "--short", "HEAD"])
  } else {
    name
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
