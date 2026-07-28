// Self-update ops, driven entirely by the webview: `check_update` asks the
// channel's manifest and reports what it found as data (never an op
// rejection — every outcome is a state the frontend renders); a user
// clicking Update runs `download_update` (fetch + verify into the staging
// dir) and then `apply_update` (swap the bundle and arrange the relaunch
// that `main` performs once the run loop exits). Nothing here runs on its
// own: the host's only startup involvement is sweeping leftovers of a
// previous update.

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
/// Sweep debris a previous update may have left behind (a staging dir, the
/// old bundle parked aside) — the host's only unprompted update work.
async fn cleanup_updates(state : UpdateState) -> Unit {
  if state.work_dir is Some(dir) && state.bundle_path is Some(bundle) {
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
async fn check_update_op(
  state : UpdateState,
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
    state.work_dir is Some(_) &&
    state.bundle_path is Some(bundle) {
    @update.self_update_unavailable_reason(bundle_path=bundle)
  } else {
    None
  }
  let installable = info.artifact is Some(_) &&
    state.work_dir is Some(_) &&
    state.bundle_path is Some(_) &&
    unavailable_reason is None
  Available(version=info.version, installable~, unavailable_reason~)
}

///|
/// Reply to `download_update`: the version now staged and verified.
priv struct DownloadUpdateReply {
  version : String
} derive(ToJson)

///|
/// Download and verify the channel's package, leaving it staged for
/// `apply_update`. Deliberately re-checks the manifest rather than trusting
/// what the frontend saw earlier — the release may have moved between the
/// check and the click. Failures raise: the frontend initiated this, so the
/// rejection message is the user-facing answer (and goes to the log too).
async fn download_update_op(
  state : UpdateState,
  payload : UpdateChannelPayload,
) -> DownloadUpdateReply {
  guard state.work_dir is Some(dir) && state.bundle_path is Some(bundle) else {
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
  let staged = @update.stage_update(info, work_dir=dir, bundle_path=bundle) catch {
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
  state.staged = Some(staged)
  { version: staged.version }
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
