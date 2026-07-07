// Applying a staged update and arranging the relaunch. macOS allows
// renaming a running .app — open files stay valid through their inodes —
// so the swap happens while the app is still up (the Sparkle approach):
// the old bundle moves aside within its own directory (a same-directory
// rename never crosses volumes), the staged bundle moves in, and the host
// then exits through the normal window-close path. `main` performs the
// actual relaunch after the run loop returns, so no orphan process is ever
// needed.

///|
/// Where the old bundle is parked during a swap; removed by
/// `cleanup_leftovers` on the next launch, once no process runs from it.
fn aside_path(bundle_path : String) -> String {
  bundle_path + ".old"
}

///|
/// The marker `main` consults after the run loop exits: present means
/// "relaunch this bundle". Written only after a successful swap.
fn relaunch_marker_path(work_dir : String) -> String {
  work_dir + "/relaunch"
}

///|
/// Swap the staged bundle into the running bundle's place. On a failed
/// move-in the old bundle is rolled back (clearing any partial copy the
/// failure left behind first); if even that fails, the raised error names
/// the parked copy instead of pretending the disk is intact.
pub async fn apply_staged(staged_app~ : String, bundle_path~ : String) -> Unit {
  guard @fs.exists(staged_app) else {
    raise UpdateError("the staged update disappeared; restart to try again")
  }
  let aside = aside_path(bundle_path)
  remove_tree(aside)
  @fs.rename(bundle_path, aside) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise UpdateError("cannot move the current app aside: \{error}")
  }
  // /bin/mv rather than rename: the staging directory may sit on another
  // volume than the bundle, and mv falls back to copying there.
  let code = @process.run("mv", [staged_app, bundle_path]) catch {
    error if @async.is_being_cancelled() => raise error
    error => raise move_in_failure(aside, bundle_path, "\{error}")
  }
  guard code == 0 else {
    raise move_in_failure(aside, bundle_path, "mv exited \{code}")
  }
}

///|
/// The error for a failed move-in, after attempting the rollback. When even
/// the rollback fails, the message says so and names the parked copy — the
/// app on disk is broken at that point, and pretending otherwise (the old
/// silent swallow) hid exactly the state the user must act on.
async fn move_in_failure(
  aside : String,
  bundle_path : String,
  reason : String,
) -> UpdateError {
  if restore_aside(aside, bundle_path) {
    UpdateError("cannot install the update: \{reason}")
  } else {
    UpdateError(
      "cannot install the update: \{reason} — and restoring the previous version failed; reinstall it from \{aside}",
    )
  }
}

///|
/// Roll the parked bundle back into place after a failed move-in, reporting
/// whether the original is back. A cross-volume mv that died mid-copy
/// leaves a partial bundle at the destination; that debris must go first,
/// or the rename-back itself fails on a non-empty directory. The partial
/// tree is always mv's leavings, never the original — the original was
/// renamed to `aside` before mv ran.
async fn restore_aside(aside : String, bundle_path : String) -> Bool {
  remove_tree(bundle_path)
  guard !@fs.exists(bundle_path) else { return false }
  @fs.rename(aside, bundle_path) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return false
  }
  true
}

///|
/// Record that `main` should relaunch the bundle once the run loop exits.
/// Failure is non-fatal — the swap already happened, the user just starts
/// the new version by hand.
pub async fn write_relaunch_marker(
  work_dir~ : String,
  bundle_path~ : String,
) -> Unit {
  @fs.write_file(
    relaunch_marker_path(work_dir),
    bundle_path,
    create_mode=CreateOrTruncate,
  ) catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
}

///|
/// Consume the relaunch marker: the bundle to reopen, or None. Reading
/// deletes it, so a crash before the relaunch cannot replay it forever.
pub async fn take_relaunch_target(work_dir~ : String) -> String? {
  let marker = relaunch_marker_path(work_dir)
  guard @fs.exists(marker) else { return None }
  let target = @fs.read_file(marker).text().trim().to_owned() catch {
      error if @async.is_being_cancelled() => raise error
      _ => return None
    }
  @fs.remove(marker) catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
  if target.is_empty() {
    None
  } else {
    Some(target)
  }
}

///|
/// Remove leftovers from a previous update on a best-effort basis: the
/// staging directory, a stale relaunch marker, and the aside bundle from
/// the last swap (safe even while the old instance is still exiting — its
/// inodes stay alive until it does).
pub async fn cleanup_leftovers(
  work_dir~ : String,
  bundle_path~ : String,
) -> Unit {
  remove_tree(staging_dir(work_dir))
  remove_tree(aside_path(bundle_path))
  @fs.remove(relaunch_marker_path(work_dir)) catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
}

///|
/// Remove a file or directory tree if present; quiet on failure — every
/// caller retries on its next run.
async fn remove_tree(path : String) -> Unit {
  if !@fs.exists(path) {
    return
  }
  if @fs.kind(path) is Directory {
    @fs.rmdir(path, recursive=true) catch {
      error if @async.is_being_cancelled() => raise error
      _ => ()
    }
  } else {
    @fs.remove(path) catch {
      error if @async.is_being_cancelled() => raise error
      _ => ()
    }
  }
}
