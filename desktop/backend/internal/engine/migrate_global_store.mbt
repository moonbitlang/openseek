// One-time relocation of the conversations the desktop used to keep in the
// global session store. Scratch conversations kept their durable records in
// `<global>/sessions` (archived twins in `<global>/archived/sessions`) while
// their working directories sat under `<Documents>/OpenSeek/<session id>`.
// Now that every conversation belongs to a registered workspace, those move
// into the default workspace's own store, where the sidebar lists them
// alongside everything else. The global root itself stays: it still holds the
// workspace registry and the global skills directory.

///|
/// Move every durable record left in the global store into the default
/// workspace's in-project store and return how many moved.
///
/// Idempotent by construction rather than by a marker: a moved record is gone
/// from the source, so a later pass finds nothing. A record whose id already
/// exists in the destination stays where it is — the destination copy is the
/// one the sidebar shows, and silently overwriting it would destroy a real
/// transcript.
///
/// Nothing moves unless the default workspace is attached right now: a record
/// relocated into a detached store would just vanish from the sidebar. The
/// working directories under `<Documents>/OpenSeek/<session id>` are left
/// exactly where they are — they already sit inside the default workspace, so
/// the agent's past output stays visible and reachable.
pub async fn migrate_global_store() -> Int {
  guard @workspaces.global_store_root() is Some(global) else { return 0 }
  guard @workspaces.default_workspace() is Some(workspace) else { return 0 }
  let destination = @workspaces.store_root(workspace)
  // An explicitly resolved global root can name the destination store itself.
  // Moving records onto themselves is not a migration.
  guard global != destination else { return 0 }
  // Where a record copied across filesystems waits until it is whole. It sits
  // in the destination store but outside both record directories, so nothing
  // lists a half-written transcript as a conversation.
  let staging = destination.join(StagingDirName)
  let moved = move_records(
      global.join("sessions"),
      destination.join("sessions"),
      staging~,
    ) +
    move_records(
      @session_store.archived_root(global).join("sessions"),
      @session_store.archived_root(destination).join("sessions"),
      staging~,
    )
  @fsx.remove_if_exists(staging.to_path()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
  moved
}

///|
/// The staging directory's name inside the destination store. `archived` and
/// `sessions` are the store's own; anything else there is ours.
const StagingDirName = ".migrating"

///|
/// Move each session-record directory from `source` into `destination`,
/// returning how many moved. Best-effort per record: one that cannot be moved
/// (a permission failure, a store that vanished mid-migration) is left behind
/// for a later launch rather than failing the whole migration.
async fn move_records(
  source : @pathx.Absolute,
  destination : @pathx.Absolute,
  staging~ : @pathx.Absolute,
) -> Int {
  guard @fsx.Directory::try_open(source.to_path()) is Some(dir) else {
    return 0
  }
  let names = []
  for entry in dir.collect() {
    // Only session records move; a stray file is not a record at all.
    guard entry.is_dir() && @session_store.safe_session_id(entry.name()) else {
      continue
    }
    names.push(entry.name())
  }
  guard !names.is_empty() else { return 0 }
  @fsx.ensure_dir(destination.to_path()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return 0
  }
  let mut moved = 0
  for name in names {
    // A record already in the destination is the live one; leave the source
    // copy alone rather than overwrite a real transcript.
    guard !@fsx.exists(destination.join(name).to_path()) else { continue }
    if move_record(
        source.join(name),
        destination.join(name),
        staging.join(name),
      ) {
      moved += 1
    }
  }
  moved
}

///|
/// Move one record directory, reporting whether it now lives at
/// `destination`. A rename does it when both stores share a filesystem, which
/// is the ordinary case. They need not: a user whose Documents folder lives on
/// another drive has a global store no `rename` can reach, and giving up there
/// would strand every conversation predating this migration somewhere nothing
/// lists. Copy the record across instead.
async fn move_record(
  record : @pathx.Absolute,
  destination : @pathx.Absolute,
  staging : @pathx.Absolute,
) -> Bool {
  @fs.rename(record.to_string(), destination.to_string()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return copy_record(record, destination, staging)
  }
  true
}

///|
/// Relocate one record by copying it, for the stores a rename cannot span.
/// The copy lands in `staging` — inside the destination store, outside the
/// directories that list conversations — and only a whole record is renamed
/// into place, so an interrupted copy is never read as a transcript. The
/// source is erased last: until the destination record exists, the original
/// is the one record there is.
async fn copy_record(
  record : @pathx.Absolute,
  destination : @pathx.Absolute,
  staging : @pathx.Absolute,
) -> Bool {
  try {
    // Whatever an earlier interrupted attempt left here is a partial copy of
    // this same record, not something anyone can reach.
    @fsx.remove_if_exists(staging.to_path())
    @fsx.copy_dir(record.to_path(), staging.to_path())
    @fs.rename(staging.to_string(), destination.to_string())
    @fsx.remove_if_exists(record.to_path())
    true
  } catch {
    error if @async.is_being_cancelled() => raise error
    _ => false
  }
}
