// Self-update orchestration. The check runs in the background of the
// app-lifetime connect task, so it never delays startup and its failures
// cannot take the engine pump down. When the manifest carries a package
// this build can install (macOS bundle, Developer ID signed), the host
// downloads and verifies it up front and announces `update_ready`; anything
// less ends at `update_available`, a purely informational nudge. The swap
// itself happens in the `apply_update` op; `main` performs the relaunch
// after the run loop exits, so no process ever outlives the host.

///|
/// What self-update needs to know about this installation, plus the staged
/// bundle once verification passed. `work_dir`/`bundle_path` are None for
/// dev binaries and non-macOS layouts, which pins the flow to the
/// informational fallback.
priv struct UpdateState {
  mut staged : @update.StagedUpdate?
  work_dir : String?
  bundle_path : String?
}

///|
fn new_update_state(
  runtime_dir : @path.Path?,
  executable : String?,
) -> UpdateState {
  {
    staged: None,
    work_dir: if runtime_dir is Some(dir) {
      Some(dir.to_string())
    } else {
      None
    },
    bundle_path: if executable is Some(exe) {
      app_bundle_path(exe)
    } else {
      None
    },
  }
}

///|
/// The `update_available` event: fallback announcement for builds that
/// cannot install the update themselves. Informational only.
priv struct UpdateAvailablePayload {
  version : String
} derive(ToJson)

///|
/// The `update_ready` event: a verified bundle is staged; clicking restarts
/// into it.
priv struct UpdateReadyPayload {
  version : String
} derive(ToJson)

///|
async fn announce_update(
  context : @app.AppCommandExtensionContext,
  state : UpdateState,
) -> Unit {
  if state.work_dir is Some(dir) && state.bundle_path is Some(bundle) {
    @update.cleanup_leftovers(work_dir=dir, bundle_path=bundle)
  }
  guard @update.check_for_update(current=@version.AppVersion) is Some(info) else {
    return
  }
  if info.artifact is Some(_) &&
    state.work_dir is Some(dir) &&
    state.bundle_path is Some(bundle) {
    let staged = @update.stage_update(info, work_dir=dir, bundle_path=bundle) catch {
      error if @async.is_being_cancelled() => raise error
      // Staging is opportunistic: a failed download or a signature that
      // does not check out downgrades to the informational announcement —
      // but the cause goes to openseek-desktop.log, or the degradation is
      // undiagnosable on exactly the installs where it matters.
      error => {
        @xlog.warn(category="update") <?
          {
            "event": "stage_failed",
            "version": info.version,
            "error": "\{error}",
          }
        announce_available(context, info)
        return
      }
    }
    state.staged = Some(staged)
    let payload : UpdateReadyPayload = { version: info.version }
    context.emit("update_ready", payload)
    return
  }
  announce_available(context, info)
}

///|
async fn announce_available(
  context : @app.AppCommandExtensionContext,
  info : @update.UpdateInfo,
) -> Unit {
  let payload : UpdateAvailablePayload = { version: info.version }
  context.emit("update_available", payload)
}

///|
/// Swap the staged bundle into place and arrange the relaunch. The reply
/// tells the frontend to close the window; the actual reopen happens in
/// `main` once the run loop has exited.
async fn apply_update_op(state : UpdateState) -> ApplyUpdateReply {
  guard state.staged is Some(staged) &&
    state.work_dir is Some(dir) &&
    state.bundle_path is Some(bundle) else {
    raise HostError("No update is staged")
  }
  @update.apply_staged(staged_app=staged.app_path, bundle_path=bundle) catch {
    @update.UpdateError(message) => raise HostError(message)
    error => raise error
  }
  state.staged = None
  @update.write_relaunch_marker(work_dir=dir, bundle_path=bundle)
  { applied: true }
}
