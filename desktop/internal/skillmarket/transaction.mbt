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
/// One process-wide boundary for every view of the skills directory. Writers
/// hold it while recovering leftovers, staging, and switching the live entry;
/// readers hold it through their complete directory snapshot, so no client can
/// observe the short target-to-backup interval.
let library_lock : @async.Mutex = Mutex()

///|
/// Paths and recovery rules for one skills library. The hidden directories
/// themselves encode state; no separate transaction record is needed.
priv struct SkillLibrary {
  root : @path.Path
}

///|
fn SkillLibrary::target(self : SkillLibrary, id : String) -> @path.Path {
  self.root.join(id)
}

///|
fn SkillLibrary::staging(self : SkillLibrary, id : String) -> @path.Path {
  self.root.join(StagingDirectory).join(id)
}

///|
fn SkillLibrary::backup(self : SkillLibrary, id : String) -> @path.Path {
  self.root.join(BackupDirectory).join(id)
}

///|
fn SkillLibrary::trash(self : SkillLibrary, id : String) -> @path.Path {
  self.root.join(TrashDirectory).join(id)
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
/// The caller holds `library_lock`. Each action is repeatable, so cancellation
/// can stop recovery and the next library operation safely resumes it.
async fn SkillLibrary::recover(self : SkillLibrary) -> Unit {
  let backup_root = self.root.join(BackupDirectory)
  if @fsx.Directory::try_open(backup_root) is Some(dir) {
    for entry in dir.collect() {
      let id = entry.name()
      if !entry.is_dir() || !valid_slug(id) {
        continue
      }
      let backup = self.backup(id)
      let target = self.target(id)
      if @fsx.exists(target) {
        @fsx.rmdir(backup, recursive=true) catch {
          error if @async.is_being_cancelled() => raise error
          error =>
            raise SkillMarketError(
              "cannot clean the backup for skill \{id}: \{error}",
            )
        }
      } else {
        @fs.rename(backup.to_string(), target.to_string(), replace=false) catch {
          error if @async.is_being_cancelled() => raise error
          error =>
            raise SkillMarketError(
              "cannot restore the backup for skill \{id}: \{error}",
            )
        }
      }
    }
  }
  let staging_root = self.root.join(StagingDirectory)
  if @fsx.Directory::try_open(staging_root) is Some(dir) {
    for entry in dir.collect() {
      let id = entry.name()
      if !entry.is_dir() || !valid_slug(id) {
        continue
      }
      @fsx.rmdir(self.staging(id), recursive=true) catch {
        error if @async.is_being_cancelled() => raise error
        error =>
          raise SkillMarketError(
            "cannot clean the staged files for skill \{id}: \{error}",
          )
      }
    }
  }
  let trash_root = self.root.join(TrashDirectory)
  if @fsx.Directory::try_open(trash_root) is Some(dir) {
    for entry in dir.collect() {
      let id = entry.name()
      if !entry.is_dir() || !valid_slug(id) {
        continue
      }
      @fsx.rmdir(self.trash(id), recursive=true) catch {
        error if @async.is_being_cancelled() => raise error
        error =>
          raise SkillMarketError(
            "cannot clean the uninstalled skill \{id}: \{error}",
          )
      }
    }
  }
}

///|
/// Write one complete candidate without changing the live entry. Cancellation
/// or an I/O error may leave an incomplete staging directory; `recover`
/// removes it before any later read or mutation.
async fn SkillLibrary::stage(
  self : SkillLibrary,
  id : String,
  content : Bytes,
  provenance : String,
) -> Unit {
  let staging = self.staging(id)
  @fsx.ensure_dir(self.root.join(StagingDirectory))
  if @fsx.exists(staging) {
    @fsx.rmdir(staging, recursive=true)
  }
  @fsx.ensure_dir(staging)
  @fsx.write_bytes(staging.join("SKILL.md"), content)
  @fsx.write_text(staging.join(SidecarFile), provenance)
}

///|
/// Make a complete staged entry live. Only the short same-filesystem switch,
/// its rollback, and the synchronous invalidation callback are cancellation-
/// shielded. Downloading, staging, and old-backup cleanup remain cancellable.
async fn SkillLibrary::activate(
  self : SkillLibrary,
  id : String,
  on_committed? : () -> Unit,
) -> Unit {
  let target = self.target(id)
  let staging = self.staging(id)
  let backup = self.backup(id)
  let upgrading = @fsx.exists(target)
  if upgrading {
    @fsx.ensure_dir(self.root.join(BackupDirectory))
  }
  @async.protect_from_cancel(() => {
    if upgrading {
      @fs.rename(target.to_string(), backup.to_string(), replace=false) catch {
        error =>
          raise SkillMarketError(
            "cannot back up the installed skill \{id}: \{error}",
          )
      }
    }
    @fs.rename(staging.to_string(), target.to_string(), replace=false) catch {
      move_error => {
        if upgrading {
          @fs.rename(backup.to_string(), target.to_string(), replace=false) catch {
            restore_error =>
              raise SkillMarketError(
                "cannot activate skill \{id}: \{move_error}; restoring its backup also failed: \{restore_error}",
              )
          }
        }
        raise SkillMarketError("cannot activate skill \{id}: \{move_error}")
      }
    }
    if on_committed is Some(callback) {
      callback()
    }
  })
  if upgrading {
    // The new target is already authoritative. Cleanup failure is recoverable
    // and must not turn a successful install into a reported failure.
    @fsx.rmdir(backup, recursive=true) catch {
      error if @async.is_being_cancelled() => raise error
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
  @fsx.ensure_dir(self.root.join(TrashDirectory))
  @async.protect_from_cancel(() => {
    @fs.rename(target.to_string(), trash.to_string(), replace=false) catch {
      error =>
        raise SkillMarketError("failed to uninstall skill \{id}: \{error}")
    }
    if on_committed is Some(callback) {
      callback()
    }
  })
  @fsx.rmdir(trash, recursive=true) catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
}
