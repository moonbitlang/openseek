// Self-update ops, driven entirely by the webview: `check_update` asks the
// channel's manifest and reports what it found as data (never an op
// rejection — every outcome is a state the frontend renders); the page
// hands one download at a time to the app-lifetime pump (it starts one by
// itself once a check reports an installable release), which fetches +
// verifies into the staging dir and reports progress and completion as
// `update.*` notifications, each stamped with the channel it serves so the
// page can void events from a channel the user has since left; the
// `update.downloaded` notification leaves the
// release staged until the user asks the page to run `apply_update` (swap
// the bundle and arrange the relaunch that `main` performs once the run
// loop exits). The download cannot live in its `op_async` request: Proton
// cancels any bridge request that exceeds its finite request deadline.

///|
/// Self-update state shared by request tasks and the app-lifetime download
/// pump. The async runtime is single-threaded and cooperative, so any
/// check-and-set on these fields that contains no suspension point is atomic;
/// `busy` is the sole serializer of downloads and applies, which consume the
/// same staging dir and bundle path.
priv struct SelfUpdate {
  work_dir : String?
  bundle_path : String?
  // At most one payload is ever buffered: `busy` flips in the same atomic
  // step as the enqueue and clears only when the pump finished the download.
  downloads : @async.Queue[UpdateChannelPayload]
  mut staged : @update.StagedUpdate?
  mut busy : Bool
}

///|
fn SelfUpdate::new(
  runtime_dir : @path.Path?,
  executable : String?,
) -> SelfUpdate {
  {
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
/// The channel half of `check_update` / `download_update`. Anything but the
/// literal "staging" reads as production, so a stale stored value can only
/// fall back to the safe default.
priv struct UpdateChannelPayload {
  channel : String?
} derive(FromJson)

///|
fn UpdateChannelPayload::to_channel(
  self : UpdateChannelPayload,
) -> @update.UpdateChannel {
  match self.channel {
    Some("staging") => Staging
    _ => Production
  }
}

///|
/// The canonical wire name of the channel this payload resolves to — what
/// the pump stamps on its notifications, normalized rather than echoed so a
/// stale stored value cannot leak an unknown channel name back to the page.
fn UpdateChannelPayload::wire_channel(self : UpdateChannelPayload) -> String {
  match self.to_channel() {
    Staging => "staging"
    Production => "production"
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
priv enum CheckUpdateReply {
  UpToDate
  Available(
    version~ : String,
    installable~ : Bool,
    unavailable_reason~ : String?
  )
  Unreachable(reason~ : String)
  Malformed(reason~ : String)
  Broken(version~ : String, reason~ : String)
}

///|
impl ToJson for CheckUpdateReply with fn to_json(self) {
  match self {
    UpToDate => { "kind": "up_to_date" }
    Available(version~, installable~, unavailable_reason~) => {
      let unavailable_reason = match unavailable_reason {
        Some(reason) => Json::string(reason)
        None => Json::null()
      }
      {
        "kind": "available",
        "version": version,
        "installable": installable,
        "unavailable_reason": unavailable_reason,
      }
    }
    Unreachable(reason~) => { "kind": "unreachable", "reason": reason }
    Malformed(reason~) => { "kind": "malformed", "reason": reason }
    Broken(version~, reason~) =>
      { "kind": "broken", "version": version, "reason": reason }
  }
}

///|
/// Ask the channel's manifest for a newer release. `installable` reports
/// whether `download_update` would work here: a real signed .app bundle in a
/// replaceable location, with a package published for this platform. Only a
/// failed installation preflight carries `unavailable_reason`; a platform
/// without a package remains the existing informational fallback.
async fn SelfUpdate::check(
  self : SelfUpdate,
  payload : UpdateChannelPayload,
) -> CheckUpdateReply {
  let info = @update.check_for_update(
    current=@version.AppVersion,
    channel=payload.to_channel(),
  ) catch {
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
  let unavailable_reason = if info.artifact is Some(_) &&
    self.work_dir is Some(_) &&
    self.bundle_path is Some(bundle) {
    @update.self_update_unavailable_reason(bundle_path=bundle)
  } else {
    None
  }
  let installable = info.artifact is Some(_) &&
    self.work_dir is Some(_) &&
    self.bundle_path is Some(_) &&
    unavailable_reason is None
  Available(version=info.version, installable~, unavailable_reason~)
}

///|
/// The immediate `update.download` reply. Completion arrives separately as
/// `update.downloaded` or `update.download_failed` from the host-owned pump.
priv struct DownloadUpdateAcceptedReply {
  accepted : Bool
} derive(ToJson)

///|
/// Reply carried by `update.downloaded`: the version now staged and
/// verified, and the channel that download served.
priv struct DownloadUpdateReply {
  version : String
  channel : String
} derive(ToJson)

///|
/// Bytes received for the active package. `total_bytes` is absent only when
/// the server omitted a usable Content-Length header.
priv struct DownloadUpdateProgress {
  downloaded_bytes : Int
  total_bytes : Int?
  channel : String
}

///|
fn DownloadUpdateProgress::to_json(self : DownloadUpdateProgress) -> Json {
  {
    "downloaded_bytes": Json::number(self.downloaded_bytes.to_double()),
    "total_bytes": match self.total_bytes {
      Some(total) => Json::number(total.to_double())
      None => Json::null()
    },
    "channel": Json::string(self.channel),
  }
}

///|
/// Accept one download for the app-lifetime pump, or say why not. The
/// decision, the `busy` flip, and the enqueue contain no suspension point, so
/// acceptance can neither race another request nor strand an accepted
/// download when this request is cancelled right after replying.
fn SelfUpdate::start_download(
  self : SelfUpdate,
  payload : UpdateChannelPayload,
) -> DownloadUpdateAcceptedReply raise {
  guard self.work_dir is Some(_) && self.bundle_path is Some(_) else {
    raise HostError("this build cannot install updates")
  }
  guard !self.busy else { raise HostError("an update is already in progress") }
  self.busy = true
  let enqueued = self.downloads.try_put(payload) catch { _ => false }
  guard enqueued else {
    // The pump has stopped and closed its queue; reject rather than parking
    // `busy` on work nobody will perform.
    self.busy = false
    raise HostError("self-update is unavailable")
  }
  { accepted: true }
}

///|
/// Download and verify the channel's package, leaving it staged for
/// `apply_update`. Deliberately re-checks the manifest rather than trusting
/// what the frontend saw earlier — the release may have moved between the
/// check and the click. Progress notifications are emitted straight from the
/// downloader's throttled callback, so they cannot overtake completion.
async fn SelfUpdate::download_package(
  self : SelfUpdate,
  payload : UpdateChannelPayload,
  emit : async (String, Json) -> Unit,
) -> @update.StagedUpdate {
  guard self.work_dir is Some(dir) && self.bundle_path is Some(bundle) else {
    raise HostError("this build cannot install updates")
  }
  let info = @update.check_for_update(
    current=@version.AppVersion,
    channel=payload.to_channel(),
  ) catch {
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
    let progress : DownloadUpdateProgress = {
      downloaded_bytes,
      total_bytes,
      channel: payload.wire_channel(),
    }
    emit("update.download_progress", progress.to_json())
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
  emit : async (String, Json) -> Unit,
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
    let payload = self.downloads.get()
    try self.download_package(payload, emit) catch {
      error if @async.is_being_cancelled() => raise error
      error => {
        self.busy = false
        let message = if error is HostError(message) {
          message
        } else {
          "\{error}"
        }
        emit("update.download_failed", {
          "message": Json::string(message),
          "channel": Json::string(payload.wire_channel()),
        })
      }
    } noraise {
      staged => {
        self.staged = Some(staged)
        self.busy = false
        let reply : DownloadUpdateReply = {
          version: staged.version,
          channel: payload.wire_channel(),
        }
        emit("update.downloaded", ToJson::to_json(reply))
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
  { applied: true }
}

///|
test "self-update accepts one download and rejects a second" {
  let updates : SelfUpdate = {
    work_dir: Some("/runtime"),
    bundle_path: Some("/Applications/OpenSeek Desktop.app"),
    downloads: Queue(kind=Blocking(1)),
    staged: None,
    busy: false,
  }
  assert_true(updates.start_download({ channel: None }).accepted)
  assert_true(updates.busy)
  assert_true(updates.downloads.try_get() is Some(_))
  let mut rejected = false
  ignore(updates.start_download({ channel: None })) catch {
    HostError(message) =>
      rejected = message == "an update is already in progress"
    error => raise error
  }
  assert_true(rejected)
}

///|
test "self-update rejects downloads unsupported by this build" {
  let updates = SelfUpdate::new(None, None)
  let mut rejected = false
  ignore(updates.start_download({ channel: None })) catch {
    HostError(message) =>
      rejected = message == "this build cannot install updates"
    error => raise error
  }
  assert_true(rejected)
  assert_false(updates.busy)
}

///|
async test "self-update pump reports download failures" {
  let updates = SelfUpdate::new(None, None)
  let events : @async.Queue[(String, Json)] = Queue(kind=Blocking(1))
  @async.with_task_group(group => {
    group.spawn_bg(allow_failure=true, () => {
      updates.run(async fn(method_, params) { events.put((method_, params)) })
    })
    // Bypass `start_download` so even this unsupported build reaches the
    // pump's failure path deterministically, with no network involved.
    updates.downloads.put({ channel: None })
    let (method_, params) = @async.with_timeout(1000, () => events.get())
    assert_eq(method_, "update.download_failed")
    assert_true(
      params is { "message": String("this build cannot install updates"), .. },
    )
    // The failure names its channel so the page can void it after a switch.
    assert_true(params is { "channel": String("production"), .. })
    group.return_immediately(())
  })
}

///|
async test "self-update apply refuses while a download is active" {
  let updates : SelfUpdate = {
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

///|
test "download progress serializes an optional total" {
  let known : DownloadUpdateProgress = {
    downloaded_bytes: 42,
    total_bytes: Some(100),
    channel: "staging",
  }
  assert_true(
    known.to_json()
    is {
      "downloaded_bytes": Number(42.0, ..),
      "total_bytes": Number(100.0, ..),
      "channel": String("staging"),
      ..
    },
  )
  let unknown : DownloadUpdateProgress = {
    downloaded_bytes: 42,
    total_bytes: None,
    channel: "production",
  }
  assert_true(unknown.to_json() is { "total_bytes": Null, .. })
}
