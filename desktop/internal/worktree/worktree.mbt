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
/// Debug is what the host boundary logs: proton renders a failed handler's
/// error through `Repr`, which prints only an opaque `<...: ...>` placeholder
/// for types without it — swallowing the one string that says what failed.
pub suberror WorktreeError {
  WorktreeError(String)
} derive(Debug)

///|
impl Show for WorktreeError with fn output(self, logger) {
  match self {
    WorktreeError(message) => logger.write_string(message)
  }
}

///|
/// What a worktree lifecycle operation needs from the engine host, which owns
/// none of this package's state and cannot be reached from here.
///
/// `lifecycle_lock` is the host's placement lock — workspace detachment holds
/// it too, so taking it for the whole operation is what keeps a workspace from
/// slipping out of the registry mid-create. `session_is_live` answers whether a
/// conversation already has a slot in the running pump (binding is only for
/// conversations that are new everywhere), and `drain_sessions` closes the
/// engines of conversations whose checkout is about to be deleted — an idle
/// serve process still has its cwd inside that directory.
pub(all) struct WorktreeHost {
  lifecycle_lock : @async.Mutex
  session_is_live : (String) -> Bool
  drain_sessions : async (Array[String]) -> Unit
}

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
  // Old registries and OpenSeek conversations use `session`; Codex-owned
  // worktrees use `codex_thread`. A valid app-created row has exactly one.
  // Both absent is tolerated for a registry edited outside the app; such a
  // row serves nobody and is cleaned up only by explicit removal.
  session : String?
  codex_thread : String?
}

///|
/// Persist only concrete owner fields. Registry reads deliberately accept
/// missing owner fields for hand-edited legacy rows, so writing `null` would
/// introduce a second representation for the same ownerless state.
impl ToJson for WorktreeEntry with fn to_json(self) {
  let fields : Map[String, Json] = {
    "name": Json(self.name),
    "branch": Json(self.branch),
    "base": Json(self.base),
  }
  if self.session is Some(session) {
    fields["session"] = Json(session)
  }
  if self.codex_thread is Some(thread_id) {
    fields["codex_thread"] = Json(thread_id)
  }
  Json(fields)
}

///|
/// The durable conversation identity that owns one Desktop worktree. Keeping
/// the two namespaces distinct prevents a Codex UUID from entering OpenSeek's
/// session-store, engine-drain, archive, or history checks merely because both
/// products happen to call their durable identity a conversation id.
enum WorktreeOwner {
  OpenSeekSession(String)
  CodexThread(String)
} derive(Debug, Eq)

///|
pub fn WorktreeOwner::openseek(session : String) -> WorktreeOwner {
  OpenSeekSession(session.trim().to_owned())
}

///|
pub fn WorktreeOwner::codex(thread_id : String) -> WorktreeOwner {
  CodexThread(thread_id.trim().to_owned())
}

///|
fn WorktreeOwner::id(self : WorktreeOwner) -> String {
  match self {
    OpenSeekSession(id) | CodexThread(id) => id
  }
}

///|
fn WorktreeOwner::session(self : WorktreeOwner) -> String? {
  match self {
    OpenSeekSession(id) => Some(id)
    CodexThread(_) => None
  }
}

///|
fn WorktreeOwner::codex_thread(self : WorktreeOwner) -> String? {
  match self {
    OpenSeekSession(_) => None
    CodexThread(id) => Some(id)
  }
}

///|
fn WorktreeEntry::belongs_to(
  self : WorktreeEntry,
  owner : WorktreeOwner,
) -> Bool {
  match owner {
    OpenSeekSession(id) => self.session == Some(id)
    CodexThread(id) => self.codex_thread == Some(id)
  }
}

///|
/// Files, Terminal, and language requests carry the owning conversation id.
/// The two products store that id in distinct registry fields, but checkout
/// resolution must recognize either field without merging their lifecycles.
fn WorktreeEntry::serves_id(self : WorktreeEntry, id : String) -> Bool {
  self.session == Some(id) || self.codex_thread == Some(id)
}

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
/// Archiving a conversation whose checkout still holds uncommitted work asks
/// the user to confirm before the checkout goes away.
type ArchiveNeedsForceReply = @protocol.ArchiveNeedsForceReply

///|
/// One Codex thread's Desktop-owned placement. The API uses this snapshot to
/// annotate app-server thread replies; it never infers ownership from a cwd,
/// so worktrees created by Codex App or another Git client remain external.
pub struct CodexWorktreeBinding {
  thread_id : String
  workspace : String
  worktree : WorktreeInfo
} derive(Debug, Eq)

///|
fn worktrees_file(workspace : @pathx.Absolute) -> @pathx.Absolute {
  @workspaces.store_root(workspace).join(WorktreesFile)
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
    let codex_thread : String? = if fields.get("codex_thread")
      is Some(String(id)) &&
      !id.is_empty() {
      Some(id)
    } else {
      None
    }
    // A row cannot be owned by both products. Drop a malformed ambiguous row
    // instead of letting whichever lookup happens first claim its checkout.
    guard session is None || codex_thread is None else { continue }
    entries.push({ name, branch, base, session, codex_thread, })
  }
  entries
}

///|
async fn write_worktrees(
  workspace : @pathx.Absolute,
  entries : Array[WorktreeEntry],
) -> Unit {
  let store = @workspaces.store_root(workspace)
  @fsx.ensure_dir(store.to_path()) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise WorktreeError("could not create \{store}: \{error}")
  }
  let registry : Json = { "worktrees": entries.to_json() }
  let target = worktrees_file(workspace)
  let temp = store.join(WorktreesFile + ".tmp")
  // A registry update may remove only one conversation's placement while
  // retaining every unrelated row. Build the whole replacement beside the
  // live file first: a failed or cancelled write then leaves the old registry
  // intact instead of truncating it and orphaning all of those other rows.
  @fs.write_file(
    temp.to_string(),
    registry.stringify(indent=2),
    create_mode=CreateOrTruncate,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise WorktreeError("could not stage the worktree list: \{error}")
  }
  // `rename` replaces a present destination as one filesystem operation. A
  // cancellation cannot interrupt this short publication step, so callers
  // learn whether the complete old or complete new registry is authoritative.
  @async.protect_from_cancel(() => {
    @fs.rename(temp.to_string(), target.to_string()) catch {
      error => raise WorktreeError("could not save the worktree list: \{error}")
    }
  })
}

///|
/// A host-native absolute path at the protocol boundary. Resource URIs use
/// their authority for the device, so UNC paths have no reversible encoding
/// and are rejected explicitly instead of being published under a new host.
fn resource_path(path : @pathx.Absolute) -> String raise WorktreeError {
  guard path.to_uri_path() is Some(uri) else {
    raise WorktreeError("UNC paths are not supported by frontend resources")
  }
  uri
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
      codex_thread: entry.codex_thread,
      path: resource_path(path),
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
async fn tree_of(workspace : @pathx.Absolute, session : String) -> SessionTree {
  worktree_registry_lock.acquire()
  defer worktree_registry_lock.release()
  for entry in read_worktrees_unlocked(workspace) {
    guard entry.serves_id(session) else { continue }
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
pub async fn tree_base(
  workspace : @pathx.Absolute,
  session : String,
) -> String? {
  worktree_registry_lock.acquire()
  defer worktree_registry_lock.release()
  for entry in read_worktrees_unlocked(workspace) {
    if entry.serves_id(session) {
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
pub async fn tree_dir(
  workspace : @pathx.Absolute,
  session : String,
) -> @pathx.Absolute? {
  match tree_of(workspace, session) {
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
pub async fn run_dir(
  workspace : @pathx.Absolute,
  session : String,
) -> @pathx.Absolute {
  match tree_of(workspace, session) {
    BoundTree(dir) => dir
    WorkspaceRoot => workspace
    MissingTree(name) =>
      raise WorktreeError(
        "worktree \{name} for this conversation is gone; rebuild it or archive the conversation",
      )
  }
}

///|
/// Find this owner's registry row while `worktree_registry_lock` is held.
/// OpenSeek can start from its durable session store; Codex deliberately scans
/// only Desktop registries, never app-server or Git path conventions.
async fn WorktreeOwner::binding_unlocked(
  self : WorktreeOwner,
) -> (@pathx.Absolute, WorktreeEntry)? {
  let workspaces = match self {
    OpenSeekSession(session) =>
      match @session_store.workspace_of(session) {
        Some(workspace) => [workspace]
        None => []
      }
    CodexThread(_) => @workspaces.registered()
  }
  for workspace in workspaces {
    for entry in read_worktrees_unlocked(workspace) {
      if entry.belongs_to(self) {
        return Some((workspace, entry))
      }
    }
  }
  None
}

///|
/// Inspect whether archiving would discard uncommitted, untracked, or ignored
/// checkout files. This preflight changes nothing; the final removal repeats
/// the check after the backend writer has been archived, closing the race
/// between confirmation and deletion.
pub async fn WorktreeOwner::archive_check(
  self : WorktreeOwner,
) -> ArchiveNeedsForceReply? {
  worktree_registry_lock.acquire()
  defer worktree_registry_lock.release()
  guard self.binding_unlocked() is Some((workspace, entry)) else { return None }
  let target = worktree_dir(workspace, entry.name)
  let present = @fsx.is_dir(target.to_path()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => false
  }
  guard present else { return None }
  let status = @gitx.output(target, [
    "status", "--porcelain=v1", "-z", "--untracked-files=all",
  ])
  if status.is_empty() {
    None
  } else {
    let (dirty_paths, dirty_path_count) = archive_dirty_path_preview(status)
    Some({ worktree: entry.name, dirty_paths, dirty_path_count, })
  }
}

///|
/// Remove the checkout bound to this owner while retaining its registry row.
/// Archiving frees the directory, but the name, branch, and owner remain the
/// durable placement needed for an explicit rebuild. Without `force` a dirty
/// checkout refuses; committed work stays on the branch either way. The caller
/// must first fence its own backend writer (OpenSeek's slot claim or a
/// successful Codex `thread/archive`). An owner without a worktree is a no-op.
pub async fn WorktreeOwner::archive_checkout(
  self : WorktreeOwner,
  force : Bool,
  on_committed? : (String, Array[WorktreeInfo]) -> Unit,
) -> ArchiveNeedsForceReply? {
  worktree_registry_lock.acquire()
  defer worktree_registry_lock.release()
  guard self.binding_unlocked() is Some((workspace, entry)) else { return None }
  let entries = read_worktrees_unlocked(workspace)
  let target = worktree_dir(workspace, entry.name)
  let present = @fsx.is_dir(target.to_path()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => false
  }
  if present {
    if !force {
      let status = @gitx.output(target, [
        "status", "--porcelain=v1", "-z", "--untracked-files=all",
      ])
      if !status.is_empty() {
        let (dirty_paths, dirty_path_count) = archive_dirty_path_preview(status)
        return Some({ worktree: entry.name, dirty_paths, dirty_path_count, })
      }
    }
    delete_worktree_checkout(workspace, entry.name)
  } else {
    // The checkout is already gone; drop git's stale bookkeeping for it.
    ignore(@gitx.probe(workspace, ["worktree", "prune"]))
  }
  // The checkout changed, not the placement. Publish the retained row with
  // `present: false` so every client blocks this conversation immediately;
  // the same row lets unarchive surface the existing Repair flow later.
  @async.protect_from_cancel(() => {
    if on_committed is Some(on_committed) {
      on_committed(resource_path(workspace), worktree_infos(workspace, entries))
    }
  })
  None
}

///|
/// Drop the placement rows bound to `sessions` from one project's registry and
/// report the remaining rows, or `None` when the registry already held none of
/// them. The registry write is atomic, so a failure leaves every row in place
/// for the caller to roll its own work back against.
///
/// This is what permanent deletion of an archived conversation needs: the
/// checkout itself went away when the conversation was archived, and removing
/// the retained row is what lets the branch survive without an unusable ghost
/// placement.
pub async fn drop_placements(
  workspace : @pathx.Absolute,
  sessions : Array[String],
) -> Array[WorktreeInfo]? {
  worktree_registry_lock.acquire()
  defer worktree_registry_lock.release()
  let entries = read_worktrees_unlocked(workspace)
  let remaining = entries.filter(entry => {
    !(entry.session is Some(bound) && sessions.contains(bound))
  })
  guard remaining.length() < entries.length() else { return None }
  write_worktrees(workspace, remaining)
  Some(worktree_infos(workspace, remaining))
}

///|
/// The tree root an absolute in-workspace `path` belongs to: the registered
/// worktree containing it when one does, otherwise the workspace itself. A
/// `.worktrees` path with no registry entry (a subtask slice, say) keeps
/// resolving to the workspace root.
pub async fn owner_dir(
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
/// Creating a worktree needs the workspace to be a git repository's MAIN
/// checkout: chaining a worktree off a linked one roots it at a checkout
/// that can itself vanish. A workspace attached before the attach-time
/// linked-worktree guard existed may still be one, so the create path
/// re-checks.
async fn require_main_worktree(dir : @pathx.Absolute) -> Unit {
  guard @gitx.dir_pair(dir) is Some((git_dir, common_dir)) else {
    raise WorktreeError(
      "\{dir} is not a git repository (or git is unavailable)",
    )
  }
  guard git_dir == common_dir else {
    raise WorktreeError(
      "\{dir} is a linked git worktree; create worktrees from the main checkout",
    )
  }
  // A repository SUBDIRECTORY stays attachable as a workspace, but cannot
  // host worktrees: `git worktree add` would drop a full-repository
  // checkout inside it — untracked noise in the main checkout (no `.git`
  // here to write an exclusion into) with a cwd at the checkout's root
  // rather than the attached subdirectory. `--show-prefix` is empty
  // exactly at the toplevel, with no path canonicalization to get wrong.
  match @gitx.probe(dir, ["rev-parse", "--show-prefix"]) {
    Some("") => ()
    Some(_) =>
      raise WorktreeError(
        "\{dir} is a repository subdirectory; attach the repository root to use worktrees",
      )
    None =>
      raise WorktreeError(
        "\{dir} is not a git repository (or git is unavailable)",
      )
  }
}

///|
/// The worktrees of a registered workspace. Read-only: a worktree whose
/// directory was deleted outside the app reports `present: false` here and
/// is cleaned up by `remove_worktree`, never by listing.
pub async fn list(workspace : String) -> WorktreesReply {
  guard @pathx.Absolute::from_uri_path(workspace) is Some(absolute) &&
    @workspaces.registered_dir(absolute) is Some(dir) else {
    raise WorktreeError("\{workspace} is not a registered workspace")
  }
  worktree_registry_lock.acquire()
  defer worktree_registry_lock.release()
  { worktrees: worktree_infos(dir, read_worktrees_unlocked(dir)), }
}

///|
/// Snapshot every worktree explicitly created for a Codex thread. Registry
/// ownership, rather than a path convention, is authoritative; this is also
/// why deleted checkouts remain discoverable for an eventual rebuild.
pub async fn list_codex_worktree_bindings() -> Array[CodexWorktreeBinding] {
  worktree_registry_lock.acquire()
  defer worktree_registry_lock.release()
  let bindings : Array[CodexWorktreeBinding] = []
  for workspace in @workspaces.registered() {
    let entries = read_worktrees_unlocked(workspace)
    let infos = worktree_infos(workspace, entries)
    for info in infos {
      if info.codex_thread is Some(thread_id) {
        bindings.push({
          thread_id,
          workspace: resource_path(workspace),
          worktree: info,
        })
      }
    }
  }
  bindings
}

///|
/// The smallest `wt-N` nobody holds: free in the registry, on disk, and as
/// a branch. Branches survive removal, so the counter moves past history
/// instead of pairing a reused name with a lookalike of an old branch.
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
    // Salted branches survive removal as `openseek/<name>-<salt>`, and
    // branches minted before salting as the bare `openseek/<name>`, so a
    // name's history is the exact ref plus the prefix match.
    if @gitx.probe(dir, [
        "for-each-ref",
        "--format=%(refname)",
        "refs/heads/\{WorktreeBranchPrefix}\{name}",
        "refs/heads/\{WorktreeBranchPrefix}\{name}-*",
      ])
      is Some(listing) &&
      !listing.is_empty() {
      continue
    }
    return name
  }
  raise WorktreeError("no free worktree name below wt-1000; remove some first")
}

///|
/// Create a worktree `<workspace>/.worktrees/<name>` on a fresh salted
/// branch `openseek/<name>-<salt>` at the workspace's current HEAD, bound
/// from birth to `owner` — creation IS the binding, so the start path never
/// mutates the registry and a refused start cannot re-route a conversation.
/// The owner id is the idempotency key: an owner that already holds a
/// worktree gets that binding back instead of a second checkout, which is
/// what makes a lost create reply safe to retry. The name is host-generated
/// (`wt-N`); the wire op takes none — `name?` exists for tests, which need
/// deterministic fixtures and keep the holder-naming refusals covered.
/// The whole op runs under `workspace_lifecycle_lock` (like removal), so
/// it serializes with workspace detachment and with binding starts; the
/// registry write and `on_committed` broadcast are one shielded commit,
/// the `add_workspace` pattern, with cancellation rolling the fresh
/// checkout back best-effort (it holds no user data yet).
pub async fn create(
  host : WorktreeHost,
  workspace : String,
  owner : WorktreeOwner,
  on_committed : (Array[WorktreeInfo]) -> Unit,
  name? : String,
) -> WorktreeCreateReply {
  let owner_id = owner.id()
  guard @session_store.safe_session_id(owner_id) else {
    let detail = match owner {
      OpenSeekSession(_) =>
        "a worktree binds to a conversation; session id invalid"
      CodexThread(_) => "a worktree binds to a conversation; thread id invalid"
    }
    raise WorktreeError(detail)
  }
  let explicit : String? = if name is Some(name) {
    let name = name.trim().to_owned()
    guard valid_worktree_name(name) else {
      raise WorktreeError(
        "worktree names start with a letter or digit and use only letters, digits, '.', '_', and '-' (at most 64 characters)",
      )
    }
    Some(name)
  } else {
    None
  }
  host.lifecycle_lock.acquire()
  defer host.lifecycle_lock.release()
  // Registration is checked under the lifecycle lock, which detachment also
  // holds: a workspace can no longer slip out of the registry between this
  // check and the registry commit below.
  guard @pathx.Absolute::from_uri_path(workspace) is Some(absolute) &&
    @workspaces.registered_dir(absolute) is Some(dir) else {
    raise WorktreeError("\{workspace} is not a registered workspace")
  }
  require_main_worktree(dir)
  if owner is OpenSeekSession(session) {
    @session_store.ensure_not_archived(session)
  }
  // Snapshot this workspace's setting once for the lifecycle operation. A
  // concurrent page edit applies to the next create or repair instead of
  // changing this checkout halfway through.
  let workspace_settings = @workspaces.settings(dir.to_string())
  let checkout_submodules = workspace_settings.checkout_submodules
  let submodule_checkout_timeout_seconds = workspace_settings.submodule_checkout_timeout_seconds
  worktree_registry_lock.acquire()
  defer worktree_registry_lock.release()
  let entries = read_worktrees_unlocked(dir)
  // This conversation already holds its environment. Two shapes land here:
  // the idempotent replay of a create whose reply was lost, and the repair
  // of a checkout deleted outside the app. The registry keeps the branch,
  // and the branch keeps every commit, so the repair restores the real
  // environment rather than an empty lookalike.
  for entry in entries {
    guard entry.belongs_to(owner) else { continue }
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
      return { name: entry.name, worktrees: infos, }
    }
    // The repair: presence is what the clients render, so the restored
    // checkout is a registry commit like any other and broadcasts as one.
    restore_worktree_checkout(
      dir,
      entry,
      checkout_submodules~,
      submodule_checkout_timeout_seconds~,
    )
    let infos = worktree_infos(dir, entries)
    @async.protect_from_cancel(() => on_committed(infos))
    return { name: entry.name, worktrees: infos, }
  }
  // OpenSeek owns its session store and in-flight engine slots, so it can
  // prove that placement is chosen before any durable history. Codex owns its
  // thread store in app-server; its thread already exists here, and the caller
  // chooses placement before the first `turn/start` instead.
  if owner is OpenSeekSession(session) {
    if (host.session_is_live)(session) {
      raise WorktreeError(
        "this conversation is already starting; a worktree binds before its first prompt",
      )
    }
    let global_record : @pathx.Absolute? = @workspaces.global_store_root().map(root => {
      root.join("sessions").join(session)
    })
    let has_history = if @session_store.workspace_of(session) is Some(_) {
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
      raise WorktreeError(
        "this conversation already has history; a worktree binds a new one",
      )
    }
  }
  for path in @workspaces.registered() {
    guard path.0 != dir.to_string() else { continue }
    for entry in read_worktrees_unlocked(path) {
      if entry.belongs_to(owner) {
        raise WorktreeError(
          "this conversation already runs in worktree \{entry.name} of \{path.0}",
        )
      }
    }
  }
  let name = match explicit {
    Some(name) => name
    None => fresh_worktree_name(dir, entries)
  }
  // Refusals name the holder: the registry entry or the directory (a subtask
  // slice can own `.worktrees/<name>` without any registry entry). The branch
  // is freshly salted, so nothing can hold it ahead of us.
  if entries.iter().any(entry => entry.name == name) {
    raise WorktreeError("worktree \{name} already exists in this workspace")
  }
  let target = worktree_dir(dir, name)
  let occupied = @fsx.exists(target.to_path()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => false
  }
  if occupied {
    raise WorktreeError(
      "\{target} already exists on disk; another tool may own it",
    )
  }
  // Salted so that two machines' independent `wt-N` counters can never mint
  // the same branch name and collide on a shared remote; 32 bits is plenty
  // for that, and anything longer only clutters the branch chip and
  // pull-request heads. No OS entropy is a hard failure, never weak
  // randomness.
  guard @entropy.random_hex(4) is Some(salt) else {
    raise WorktreeError("no OS entropy available to mint a worktree branch")
  }
  let branch = "\{WorktreeBranchPrefix}\{name}-\{salt}"
  @workspaces.exclude_from_git(dir, WorktreesDirName)
  let base = @gitx.run(dir, ["rev-parse", "HEAD"])
  // The branch comes first, on its own: our locks are in-process only, so
  // another process can race the probes above — `git branch` then fails
  // atomically having created nothing, and from here on the branch is
  // provably THIS invocation's, which is what makes the rollback's
  // `branch -D` safe.
  ignore(@gitx.run(dir, ["branch", branch, base]))
  {
    errdefer @async.protect_from_cancel(() => {
      rollback_worktree(dir, name, branch)
    })
    ignore(
      @gitx.run(dir, ["worktree", "add", "\{WorktreesDirName}/\{name}", branch]),
    )
    if checkout_submodules {
      provision_initialized_submodules(
        dir, target, submodule_checkout_timeout_seconds,
      )
    }
  }
  entries.push({
    name,
    branch,
    base,
    session: owner.session(),
    codex_thread: owner.codex_thread(),
  })
  let mut infos : Array[WorktreeInfo] = []
  @async.protect_from_cancel(() => {
    {
      errdefer rollback_worktree(dir, name, branch)
      write_worktrees(dir, entries)
    }
    infos = worktree_infos(dir, entries)
    on_committed(infos)
  })
  { name, worktrees: infos, }
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
  submodule_checkout_timeout_seconds~ : Int,
) -> Unit {
  guard @gitx.probe(dir, [
      "show-ref",
      "--verify",
      "--quiet",
      "refs/heads/\{entry.branch}",
    ])
    is Some(_) else {
    raise WorktreeError(
      "branch \{entry.branch} is gone too; this worktree cannot be restored",
    )
  }
  ignore(@gitx.probe(dir, ["worktree", "prune"]))
  @workspaces.exclude_from_git(dir, WorktreesDirName)
  let target = worktree_dir(dir, entry.name)
  errdefer @async.protect_from_cancel(() => {
    rollback_worktree_checkout(dir, entry.name, entry.branch)
  })
  ignore(
    @gitx.run(dir, [
      "worktree",
      "add",
      "\{WorktreesDirName}/\{entry.name}",
      entry.branch,
    ]),
  )
  if checkout_submodules {
    provision_initialized_submodules(
      dir, target, submodule_checkout_timeout_seconds,
    )
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
  @gitx.rollback(dir, ["worktree", "prune"])
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
  @gitx.rollback(dir, ["branch", "-D", branch])
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
  guard @gitx.probe(dir, ["worktree", "list", "--porcelain"]) is Some(output) else {
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
  guard @gitx.probe(dir, ["worktree", "list", "--porcelain"]) is Some(output) else {
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
    @gitx.run(workspace, [
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
pub async fn remove(
  host : WorktreeHost,
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
  host.lifecycle_lock.acquire()
  defer host.lifecycle_lock.release()
  guard @pathx.Absolute::from_uri_path(workspace) is Some(absolute) &&
    @workspaces.registered_dir(absolute) is Some(dir) else {
    raise WorktreeError("\{workspace} is not a registered workspace")
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
    raise WorktreeError("no worktree named \{name} in this workspace")
  }
  if entry.codex_thread is Some(_) {
    raise WorktreeError(
      "this worktree belongs to a Codex task; archive that task before removing its checkout",
    )
  }
  if entry.session is Some(bound) {
    (host.drain_sessions)([bound])
  }
  let target = worktree_dir(dir, name)
  let present = @fsx.is_dir(target.to_path()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => false
  }
  if present {
    if !force {
      let status = @gitx.run(target, ["status", "--porcelain"])
      guard status.is_empty() else {
        raise WorktreeError(
          "worktree \{name} has uncommitted changes; force removal discards them",
        )
      }
    }
    delete_worktree_checkout(dir, name)
  } else {
    // The checkout is already gone; drop git's stale bookkeeping for it.
    ignore(@gitx.probe(dir, ["worktree", "prune"]))
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
  { worktrees: infos, }
}

// Tests. The lifecycle tests exercise the real git binary (like the CLI's
// subtask lifecycle tests); the environment-dependent ones serialize on
// `worktree_env_test_lock` because they redirect HOME.

///|
/// A fixture root in the tmpdir's physical spelling. The workspace registry
/// canonicalizes what it stores, so a fixture built from the symlinked
/// spelling (`/tmp` on macOS) would compare unequal to every path the
/// registry hands back.
async fn worktree_test_root(prefix : String) -> @pathx.Absolute {
  @pathx.Path(@fs.realpath(@fs.tmpdir(prefix~))).resolve()
}

///|
/// Tests that redirect HOME share the process environment,
/// so they run one at a time.
#cfg(not(platform="windows"))
let worktree_env_test_lock : @async.Mutex = Mutex()

///|
#cfg(not(platform="windows"))
fn restore_home_env(previous : String?) -> Unit {
  if previous is Some(value) {
    @sys.set_env_var("HOME", value)
  } else {
    @sys.unset_env_var("HOME")
  }
}

///|
/// A host with no engine behind it: `live` names the conversations the pump
/// would report a slot for, and every drained session is appended to
/// `drained` instead of closing a process.
#cfg(not(platform="windows"))
fn test_host(
  live? : Array[String] = [],
  drained? : Array[String] = [],
) -> WorktreeHost {
  {
    lifecycle_lock: Mutex(),
    session_is_live: session => live.contains(session),
    drain_sessions: sessions => {
      for session in sessions {
        drained.push(session)
      }
    },
  }
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
  defer @fs.rmdir(root.to_string(), recursive=true)
  @fsx.ensure_dir(@workspaces.store_root(root).to_path())
  @fsx.write_text(worktrees_file(root).to_path(), "{ not json")
  assert_eq(read_worktrees_unlocked(root).length(), 0)
  let registry : Json = {
    "worktrees": [
      { "name": "ok", "branch": "openseek/ok", "base": "abc", "session": "s1" },
      {
        "name": "codex",
        "branch": "openseek/codex",
        "base": "def",
        "codex_thread": "thread-1",
      },
      {
        "name": "ambiguous",
        "branch": "openseek/ambiguous",
        "base": "ghi",
        "session": "s2",
        "codex_thread": "thread-2",
      },
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
  assert_eq(entries.length(), 3)
  assert_eq(entries[0].name, "ok")
  assert_eq(entries[0].branch, "openseek/ok")
  assert_eq(entries[0].base, "abc")
  assert_eq(entries[0].session, Some("s1"))
  assert_eq(entries[0].codex_thread, None)
  assert_eq(entries[1].name, "codex")
  assert_eq(entries[1].session, None)
  assert_eq(entries[1].codex_thread, Some("thread-1"))
  // A blank session self-heals to unbound rather than a phantom id.
  assert_eq(entries[2].name, "blank")
  assert_true(entries[2].session is None)
  assert_true(entries[2].codex_thread is None)
}

///|
async test "failed worktree registry staging preserves every live row" {
  let root = worktree_test_root("openseek-worktree-atomic-write-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  let retained : WorktreeEntry = {
    name: "retained",
    branch: "openseek/retained",
    base: "abc",
    session: Some("other-session"),
    codex_thread: None,
  }
  write_worktrees(root, [retained])
  // A directory at the candidate path makes the next file write fail before
  // publication, modeling an interrupted or rejected staging write.
  let temp = @workspaces.store_root(root).join(WorktreesFile + ".tmp")
  @fs.mkdir(temp.to_string())
  let failed = try {
    write_worktrees(root, [])
    false
  } catch {
    error if @async.is_being_cancelled() => raise error
    _ => true
  }
  assert_true(failed)
  guard read_worktrees_unlocked(root) is [after] else {
    fail("the previous worktree registry must remain readable")
  }
  assert_eq(after.name, retained.name)
  assert_eq(after.branch, retained.branch)
  assert_eq(after.base, retained.base)
  assert_eq(after.session, retained.session)
}

///|
#cfg(not(platform="windows"))
async fn prepare_git_repo(dir : @pathx.Absolute) -> Unit {
  @fsx.ensure_dir(dir.to_path())
  ignore(@gitx.run(dir, ["init", "-q"]))
  ignore(
    @gitx.run(dir, [
      "-c", "user.email=test@example.com", "-c", "user.name=test", "-c", "commit.gpgsign=false",
      "commit", "--allow-empty", "-q", "-m", "init",
    ]),
  )
}

///|
#cfg(not(platform="windows"))
async test "attach refuses a linked worktree, keeps main and non-git attachable" {
  worktree_env_test_lock.acquire()
  defer worktree_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let root = worktree_test_root("openseek-worktree-attach-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  @sys.set_env_var("HOME", root.join("global").to_string())
  defer restore_home_env(previous)
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(
    @gitx.run(repo, ["worktree", "add", "-q", root.join("linked").to_string()]),
  )
  let detail = try {
    ignore(@workspaces.add(root.join("linked").to_string(), fn(_) {  }))
    "no error"
  } catch {
    WorktreeError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
  assert_true(detail.contains("linked git worktree"))
  // The main checkout, one of its subdirectories, and a plain directory all
  // stay attachable — in particular the guard must not misfire on paths whose
  // `.git` is elsewhere for other reasons.
  assert_true(@workspaces.add(repo.to_string(), fn(_) {  }).contains(repo))
  let sub = repo.join("sub")
  @fsx.ensure_dir(sub.to_path())
  assert_true(@workspaces.add(sub.to_string(), fn(_) {  }).contains(sub))
  let plain = root.join("plain")
  @fsx.ensure_dir(plain.to_path())
  assert_true(@workspaces.add(plain.to_string(), fn(_) {  }).contains(plain))
}

///|
#cfg(not(platform="windows"))
async test "worktree create provisions checkout, branch, registry, exclusion" {
  worktree_env_test_lock.acquire()
  defer worktree_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let root = worktree_test_root("openseek-worktree-create-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  @sys.set_env_var("HOME", root.join("global").to_string())
  defer restore_home_env(previous)
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(@workspaces.add(repo.to_string(), fn(_) {  }))
  let host = test_host()
  let committed : Ref[Int] = Ref(-1)
  let reply = create(
    host,
    repo.to_string(),
    WorktreeOwner::openseek("s-fix-auth"),
    infos => committed.val = infos.length(),
    name="fix-auth",
  )
  assert_eq(committed.val, 1)
  assert_eq(reply.name, "fix-auth")
  guard reply.worktrees is [info] else { fail("expected one worktree") }
  assert_eq(info.name, "fix-auth")
  // The minted branch is `openseek/<name>-<8 hex chars of salt>`.
  assert_true(info.branch.has_prefix("openseek/fix-auth-"))
  assert_eq(info.branch.length(), "openseek/fix-auth-".length() + 8)
  assert_eq(info.base, @gitx.run(repo, ["rev-parse", "HEAD"]))
  // Creation IS the binding: the entry carries its conversation from birth.
  assert_eq(info.session, Some("s-fix-auth"))
  assert_eq(tree_base(repo, "s-fix-auth"), Some(info.base))
  assert_eq(tree_base(repo, "workspace-root"), None)
  assert_eq(info.path, repo.join(".worktrees/fix-auth").to_string())
  assert_true(info.present)
  assert_true(@fsx.is_dir(repo.join(".worktrees/fix-auth").to_path()))
  assert_true(
    @gitx.probe(repo, [
      "show-ref",
      "--verify",
      "--quiet",
      "refs/heads/\{info.branch}",
    ])
    is Some(_),
  )
  // The new checkout sits on its own branch at the recorded base.
  assert_eq(
    @gitx.run(repo.join(".worktrees/fix-auth"), [
      "rev-parse", "--abbrev-ref", "HEAD",
    ]),
    info.branch,
  )
  let exclude = @fsx.read_text(repo.join(".git/info/exclude").to_path())
  assert_true(exclude.contains(".worktrees/"))
  assert_true(exclude.contains(".openseek/"))
  guard list(repo.to_string()).worktrees is [listed] else {
    fail("expected one listed worktree")
  }
  assert_eq(listed.name, "fix-auth")
  assert_true(listed.present)
}

///|
#cfg(not(platform="windows"))
async test "explicit registry removal can prune a vanished worktree" {
  worktree_env_test_lock.acquire()
  defer worktree_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let root = worktree_test_root("openseek-worktree-release-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  @sys.set_env_var("HOME", root.join("global").to_string())
  defer restore_home_env(previous)
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(@workspaces.add(repo.to_string(), fn(_) {  }))
  let host = test_host()
  ignore(
    create(
      host,
      repo.to_string(),
      WorktreeOwner::openseek("s-release"),
      fn(_) {  },
      name="wt",
    ),
  )
  @fs.rmdir(repo.join(".worktrees/wt").to_string(), recursive=true)
  // The low-level protocol operation remains available for orphan cleanup.
  // The bundled UI does not expose it for a conversation; Archive retains the
  // row so a later Unarchive still requires explicit Repair.
  let reply = remove(host, repo.to_string(), "wt", false, fn(_) {  })
  assert_eq(reply.worktrees.length(), 0)
  // Unbound, the conversation runs in the workspace again — no refusal.
  assert_eq(run_dir(repo, "s-release").to_string(), repo.to_string())
}

///|
#cfg(not(platform="windows"))
async test "worktree names are host-generated and skip surviving branches" {
  worktree_env_test_lock.acquire()
  defer worktree_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let root = worktree_test_root("openseek-worktree-autoname-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  @sys.set_env_var("HOME", root.join("global").to_string())
  defer restore_home_env(previous)
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(@workspaces.add(repo.to_string(), fn(_) {  }))
  let host = test_host()
  let first = create(host, repo.to_string(), WorktreeOwner::openseek("s-1"), fn(
    _,
  ) {

  })
  assert_eq(first.name, "wt-1")
  // The session is the idempotency key: a replay (a retry after a lost
  // reply) gets the existing binding back, never a second checkout.
  let replay = create(host, repo.to_string(), WorktreeOwner::openseek("s-1"), fn(
    _,
  ) {

  })
  assert_eq(replay.name, "wt-1")
  assert_eq(replay.worktrees.length(), 1)
  let second = create(host, repo.to_string(), WorktreeOwner::openseek("s-2"), fn(
    _,
  ) {

  })
  assert_eq(second.name, "wt-2")
  // Removal keeps the branch, so a fresh name never resurrects wt-1: the
  // counter moves past every holder, branches included.
  ignore(remove(host, repo.to_string(), "wt-1", false, fn(_) {  }))
  let third = create(host, repo.to_string(), WorktreeOwner::openseek("s-3"), fn(
    _,
  ) {

  })
  assert_eq(third.name, "wt-3")
  guard list(repo.to_string()).worktrees is [a, b] else {
    fail("expected two registered worktrees")
  }
  assert_eq(a.name, "wt-2")
  assert_eq(b.name, "wt-3")
  // A bare `openseek/wt-4` left behind by a build that minted unsalted
  // branches is history too: the counter moves past it instead of pairing
  // the directory with a lookalike salted branch.
  ignore(@gitx.run(repo, ["branch", "openseek/wt-4"]))
  // Codex uses the same registry, name allocator, and idempotency contract,
  // but its owner remains in a distinct field from OpenSeek sessions.
  let codex = create(host, repo.to_string(), WorktreeOwner::codex("thread-1"), fn(
    _,
  ) {

  })
  assert_eq(codex.name, "wt-5")
  let codex_replay = create(
    host,
    repo.to_string(),
    WorktreeOwner::codex("thread-1"),
    fn(_) {  },
  )
  assert_eq(codex_replay.name, "wt-5")
  guard codex_replay.worktrees.iter().find_first(info => info.name == "wt-5")
    is Some(codex_info) else {
    fail("expected Codex-owned worktree row")
  }
  assert_eq(codex_info.session, None)
  assert_eq(codex_info.codex_thread, Some("thread-1"))
}

///|
#cfg(not(platform="windows"))
async fn create_refusal(
  host : WorktreeHost,
  workspace : String,
  session : String,
  name : String,
) -> String {
  try {
    ignore(
      create(
        host,
        workspace,
        WorktreeOwner::openseek(session),
        fn(_) {  },
        name~,
      ),
    )
    "no error"
  } catch {
    WorktreeError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
}

///|
#cfg(not(platform="windows"))
async test "worktree create names the holder in every refusal" {
  worktree_env_test_lock.acquire()
  defer worktree_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let root = worktree_test_root("openseek-worktree-refuse-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  @sys.set_env_var("HOME", root.join("global").to_string())
  defer restore_home_env(previous)
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(@workspaces.add(repo.to_string(), fn(_) {  }))
  let host = test_host()
  assert_true(
    create_refusal(host, root.join("unregistered").to_string(), "s", "x").contains(
      "not a registered workspace",
    ),
  )
  assert_true(
    create_refusal(host, repo.to_string(), "s", "-x").contains("worktree names"),
  )
  assert_true(
    create_refusal(host, repo.to_string(), "a/b", "x").contains(
      "session id invalid",
    ),
  )
  // Binding is for new conversations: one with durable history keeps the
  // tree it grew up in.
  @fsx.ensure_dir(
    @workspaces.store_root(repo).join("sessions").join("s-old").to_path(),
  )
  assert_true(
    create_refusal(host, repo.to_string(), "s-old", "x").contains(
      "already has history",
    ),
  )
  // The session must be new EVERYWHERE: history in the global store, a
  // binding in another workspace's registry, and an in-flight first turn
  // all refuse — any of them would fork the conversation's routing.
  guard @workspaces.global_store_root() is Some(global) else {
    fail("expected a global store under HOME")
  }
  @fsx.ensure_dir(global.join("sessions/s-global").to_path())
  assert_true(
    create_refusal(host, repo.to_string(), "s-global", "x").contains(
      "already has history",
    ),
  )
  let elsewhere = root.join("elsewhere")
  @fsx.ensure_dir(elsewhere.to_path())
  ignore(@workspaces.add(elsewhere.to_string(), fn(_) {  }))
  write_worktrees(elsewhere, [
    {
      name: "wt-e",
      branch: "openseek/wt-e",
      base: "abc",
      session: Some("s-elsewhere"),
      codex_thread: None,
    },
  ])
  assert_true(
    create_refusal(host, repo.to_string(), "s-elsewhere", "x").contains(
      "already runs in worktree wt-e",
    ),
  )
  // A conversation the host already holds a slot for is mid-first-turn; its
  // durable record has not landed yet, so only the host can say so.
  assert_true(
    create_refusal(test_host(live=["s-live"]), repo.to_string(), "s-live", "x").contains(
      "already starting",
    ),
  )
  ignore(
    create(
      host,
      repo.to_string(),
      WorktreeOwner::openseek("s-dup"),
      fn(_) {  },
      name="dup",
    ),
  )
  assert_true(
    create_refusal(host, repo.to_string(), "s-2", "dup").contains(
      "already exists",
    ),
  )
  @fsx.ensure_dir(repo.join(".worktrees/held").to_path())
  assert_true(
    create_refusal(host, repo.to_string(), "s-3", "held").contains(
      "already exists on disk",
    ),
  )
  // A workspace that is not a git repository cannot host worktrees; a linked
  // worktree registered before the attach guard existed is refused too.
  let plain = root.join("plain")
  @fsx.ensure_dir(plain.to_path())
  ignore(@workspaces.add(plain.to_string(), fn(_) {  }))
  assert_true(
    create_refusal(host, plain.to_string(), "s", "x").contains(
      "not a git repository",
    ),
  )
  // A repository SUBDIRECTORY stays attachable but cannot host worktrees:
  // the checkout would land inside it as untracked noise at the wrong depth.
  let sub = repo.join("sub")
  @fsx.ensure_dir(sub.to_path())
  ignore(@workspaces.add(sub.to_string(), fn(_) {  }))
  assert_true(
    create_refusal(host, sub.to_string(), "s-sub", "x").contains(
      "repository subdirectory",
    ),
  )
}

///|
#cfg(not(platform="windows"))
async fn remove_refusal(
  host : WorktreeHost,
  workspace : String,
  name : String,
  force : Bool,
) -> String {
  try {
    ignore(remove(host, workspace, name, force, fn(_) {  }))
    "no error"
  } catch {
    WorktreeError(detail) => detail
    error if @async.is_being_cancelled() => raise error
    error => "\{error}"
  }
}

///|
#cfg(not(platform="windows"))
async test "worktree remove enforces the dirty check and keeps the branch" {
  worktree_env_test_lock.acquire()
  defer worktree_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let root = worktree_test_root("openseek-worktree-remove-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  @sys.set_env_var("HOME", root.join("global").to_string())
  defer restore_home_env(previous)
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(@workspaces.add(repo.to_string(), fn(_) {  }))
  let host = test_host()
  assert_true(
    remove_refusal(host, repo.to_string(), "nope", false).contains(
      "no worktree named",
    ),
  )
  let w1 = create(
    host,
    repo.to_string(),
    WorktreeOwner::openseek("s-w1"),
    fn(_) {  },
    name="w1",
  )
  @fs.write_file(
    repo.join(".worktrees/w1/junk.txt").to_string(),
    b"x",
    create_mode=CreateOrTruncate,
  )
  assert_true(
    remove_refusal(host, repo.to_string(), "w1", false).contains(
      "uncommitted changes",
    ),
  )
  assert_eq(list(repo.to_string()).worktrees.length(), 1)
  let committed : Ref[Int] = Ref(-1)
  let forced = remove(host, repo.to_string(), "w1", true, infos => {
    committed.val = infos.length()
  })
  assert_eq(committed.val, 0)
  assert_eq(forced.worktrees.length(), 0)
  assert_false(@fsx.exists(repo.join(".worktrees/w1").to_path()))
  guard w1.worktrees is [w1_info] else { fail("expected one worktree") }
  // Committed work is never lost: the branch survives every removal.
  assert_true(
    @gitx.probe(repo, [
      "show-ref",
      "--verify",
      "--quiet",
      "refs/heads/\{w1_info.branch}",
    ])
    is Some(_),
  )
  let w2 = create(
    host,
    repo.to_string(),
    WorktreeOwner::openseek("s-w2"),
    fn(_) {  },
    name="w2",
  )
  ignore(remove(host, repo.to_string(), "w2", false, fn(_) {  }))
  assert_eq(list(repo.to_string()).worktrees.length(), 0)
  guard w2.worktrees is [w2_info] else { fail("expected one worktree") }
  assert_true(
    @gitx.probe(repo, [
      "show-ref",
      "--verify",
      "--quiet",
      "refs/heads/\{w2_info.branch}",
    ])
    is Some(_),
  )
}

///|
#cfg(not(platform="windows"))
async test "worktree remove prunes an externally deleted checkout" {
  worktree_env_test_lock.acquire()
  defer worktree_env_test_lock.release()
  let previous = @sys.get_env_var("HOME")
  let root = worktree_test_root("openseek-worktree-prune-")
  defer @fs.rmdir(root.to_string(), recursive=true)
  @sys.set_env_var("HOME", root.join("global").to_string())
  defer restore_home_env(previous)
  let repo = root.join("repo")
  prepare_git_repo(repo)
  ignore(@workspaces.add(repo.to_string(), fn(_) {  }))
  let host = test_host()
  ignore(
    create(
      host,
      repo.to_string(),
      WorktreeOwner::openseek("s-gone"),
      fn(_) {  },
      name="gone",
    ),
  )
  @fs.rmdir(repo.join(".worktrees/gone").to_string(), recursive=true)
  guard list(repo.to_string()).worktrees is [listed] else {
    fail("expected the deleted worktree to stay listed")
  }
  assert_false(listed.present)
  ignore(remove(host, repo.to_string(), "gone", false, fn(_) {  }))
  assert_eq(list(repo.to_string()).worktrees.length(), 0)
  assert_false(
    @gitx.run(repo, ["worktree", "list", "--porcelain"]).contains(
      ".worktrees/gone",
    ),
  )
}

///|
pub extend CodexWorktreeBinding with Debug::{to_repr}

///|
pub extend CodexWorktreeBinding with Eq::{equal, not_equal}

///|
pub extend WorktreeError with Debug::{to_repr}

///|
pub extend WorktreeOwner with Debug::{to_repr}

///|
pub extend WorktreeOwner with Eq::{equal, not_equal}

///|
/// Mark the platform-gated import alias as used: this binding is `_`-prefixed
/// (never warned about) and its body is never evaluated.
let _unused_imports : Unit = ignore(@sys.get_env_var)
