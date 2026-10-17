// Worktrees of a registered workspace: isolated checkouts under
// `<workspace>/.worktrees/<name>` where conversations work on a detached
// HEAD of their own — a worktree is an execution environment, created for
// the conversation that chose it and held by every conversation bound to it
// — while the durable record stays in the main repository's store. A
// worktree is never itself a workspace; this registry —
// `<workspace>/.openseek/worktrees.json`, desktop-owned — remembers each
// worktree's recovery ref, base commit, and bound conversations. The
// worktree's path is always derived from its name, never stored.

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
/// serve process still has its cwd inside that directory. `session_is_moving`
/// answers whether an archive, restore or delete has claimed a conversation's
/// record: such an operation removes the checkout and then settles the
/// placement, and a checkout created or repaired in between would outlive it.
pub(all) struct WorktreeHost {
  lifecycle_lock : @async.Mutex
  session_is_live : (String) -> Bool
  session_is_moving : (String) -> Bool
  drain_sessions : async (Array[String]) -> Unit
}

///|
const WorktreesFile = "worktrees.json"

///|
const WorktreesDirName = ".worktrees"

///|
/// Legacy desktop branches remain reserved when allocating worktree names.
const WorktreeBranchPrefix = "openseek/"

///|
/// Registry reads and read-modify-write mutations share one process-wide
/// lock, exactly like `workspaces.json` — without it two concurrent
/// create/remove operations could both read the same old list and let the
/// later write silently erase the earlier one. And exactly like
/// `workspaces.json`, it orders this process only: each operation that
/// rewrites a workspace's registry also holds `lock_worktrees_file` across its
/// read and its write, while reads rely on the save being atomic.
let worktree_registry_lock : @async.Mutex = Mutex()

///|
/// The cross-process half of a registry mutation in `workspace`, taken after
/// `worktree_registry_lock` and before the registry is read.
async fn lock_worktrees_file(workspace : @pathx.Absolute) -> @fsx.FileLock {
  @fsx.FileLock::acquire(worktrees_file(workspace).to_path()) catch {
    error => raise WorktreeError("could not lock the worktree list: \{error}")
  }
}

///|
priv struct WorktreeEntry {
  name : String
  checkout : WorktreeCheckout
  base : String
  // OpenSeek conversations are the members of `sessions`; a Codex-owned
  // worktree names its one `codex_thread` instead. A valid app-created row
  // has members or a thread, never both. Neither is tolerated for a registry
  // edited outside the app; such a row serves nobody and is cleaned up only
  // by explicit removal.
  sessions : Array[String]
  codex_thread : String?
}

///|
/// Persist only concrete owner fields. Registry reads deliberately accept
/// missing owner fields for hand-edited legacy rows, so writing `null` would
/// introduce a second representation for the same ownerless state.
impl ToJson for WorktreeEntry with fn to_json(self) {
  let fields : Map[String, Json] = {
    "name": Json(self.name),
    "base": Json(self.base),
  }
  match self.checkout {
    Branch(branch) => fields["branch"] = Json(branch)
    Detached(recovery_ref) => fields["recovery_ref"] = Json(recovery_ref)
  }
  if !self.sessions.is_empty() {
    fields["sessions"] = Json(self.sessions)
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
/// The members a row created for this owner starts with.
fn WorktreeOwner::sessions(self : WorktreeOwner) -> Array[String] {
  match self {
    OpenSeekSession(id) => [id]
    CodexThread(_) => []
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
    OpenSeekSession(id) => self.sessions.contains(id)
    CodexThread(id) => self.codex_thread is Some(matched) && matched == id
  }
}

///|
/// Files, Terminal, and language requests carry the owning conversation id.
/// The two products store that id in distinct registry fields, but checkout
/// resolution must recognize either field without merging their lifecycles.
fn WorktreeEntry::serves_id(self : WorktreeEntry, id : String) -> Bool {
  self.sessions.contains(id) ||
  (self.codex_thread is Some(codex_thread) && codex_thread == id)
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
type CheckoutRemoval = @protocol.CheckoutRemoval

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
/// A registry row's optional owner id: present, a JSON string, and non-empty.
/// A blank id names no conversation, so it reads as an unbound row.
fn owner_field(fields : Map[String, Json], key : String) -> String? {
  guard fields.get(key) is Some(String(id)) && !id.is_empty() else {
    return None
  }
  Some(id)
}

///|
/// A registry row's OpenSeek members. Rows written before a worktree could
/// hold more than one conversation name their single member as `session`;
/// that spelling stays readable and is rewritten as `sessions` by the next
/// registry commit. Blank and repeated ids name no further conversation.
fn session_members(fields : Map[String, Json]) -> Array[String] {
  guard fields.get("sessions") is Some(Array(items)) else {
    return match owner_field(fields, "session") {
      Some(id) => [id]
      None => []
    }
  }
  let members : Array[String] = []
  for item in items {
    if item is String(id) && !id.is_empty() && !members.contains(id) {
      members.push(id)
    }
  }
  members
}

///|
/// The registered worktrees of `workspace`, dropping anything malformed: an
/// entry without a valid name, checkout reference, and base string is dropped
/// rather than poisoning every later operation. A missing or unreadable
/// registry reads as "no worktrees".
async fn read_worktrees_unlocked(
  workspace : @pathx.Absolute,
) -> Array[WorktreeEntry] {
  let text = @fsx.try_read_text(worktrees_file(workspace).to_path()) catch {
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
    if entries.any(existing => existing.name == name) {
      continue
    }
    let checkout = match (fields.get("branch"), fields.get("recovery_ref")) {
      (Some(String(branch)), None) if !branch.is_empty() => Branch(branch)
      (None, Some(String(recovery_ref))) if valid_recovery_ref(
          name, recovery_ref,
        ) => Detached(recovery_ref)
      _ => continue
    }
    guard fields.get("base") is Some(String(base)) else { continue }
    let sessions = session_members(fields)
    let codex_thread = owner_field(fields, "codex_thread")
    // A row cannot be owned by both products. Drop a malformed ambiguous row
    // instead of letting whichever lookup happens first claim its checkout.
    guard sessions.is_empty() || codex_thread is None else { continue }
    entries.push({ name, checkout, base, sessions, codex_thread, })
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
    error => raise WorktreeError("could not create \{store}: \{error}")
  }
  let registry : Json = { "worktrees": Json(entries) }
  // A registry update may remove only one conversation's placement while
  // retaining every unrelated row. The save builds the whole replacement
  // beside the live file and renames it into place: a failed or cancelled
  // write leaves the old registry intact instead of truncating it and
  // orphaning all of those other rows, and a reader in another process never
  // sees a partial list.
  @fsx.write_text_atomic(
    worktrees_file(workspace).to_path(),
    registry.stringify(indent=2),
  ) catch {
    error => raise WorktreeError("could not save the worktree list: \{error}")
  }
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
    let present = @fsx.is_dir(path.to_path()) catch { _ => false }
    infos.push({
      name: entry.name,
      branch: entry.checkout.branch(),
      base: entry.base,
      sessions: entry.sessions,
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
    let present = @fsx.is_dir(dir.to_path()) catch { _ => false }
    return if present { BoundTree(dir) } else { MissingTree(entry.name) }
  }
  WorkspaceRoot
}

///|
/// The immutable commit a conversation's worktree was created from.
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
    MissingTree(name) => raise WorktreeError(missing_checkout_refusal(name))
  }
}

///|
/// What a conversation is told when its worktree's checkout is gone.
fn missing_checkout_refusal(name : String) -> String {
  "worktree \{name} for this conversation is gone; rebuild it or archive the conversation"
}

///|
/// Find this owner's registry row while `worktree_registry_lock` is held.
/// OpenSeek can start from its durable session store; Codex deliberately scans
/// only Desktop registries, never app-server or Git path conventions.
async fn WorktreeOwner::binding_unlocked(
  self : WorktreeOwner,
  workspace? : @pathx.Absolute,
) -> (@pathx.Absolute, WorktreeEntry)? {
  let workspaces = match (workspace, self) {
    (Some(workspace), _) => [workspace]
    (None, OpenSeekSession(session)) =>
      match @session_store.workspace_of(session) {
        Some(workspace) => [workspace]
        None => []
      }
    (None, CodexThread(_)) => @workspaces.registered()
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
  host : WorktreeHost,
) -> ArchiveNeedsForceReply? {
  match self.checkout_removal(host) {
    Some({ worktree, dirty_paths, dirty_path_count, }) if dirty_path_count > 0 =>
      Some({ worktree, dirty_paths, dirty_path_count, })
    _ => None
  }
}

///|
/// The checkout this owner would remove, when one is on disk and no other
/// conversation still holds it, with a preview of
/// what removing it would discard: its uncommitted and untracked paths, none
/// for a clean checkout. Read-only, like `archive_check`. `workspace` is the
/// one project to look in, as for `archive_checkout`.
pub async fn WorktreeOwner::checkout_removal(
  self : WorktreeOwner,
  host : WorktreeHost,
  workspace? : @pathx.Absolute,
) -> CheckoutRemoval? {
  worktree_registry_lock.acquire()
  defer worktree_registry_lock.release()
  guard self.binding_unlocked(workspace?) is Some((workspace, _)) else {
    return None
  }
  let shared = lock_worktrees_file(workspace)
  defer shared.release()
  guard read_worktrees_unlocked(workspace)
    .iter()
    .find_first(entry => entry.belongs_to(self))
    is Some(entry) else {
    return None
  }
  guard !entry.held_by_another(host, workspace, self) else { return None }
  let target = worktree_dir(workspace, entry.name)
  let present = @fsx.is_dir(target.to_path()) catch { _ => false }
  guard present else { return None }
  let status = @gitx.output(target, [
    "status", "--porcelain=v1", "-z", "--untracked-files=all",
  ])
  let (dirty_paths, dirty_path_count) = archive_dirty_path_preview(status)
  Some({ worktree: entry.name, dirty_paths, dirty_path_count, })
}

///|
/// Whether a conversation other than `leaving` still works in this row's
/// checkout: it has a slot in the running pump or a live durable record in
/// `workspace`'s store. An archived member keeps its placement but not the
/// directory, and a member that was bound and never started holds nothing
/// either. A session id names a record only within one store, so a record
/// with a member's id in another attached project is a different
/// conversation and holds nothing here.
///
/// Only a record that is not there says its conversation has left. One that
/// cannot be read — a permission or I/O failure — may belong to a
/// conversation still working here, so the archive is refused rather than
/// allowed to delete the checkout under it.
async fn WorktreeEntry::held_by_another(
  self : WorktreeEntry,
  host : WorktreeHost,
  workspace : @pathx.Absolute,
  leaving : WorktreeOwner,
) -> Bool {
  let records = @workspaces.store_root(workspace).join("sessions")
  for bound in self.sessions {
    guard leaving != OpenSeekSession(bound) else { continue }
    if (host.session_is_live)(bound) {
      return true
    }
    guard @session_store.safe_session_id(bound) else { continue }
    let record : @fs.FileKind? = Some(@fs.kind(records.join(bound).to_string())) catch {
      @os_error.OSError(_) as error if error.is_ENOENT() => None
      error =>
        raise WorktreeError(
          "could not tell whether conversation \{bound} still uses this worktree: \{error}",
        )
    }
    if record is Some(Directory) {
      return true
    }
  }
  false
}

///|
/// Remove the checkout bound to this owner while retaining its registry row.
/// Archiving frees the directory, but the placement and a Git reference keep
/// committed work available for an explicit rebuild. Without `force` a dirty
/// checkout refuses; detached HEAD is pinned before its directory is removed.
/// A checkout another conversation still works in stays exactly as it is —
/// this owner keeps its placement there, so unarchiving returns to it — and
/// goes only with the last conversation that holds it.
/// The caller must first fence its own backend writer (OpenSeek's slot claim or a
/// successful Codex `thread/archive`). An owner without a worktree is a no-op.
///
/// `workspace` names the one project whose registry may hold the placement.
/// A caller that already selected a store passes it: session ids can repeat
/// across projects, and the owner alone resolves to the first project that
/// holds a record with that id.
pub async fn WorktreeOwner::archive_checkout(
  self : WorktreeOwner,
  host : WorktreeHost,
  force : Bool,
  workspace? : @pathx.Absolute,
  on_committed? : (String, Array[WorktreeInfo]) -> Unit,
) -> ArchiveNeedsForceReply? {
  worktree_registry_lock.acquire()
  defer worktree_registry_lock.release()
  guard self.binding_unlocked(workspace?) is Some((workspace, _)) else {
    return None
  }
  // Another host adding a fork to this worktree holds this lock from the
  // member's binding until its record exists. Deciding in between would see
  // a member that holds nothing yet and delete the checkout its fork is
  // being made in. The row is read again once the lock is granted: the read
  // that found the project may already be stale.
  let shared = lock_worktrees_file(workspace)
  defer shared.release()
  let entries = read_worktrees_unlocked(workspace)
  guard entries.iter().find_first(entry => entry.belongs_to(self))
    is Some(entry) else {
    return None
  }
  guard !entry.held_by_another(host, workspace, self) else { return None }
  let target = worktree_dir(workspace, entry.name)
  let present = @fsx.is_dir(target.to_path()) catch { _ => false }
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
    preserve_worktree_head(workspace, entry)
    delete_worktree_checkout(workspace, entry.name)
  } else {
    // The checkout is already gone; retain its last OpenSeek save point.
    remove_missing_checkout(workspace, entry.name)
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
/// Drop the placements of `sessions` from one project's registry and report
/// the remaining rows, or `None` when the registry already held none of them.
/// A row goes with its last member; a row other conversations are still
/// bound to only loses the departing ones. The registry write is atomic, so
/// a failure leaves every row in place for the caller to roll its own work
/// back against.
///
/// This is what permanent deletion of an archived conversation needs: the
/// checkout itself went away when its last conversation was archived.
/// Removing the placement row leaves the recovery reference intact,
/// preserving commits without an unusable ghost placement.
pub async fn drop_placements(
  workspace : @pathx.Absolute,
  sessions : Array[String],
) -> Array[WorktreeInfo]? {
  worktree_registry_lock.acquire()
  defer worktree_registry_lock.release()
  let shared = lock_worktrees_file(workspace)
  defer shared.release()
  let entries = read_worktrees_unlocked(workspace)
  let remaining : Array[WorktreeEntry] = []
  let mut changed = false
  for entry in entries {
    let staying = entry.sessions.filter(bound => !sessions.contains(bound))
    if staying.length() == entry.sessions.length() {
      remaining.push(entry)
      continue
    }
    changed = true
    if !staying.is_empty() {
      remaining.push({ ..entry, sessions: staying, })
    }
  }
  guard changed else { return None }
  write_worktrees(workspace, remaining)
  Some(worktree_infos(workspace, remaining))
}

///|
/// Add `session` to the worktree `worktree_of` works in, around the creation
/// of `session`'s durable record: a conversation forked from one that works
/// in a worktree keeps working in that checkout. When `worktree_of` works in
/// the workspace root there is no worktree to join, and only the record is
/// created.
///
/// `create_record` is handed the directory `session` will work in. It is
/// read here, under the same locks as the binding, because a directory
/// resolved any earlier may name a checkout that was removed since — and a
/// record written for it would describe a place the registry no longer has.
/// A worktree whose checkout is gone is refused, as a turn there would be.
///
/// The registry stays held from the binding until `create_record` returns,
/// which is what an archive of `worktree_of` serializes against: it sees
/// either the row before the fork existed, or a member whose record is
/// already live. The binding is committed first so that an interruption
/// leaves at worst a member without a record, which holds nothing. Another
/// host's registry writes wait as well, for as long: a create or removal
/// that slipped between this read and this write would be lost to it.
///
/// When `create_record` does not return — it raised, or the request was
/// cancelled — what says whether the fork exists is its record, not how the
/// call that wrote it ended. `record_exists` is asked, and only a fork that
/// is not there has its binding taken back out: a record left without its
/// placement would work in the workspace root on a history made elsewhere.
/// `on_committed` reports the rows whenever the binding stays.
pub async fn add_session_to_worktree(
  workspace : @pathx.Absolute,
  session~ : String,
  worktree_of~ : String,
  create_record : async (@pathx.Absolute) -> Unit,
  record_exists~ : async () -> Bool,
  on_committed : (Array[WorktreeInfo]) -> Unit,
) -> Unit {
  worktree_registry_lock.acquire()
  defer worktree_registry_lock.release()
  let shared = lock_worktrees_file(workspace)
  defer shared.release()
  let entries = read_worktrees_unlocked(workspace)
  guard entries.search_by(entry => entry.sessions.contains(worktree_of))
    is Some(index) else {
    create_record(workspace)
    return
  }
  let row = entries[index]
  let checkout = worktree_dir(workspace, row.name)
  let present = @fsx.is_dir(checkout.to_path())
  guard present else { raise WorktreeError(missing_checkout_refusal(row.name)) }
  entries[index] = { ..row, sessions: [..row.sessions, session], }
  write_worktrees(workspace, entries)
  {
    errdefer @async.protect_from_cancel(() => {
      if record_exists() {
        on_committed(worktree_infos(workspace, entries))
      } else {
        entries[index] = row
        write_worktrees(workspace, entries)
      }
    })
    create_record(checkout)
  }
  @async.protect_from_cancel(() => {
    on_committed(worktree_infos(workspace, entries))
  })
}

///|
/// The tree root an absolute in-workspace `path` belongs to: the registered
/// worktree containing it when one does, otherwise the workspace itself. A
/// `.worktrees` path with no registry entry (a worker slice, say) keeps
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
fn archive_dirty_path_preview(status : String) -> (Array[String], Int32) {
  let fields = status.split("\u{0}").collect()
  let paths : Array[String] = []
  let mut count = 0
  let mut index = 0
  while index < fields.length() {
    let record = fields[index]
    if record.length() < 4 {
      index += 1
      continue
    }
    let index_status = record.view(end_offset=1)
    let worktree_status = record.view(start_offset=1, end_offset=2)
    let path = record.view(start_offset=3).to_owned()
    count += 1
    if paths.length() < ArchiveDirtyPathPreviewLimit {
      paths.push(path)
    }
    if index_status is ("R" | "C") || worktree_status is ("R" | "C") {
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
/// a retained reference. References survive removal, so the counter moves
/// past history instead of pairing a reused name with an old checkout.
async fn fresh_worktree_name(
  dir : @pathx.Absolute,
  entries : Array[WorktreeEntry],
) -> String {
  for n in 1..<=1000 {
    let name = "wt-\{n}"
    if entries.any(entry => entry.name == name) {
      continue
    }
    let occupied = @fsx.exists(worktree_dir(dir, name).to_path()) catch {
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
        "\{WorktreeRecoveryPrefix}\{name}-*",
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
/// Create a detached worktree `<workspace>/.worktrees/<name>` at the
/// workspace's current HEAD, with a private recovery reference, bound
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
  // Verify the lossless metadata format before creating any ref, checkout or
  // registry row. Older Git accepts add but rejects list -z during the final
  // unlock, otherwise leaving a published, provisioning-locked checkout.
  ignore(worktree_listing(dir))
  if owner is OpenSeekSession(session) {
    @session_store.ensure_not_archived(session)
    // The claim is taken under this same lifecycle lock, so the operation
    // that holds it either has not started or is not finished.
    guard !(host.session_is_moving)(session) else {
      raise WorktreeError("this conversation is being archived or deleted")
    }
  }
  // Snapshot this workspace's setting once for the lifecycle operation. A
  // concurrent page edit applies to the next create or repair instead of
  // changing this checkout halfway through.
  let workspace_settings = @workspaces.settings(resource_path(dir))
  let checkout_submodules = workspace_settings.checkout_submodules
  let submodule_checkout_timeout_seconds = workspace_settings.submodule_checkout_timeout_seconds
  worktree_registry_lock.acquire()
  defer worktree_registry_lock.release()
  // Held across the git work below as well as the registry write: a create
  // that released between them would let another host's create pick the same
  // name after this one probed it as free.
  let shared = lock_worktrees_file(dir)
  defer shared.release()
  let entries = read_worktrees_unlocked(dir)
  // This conversation already holds its environment. Two shapes land here:
  // the idempotent replay of a create whose reply was lost, and the repair
  // of a checkout deleted outside the app. Repair uses the saved
  // reference without adopting external changes to the missing checkout.
  for entry in entries {
    guard entry.belongs_to(owner) else { continue }
    let present = @fsx.is_dir(worktree_dir(dir, entry.name).to_path()) catch {
      _ => false
    }
    if present {
      // A replay can follow a repair cancelled after `git worktree add`
      // restored the checkout but before its notification ran. Republish the
      // complete host-derived list so that retry repairs every client's stale
      // `present: false` view instead of returning success invisibly.
      finish_worktree_creation(dir, entry)
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
  // Refusals name the holder: the registry entry or the directory (a worker
  // slice can own `.worktrees/<name>` without any registry entry). The recovery
  // reference is freshly salted, so nothing can hold it ahead of us.
  if entries.any(entry => entry.name == name) {
    raise WorktreeError("worktree \{name} already exists in this workspace")
  }
  let target = worktree_dir(dir, name)
  let occupied = @fsx.exists(target.to_path()) catch { _ => false }
  if occupied {
    raise WorktreeError(
      "\{target} already exists on disk; another tool may own it",
    )
  }
  // A unique reference keeps archived commits reachable without creating a
  // user branch. Creating it with an expected absent old value is atomic.
  guard @entropy.random_hex(16) is Some(salt) else {
    raise WorktreeError("no OS entropy available to identify a worktree")
  }
  let recovery_ref = "\{WorktreeRecoveryPrefix}\{name}-\{salt}"
  @workspaces.exclude_from_git(dir, WorktreesDirName)
  let base = @gitx.run(dir, ["rev-parse", "HEAD"])
  ignore(
    @gitx.run(dir, ["update-ref", recovery_ref, base, "0".repeat(base.length())]),
  )
  let entry : WorktreeEntry = {
    name,
    checkout: Detached(recovery_ref),
    base,
    sessions: owner.sessions(),
    codex_thread: owner.codex_thread(),
  }
  let lock_reason = "\{entry.lock_prefix()}\{salt}"
  let mut infos : Array[WorktreeInfo] = []
  {
    errdefer @async.protect_from_cancel(() => {
      rollback_worktree_checkout(dir, name, lock_reason)
      @gitx.rollback(dir, ["update-ref", "-d", recovery_ref, base])
    })
    ignore(
      @gitx.run(dir, [
        "worktree",
        "add",
        "--detach",
        "--lock",
        "--reason",
        lock_reason,
        "\{WorktreesDirName}/\{name}",
        base,
      ]),
    )
    if checkout_submodules {
      provision_initialized_submodules(
        dir, target, submodule_checkout_timeout_seconds,
      )
    }
    entries.push(entry)
    @async.protect_from_cancel(() => {
      // Keep the ownership lock through every fallible preparation step.
      infos = worktree_infos(dir, entries)
      write_worktrees(dir, entries)
    })
  }
  // Once the registry is committed, cleanup must never erase the checkout.
  // A retry can finish this unlock if the subprocess fails after publication.
  finish_worktree_creation(dir, entry)
  @async.protect_from_cancel(() => on_committed(infos))
  { name, worktrees: infos, }
}

///|
/// Restore the last saved detached HEAD, or an existing legacy branch.
/// Only this checkout's stale registration is removed; other worktrees and
/// their saved references are unaffected.
async fn restore_worktree_checkout(
  dir : @pathx.Absolute,
  entry : WorktreeEntry,
  checkout_submodules~ : Bool,
  submodule_checkout_timeout_seconds~ : Int32,
) -> Unit {
  let revision = entry.checkout.revision()
  let commit = @gitx.run(dir, ["rev-parse", "--verify", "\{revision}^{commit}"])
  finish_worktree_creation(dir, entry)
  remove_missing_checkout(dir, entry.name)
  guard @entropy.random_hex(16) is Some(salt) else {
    raise WorktreeError("no OS entropy available to identify a worktree repair")
  }
  let lock_reason = "\{entry.lock_prefix()}\{salt}"
  @workspaces.exclude_from_git(dir, WorktreesDirName)
  let target = worktree_dir(dir, entry.name)
  errdefer @async.protect_from_cancel(() => {
    rollback_worktree_checkout(dir, entry.name, lock_reason)
  })
  let args = ["worktree", "add", "--lock", "--reason", lock_reason]
  match entry.checkout {
    Branch(branch) => {
      args.push("\{WorktreesDirName}/\{entry.name}")
      args.push(branch)
    }
    Detached(_) => {
      args.push("--detach")
      args.push("\{WorktreesDirName}/\{entry.name}")
      args.push(commit)
    }
  }
  ignore(@gitx.run(dir, args))
  if checkout_submodules {
    provision_initialized_submodules(
      dir, target, submodule_checkout_timeout_seconds,
    )
  }
  @async.protect_from_cancel(() => {
    ignore(
      @gitx.run(dir, ["worktree", "unlock", "\{WorktreesDirName}/\{entry.name}"]),
    )
  })
}

///|
/// Only a checkout bearing this invocation's random lock token is ours to
/// roll back. A failed add that raced another process cannot remove its tree,
/// even when both checkouts would have had the same detached commit.
async fn rollback_worktree_checkout(
  dir : @pathx.Absolute,
  name : String,
  lock_reason : String,
) -> Unit {
  // Called under a cancellation shield while an earlier error propagates.
  let reason = worktree_lock_reason(dir, name) catch { _ => return }
  if reason == Some(lock_reason) {
    @gitx.rollback(dir, [
      "worktree",
      "remove",
      "--force",
      "--force",
      "\{WorktreesDirName}/\{name}",
    ])
  }
}

///|
/// An external `git worktree lock` must remain authoritative even on the
/// gitlink cleanup path, where Git cannot perform the removal itself.
async fn worktree_lock_reason(dir : @pathx.Absolute, name : String) -> String? {
  guard checkout_states(dir).get(name) is Some(state) else { return None }
  state.lock_reason
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
/// Remove a worktree's checkout and registry entry. Its recovery reference
/// (or legacy branch) survives, retaining committed work. Uncommitted changes
/// are discarded only behind `force`.
/// Every bound conversation is drained first (an idle serve process still
/// has its cwd inside the directory being deleted); each then becomes a
/// plain workspace conversation with its history intact. If its directory was
/// deleted outside the app, only this worktree's Git registration is removed.
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
  (host.drain_sessions)(entry.sessions)
  // Serialize saving and removal with archive and repair.
  worktree_registry_lock.acquire()
  defer worktree_registry_lock.release()
  // Before the deletion, not just before the write: a sidecar this process
  // refuses to open would otherwise fail the removal only once the checkout
  // — and under `force` its uncommitted work — was already gone, leaving the
  // registry row behind.
  let shared = lock_worktrees_file(dir)
  defer shared.release()
  let target = worktree_dir(dir, name)
  let present = @fsx.is_dir(target.to_path()) catch { _ => false }
  if present {
    if !force {
      let status = @gitx.run(target, ["status", "--porcelain"])
      guard status.is_empty() else {
        raise WorktreeError(
          "worktree \{name} has uncommitted changes; force removal discards them",
        )
      }
    }
    preserve_worktree_head(dir, entry)
    delete_worktree_checkout(dir, name)
  } else {
    // The checkout is already gone; retain its last OpenSeek save point.
    remove_missing_checkout(dir, name)
  }
  // Re-read after draining the bound sessions; keep unrelated placements.
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
