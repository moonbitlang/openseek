// Detached worktrees keep their commits reachable through private Git refs.
// The original base remains immutable; the recovery ref tracks the last HEAD
// saved before checkout removal or administrative pruning.

///|
const WorktreeRecoveryPrefix = "refs/openseek/worktrees/"

///|
priv enum WorktreeCheckout {
  Branch(String)
  Detached(String)
} derive(Debug, Eq)

///|
fn WorktreeCheckout::branch(self : WorktreeCheckout) -> String? {
  match self {
    Branch(branch) => Some(branch)
    Detached(_) => None
  }
}

///|
fn WorktreeCheckout::revision(self : WorktreeCheckout) -> String {
  match self {
    Branch(branch) => "refs/heads/\{branch}"
    Detached(recovery_ref) => recovery_ref
  }
}

///|
fn valid_recovery_ref(name : String, recovery_ref : String) -> Bool {
  let prefix = "\{WorktreeRecoveryPrefix}\{name}-"
  guard recovery_ref.has_prefix(prefix) else { return false }
  let suffix = recovery_ref.view(start_offset=prefix.length())
  suffix.length() == 32 &&
  suffix.iter().all(ch => ch.is_ascii_digit() || (ch >= 'a' && ch <= 'f'))
}

///|
priv struct CheckoutState {
  head : String?
  lock_reason : String?
}

///|
/// NUL-delimited porcelain preserves spaces, newlines and non-ASCII paths.
/// Git canonicalizes the workspace root and the listed checkout paths alike.
async fn checkout_states(dir : @pathx.Absolute) -> Map[String, CheckoutState] {
  let root = @gitx.output(dir, ["rev-parse", "--show-toplevel"])
    .trim_end(chars="\r\n")
    .trim_end(chars="/")
  let prefix = "\{root}/\{WorktreesDirName}/"
  let output = @gitx.output(dir, ["worktree", "list", "--porcelain", "-z"])
  let states : Map[String, CheckoutState] = Map([])
  let mut current : String? = None
  for field in output.split("\u{0}") {
    if field is [.. "worktree ", .. path] {
      current = if path.has_prefix(prefix) {
        let name = path.view(start_offset=prefix.length()).to_owned()
        if valid_worktree_name(name) {
          Some(name)
        } else {
          None
        }
      } else {
        None
      }
      if current is Some(name) {
        states[name] = { head: None, lock_reason: None, }
      }
    } else if current is Some(name) && states.get(name) is Some(state) {
      if field is [.. "HEAD ", .. head] {
        states[name] = { ..state, head: Some(head.to_owned()), }
      } else if field is [.. "locked ", .. reason] {
        states[name] = { ..state, lock_reason: Some(reason.to_owned()), }
      }
    }
  }
  states
}

///|
async fn preserve_worktree_head(
  dir : @pathx.Absolute,
  entry : WorktreeEntry,
) -> Unit {
  guard entry.checkout is Detached(recovery_ref) else { return }
  let head = @gitx.run(worktree_dir(dir, entry.name), [
    "rev-parse", "--verify", "HEAD^{commit}",
  ])
  ignore(@gitx.run(dir, ["update-ref", "--no-deref", recovery_ref, head]))
}

///|
/// Git pruning is repository-wide. Save ALL managed detached HEADs first,
/// including those whose directories were removed by another tool. If saving
/// fails, leave the metadata intact. A JSON SHA alone would not prevent GC.
/// Callers hold worktree_registry_lock through the snapshot and the prune.
async fn prune_worktrees(dir : @pathx.Absolute) -> Unit {
  let states = checkout_states(dir)
  for entry in read_worktrees_unlocked(dir) {
    if entry.checkout is Detached(recovery_ref) &&
      states.get(entry.name) is Some({ head: Some(head), .. }) {
      ignore(@gitx.run(dir, ["update-ref", "--no-deref", recovery_ref, head]))
    }
  }
  ignore(@gitx.run(dir, ["worktree", "prune"]))
}

///|
fn WorktreeEntry::lock_prefix(self : WorktreeEntry) -> String {
  "openseek-provision:\{self.checkout.revision()}:"
}

///|
/// Publication may succeed just before cancellation or an unlock failure.
/// Replays finish only our own provisioning lock, never a user's lock.
async fn finish_worktree_creation(
  dir : @pathx.Absolute,
  entry : WorktreeEntry,
) -> Unit {
  if worktree_lock_reason(dir, entry.name) is Some(reason) &&
    reason.has_prefix(entry.lock_prefix()) {
    ignore(
      @gitx.run(dir, ["worktree", "unlock", "\{WorktreesDirName}/\{entry.name}"]),
    )
  }
}
