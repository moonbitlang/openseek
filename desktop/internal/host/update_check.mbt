// Self-update ops, driven entirely by the webview: `check_update` asks the
// release manifest and reports what it found as data (never an op
// rejection — every outcome is a state the frontend renders); a user
// clicking Update hands one download to the app-lifetime pump, which fetches
// + verifies into the staging dir and reports progress and completion as
// `update.*` notifications; the `update.downloaded` notification then lets
// the page run `apply_update` (swap the bundle and arrange the relaunch that
// `main` performs once the run loop exits). The download cannot live in its
// `op_async` request: Proton cancels any bridge request that exceeds its
// finite request deadline.

///|
/// Self-update state shared by request tasks and the app-lifetime download
/// pump. The async runtime is single-threaded and cooperative, so any
/// check-and-set on these fields that contains no suspension point is atomic;
/// `busy` is the sole serializer of downloads and applies, which consume the
/// same staging dir and bundle path.
priv struct SelfUpdate {
  // The installed version comes from Proton's package manifest, not source.
  app_version : String
  work_dir : String?
  bundle_path : String?
  // At most one download is ever buffered: `busy` flips in the same atomic
  // step as the enqueue and clears only when the pump finished the download.
  downloads : @async.Queue[Unit]
  mut staged : @update.StagedUpdate?
  mut busy : Bool
}

///|
fn SelfUpdate::SelfUpdate(
  runtime_dir : @pathx.Path?,
  executable : String?,
  app_version? : String = "development",
) -> SelfUpdate {
  {
    app_version,
    work_dir: runtime_dir.map(dir => dir.to_string()),
    bundle_path: executable.bind(app_bundle_path),
    downloads: Queue(kind=Blocking(1)),
    staged: None,
    busy: false,
  }
}

///|
/// Sweep debris a previous update may have left behind (a staging dir, the
/// old bundle parked aside) — the host's only unprompted update work.
async fn SelfUpdate::cleanup(self : SelfUpdate) -> Unit {
  if self.work_dir is Some(dir) && self.bundle_path is Some(bundle) {
    @update.cleanup_leftovers(work_dir=dir, bundle_path=bundle)
  }
}

///|
/// Reply to `check_update`, discriminated on the wire by a `kind` field.
/// Every outcome is data — the op only rejects on cancellation — because
/// each kind is worth a different amount of noise: `broken` can only be the
/// publisher's fault (toast material), `malformed` also happens under
/// captive portals (log material), `unreachable` is routine offline life.
/// An available release carries an optional actionable reason when this
/// installation itself cannot be replaced.
type CheckUpdateReply = @protocol.CheckUpdateReply

///|
/// Ask the release manifest for a newer release. `installable` reports
/// whether `download_update` would work here: a real signed .app bundle in a
/// replaceable location, with a package published for this platform. Only a
/// failed installation preflight carries `unavailable_reason`; a platform
/// without a package remains the existing informational fallback.
async fn SelfUpdate::check(self : SelfUpdate) -> CheckUpdateReply {
  let info = @update.check_for_update(current=self.app_version) catch {
    @update.Unreachable(reason~) => return Unreachable(reason~)
    @update.MalformedManifest(reason~) => {
      @xlog.warn(category="update") <?
        { "event": "manifest_malformed", "error": reason }
      return Malformed(reason~)
    }
    @update.MalformedArtifact(version~, reason~) => {
      @xlog.warn(category="update") <?
        {
          "event": "manifest_artifact_malformed",
          "version": version,
          "error": reason,
        }
      return Broken(version~, reason~)
    }
    error => raise error
  }
  guard info is Some(info) else { return UpToDate }
  let (installable, unavailable_reason) = if info.artifact is Some(_) &&
    self.work_dir is Some(_) &&
    self.bundle_path is Some(bundle) {
    let reason = @update.self_update_unavailable_reason(bundle_path=bundle)
    (reason is None, reason)
  } else {
    (false, None)
  }
  Available(version=info.version, installable~, unavailable_reason~)
}

///|
/// The immediate `update.download` reply. Completion arrives separately as
/// `update.downloaded` or `update.download_failed` from the host-owned pump.
type DownloadUpdateAcceptedReply = @protocol.DownloadUpdateAcceptedReply

///|
/// Accept one download for the app-lifetime pump, or say why not. The
/// decision, the `busy` flip, and the enqueue contain no suspension point, so
/// acceptance can neither race another request nor strand an accepted
/// download when this request is cancelled right after replying.
fn SelfUpdate::start_download(
  self : SelfUpdate,
) -> DownloadUpdateAcceptedReply raise {
  guard self.work_dir is Some(_) && self.bundle_path is Some(_) else {
    raise HostError("this build cannot install updates")
  }
  guard !self.busy else { raise HostError("an update is already in progress") }
  self.busy = true
  let enqueued = self.downloads.try_put(()) catch { _ => false }
  guard enqueued else {
    // The pump has stopped and closed its queue; reject rather than parking
    // `busy` on work nobody will perform.
    self.busy = false
    raise HostError("self-update is unavailable")
  }
  { accepted: true, }
}

///|
/// Download and verify the release package, leaving it staged for
/// `apply_update`. Deliberately re-checks the manifest rather than trusting
/// what the frontend saw earlier — the release may have moved between the
/// check and the click. Progress notifications are emitted straight from the
/// downloader's throttled callback, so they cannot overtake completion.
async fn SelfUpdate::download_package(
  self : SelfUpdate,
  emit : async (@protocol.Notification) -> Unit,
) -> @update.StagedUpdate {
  guard self.work_dir is Some(dir) && self.bundle_path is Some(bundle) else {
    raise HostError("this build cannot install updates")
  }
  let info = @update.check_for_update(current=self.app_version) catch {
    @update.Unreachable(reason~) => raise HostError(reason)
    @update.MalformedManifest(reason~) => raise HostError(reason)
    @update.MalformedArtifact(reason~, ..) => raise HostError(reason)
    error => raise error
  }
  guard info is Some(info) else {
    raise HostError("no newer release is published")
  }
  let staged = @update.stage_update(info, work_dir=dir, bundle_path=bundle, on_progress=async fn(
    downloaded_bytes,
    total_bytes,
  ) {
    emit(UpdateDownloadProgress({ downloaded_bytes, total_bytes, }))
  }) catch {
    error if @async.is_being_cancelled() => raise error
    error => {
      @xlog.warn(category="update") <?
        {
          "event": "stage_failed",
          "version": info.version,
          "error": "\{error}",
        }
      raise match error {
        @update.UpdateError(message) => HostError(message)
        _ => HostError("\{error}")
      }
    }
  }
  staged
}

///|
/// The app-lifetime pump: sweep leftovers once, then perform accepted
/// downloads one at a time and report each outcome as a notification. Only
/// this task downloads and installs staged state, so `busy` stays true from
/// acceptance until the matching completion notification.
async fn SelfUpdate::run(
  self : SelfUpdate,
  emit : async (@protocol.Notification) -> Unit,
) -> Unit {
  // A closed queue turns later `update.download` requests into rejections
  // instead of accepted work nobody will perform.
  defer self.downloads.close()
  self.cleanup() catch {
    error if @async.is_being_cancelled() => raise error
    error =>
      @xlog.warn(category="update") <?
        { "event": "cleanup_failed", "error": "\{error}" }
  }
  for ;; {
    self.downloads.get()
    try self.download_package(emit) catch {
      error if @async.is_being_cancelled() => raise error
      error => {
        self.busy = false
        let message = if error is HostError(message) {
          message
        } else {
          "\{error}"
        }
        emit(UpdateDownloadFailed({ message, }))
      }
    } noraise {
      staged => {
        self.staged = Some(staged)
        self.busy = false
        emit(UpdateDownloaded({ version: staged.version, }))
      }
    }
  }
}

///|
/// Swap the staged bundle into place and arrange the relaunch. The reply
/// tells the frontend to close the window; the actual reopen happens in
/// `main` once the run loop has exited. `busy` covers the swap so no download
/// can start while the staging dir and bundle path are being consumed.
async fn SelfUpdate::apply(self : SelfUpdate) -> ApplyUpdateReply {
  guard !self.busy else {
    raise HostError("an update download is still in progress")
  }
  guard self.staged is Some(staged) &&
    self.work_dir is Some(dir) &&
    self.bundle_path is Some(bundle) else {
    raise HostError("No update is staged")
  }
  self.busy = true
  defer {
    self.busy = false
  }
  // Once the running bundle can move to `.old`, finish the swap and marker
  // even if app shutdown starts. Otherwise cancellation during `mv` bypasses
  // rollback and can leave no launchable bundle at the original path.
  @async.protect_from_cancel(() => {
    @update.apply_staged(staged_app=staged.app_path, bundle_path=bundle) catch {
      @update.UpdateError(message) => raise HostError(message)
      error => raise error
    }
    self.staged = None
    @update.write_relaunch_marker(work_dir=dir, bundle_path=bundle)
  })
  { applied: true, }
}

///|
test "self-update accepts one download and rejects a second" {
  let updates : SelfUpdate = {
    app_version: "0.1.0",
    work_dir: Some("/runtime"),
    bundle_path: Some("/Applications/OpenSeek Desktop.app"),
    downloads: Queue(kind=Blocking(1)),
    staged: None,
    busy: false,
  }
  assert_true(updates.start_download().accepted)
  assert_true(updates.busy)
  assert_true(updates.downloads.try_get() is Some(_))
  let mut rejected = false
  ignore(updates.start_download()) catch {
    HostError(message) =>
      rejected = message == "an update is already in progress"
    error => raise error
  }
  assert_true(rejected)
}

///|
test "self-update rejects downloads unsupported by this build" {
  let updates = SelfUpdate::SelfUpdate(None, None)
  let mut rejected = false
  ignore(updates.start_download()) catch {
    HostError(message) =>
      rejected = message == "this build cannot install updates"
    error => raise error
  }
  assert_true(rejected)
  assert_false(updates.busy)
}

///|
async test "self-update pump reports download failures" {
  let updates = SelfUpdate::SelfUpdate(None, None)
  let events : @async.Queue[@protocol.Notification] = Queue(kind=Blocking(1))
  @async.with_task_group(group => {
    group.spawn_bg(allow_failure=true, () => {
      updates.run(async fn(notification) { events.put(notification) })
    })
    // Bypass `start_download` so even this unsupported build reaches the
    // pump's failure path deterministically, with no network involved.
    updates.downloads.put(())
    let notification = @async.with_timeout(1000, () => events.get())
    assert_eq(notification.wire_name(), "update.download_failed")
    let params = notification.params()
    assert_true(
      params is { "message": String("this build cannot install updates"), .. },
    )
    group.return_immediately(())
  })
}

///|
async test "self-update apply refuses while a download is active" {
  let updates : SelfUpdate = {
    app_version: "0.1.0",
    work_dir: Some("/runtime"),
    bundle_path: Some("/Applications/OpenSeek Desktop.app"),
    downloads: Queue(kind=Blocking(1)),
    staged: None,
    busy: false,
  }
  let mut no_staged = false
  ignore(updates.apply()) catch {
    HostError(message) => no_staged = message == "No update is staged"
    error => raise error
  }
  assert_true(no_staged)
  updates.busy = true
  let mut still_downloading = false
  ignore(updates.apply()) catch {
    HostError(message) =>
      still_downloading = message == "an update download is still in progress"
    error => raise error
  }
  assert_true(still_downloading)
}
