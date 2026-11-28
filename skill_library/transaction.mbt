// Recoverable local skill-library changes. Network downloads happen before
// these paths are touched. A complete candidate is written under `.staging`;
// switching an existing entry parks the old directory under `.backup`, while
// uninstall first moves the live directory under `.trash`. All paths stay
// below the library root, so every rename is on one filesystem.

///|
const StagingDirectory = ".staging"

///|
const BackupDirectory = ".backup"

///|
const TrashDirectory = ".trash"

///|
const DisabledDirectory = ".disabled"

///|
const LockDirectory = ".lock"

///|
const LockFile = "lock"

///|
/// Advisory lock file placed inside a reserved hidden directory under
/// `library_dir` (e.g. `~/.openseek/skills/.lock/lock`) so path aliases such
/// as `/data/skills` and `/data/skills/.` share one lock, read-only parent
/// directories remain usable, and skill discovery skips `.lock` cleanly
/// because it contains no `SKILL.md`.
fn library_lock_dir(library_dir : String) -> String {
  @path.Path(library_dir).join(Path(LockDirectory)).to_string()
}

///|
fn library_lock_path(library_dir : String) -> String {
  @path.Path(library_dir)
  .join(Path(LockDirectory))
  .join(Path(LockFile))
  .to_string()
}

///|
/// One process-wide boundary for every view of the skills directory, paired
/// with the cross-process advisory file lock in `with_library_lock`. Writers
/// hold both while recovering leftovers, staging, and switching the live entry;
/// readers hold both through their complete directory snapshot, so no client
/// can observe the short target-to-backup interval.
let library_lock : @async.Mutex = Mutex()

///|
async fn open_lock_file(sidecar : String) -> @fs.File {
  let created = Some(
    @fs.open(sidecar, mode=ReadWrite, create_mode=CreateNew, permission=0o600),
  ) catch {
    @os_error.OsError(AlreadyExists, ..) => None
    error => raise error
  }
  if created is Some(file) {
    return file
  }
  guard @fs.kind(sidecar, follow_symlink=false) is Regular else {
    fail("\{sidecar} is not a regular file; refusing to lock through it")
  }
  @fs.open(sidecar, mode=ReadWrite, create_mode=OpenExisting)
}

///|
async fn[T] with_acquired_file_lock(
  library_dir : String,
  action : async () -> T,
) -> T {
  @fs.mkdir(library_lock_dir(library_dir), recursive=true, allow_existing=true) catch {
    error => raise SkillsError("cannot lock skills library: \{error}")
  }
  let file = open_lock_file(library_lock_path(library_dir)) catch {
    error => raise SkillsError("cannot lock skills library: \{error}")
  }
  defer file.close()
  file.lock(Exclusive) catch {
    error => raise SkillsError("cannot lock skills library: \{error}")
  }
  defer file.unlock()
  action()
}

///|
/// Serialize access to `library_dir` across both tasks in this process and
/// concurrent OpenSeek hosts sharing the same directory, creating `library_dir`
/// if needed.
async fn[T] with_library_lock(
  library_dir : String,
  action : async () -> T,
) -> T {
  library_lock.acquire()
  defer library_lock.release()
  @fs.mkdir(library_dir, recursive=true, allow_existing=true) catch {
    error => raise SkillsError("cannot create skills library: \{error}")
  }
  with_acquired_file_lock(library_dir, action)
}

///|
/// Serialize access to an existing `library_dir` without creating it or its
/// lock file. Returns `None` without running `action` when the directory does
/// not exist yet, so an unlocked reader can never race a concurrent first-time
/// installer's staging directory.
async fn[T] with_existing_library_lock(
  library_dir : String,
  action : async () -> T,
) -> T? {
  library_lock.acquire()
  defer library_lock.release()
  let exists = try @fs.kind(library_dir) catch {
    @os_error.OsError(NotFound | NotDirectory, ..) => false
    error => raise SkillsError("cannot access skills library: \{error}")
  } noraise {
    kind => kind is Directory
  }
  if !exists {
    return None
  }
  Some(with_acquired_file_lock(library_dir, action))
}

///|
/// Paths and recovery rules for one skills library. The hidden directories
/// themselves encode state; no separate transaction record is needed.
priv struct SkillLibrary {
  root : @path.Path
}

///|
priv struct SkillLocation {
  library : SkillLibrary
  enabled : Bool
}

///|
fn SkillLibrary::child(self : SkillLibrary, name : String) -> String {
  self.root.join(Path(name)).to_string()
}

///|
fn SkillLibrary::disabled(self : SkillLibrary) -> SkillLibrary {
  { root: self.root.join(Path(DisabledDirectory)), }
}

///|
async fn SkillLibrary::has_directory_skill(
  self : SkillLibrary,
  id : String,
) -> Bool {
  @fs.exists(self.root.join(Path(id)).join(Path(SkillFile)).to_string())
}

///|
async fn SkillLibrary::has_flat_skill(self : SkillLibrary, id : String) -> Bool {
  (@fs.kind(self.flat(id)) is Regular) catch {
    _ => false
  }
}

///|
async fn SkillLibrary::contains(self : SkillLibrary, id : String) -> Bool {
  self.has_directory_skill(id) || self.has_flat_skill(id)
}

///|
/// Resolve an entry at commit time: an enable/disable request may have moved
/// it while an update was downloading. The app keeps each entry in one region;
/// new installs default to enabled.
async fn SkillLibrary::locate(
  self : SkillLibrary,
  id : String,
) -> SkillLocation {
  let disabled = self.disabled()
  guard disabled.contains(id) else { return { library: self, enabled: true, } }
  { library: disabled, enabled: false, }
}

///|
async fn SkillLibrary::recover_all(self : SkillLibrary) -> Unit {
  self.recover()
  self.disabled().recover()
}

///|
fn SkillLibrary::target(self : SkillLibrary, id : String) -> String {
  self.child(id)
}

///|
fn SkillLibrary::flat(self : SkillLibrary, id : String) -> String {
  self.child("\{id}.md")
}

///|
fn SkillLibrary::staging(self : SkillLibrary, id : String) -> String {
  self.root.join(Path(StagingDirectory)).join(Path(id)).to_string()
}

///|
fn SkillLibrary::backup(self : SkillLibrary, id : String) -> String {
  self.root.join(Path(BackupDirectory)).join(Path(id)).to_string()
}

///|
fn SkillLibrary::trash(self : SkillLibrary, id : String) -> String {
  self.root.join(Path(TrashDirectory)).join(Path(id)).to_string()
}

///|
async fn collect_slug_dirs(path : String) -> Array[String] {
  let dir = Some(@fs.opendir(path)) catch { _ => None }
  guard dir is Some(dir) else { return [] }
  defer dir.close()
  let ids : Array[String] = []
  while dir.next() is Some(entry) {
    if entry.is_dir && valid_slug(entry.name) {
      ids.push(entry.name)
    }
  }
  ids
}

///|
/// Restore or discard leftovers from an interrupted local change:
///
/// - missing target + backup: switching stopped after parking the old entry,
///   so restore it;
/// - target + backup: the new entry is already live, so discard the old one;
/// - staging: never became live, so discard it;
/// - trash: uninstall already removed the live path, so finish deleting it.
///
/// The caller holds the library lock. Each action is repeatable, so
/// cancellation can stop recovery and the next library operation safely
/// resumes it.
async fn SkillLibrary::recover(self : SkillLibrary) -> Unit {
  for id in collect_slug_dirs(self.child(BackupDirectory)) {
    let backup = self.backup(id)
    let target = self.target(id)
    if @fs.exists(target) {
      @fs.remove(backup, recursive=true) catch {
        error =>
          raise SkillsError("cannot clean the backup for skill \{id}: \{error}")
      }
    } else {
      @fs.rename(backup, target, replace=false) catch {
        error =>
          raise SkillsError(
            "cannot restore the backup for skill \{id}: \{error}",
          )
      }
    }
  }
  for id in collect_slug_dirs(self.child(StagingDirectory)) {
    @fs.remove(self.staging(id), recursive=true) catch {
      error =>
        raise SkillsError(
          "cannot clean the staged files for skill \{id}: \{error}",
        )
    }
  }
  for id in collect_slug_dirs(self.child(TrashDirectory)) {
    @fs.remove(self.trash(id), recursive=true) catch {
      error =>
        raise SkillsError("cannot clean the uninstalled skill \{id}: \{error}")
    }
  }
}

///|
/// Write one complete candidate without changing the live entry: every
/// archive file below one staged directory, then the provenance sidecar.
/// Cancellation or an I/O error may leave an incomplete staging directory;
/// `recover` removes it before any later read or mutation.
async fn SkillLibrary::stage(
  self : SkillLibrary,
  id : String,
  files : Map[String, Bytes],
  provenance : String,
) -> Unit {
  let staging_path = self.root.join(Path(StagingDirectory)).join(Path(id))
  let staging = staging_path.to_string()
  @fs.mkdir(self.child(StagingDirectory), recursive=true, allow_existing=true)
  @fs.remove(staging, recursive=true, allow_missing=true)
  @fs.mkdir(staging, recursive=true, allow_existing=true)
  for path, content in files {
    let target = staging_path.join(Path(path))
    @fs.mkdir(target.dirname().to_string(), recursive=true, allow_existing=true)
    @fs.write_binary(target.to_string(), content, create_mode=CreateOrTruncate)
  }
  @fs.write_text(
    staging_path.join(Path(SidecarFile)).to_string(),
    provenance,
    create_mode=CreateOrTruncate,
  )
}

///|
/// Make a complete staged entry live. Only the short same-filesystem switch,
/// its rollback, and the synchronous invalidation callback are cancellation-
/// shielded. Downloading, staging, and old-backup cleanup remain cancellable.
async fn SkillLibrary::activate(
  self : SkillLibrary,
  id : String,
  on_committed~ : () -> Unit,
) -> Unit {
  let target = self.target(id)
  let staging = self.staging(id)
  let backup = self.backup(id)
  let upgrading = @fs.exists(target)
  if upgrading {
    @fs.mkdir(self.child(BackupDirectory), recursive=true, allow_existing=true)
  }
  @async.protect_from_cancel(() => {
    if upgrading {
      @fs.rename(target, backup, replace=false) catch {
        error =>
          raise SkillsError(
            "cannot back up the installed skill \{id}: \{error}",
          )
      }
    }
    @fs.rename(staging, target, replace=false) catch {
      move_error => {
        if upgrading {
          @fs.rename(backup, target, replace=false) catch {
            restore_error =>
              raise SkillsError(
                "cannot activate skill \{id}: \{move_error}; restoring its backup also failed: \{restore_error}",
              )
          }
        }
        raise SkillsError("cannot activate skill \{id}: \{move_error}")
      }
    }
    on_committed()
  })
  if upgrading {
    // The new target is already authoritative. Cleanup failure is recoverable
    // and must not turn a successful install into a reported failure.
    @fs.remove(backup, recursive=true) catch {
      _ => ()
    }
  }
}

///|
/// Remove a live entry with one same-filesystem rename. Once it is under
/// `.trash`, readers and the engine no longer discover it; deletion is an
/// immediate best effort and `recover` retries any leftover.
async fn SkillLibrary::move_to_trash(
  self : SkillLibrary,
  id : String,
  on_committed? : () -> Unit,
) -> Unit {
  let target = self.target(id)
  let trash = self.trash(id)
  @fs.mkdir(self.child(TrashDirectory), recursive=true, allow_existing=true)
  @async.protect_from_cancel(() => {
    @fs.rename(target, trash, replace=false) catch {
      error => raise SkillsError("failed to uninstall skill \{id}: \{error}")
    }
    if on_committed is Some(callback) {
      callback()
    }
  })
  @fs.remove(trash, recursive=true) catch {
    _ => ()
  }
}
