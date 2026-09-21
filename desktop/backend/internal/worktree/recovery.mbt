// Detached worktrees keep their commits reachable through private Git refs.
// The original base remains immutable; the recovery ref tracks the last HEAD
// saved by OpenSeek at creation or before removing an existing checkout.
// Repair never advances it from externally modified worktree metadata.

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
  lock_reason : String?
}

///|
/// NUL-delimited porcelain preserves spaces, newlines and non-ASCII paths.
/// Match Git's resolved paths even when `.worktrees` is a symlink.
async fn checkout_states(dir : @pathx.Absolute) -> Map[String, CheckoutState] {
  let root = @gitx.output(dir, ["rev-parse", "--show-toplevel"])
    .trim_end(chars="\r\n")
    .trim_end(chars="/")
  let managed_root = "\{root}/\{WorktreesDirName}"
  let managed_root = @pathx.Path(@fs.realpath(managed_root))
    .resolve()
    .normalize()
    .to_string() catch {
      // Keep stale registrations discoverable if the whole directory was deleted.
      @os_error.OSError(_) as error if error.is_ENOENT() => managed_root
      error => raise error
    }
  let prefix = managed_root.trim_end(chars="/").to_owned() + "/"
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
        states[name] = { lock_reason: None, }
      }
    } else if current is Some(name) {
      if field is [.. "locked ", .. reason] {
        states[name] = { lock_reason: Some(reason.to_owned()), }
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
/// Forget only this missing checkout's registration. The saved reference is
/// authoritative even if external commits remain in Git's administrative files.
/// An external prune may already have removed the registration; that is a no-op.
async fn remove_missing_checkout(dir : @pathx.Absolute, name : String) -> Unit {
  guard !@fsx.exists(worktree_dir(dir, name).to_path()) else {
    raise WorktreeError("worktree \{name} already exists on disk")
  }
  if checkout_states(dir).get(name) is Some(_) {
    delete_worktree_checkout(dir, name)
  }
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
