// Worktrees of a registered workspace: isolated checkouts under
// `<workspace>/.worktrees/<name>` where ONE conversation works on its own
// branch — a worktree is an execution environment, bound 1:1 to the
// conversation that chose it — while the durable record stays in the main
// repository's store. A worktree is never itself a workspace; this
// registry — `<workspace>/.openseek/worktrees.json`,
// desktop-owned — remembers each worktree's branch, base commit, and bound
// session. The worktree's path is always derived from its name, never
// stored.

///|
const WorktreesFile = "worktrees.json"

///|
const WorktreesDirName = ".worktrees"

///|
/// Prefix for desktop-created branches: keeps them recognizable and away
/// from user branch names.
const WorktreeBranchPrefix = "openseek/"

///|
/// Registry reads and read-modify-write mutations share one process-wide
/// lock, exactly like `workspaces.json` — without it two concurrent
/// create/remove operations could both read the same old list and let the
/// later write silently erase the earlier one.
let worktree_registry_lock : @async.Mutex = Mutex()

///|
priv struct WorktreeEntry {
  name : String
  branch : String
  base : String
  // The one conversation this worktree is the environment of, recorded at
  // creation. `None` only for a registry edited outside the app; such an
  // entry serves nobody and is cleaned up by removal.
  session : String?
} derive(ToJson)

///|
/// One worktree as ops report it: the registry entry plus its derived
/// checkout path and whether that directory still exists on disk.
type WorktreeInfo = @protocol.WorktreeInfo

///|
type WorktreesReply = @protocol.WorktreesReply

///|
/// A create's reply names the worktree it made — the client sends no name
/// and needs the generated one to start the bound conversation.
type WorktreeCreateReply = @protocol.WorktreeCreateReply

///|
fn worktrees_file(workspace : @pathx.Absolute) -> @pathx.Absolute {
  workspace_session_root(workspace).join(WorktreesFile)
}

///|
fn worktree_dir(workspace : @pathx.Absolute, name : String) -> @pathx.Absolute {
  workspace.join(WorktreesDirName).join(name).normalize()
}

///|
/// One path component and a branch-safe slug: an ASCII letter or digit
/// first, then letters, digits, `.`, `_`, or `-`, at most 64 characters.
/// The leading-alphanumeric rule also excludes `.`, `..`, and a leading `-`
/// (which git would parse as an option).
fn valid_worktree_name(name : String) -> Bool {
  guard name.length() >= 1 && name.length() <= 64 else { return false }
  let mut first = true
  for ch in name {
    let allowed = ch.is_ascii_alphabetic() ||
      ch.is_ascii_digit() ||
      (!first && (ch == '.' || ch == '_' || ch == '-'))
    guard allowed else { return false }
    first = false
  }
  true
}

///|
/// The registered worktrees of `workspace`, dropping anything malformed: an
/// entry without a valid name, branch, and base string self-heals to absent
/// rather than poisoning every later operation. A missing or unreadable
/// registry reads as "no worktrees".
async fn read_worktrees_unlocked(
  workspace : @pathx.Absolute,
) -> Array[WorktreeEntry] {
  let text = @fsx.try_read_text(worktrees_file(workspace).to_path()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return []
  }
  guard text is Some(text) else { return [] }
  let json = @json.parse(text) catch { _ => return [] }
  guard json is Object(fields) && fields.get("worktrees") is Some(Array(items)) else {
    return []
  }
  let entries : Array[WorktreeEntry] = []
  for item in items {
    guard item is Object(fields) else { continue }
    guard fields.get("name") is Some(String(name)) && valid_worktree_name(name) else {
      continue
    }
    if entries.iter().any(existing => existing.name == name) {
      continue
    }
    guard fields.get("branch") is Some(String(branch)) && !branch.is_empty() else {
      continue
    }
    guard fields.get("base") is Some(String(base)) else { continue }
    let session : String? = if fields.get("session") is Some(String(id)) &&
      !id.is_empty() {
      Some(id)
    } else {
      None
    }
    entries.push({ name, branch, base, session })
  }
  entries
}

///|
async fn write_worktrees(
  workspace : @pathx.Absolute,
  entries : Array[WorktreeEntry],
) -> Unit {
  let store = workspace_session_root(workspace)
  @fsx.ensure_dir(store.to_path()) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise EngineError("could not create \{store}: \{error}")
  }
  let registry : Json = { "worktrees": entries.to_json() }
  @fsx.write_text(
    worktrees_file(workspace).to_path(),
    registry.stringify(indent=2),
  ) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise EngineError("could not save the worktree list: \{error}")
  }
}

///|
async fn worktree_infos(
  workspace : @pathx.Absolute,
  entries : Array[WorktreeEntry],
) -> Array[WorktreeInfo] {
  let infos : Array[WorktreeInfo] = []
  for entry in entries {
    let path = worktree_dir(workspace, entry.name)
    let present = @fsx.is_dir(path.to_path()) catch {
      error if @async.is_being_cancelled() => raise error
      _ => false
    }
    infos.push({
      name: entry.name,
      branch: entry.branch,
      base: entry.base,
      session: entry.session,
      path: path.resource_path(),
      present,
    })
  }
  infos
}

///|
/// Where a conversation of `workspace` runs, as the registry sees it. The
/// third case is deliberately distinct from the first: the registry row is
/// the conversation's durable placement, so a missing checkout must never
/// silently turn that conversation into a workspace-root one. External
/// deletion and unarchiving a worktree conversation both land there.
priv enum SessionTree {
  /// No binding: the conversation runs in the workspace root.
  WorkspaceRoot
  /// Bound, and the checkout is there.
  BoundTree(@pathx.Absolute)
  /// Bound, but the checkout is gone.
  MissingTree(String)
}

///|
async fn session_tree(
  workspace : @pathx.Absolute,
  session : String,
) -> SessionTree {
  worktree_registry_lock.acquire()
  defer worktree_registry_lock.release()
  for entry in read_worktrees_unlocked(workspace) {
    guard entry.session is Some(bound) && bound == session else { continue }
    let dir = worktree_dir(workspace, entry.name)
    let present = @fsx.is_dir(dir.to_path()) catch {
      error if @async.is_being_cancelled() => raise error
      _ => false
    }
    return if present { BoundTree(dir) } else { MissingTree(entry.name) }
  }
  WorkspaceRoot
}

///|
/// The immutable commit a conversation's worktree branch was created from.
/// Workspace-root conversations have no desktop-owned task boundary and
/// therefore return `None`; their review surface may derive a branch boundary
/// separately. The registry owns the task fact, so callers never infer a
/// worktree base from mutable branch or remote configuration.
async fn session_tree_base(
  workspace : @pathx.Absolute,
  session : String,
) -> String? {
  worktree_registry_lock.acquire()
  defer worktree_registry_lock.release()
  for entry in read_worktrees_unlocked(workspace) {
    if entry.session is Some(bound) && bound == session {
      return Some(entry.base)
    }
  }
  None
}

///|
/// The directory session-scoped file, terminal, and language operations use.
/// `None` for a missing bound checkout: every tool must refuse that state, not
/// let one surface silently operate in the workspace root while the agent is
/// blocked.
async fn session_tree_dir(
  workspace : @pathx.Absolute,
  session : String,
) -> @pathx.Absolute? {
  match session_tree(workspace, session) {
    BoundTree(dir) => Some(dir)
    WorkspaceRoot => Some(workspace)
    MissingTree(_) => None
  }
}

///|
/// The run cwd for a conversation of `workspace`: like `session_tree_dir`,
/// except that a binding whose checkout disappeared is an error rather than
/// a silent move into the main checkout. The client turns this refusal into
/// the composer's recovery choices: rebuild the checkout or archive the
/// conversation.
async fn session_run_dir(
  workspace : @pathx.Absolute,
  session : String,
) -> @pathx.Absolute {
  match session_tree(workspace, session) {
    BoundTree(dir) => dir
    WorkspaceRoot => workspace
    MissingTree(name) =>
      raise EngineError(
        "worktree \{name} for this conversation is gone; rebuild it or archive the conversation",
      )
  }
}

///|
/// Remove the checkout bound to `session`, if any, while retaining its
/// registry entry. Archiving frees the directory, but the name/branch/session
/// row remains the durable placement needed to make a later unarchive read as
/// `MissingTree` and offer an explicit rebuild. Without `force` a dirty
/// checkout refuses (naming the worktree), which the client turns into its
/// discard-confirmation dialog; committed work stays on the branch either
/// way. The caller has already drained the session's engine (archive's slot
/// claim), so the checkout is free to go. A session without a worktree is a
/// no-op.
async fn archive_bound_worktree_checkout(
  session : String,
  force : Bool,
  on_committed? : (String, Array[WorktreeInfo]) -> Unit,
) -> ArchiveNeedsForceReply? {
  guard workspace_of_session(session) is Some(workspace) else { return None }
  worktree_registry_lock.acquire()
  defer worktree_registry_lock.release()
  let entries = read_worktrees_unlocked(workspace)
  let mut found : WorktreeEntry? = None
  for entry in entries {
    if entry.session is Some(bound) && bound == session {
      found = Some(entry)
      break
    }
  }
  guard found is Some(entry) else { return None }
  let target = worktree_dir(workspace, entry.name)
  let present = @fsx.is_dir(target.to_path()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => false
  }
  if present {
    if !force {
      let status = git_output_text(target, [
        "status", "--porcelain=v1", "-z", "--untracked-files=all",
      ])
      if !status.is_empty() {
        let (dirty_paths, dirty_path_count) = archive_dirty_path_preview(status)
        return Some({ worktree: entry.name, dirty_paths, dirty_path_count })
      }
    }
    delete_worktree_checkout(workspace, entry.name)
  } else {
    // The checkout is already gone; drop git's stale bookkeeping for it.
    ignore(git_probe(workspace, ["worktree", "prune"]))
  }
  // The checkout changed, not the placement. Publish the retained row with
  // `present: false` so every client blocks this conversation immediately;
  // the same row lets unarchive surface the existing Repair flow later.
  @async.protect_from_cancel(() => {
    if on_committed is Some(on_committed) {
      on_committed(
        workspace.resource_path(),
        worktree_infos(workspace, entries),
      )
    }
  })
  None
}

///|
/// The tree root an absolute in-workspace `path` belongs to: the registered
/// worktree containing it when one does, otherwise the workspace itself. A
/// `.worktrees` path with no registry entry (a subtask slice, say) keeps
/// resolving to the workspace root.
async fn worktree_owner_dir(
  workspace : @pathx.Absolute,
  path : @pathx.Absolute,
) -> @pathx.Absolute {
  worktree_registry_lock.acquire()
  defer worktree_registry_lock.release()
  for entry in read_worktrees_unlocked(workspace) {
    let dir = worktree_dir(workspace, entry.name)
    if dir.contains(path) {
      return dir
    }
  }
  workspace
}

///|
/// Run git in `dir` and return its stdout exactly. Porcelain `-z` callers need
/// the leading status-space and NUL separators intact; ordinary callers trim
/// this value in `git_in` below.
async fn git_output_text(dir : @pathx.Absolute, args : Array[String]) -> String {
  let (code, stdout, stderr) = @process.collect_output(
    "git",
    args,
    cwd=dir.to_string(),
    no_console_window=true,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise EngineError("failed to run git: \{error}")
  }
  guard code == 0 else {
    let detail = (stderr.text() catch { _ => "" }).trim().to_owned()
    raise EngineError(
      if detail.is_empty() {
        "git \{args.join(" ")} exited with code \{code}"
      } else {
        detail
      },
    )
  }
  stdout.text() catch {
    _ => raise EngineError("git produced non-text output")
  }
}

///|
/// Run git in `dir` and return its trimmed stdout; a failure raises with
/// git's own message so refusals ("branch already exists", a checkout
/// conflict) reach the user verbatim.
async fn git_in(dir : @pathx.Absolute, args : Array[String]) -> String {
  git_output_text(dir, args).trim().to_owned()
}

///|
const ArchiveDirtyPathPreviewLimit = 8

///|
/// Extract a bounded path preview from `git status --porcelain=v1 -z` while
/// retaining the full row count. In `-z` mode a rename/copy consumes the next
/// NUL field as its source; only the current path is useful in the archive
/// warning.
fn archive_dirty_path_preview(status : String) -> (Array[String], Int) {
  let fields = status.split("\u{0}").map(field => field.to_owned()).collect()
  let paths : Array[String] = []
  let mut count = 0
  let mut index = 0
  while index < fields.length() {
    let record = fields[index]
    if record.length() < 4 {
      index += 1
      continue
    }
    let index_status = record.view(end_offset=1).to_owned()
    let worktree_status = record.view(start_offset=1, end_offset=2).to_owned()
    let path = record.view(start_offset=3).to_owned()
    count += 1
    if paths.length() < ArchiveDirtyPathPreviewLimit {
      paths.push(path)
    }
    if index_status == "R" ||
      worktree_status == "R" ||
      index_status == "C" ||
      worktree_status == "C" {
      index += 1
    }
    index += 1
  }
  (paths, count)
}

///|
test "archive dirty preview includes submodules and counts renames once" {
  let status = " m desktop/lepus\u{0}R  renamed.mbt\u{0}old.mbt\u{0}?? loose.txt\u{0}"
  let (paths, count) = archive_dirty_path_preview(status)
  assert_eq(paths, ["desktop/lepus", "renamed.mbt", "loose.txt"])
  assert_eq(count, 3)
}

///|
/// Probe variant of `git_in`: `None` when git is unavailable or the command
/// fails, for questions where failure itself is the answer (is this a
/// repository? does this branch exist?).
async fn git_probe(dir : @pathx.Absolute, args : Array[String]) -> String? {
  let (code, stdout, _) = @process.collect_output(
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
async fn git_rollback(dir : @pathx.Absolute, args : Array[String]) -> Unit {
  let _ = @process.collect_output(
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
async fn git_dir_pair(dir : @pathx.Absolute) -> (String, String)? {
  guard git_probe(dir, [
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
async fn linked_git_worktree(dir : @pathx.Absolute) -> Bool {
  guard git_dir_pair(dir) is Some((git_dir, common_dir)) else { return false }
  git_dir != common_dir
}

///|
/// Creating a worktree needs the workspace to be a git repository's MAIN
/// checkout: chaining a worktree off a linked one roots it at a checkout
/// that can itself vanish. A workspace attached before the attach-time
/// linked-worktree guard existed may still be one, so the create path
/// re-checks.
async fn require_main_worktree(dir : @pathx.Absolute) -> Unit {
  guard git_dir_pair(dir) is Some((git_dir, common_dir)) else {
    raise EngineError("\{dir} is not a git repository (or git is unavailable)")
  }
  guard git_dir == common_dir else {
    raise EngineError(
      "\{dir} is a linked git worktree; create worktrees from the main checkout",
    )
  }
  // A repository SUBDIRECTORY stays attachable as a workspace, but cannot
  // host worktrees: `git worktree add` would drop a full-repository
  // checkout inside it — untracked noise in the main checkout (no `.git`
  // here to write an exclusion into) with a cwd at the checkout's root
  // rather than the attached subdirectory. `--show-prefix` is empty
  // exactly at the toplevel, with no path canonicalization to get wrong.
  match git_probe(dir, ["rev-parse", "--show-prefix"]) {
    Some("") => ()
    Some(_) =>
      raise EngineError(
        "\{dir} is a repository subdirectory; attach the repository root to use worktrees",
      )
    None =>
      raise EngineError(
        "\{dir} is not a git repository (or git is unavailable)",
      )
  }
}

///|
/// The worktrees of a registered workspace. Read-only: a worktree whose
/// directory was deleted outside the app reports `present: false` here and
/// is cleaned up by `remove_worktree`, never by listing.
pub async fn list_worktrees(workspace : String) -> WorktreesReply {
  guard @pathx.Absolute::from_uri_path(workspace) is Some(absolute) &&
    registered_workspace(absolute) is Some(dir) else {
    raise EngineError("\{workspace} is not a registered workspace")
  }
  worktree_registry_lock.acquire()
  defer worktree_registry_lock.release()
  { worktrees: worktree_infos(dir, read_worktrees_unlocked(dir)) }
}

///|
/// The smallest `wt-N` nobody holds: free in the registry, on disk, and as
/// a branch. Branches survive removal, so the counter naturally skips past
/// history instead of resurrecting an old branch.
async fn fresh_worktree_name(
  dir : @pathx.Absolute,
  entries : Array[WorktreeEntry],
) -> String {
  for n in 1..<=1000 {
    let name = "wt-\{n}"
    if entries.iter().any(entry => entry.name == name) {
      continue
    }
    let occupied = @fsx.exists(worktree_dir(dir, name).to_path()) catch {
      error if @async.is_being_cancelled() => raise error
      _ => false
    }
    if occupied {
      continue
    }
    if git_probe(dir, [
        "show-ref",
        "--verify",
        "--quiet",
        "refs/heads/\{WorktreeBranchPrefix}\{name}",
      ])
      is Some(_) {
      continue
    }
    return name
  }
  raise EngineError("no free worktree name below wt-1000; remove some first")
}

///|
/// Create a worktree `<workspace>/.worktrees/<name>` on a fresh branch
/// `openseek/<name>` at the workspace's current HEAD, bound from birth to
/// `session` — creation IS the binding, so the start path never mutates
/// the registry and a refused start cannot re-route a conversation. The
/// session is the idempotency key: a session that already holds a worktree
/// gets that binding back instead of a second checkout, which is what
/// makes a lost create reply safe to retry. The name is host-generated
/// (`wt-N`); the wire op takes none — `name?` exists for tests, which need
/// deterministic fixtures and keep the holder-naming refusals covered.
/// The whole op runs under `workspace_lifecycle_lock` (like removal), so
/// it serializes with workspace detachment and with binding starts; the
/// registry write and `on_committed` broadcast are one shielded commit,
/// the `add_workspace` pattern, with cancellation rolling the fresh
/// checkout back best-effort (it holds no user data yet).
pub async fn create_worktree(
  manager : EngineManager,
  workspace : String,
  session : String,
  on_committed : (Array[WorktreeInfo]) -> Unit,
  name? : String,
) -> WorktreeCreateReply {
  let session = session.trim().to_owned()
  guard safe_workspace_id(session) else {
    raise EngineError("a worktree binds to a conversation; session id invalid")
  }
  let explicit : String? = if name is Some(name) {
    let name = name.trim().to_owned()
    guard valid_worktree_name(name) else {
      raise EngineError(
        "worktree names start with a letter or digit and use only letters, digits, '.', '_', and '-' (at most 64 characters)",
      )
    }
    Some(name)
  } else {
    None
  }
  manager.workspace_lifecycle_lock.acquire()
  defer manager.workspace_lifecycle_lock.release()
  // Registration is checked under the lifecycle lock, which detachment also
  // holds: a workspace can no longer slip out of the registry between this
  // check and the registry commit below.
  guard @pathx.Absolute::from_uri_path(workspace) is Some(absolute) &&
    registered_workspace(absolute) is Some(dir) else {
    raise EngineError("\{workspace} is not a registered workspace")
  }
  require_main_worktree(dir)
  ensure_session_not_archived(session)
  // Snapshot this workspace's setting once for the lifecycle operation. A
  // concurrent page edit applies to the next create or repair instead of
  // changing this checkout halfway through.
  let workspace_settings = workspace_settings(dir.to_string())
  let checkout_submodules = workspace_settings.checkout_submodules
  worktree_registry_lock.acquire()
  defer worktree_registry_lock.release()
  let entries = read_worktrees_unlocked(dir)
  // This conversation already holds its environment. Two shapes land here:
  // the idempotent replay of a create whose reply was lost, and the repair
  // of a checkout deleted outside the app. The registry keeps the branch,
  // and the branch keeps every commit, so the repair restores the real
  // environment rather than an empty lookalike.
  for entry in entries {
    guard entry.session is Some(bound) && bound == session else { continue }
    let present = @fsx.is_dir(worktree_dir(dir, entry.name).to_path()) catch {
      error if @async.is_being_cancelled() => raise error
      _ => false
    }
    if present {
      // A replay can follow a repair cancelled after `git worktree add`
      // restored the checkout but before its notification ran. Republish the
      // complete host-derived list so that retry repairs every client's stale
      // `present: false` view instead of returning success invisibly.
      let infos = worktree_infos(dir, entries)
      @async.protect_from_cancel(() => on_committed(infos))
      return { name: entry.name, worktrees: infos }
    }
    // The repair: presence is what the clients render, so the restored
    // checkout is a registry commit like any other and broadcasts as one.
    restore_worktree_checkout(dir, entry, checkout_submodules~)
    let infos = worktree_infos(dir, entries)
    @async.protect_from_cancel(() => on_committed(infos))
    return { name: entry.name, worktrees: infos }
  }
  // Binding is for conversations that are genuinely NEW — everywhere, not
  // merely in this workspace. A durable record in any store, a binding in
  // any other workspace's registry, or an in-flight first turn (a live
  // slot whose record has not landed yet) would each fork the
  // conversation's durable routing later.
  if manager.pump is Serving(sessions~) && sessions.get(session) is Some(_) {
    raise EngineError(
      "this conversation is already starting; a worktree binds before its first prompt",
    )
  }
  let global_record : @pathx.Absolute? = resolved_session_root().map(root => {
    root.join("sessions").join(session)
  })
  let has_history = if workspace_of_session(session) is Some(_) {
    true
  } else if global_record is Some(record) {
    @fsx.is_dir(record.to_path()) catch {
      error if @async.is_being_cancelled() => raise error
      _ => false
    }
  } else {
    false
  }
  if has_history {
    raise EngineError(
      "this conversation already has history; a worktree binds a new one",
    )
  }
  for path in registered_workspaces() {
    guard path.0 != dir.to_string() else { continue }
    for entry in read_worktrees_unlocked(path) {
      if entry.session is Some(bound) && bound == session {
        raise EngineError(
          "this conversation already runs in worktree \{entry.name} of \{path.0}",
        )
      }
    }
  }
  let name = match explicit {
    Some(name) => name
    None => fresh_worktree_name(dir, entries)
  }
  // Refusals name the holder: the registry entry, the directory (a subtask
  // slice can own `.worktrees/<name>` without any registry entry), or the
  // branch.
  if entries.iter().any(entry => entry.name == name) {
    raise EngineError("worktree \{name} already exists in this workspace")
  }
  let target = worktree_dir(dir, name)
  let occupied = @fsx.exists(target.to_path()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => false
  }
  if occupied {
    raise EngineError(
      "\{target} already exists on disk; another tool may own it",
    )
  }
  let branch = WorktreeBranchPrefix + name
  if git_probe(dir, ["show-ref", "--verify", "--quiet", "refs/heads/\{branch}"])
    is Some(_) {
    raise EngineError(
      "branch \{branch} already exists; delete it or pick another name",
    )
  }
  exclude_from_git(dir, WorktreesDirName)
  let base = git_in(dir, ["rev-parse", "HEAD"])
  // The branch comes first, on its own: our locks are in-process only, so
  // another process can race the probes above — `git branch` then fails
  // atomically having created nothing, and from here on the branch is
  // provably THIS invocation's, which is what makes the rollback's
  // `branch -D` safe.
  ignore(git_in(dir, ["branch", branch, base]))
  try {
    ignore(
      git_in(dir, ["worktree", "add", "\{WorktreesDirName}/\{name}", branch]),
    )
    if checkout_submodules {
      provision_initialized_submodules(dir, target)
    }
  } catch {
    error => {
      @async.protect_from_cancel(() => rollback_worktree(dir, name, branch))
      raise error
    }
  }
  entries.push({ name, branch, base, session: Some(session) })
  let mut infos : Array[WorktreeInfo] = []
  @async.protect_from_cancel(() => {
    write_worktrees(dir, entries) catch {
      error => {
        rollback_worktree(dir, name, branch)
        raise error
      }
    }
    infos = worktree_infos(dir, entries)
    on_committed(infos)
  })
  { name, worktrees: infos }
}

///|
/// Rebuild a registered worktree's checkout on the branch it already owns,
/// after the directory was deleted outside the app. The stale bookkeeping
/// that deletion left behind would make `worktree add` refuse the path, so
/// it is pruned first — deliberately unguarded by `worktree_checked_out_on`,
/// since the whole premise here is that the checkout is gone. The branch is
/// never re-created: it survived the deletion and carries the conversation's
/// commits, which is what makes this a repair rather than a fresh start.
async fn restore_worktree_checkout(
  dir : @pathx.Absolute,
  entry : WorktreeEntry,
  checkout_submodules~ : Bool,
) -> Unit {
  guard git_probe(dir, [
      "show-ref",
      "--verify",
      "--quiet",
      "refs/heads/\{entry.branch}",
    ])
    is Some(_) else {
    raise EngineError(
      "branch \{entry.branch} is gone too; this worktree cannot be restored",
    )
  }
  ignore(git_probe(dir, ["worktree", "prune"]))
  exclude_from_git(dir, WorktreesDirName)
  let target = worktree_dir(dir, entry.name)
  try {
    ignore(
      git_in(dir, [
        "worktree",
        "add",
        "\{WorktreesDirName}/\{entry.name}",
        entry.branch,
      ]),
    )
    if checkout_submodules {
      provision_initialized_submodules(dir, target)
    }
  } catch {
    error => {
      @async.protect_from_cancel(() => {
        rollback_worktree_checkout(dir, entry.name, entry.branch)
      })
      raise error
    }
  }
}

///|
/// Best-effort removal of an app-created checkout while preserving its branch.
/// Deliberately not `git worktree remove --force`: rollback must only delete
/// what THIS invocation provably created, and Git's validation does not
/// check the branch — `worktree_checked_out_on` does, leaving a path another
/// process claimed in the race window alone. Unforced removal is no
/// alternative either: it refuses any tree containing a gitlink.
async fn rollback_worktree_checkout(
  dir : @pathx.Absolute,
  name : String,
  branch : String,
) -> Unit {
  if worktree_checked_out_on(dir, name, branch) &&
    worktree_lock_reason(dir, name) is None {
    @fs.rmdir(worktree_dir(dir, name).to_string(), recursive=true) catch {
      _ => ()
    }
  }
  git_rollback(dir, ["worktree", "prune"])
}

///|
/// Best-effort removal of a half-created worktree, deleting only what this
/// invocation provably created: the branch was made first on its own, so
/// `branch -D` is always ours to run, while the checkout is force-removed
/// only when git's own bookkeeping shows the target path checked out on
/// that branch — a path another process claimed in the race window is left
/// alone. Only ever runs inside a cancellation shield while the original
/// failure propagates.
async fn rollback_worktree(
  dir : @pathx.Absolute,
  name : String,
  branch : String,
) -> Unit {
  rollback_worktree_checkout(dir, name, branch)
  git_rollback(dir, ["branch", "-D", branch])
}

///|
/// Whether `git worktree list` shows a checkout at `.worktrees/<name>` on
/// `branch`. Matched by path suffix — git prints canonicalized absolute
/// paths (`/private/var` for a `/var` workspace, say), so a literal
/// comparison against our derived path would misfire.
async fn worktree_checked_out_on(
  dir : @pathx.Absolute,
  name : String,
  branch : String,
) -> Bool {
  guard git_probe(dir, ["worktree", "list", "--porcelain"]) is Some(output) else {
    return false
  }
  let suffix = "/\{WorktreesDirName}/\{name}"
  let mut at_target = false
  for line in output.split("\n") {
    let line = line.trim().to_owned()
    if line.has_prefix("worktree ") {
      at_target = line.has_suffix(suffix)
    } else if at_target && line == "branch refs/heads/\{branch}" {
      return true
    }
  }
  false
}

///|
/// An external `git worktree lock` must remain authoritative even on the
/// gitlink cleanup path, where Git cannot perform the removal itself.
async fn worktree_lock_reason(dir : @pathx.Absolute, name : String) -> String? {
  guard git_probe(dir, ["worktree", "list", "--porcelain"]) is Some(output) else {
    return None
  }
  let suffix = "/\{WorktreesDirName}/\{name}"
  let mut at_target = false
  for line in output.split("\n") {
    let line = line.trim().to_owned()
    if line.has_prefix("worktree ") {
      at_target = line.has_suffix(suffix)
    } else if at_target && line == "locked" {
      return Some("")
    } else if at_target && line.has_prefix("locked ") {
      return Some(line.view(start_offset="locked ".length()).to_owned())
    }
  }
  None
}

///|
/// Delete a registered worktree's checkout with `git worktree remove
/// --force` — always forced, because plain `worktree remove` refuses ANY
/// checkout containing a submodule gitlink, initialized or not, even a
/// perfectly clean one. The caller's porcelain dirty check (and its
/// discard-confirmation dialog) is the one cleanliness policy; Git's own
/// would add nothing but the gitlink refusal. Everything else worth
/// enforcing, Git still enforces under a single `--force`: it validates
/// that the path really is this repository's linked worktree (a directory
/// re-occupied by some other repository fails validation and survives),
/// refuses an externally locked worktree (that takes a second `--force`,
/// never passed here), and cleans up the checkout's admin directory —
/// submodule clones under it included, Git's native `--force` semantics.
async fn delete_worktree_checkout(
  workspace : @pathx.Absolute,
  name : String,
) -> Unit {
  ignore(
    git_in(workspace, [
      "worktree",
      "remove",
      "--force",
      "\{WorktreesDirName}/\{name}",
    ]),
  )
}

///|
/// Remove a worktree's checkout and registry entry. The branch
/// `openseek/<name>` always survives — committed work is never lost by
/// deleting a worktree; uncommitted changes are, and only behind `force`.
/// The bound conversation is drained first (an idle serve process still
/// has its cwd inside the directory being deleted); it then becomes a
/// plain workspace conversation with its history intact. A registry entry
/// whose directory is already gone is pruned — the self-heal for a
/// worktree deleted outside the app.
pub async fn remove_worktree(
  manager : EngineManager,
  workspace : String,
  name : String,
  force : Bool,
  on_committed : (Array[WorktreeInfo]) -> Unit,
) -> WorktreesReply {
  let name = name.trim().to_owned()
  // The lifecycle lock excludes concurrent creates and workspace
  // detachments for the whole removal — the registration check below runs
  // under it, so a detach that wins the lock cannot leave this op deleting
  // a checkout from an already-detached workspace.
  manager.workspace_lifecycle_lock.acquire()
  defer manager.workspace_lifecycle_lock.release()
  guard @pathx.Absolute::from_uri_path(workspace) is Some(absolute) &&
    registered_workspace(absolute) is Some(dir) else {
    raise EngineError("\{workspace} is not a registered workspace")
  }
  let entry = {
    worktree_registry_lock.acquire()
    defer worktree_registry_lock.release()
    let entries = read_worktrees_unlocked(dir)
    let mut found : WorktreeEntry? = None
    for entry in entries {
      if entry.name == name {
        found = Some(entry)
        break
      }
    }
    found
  }
  guard entry is Some(entry) else {
    raise EngineError("no worktree named \{name} in this workspace")
  }
  if entry.session is Some(bound) {
    manager.close_engines_for_sessions([bound])
  }
  let target = worktree_dir(dir, name)
  let present = @fsx.is_dir(target.to_path()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => false
  }
  if present {
    if !force {
      let status = git_in(target, ["status", "--porcelain"])
      guard status.is_empty() else {
        raise EngineError(
          "worktree \{name} has uncommitted changes; force removal discards them",
        )
      }
    }
    delete_worktree_checkout(dir, name)
  } else {
    // The checkout is already gone; drop git's stale bookkeeping for it.
    ignore(git_probe(dir, ["worktree", "prune"]))
  }
  worktree_registry_lock.acquire()
  defer worktree_registry_lock.release()
  // Re-read: another worktree may have been created while the checkout was
  // being removed (creation takes only the registry lock).
  let remaining = read_worktrees_unlocked(dir).filter(entry => {
    entry.name != name
  })
  let mut infos : Array[WorktreeInfo] = []
  @async.protect_from_cancel(() => {
    write_worktrees(dir, remaining)
    infos = worktree_infos(dir, remaining)
    on_committed(infos)
  })
  { worktrees: infos }
}

// Tests. The lifecycle tests exercise the real git binary (like the CLI's
// subtask lifecycle tests); the environment-dependent ones serialize on
// `archive_env_test_lock` because they redirect OPENSEEK_SESSION_ROOT.

///|
/// A fixture root in the tmpdir's physical spelling. The workspace registry
/// canonicalizes what it stores, so a fixture built from the symlinked
/// spelling (`/tmp` on macOS) would compare unequal to every path the
/// registry hands back.
async fn worktree_test_root(prefix : String) -> @pathx.Absolute {
  @pathx.Path(@fs.realpath(@fs.tmpdir(prefix~))).resolve()
}

///|
test "worktree names are one branch-safe path component" {
  assert_true(valid_worktree_name("fix-auth"))
  assert_true(valid_worktree_name("a.b_c-d"))
  assert_true(valid_worktree_name("A0"))
  assert_true(valid_worktree_name("x".repeat(64)))
  assert_false(valid_worktree_name(""))
  assert_false(valid_worktree_name("."))
  assert_false(valid_worktree_name(".."))
  assert_false(valid_worktree_name("-x"))
  assert_false(valid_worktree_name(".hidden"))
  assert_false(valid_worktree_name("a/b"))
  assert_false(valid_worktree_name("a\\b"))
  assert_false(valid_worktree_name("a b"))
  assert_false(valid_worktree_name("名字"))
  assert_false(valid_worktree_name("x".repeat(65)))
}

///|
async test "worktree registry decode drops malformed entries" {
  let root = worktree_test_root("openseek-worktree-decode-")
  @fsx.ensure_dir(workspace_session_root(root).to_path())
  @fsx.write_text(worktrees_file(root).to_path(), "{ not json")
  assert_eq(read_worktrees_unlocked(root).length(), 0)
  let registry : Json = {
    "worktrees": [
      { "name": "ok", "branch": "openseek/ok", "base": "abc", "session": "s1" },
      {
        "name": "blank",
        "branch": "openseek/blank",
        "base": "y",
        "session": "",
      },
      { "name": "bad/slash", "branch": "x", "base": "y" },
      { "name": "nobranch", "base": "y" },
      { "name": "ok", "branch": "dup", "base": "y" },
      "not-an-object",
    ],
  }
  @fsx.write_text(worktrees_file(root).to_path(), registry.stringify())
  let entries = read_worktrees_unlocked(root)
  assert_eq(entries.length(), 2)
  assert_eq(entries[0].name, "ok")
  assert_eq(entries[0].branch, "openseek/ok")
  assert_eq(entries[0].base, "abc")
  assert_eq(entries[0].session, Some("s1"))
  // A blank session self-heals to unbound rather than a phantom id.
  assert_eq(entries[1].name, "blank")
  assert_true(entries[1].session is None)
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "session workspace dir follows the worktree mapping while it exists" {
  archive_env_test_lock.acquire()
  defer archive_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  let root = worktree_test_root("openseek-worktree-seam-")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", root.join("global").to_string())
  defer restore_session_root_env(previous)
  let ws = root.join("ws")
  @fsx.ensure_dir(ws.join(".openseek/sessions/s-wt").to_path())
  @fsx.ensure_dir(ws.join(".openseek/sessions/s-plain").to_path())
  ignore(add_workspace(ws.to_string(), fn(_) {  }))
  write_worktrees(ws, [
    { name: "wt", branch: "openseek/wt", base: "abc", session: Some("s-wt") },
  ])
  @fsx.ensure_dir(ws.join(".worktrees/wt").to_path())
  assert_eq(
    session_workspace_dir("s-wt").map(dir => dir.to_string()),
    Some(ws.join(".worktrees/wt").to_string()),
  )
  assert_eq(
    session_workspace_dir("s-plain").map(dir => dir.to_string()),
    Some(ws.to_string()),
  )
  // The workspace hint refines to the worktree too — the FS bridge sends the
  // hint on every op.
  assert_eq(
    resolve_in_workspace("s-wt", "src", workspace=ws.to_string()).map(dir => {
      dir.to_string()
    }),
    Some(ws.join(".worktrees/wt/src").to_string()),
  )
  // Deleting the checkout retains the binding but removes the usable root:
  // every session-scoped operation refuses until Repair recreates it.
  @fs.rmdir(ws.join(".worktrees/wt").to_string(), recursive=true)
  assert_true(session_workspace_dir("s-wt") is None)
  assert_true(
    resolve_in_workspace("s-wt", "", workspace=ws.to_string()) is None,
  )
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "attached workspace dir resolves registered worktree paths" {
  archive_env_test_lock.acquire()
  defer archive_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  let root = worktree_test_root("openseek-worktree-attached-")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", root.join("global").to_string())
  defer restore_session_root_env(previous)
  let ws = root.join("ws")
  @fsx.ensure_dir(ws.to_path())
  ignore(add_workspace(ws.to_string(), fn(_) {  }))
  write_worktrees(ws, [
    { name: "wt", branch: "openseek/wt", base: "abc", session: None },
  ])
  @fsx.ensure_dir(ws.join(".worktrees/wt/src").to_path())
  @fsx.ensure_dir(ws.join(".worktrees/stray").to_path())
  @fsx.ensure_dir(ws.join("src").to_path())
  @fs.write_file(
    ws.join("src/main.mbt").to_string(),
    b"main",
    create_mode=CreateOrTruncate,
  )
  let worktree_file = ws.join(".worktrees/wt/src/main.mbt")
  let stray_file = ws.join(".worktrees/stray/x.mbt")
  let workspace_file = ws.join("src/lib.mbt")
  guard @pathx.Path("\{ws}/.worktrees/wt/../../src/main.mbt").to_absolute()
    is Some(dot_segment_file) else {
    fail("expected absolute worktree fixtures")
  }
  // A registered worktree path answers from the worktree root.
  assert_eq(
    attached_workspace_dir(worktree_file).map(dir => dir.to_string()),
    Some(ws.join(".worktrees/wt").to_string()),
  )
  // An unregistered `.worktrees` path (a subtask slice) and a main-tree path
  // keep resolving to the workspace root.
  assert_eq(
    attached_workspace_dir(stray_file).map(dir => dir.to_string()),
    Some(ws.to_string()),
  )
  assert_eq(
    attached_workspace_dir(workspace_file).map(dir => dir.to_string()),
    Some(ws.to_string()),
  )
  // Dot segments are cleaned before choosing the deepest owning tree. Although
  // its spelling enters a registered worktree, this file physically belongs to
  // the main workspace after `../..` is resolved.
  assert_eq(
    attached_workspace_dir(dot_segment_file).map(dir => dir.to_string()),
    Some(ws.to_string()),
  )
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "a bound session routes every start through its checkout" {
  archive_env_test_lock.acquire()
  defer archive_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  let root = worktree_test_root("openseek-worktree-route-")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", root.join("global").to_string())
  defer restore_session_root_env(previous)
  let ws = root.join("ws")
  @fsx.ensure_dir(ws.join(".worktrees/wt").to_path())
  ignore(add_workspace(ws.to_string(), fn(_) {  }))
  // Creation is the binding; the start path only READS the registry.
  write_worktrees(ws, [
    { name: "wt", branch: "openseek/wt", base: "abc", session: Some("s-bind") },
  ])
  let manager = new_engine_manager("openseek")
  let first = run_config(manager, {
    task: "go",
    submission_id: None,
    model: None,
    max_steps: None,
    session: "s-bind",
    workspace: Some(ws.to_string()),
  })
  assert_eq(
    first.cwd.map(dir => dir.to_string()),
    Some(ws.join(".worktrees/wt").to_string()),
  )
  // The durable record stays in the MAIN repository's store.
  assert_eq(
    first.session_root.map(dir => dir.to_string()),
    Some(ws.join(".openseek").to_string()),
  )
  // A hint-less resume goes through the durable record and the mapping.
  @fsx.ensure_dir(ws.join(".openseek/sessions/s-bind").to_path())
  let resumed = run_config(manager, {
    task: "resume",
    submission_id: None,
    model: None,
    max_steps: None,
    session: "s-bind",
    workspace: None,
  })
  assert_eq(
    resumed.cwd.map(dir => dir.to_string()),
    Some(ws.join(".worktrees/wt").to_string()),
  )
  assert_eq(
    resumed.session_root.map(dir => dir.to_string()),
    Some(ws.join(".openseek").to_string()),
  )
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "worktree remove refuses a running conversation without unmapping it" {
  archive_env_test_lock.acquire()
  defer archive_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  let root = worktree_test_root("openseek-worktree-busy-")
  let engine = root.join("bin/engine.sh")
  let runtime = root.join("runtime")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", root.join("global").to_string())
  defer restore_session_root_env(previous)
  let ws = root.join("ws")
  @fsx.ensure_dir(ws.join(".worktrees/wt").to_path())
  prepare_fake_moonbit_seed(
    root.join("bin/toolchains/moonbit/macos-arm64").to_path(),
    version="0.10.0-test",
  )
  prepare_fake_bundled_moonbit_home(
    runtime.join("toolchains/moonbit/macos-arm64").to_path(),
    version="0.10.0-test",
  )
  @fs.write_file(
    engine.to_string(),
    "#!/bin/sh\nif [ \"$1\" = \"sessions\" ]; then printf '%s' '{\"events\":[]}' ; exit 0; fi\nwhile IFS= read -r line; do sleep 30; done\n",
    create_mode=CreateOrTruncate,
  )
  assert_eq(@process.run("chmod", ["+x", engine.to_string()]), 0)
  let actor = new_engine_actor(
    engine.to_string(),
    runtime_dir=runtime.to_path(),
  )
  let manager = actor.manager()
  ignore(
    update_settings(manager, {
      provider: Some("custom"),
      custom_api_url: Some("https://example.invalid/chat/completions"),
      deepseek_api_key: None,
      custom_api_key: None,
    }),
  )
  let sink = EventSink(fn(_) {  })
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      actor.run(sink, fn(_) {  })
    })
    while manager.pump is Stopped {
      @async.sleep(1)
    }
    ignore(add_workspace(ws.to_string(), fn(_) {  }))
    write_worktrees(ws, [
      {
        name: "wt",
        branch: "openseek/wt",
        base: "abc",
        session: Some("s-wt-run"),
      },
    ])
    let reply = start_run(sink, manager, {
      task: "keep running",
      submission_id: None,
      model: None,
      max_steps: None,
      session: "s-wt-run",
      workspace: Some(ws.to_string()),
    })
    assert_eq(reply.status, "accepted")
    let committed : Ref[Bool] = Ref(false)
    let detail = try {
      ignore(
        remove_worktree(manager, ws.to_string(), "wt", false, fn(_) {
          committed.val = true
        }),
      )
      "no error"
    } catch {
      EngineError(detail) => detail
      error if @async.is_being_cancelled() => raise error
      error => "\{error}"
    }
    assert_true(detail.contains("still running"))
    assert_false(committed.val)
    assert_true(@fsx.is_dir(ws.join(".worktrees/wt").to_path()))
    guard list_worktrees(ws.to_string()).worktrees is [info] else {
      fail("expected the worktree to stay registered")
    }
    assert_eq(info.session, Some("s-wt-run"))
    group.return_immediately(())
  })
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
#cfg(not(platform="windows"))
async fn prepare_git_repo(dir : @pathx.Absolute) -> Unit {
  @fsx.ensure_dir(dir.to_path())
  ignore(git_in(dir, ["init", "-q"]))
  ignore(
    git_in(dir, [
      "-c", "user.email=test@example.com", "-c", "user.name=test", "-c", "commit.gpgsign=false",
      "commit", "--allow-empty", "-q", "-m", "init",
    ]),
  )
}

///|
#cfg(not(platform="windows"))
async test "attach refuses a linked worktree, keeps main and non-git attachable" {
  archive_env_test_lock.acquire()
  defer archive_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  let root = worktree_test_root("openseek-worktree-attach-")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", root.join("global").to_string())
  defer restore_session_root_env(previous)
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(
    git_in(repo, ["worktree", "add", "-q", root.join("linked").to_string()]),
  )
  let detail = try {
    ignore(add_workspace(root.join("linked").to_string(), fn(_) {  }))
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(detail.contains("linked git worktree"))
  // The main checkout, one of its subdirectories, and a plain directory all
  // stay attachable — in particular the guard must not misfire on paths whose
  // `.git` is elsewhere for other reasons.
  assert_true(add_workspace(repo.to_string(), fn(_) {  }).contains(repo))
  let sub = repo.join("sub")
  @fsx.ensure_dir(sub.to_path())
  assert_true(add_workspace(sub.to_string(), fn(_) {  }).contains(sub))
  let plain = root.join("plain")
  @fsx.ensure_dir(plain.to_path())
  assert_true(add_workspace(plain.to_string(), fn(_) {  }).contains(plain))
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "worktree create provisions checkout, branch, registry, exclusion" {
  archive_env_test_lock.acquire()
  defer archive_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  let root = worktree_test_root("openseek-worktree-create-")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", root.join("global").to_string())
  defer restore_session_root_env(previous)
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(add_workspace(repo.to_string(), fn(_) {  }))
  let manager = new_engine_manager("openseek")
  let committed : Ref[Int] = Ref(-1)
  let reply = create_worktree(
    manager,
    repo.to_string(),
    "s-fix-auth",
    infos => committed.val = infos.length(),
    name="fix-auth",
  )
  assert_eq(committed.val, 1)
  assert_eq(reply.name, "fix-auth")
  guard reply.worktrees is [info] else { fail("expected one worktree") }
  assert_eq(info.name, "fix-auth")
  assert_eq(info.branch, "openseek/fix-auth")
  assert_eq(info.base, git_in(repo, ["rev-parse", "HEAD"]))
  // Creation IS the binding: the entry carries its conversation from birth.
  assert_eq(info.session, Some("s-fix-auth"))
  assert_eq(
    session_review_base("s-fix-auth", workspace=repo.to_string()),
    Some(info.base),
  )
  assert_eq(
    session_review_base("workspace-root", workspace=repo.to_string()),
    None,
  )
  assert_eq(info.path, repo.join(".worktrees/fix-auth").to_string())
  assert_true(info.present)
  assert_true(@fsx.is_dir(repo.join(".worktrees/fix-auth").to_path()))
  assert_true(
    git_probe(repo, [
      "show-ref", "--verify", "--quiet", "refs/heads/openseek/fix-auth",
    ])
    is Some(_),
  )
  // The new checkout sits on its own branch at the recorded base.
  assert_eq(
    git_in(repo.join(".worktrees/fix-auth"), [
      "rev-parse", "--abbrev-ref", "HEAD",
    ]),
    "openseek/fix-auth",
  )
  let exclude = @fsx.read_text(repo.join(".git/info/exclude").to_path())
  assert_true(exclude.contains(".worktrees/"))
  assert_true(exclude.contains(".openseek/"))
  guard list_worktrees(repo.to_string()).worktrees is [listed] else {
    fail("expected one listed worktree")
  }
  assert_eq(listed.name, "fix-auth")
  assert_true(listed.present)
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "a checkout deleted outside the app refuses runs and is repairable" {
  archive_env_test_lock.acquire()
  defer archive_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  let root = worktree_test_root("openseek-worktree-vanished-")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", root.join("global").to_string())
  defer restore_session_root_env(previous)
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(add_workspace(repo.to_string(), fn(_) {  }))
  let manager = new_engine_manager("openseek")
  let created = create_worktree(
    manager,
    repo.to_string(),
    "s-vanish",
    fn(_) {  },
    name="wt",
  )
  let checkout = repo.join(".worktrees/wt")
  // A commit on the worktree's branch stands in for the conversation's
  // work: the repair must bring it back, not just an empty directory.
  @fsx.write_text(checkout.join("kept.txt").to_path(), "committed work")
  ignore(git_in(checkout, ["add", "kept.txt"]))
  ignore(
    git_in(checkout, [
      "-c", "user.email=test@example.com", "-c", "user.name=test", "-c", "commit.gpgsign=false",
      "commit", "-q", "-m", "work",
    ]),
  )
  // Someone deletes the checkout outside the app; the registry row survives,
  // which is what distinguishes this from our own removal.
  @fs.rmdir(checkout.to_string(), recursive=true)
  // The durable record is how a hint-less resume recovers its registered
  // workspace after an app restart.
  @fsx.ensure_dir(
    workspace_session_root(repo).join("sessions").join("s-vanish").to_path(),
  )
  guard list_worktrees(repo.to_string()).worktrees is [gone] else {
    fail("the registry row must survive an external deletion")
  }
  assert_false(gone.present)
  assert_eq(gone.session, Some("s-vanish"))
  // Every session-scoped surface refuses rather than silently moving into the
  // main checkout: file/terminal resolution returns no root, and a run names
  // the missing worktree.
  assert_true(session_tree_dir(repo, "s-vanish") is None)
  assert_true(session_workspace_dir("s-vanish") is None)
  assert_true(session_cwd("s-vanish") is None)
  assert_true(
    resolve_in_workspace("s-vanish", "", workspace=repo.to_string()) is None,
  )
  let refusal = try {
    ignore(session_run_dir(repo, "s-vanish"))
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(refusal.contains("wt") && refusal.contains("gone"))
  let hinted_refusal = try {
    ignore(
      run_config(manager, {
        task: "continue",
        submission_id: None,
        model: None,
        max_steps: None,
        session: "s-vanish",
        workspace: Some(repo.to_string()),
      }),
    )
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(hinted_refusal.contains("wt") && hinted_refusal.contains("gone"))
  let resumed_refusal = try {
    ignore(
      run_config(manager, {
        task: "resume",
        submission_id: None,
        model: None,
        max_steps: None,
        session: "s-vanish",
        workspace: None,
      }),
    )
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(
    resumed_refusal.contains("wt") && resumed_refusal.contains("gone"),
  )
  // Recreating repairs the SAME environment: same name, same branch, and the
  // branch's commit is back in the working tree.
  let repaired = create_worktree(manager, repo.to_string(), "s-vanish", fn(_) {

  })
  assert_eq(repaired.name, created.name)
  assert_true(@fsx.is_dir(checkout.to_path()))
  assert_eq(
    @fsx.read_text(checkout.join("kept.txt").to_path()),
    "committed work",
  )
  assert_eq(
    git_in(checkout, ["rev-parse", "--abbrev-ref", "HEAD"]),
    "openseek/wt",
  )
  assert_eq(session_run_dir(repo, "s-vanish").to_string(), checkout.to_string())
  // If the first repair's request was cancelled after restoring the checkout
  // but before broadcasting, its idempotent retry must publish the complete
  // host-derived list so clients leave MissingWorktree.
  let replayed : Array[WorktreeInfo] = []
  let replay = create_worktree(manager, repo.to_string(), "s-vanish", infos => {
    for info in infos {
      replayed.push(info)
    }
  })
  assert_eq(replay.name, repaired.name)
  guard replayed is [replayed_info] else {
    fail("repair replay did not publish its worktree list")
  }
  assert_eq(replayed_info.name, repaired.name)
  assert_eq(replayed_info.session, Some("s-vanish"))
  assert_true(replayed_info.present)
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "explicit registry removal can prune a vanished worktree" {
  archive_env_test_lock.acquire()
  defer archive_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  let root = worktree_test_root("openseek-worktree-release-")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", root.join("global").to_string())
  defer restore_session_root_env(previous)
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(add_workspace(repo.to_string(), fn(_) {  }))
  let manager = new_engine_manager("openseek")
  ignore(
    create_worktree(
      manager,
      repo.to_string(),
      "s-release",
      fn(_) {  },
      name="wt",
    ),
  )
  @fs.rmdir(repo.join(".worktrees/wt").to_string(), recursive=true)
  // The low-level protocol operation remains available for orphan cleanup.
  // The bundled UI does not expose it for a conversation; Archive retains the
  // row so a later Unarchive still requires explicit Repair.
  let reply = remove_worktree(manager, repo.to_string(), "wt", false, fn(_) {  })
  assert_eq(reply.worktrees.length(), 0)
  // Unbound, the conversation runs in the workspace again — no refusal.
  assert_eq(session_run_dir(repo, "s-release").to_string(), repo.to_string())
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "worktree names are host-generated and skip surviving branches" {
  archive_env_test_lock.acquire()
  defer archive_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  let root = worktree_test_root("openseek-worktree-autoname-")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", root.join("global").to_string())
  defer restore_session_root_env(previous)
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(add_workspace(repo.to_string(), fn(_) {  }))
  let manager = new_engine_manager("openseek")
  let first = create_worktree(manager, repo.to_string(), "s-1", fn(_) {  })
  assert_eq(first.name, "wt-1")
  // The session is the idempotency key: a replay (a retry after a lost
  // reply) gets the existing binding back, never a second checkout.
  let replay = create_worktree(manager, repo.to_string(), "s-1", fn(_) {  })
  assert_eq(replay.name, "wt-1")
  assert_eq(replay.worktrees.length(), 1)
  let second = create_worktree(manager, repo.to_string(), "s-2", fn(_) {  })
  assert_eq(second.name, "wt-2")
  // Removal keeps the branch, so a fresh name never resurrects wt-1: the
  // counter moves past every holder, branches included.
  ignore(remove_worktree(manager, repo.to_string(), "wt-1", false, fn(_) {  }))
  let third = create_worktree(manager, repo.to_string(), "s-3", fn(_) {  })
  assert_eq(third.name, "wt-3")
  guard list_worktrees(repo.to_string()).worktrees is [a, b] else {
    fail("expected two registered worktrees")
  }
  assert_eq(a.name, "wt-2")
  assert_eq(b.name, "wt-3")
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
#cfg(not(platform="windows"))
async fn create_refusal(
  manager : EngineManager,
  workspace : String,
  session : String,
  name : String,
) -> String {
  try {
    ignore(create_worktree(manager, workspace, session, fn(_) {  }, name~))
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
}

///|
#cfg(not(platform="windows"))
async test "worktree create names the holder in every refusal" {
  archive_env_test_lock.acquire()
  defer archive_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  let root = worktree_test_root("openseek-worktree-refuse-")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", root.join("global").to_string())
  defer restore_session_root_env(previous)
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(add_workspace(repo.to_string(), fn(_) {  }))
  let manager = new_engine_manager("openseek")
  assert_true(
    create_refusal(manager, root.join("unregistered").to_string(), "s", "x").contains(
      "not a registered workspace",
    ),
  )
  assert_true(
    create_refusal(manager, repo.to_string(), "s", "-x").contains(
      "worktree names",
    ),
  )
  assert_true(
    create_refusal(manager, repo.to_string(), "a/b", "x").contains(
      "session id invalid",
    ),
  )
  // Binding is for new conversations: one with durable history keeps the
  // tree it grew up in.
  @fsx.ensure_dir(
    workspace_session_root(repo).join("sessions").join("s-old").to_path(),
  )
  assert_true(
    create_refusal(manager, repo.to_string(), "s-old", "x").contains(
      "already has history",
    ),
  )
  // The session must be new EVERYWHERE: history in the global store, a
  // binding in another workspace's registry, and an in-flight first turn
  // all refuse — any of them would fork the conversation's routing.
  @fsx.ensure_dir(root.join("global/sessions/s-global").to_path())
  assert_true(
    create_refusal(manager, repo.to_string(), "s-global", "x").contains(
      "already has history",
    ),
  )
  let elsewhere = root.join("elsewhere")
  @fsx.ensure_dir(elsewhere.to_path())
  ignore(add_workspace(elsewhere.to_string(), fn(_) {  }))
  write_worktrees(elsewhere, [
    {
      name: "wt-e",
      branch: "openseek/wt-e",
      base: "abc",
      session: Some("s-elsewhere"),
    },
  ])
  assert_true(
    create_refusal(manager, repo.to_string(), "s-elsewhere", "x").contains(
      "already runs in worktree wt-e",
    ),
  )
  manager.pump = Serving(sessions=Map([]))
  guard manager.pump is Serving(sessions~) else { fail("pump not serving") }
  ignore(slot_for(sessions, "s-live"))
  assert_true(
    create_refusal(manager, repo.to_string(), "s-live", "x").contains(
      "already starting",
    ),
  )
  ignore(
    create_worktree(manager, repo.to_string(), "s-dup", fn(_) {  }, name="dup"),
  )
  assert_true(
    create_refusal(manager, repo.to_string(), "s-2", "dup").contains(
      "already exists",
    ),
  )
  @fsx.ensure_dir(repo.join(".worktrees/held").to_path())
  assert_true(
    create_refusal(manager, repo.to_string(), "s-3", "held").contains(
      "already exists on disk",
    ),
  )
  ignore(git_in(repo, ["branch", "openseek/task"]))
  assert_true(
    create_refusal(manager, repo.to_string(), "s-4", "task").contains(
      "branch openseek/task already exists",
    ),
  )
  // A workspace that is not a git repository cannot host worktrees; a linked
  // worktree registered before the attach guard existed is refused too.
  let plain = root.join("plain")
  @fsx.ensure_dir(plain.to_path())
  ignore(add_workspace(plain.to_string(), fn(_) {  }))
  assert_true(
    create_refusal(manager, plain.to_string(), "s", "x").contains(
      "not a git repository",
    ),
  )
  // A repository SUBDIRECTORY stays attachable but cannot host worktrees:
  // the checkout would land inside it as untracked noise at the wrong depth.
  let sub = repo.join("sub")
  @fsx.ensure_dir(sub.to_path())
  ignore(add_workspace(sub.to_string(), fn(_) {  }))
  assert_true(
    create_refusal(manager, sub.to_string(), "s-sub", "x").contains(
      "repository subdirectory",
    ),
  )
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "archive keeps worktree placement for explicit repair after unarchive" {
  archive_env_test_lock.acquire()
  defer archive_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  let root = worktree_test_root("openseek-worktree-archive-")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", root.join("global").to_string())
  defer restore_session_root_env(previous)
  @fsx.ensure_dir(root.join("global").to_path())
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(add_workspace(repo.to_string(), fn(_) {  }))
  let manager = new_engine_manager("openseek")
  manager.pump = Serving(sessions=Map([]))
  ignore(create_worktree(manager, repo.to_string(), "s-arc", fn(_) {  }))
  // The first turn has landed: the durable record now exists in the
  // workspace store (create's has-history refusal applies only before the
  // binding, so this is the normal begun-conversation shape).
  @fsx.ensure_dir(
    workspace_session_root(repo).join("sessions").join("s-arc").to_path(),
  )
  @fs.write_file(
    repo.join(".worktrees/wt-1/junk.txt").to_string(),
    b"x",
    create_mode=CreateOrTruncate,
  )
  // A dirty checkout returns a structured confirmation state before anything
  // irreversible: the record stays live and the checkout stays on disk.
  guard archive_session(manager, "s-arc", _ => ()) is NeedsForce(refusal) else {
    fail("dirty archive returned no force confirmation")
  }
  assert_eq(refusal.worktree, "wt-1")
  assert_eq(refusal.dirty_paths, ["junk.txt"])
  assert_eq(refusal.dirty_path_count, 1)
  assert_true(
    @fsx.is_dir(
      workspace_session_root(repo).join("sessions").join("s-arc").to_path(),
    ),
  )
  assert_true(@fsx.is_dir(repo.join(".worktrees/wt-1").to_path()))
  // The confirmed dialog retries with force: the checkout goes away, while
  // the branch, archived history, and placement row all survive. The retained
  // row broadcasts as missing before the conversation is archived.
  let changes : Array[(String, Array[WorktreeInfo])] = []
  guard archive_session(manager, "s-arc", _ => (), force=true, on_worktree_changed=(
      workspace,
      rows,
    ) => changes.push((workspace, rows)))
    is Archived(_) else {
    fail("forced archive did not commit")
  }
  assert_eq(changes.length(), 1)
  let (workspace, rows) = changes[0]
  assert_eq(workspace, repo.to_string())
  guard rows is [archived_worktree] else {
    fail("archive must retain one missing worktree placement")
  }
  assert_eq(archived_worktree.session, Some("s-arc"))
  assert_false(archived_worktree.present)
  assert_false(@fsx.exists(repo.join(".worktrees/wt-1").to_path()))
  assert_true(
    git_probe(repo, [
      "show-ref", "--verify", "--quiet", "refs/heads/openseek/wt-1",
    ])
    is Some(_),
  )
  assert_true(
    @fsx.is_dir(
      archived_session_root(workspace_session_root(repo))
      .join("sessions")
      .join("s-arc")
      .to_path(),
    ),
  )
  guard list_worktrees(repo.to_string()).worktrees is [retained] else {
    fail("archived worktree placement was not retained")
  }
  assert_eq(retained.session, Some("s-arc"))
  assert_false(retained.present)
  // Unarchive restores only the durable conversation. The retained placement
  // keeps every workspace surface blocked until the user explicitly repairs.
  ignore(unarchive_session(manager, "s-arc", _ => ()))
  assert_true(
    @fsx.is_dir(
      workspace_session_root(repo).join("sessions").join("s-arc").to_path(),
    ),
  )
  assert_true(session_tree_dir(repo, "s-arc") is None)
  assert_true(
    resolve_in_workspace("s-arc", "", workspace=repo.to_string()) is None,
  )
  let repaired = create_worktree(manager, repo.to_string(), "s-arc", fn(_) {  })
  assert_eq(repaired.name, "wt-1")
  assert_true(@fsx.is_dir(repo.join(".worktrees/wt-1").to_path()))
  // A clean bound worktree archives in one go, no force needed.
  ignore(create_worktree(manager, repo.to_string(), "s-arc2", fn(_) {  }))
  @fsx.ensure_dir(
    workspace_session_root(repo).join("sessions").join("s-arc2").to_path(),
  )
  assert_true(archive_session(manager, "s-arc2", _ => ()) is Archived(_))
  assert_false(@fsx.exists(repo.join(".worktrees/wt-2").to_path()))
  guard list_worktrees(repo.to_string()).worktrees is [first, second] else {
    fail("both worktree placements must survive archive")
  }
  assert_true(first.present)
  assert_false(second.present)
  assert_eq(second.session, Some("s-arc2"))
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
#cfg(not(platform="windows"))
async fn remove_refusal(
  manager : EngineManager,
  workspace : String,
  name : String,
  force : Bool,
) -> String {
  try {
    ignore(remove_worktree(manager, workspace, name, force, fn(_) {  }))
    "no error"
  } catch {
    EngineError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
}

///|
#cfg(not(platform="windows"))
async test "worktree remove enforces the dirty check and keeps the branch" {
  archive_env_test_lock.acquire()
  defer archive_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  let root = worktree_test_root("openseek-worktree-remove-")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", root.join("global").to_string())
  defer restore_session_root_env(previous)
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(add_workspace(repo.to_string(), fn(_) {  }))
  let manager = new_engine_manager("openseek")
  assert_true(
    remove_refusal(manager, repo.to_string(), "nope", false).contains(
      "no worktree named",
    ),
  )
  ignore(
    create_worktree(manager, repo.to_string(), "s-w1", fn(_) {  }, name="w1"),
  )
  @fs.write_file(
    repo.join(".worktrees/w1/junk.txt").to_string(),
    b"x",
    create_mode=CreateOrTruncate,
  )
  assert_true(
    remove_refusal(manager, repo.to_string(), "w1", false).contains(
      "uncommitted changes",
    ),
  )
  assert_eq(list_worktrees(repo.to_string()).worktrees.length(), 1)
  let committed : Ref[Int] = Ref(-1)
  let forced = remove_worktree(manager, repo.to_string(), "w1", true, infos => {
    committed.val = infos.length()
  })
  assert_eq(committed.val, 0)
  assert_eq(forced.worktrees.length(), 0)
  assert_false(@fsx.exists(repo.join(".worktrees/w1").to_path()))
  // Committed work is never lost: the branch survives every removal.
  assert_true(
    git_probe(repo, [
      "show-ref", "--verify", "--quiet", "refs/heads/openseek/w1",
    ])
    is Some(_),
  )
  ignore(
    create_worktree(manager, repo.to_string(), "s-w2", fn(_) {  }, name="w2"),
  )
  ignore(remove_worktree(manager, repo.to_string(), "w2", false, fn(_) {  }))
  assert_eq(list_worktrees(repo.to_string()).worktrees.length(), 0)
  assert_true(
    git_probe(repo, [
      "show-ref", "--verify", "--quiet", "refs/heads/openseek/w2",
    ])
    is Some(_),
  )
  @fs.rmdir(root.to_string(), recursive=true)
}

///|
#cfg(not(platform="windows"))
async test "worktree remove prunes an externally deleted checkout" {
  archive_env_test_lock.acquire()
  defer archive_env_test_lock.release()
  let previous = @sys.get_env_var("OPENSEEK_SESSION_ROOT")
  let root = worktree_test_root("openseek-worktree-prune-")
  @sys.set_env_var("OPENSEEK_SESSION_ROOT", root.join("global").to_string())
  defer restore_session_root_env(previous)
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(add_workspace(repo.to_string(), fn(_) {  }))
  let manager = new_engine_manager("openseek")
  ignore(
    create_worktree(
      manager,
      repo.to_string(),
      "s-gone",
      fn(_) {  },
      name="gone",
    ),
  )
  @fs.rmdir(repo.join(".worktrees/gone").to_string(), recursive=true)
  guard list_worktrees(repo.to_string()).worktrees is [listed] else {
    fail("expected the deleted worktree to stay listed")
  }
  assert_false(listed.present)
  ignore(remove_worktree(manager, repo.to_string(), "gone", false, fn(_) {  }))
  assert_eq(list_worktrees(repo.to_string()).worktrees.length(), 0)
  assert_false(
    git_in(repo, ["worktree", "list", "--porcelain"]).contains(
      ".worktrees/gone",
    ),
  )
  @fs.rmdir(root.to_string(), recursive=true)
}
