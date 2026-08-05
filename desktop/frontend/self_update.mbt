// The self-update flow, driven from this side: the app asks `check_update`
// when the authoritative settings first load, again whenever the update
// channel moves, and whenever the user asks in Settings; it starts
// `download_update` by itself as soon as a check reports an installable
// release. The staged download then waits in `UpdateReady` until the user
// asks to restart — confirming first when a conversation would be
// interrupted — and only that click walks `apply_update` → window close.

///|
/// Which release stream `check_update` asks. Derived from the server
/// selection (`ApiProvider::update_channel`): the staging server serves
/// staging builds.
priv enum UpdateChannel {
  Production
  Staging
} derive(Eq)

///|
fn UpdateChannel::wire(self : UpdateChannel) -> String {
  match self {
    Production => "production"
    Staging => "staging"
  }
}

///|
/// The inverse of `wire`, for the channel tag the host stamps on its
/// download notifications. An unknown name reads as `None` — an untagged
/// event, which the handlers accept rather than fence.
fn UpdateChannel::from_wire(wire : String) -> UpdateChannel? {
  match wire {
    "production" => Some(Production)
    "staging" => Some(Staging)
    _ => None
  }
}

///|
/// Byte progress for the package currently being downloaded. The total is
/// optional because HTTP permits responses without Content-Length.
priv struct UpdateDownloadProgress {
  downloaded_bytes : Int
  total_bytes : Int?
} derive(Eq)

///|
fn UpdateDownloadProgress::percentage(self : UpdateDownloadProgress) -> Int? {
  match self.total_bytes {
    Some(total) if total > 0 =>
      Some(
        @cmp.minimum(
          100,
          (self.downloaded_bytes.to_double() * 100.0 / total.to_double()).to_int(),
        ),
      )
    _ => None
  }
}

///|
fn UpdateDownloadProgress::status_text(
  self : UpdateDownloadProgress,
  version : String,
) -> String {
  match (self.percentage(), self.total_bytes) {
    (Some(percent), Some(total)) => {
      let downloaded_mb = self.downloaded_bytes / (1024 * 1024)
      let total_mb = @cmp.maximum(1, total / (1024 * 1024))
      "Downloading \{version}… \{percent}% (\{downloaded_mb} / \{total_mb} MB)"
    }
    _ if self.downloaded_bytes > 0 =>
      "Downloading \{version}… \{self.downloaded_bytes / (1024 * 1024)} MB"
    _ => "Downloading \{version}…"
  }
}

///|
fn UpdateDownloadProgress::sidebar_label(
  self : UpdateDownloadProgress,
) -> String {
  match self.percentage() {
    Some(percent) => "Downloading \{percent}%"
    None => "Downloading…"
  }
}

///|
test "update download progress labels known and unknown totals" {
  let known : UpdateDownloadProgress = {
    downloaded_bytes: 50 * 1024 * 1024,
    total_bytes: Some(100 * 1024 * 1024),
  }
  assert_eq(known.percentage(), Some(50))
  assert_eq(known.sidebar_label(), "Downloading 50%")
  assert_eq(
    known.status_text("0.2.0"),
    "Downloading 0.2.0… 50% (50 / 100 MB)",
  )
  let unknown : UpdateDownloadProgress = {
    downloaded_bytes: 3 * 1024 * 1024,
    total_bytes: None,
  }
  assert_eq(unknown.percentage(), None)
  assert_eq(unknown.sidebar_label(), "Downloading…")
  assert_eq(unknown.status_text("0.2.0"), "Downloading 0.2.0… 3 MB")
}

///|
/// Where the self-update flow stands. Who asked (the user from Settings or
/// the app at startup) travels with the request instead — `explicit` on
/// `UpdateCheckFinished` — since it is a property of the reply's routing,
/// not of the state.
priv enum UpdateUx {
  UpdateUnknown
  CheckingForUpdate
  UpToDate
  // A newer release; `installable` gates whether a download can start — a
  // dev binary or a platform without a package only gets the announcement.
  // Installable releases download themselves straight from the check, so
  // this state is the resting point after a failed download, where the
  // accent button offers a retry.
  UpdateAvailable(version~ : String, installable~ : Bool)
  // A download in flight — started by the app itself right after a check,
  // or by a retry click on the restored offer. `channel` is the one the
  // download serves: notifications tagged with another channel are void,
  // and a channel no longer matching the provider's marks the flow as
  // draining — kept only until its terminal event, whose result is
  // discarded in favor of a fresh check.
  DownloadingUpdate(
    version~ : String,
    progress~ : UpdateDownloadProgress,
    channel~ : UpdateChannel
  )
  // Downloaded and staged; restarting is the user's call.
  UpdateReady(version~ : String)
  // The modal asking to interrupt running conversations is up.
  ConfirmingRestart(version~ : String)
  // The bundle is swapped; the window is about to close.
  RestartingForUpdate(version~ : String)
  // What the Settings row shows when a check could not answer.
  UpdateCheckFailed(message~ : String)
} derive(Eq)

///|
/// A decoded `check_update` reply. Kinds mirror the wire contract; see the
/// host's `CheckUpdateReply` for what each means and how loud it deserves
/// to be. `unavailable_reason` is present only when this installation failed
/// the host's replacement preflight; package-less platforms stay quiet.
priv enum UpdateCheck {
  CheckUpToDate
  CheckFound(
    version~ : String,
    installable~ : Bool,
    unavailable_reason~ : String?
  )
  CheckUnreachable(reason~ : String)
  CheckMalformed(reason~ : String)
  CheckBroken(version~ : String, reason~ : String)
}

///|
fn decode_update_check(text : String) -> UpdateCheck? {
  // Every kind's fields are unconditional on the wire; a reply missing one
  // is malformed and reads as `None` (the caller folds that into
  // `CheckUnreachable`).
  let json = @json.parse(text) catch { _ => return None }
  guard json is Object(reply) else { return None }
  let reason = @jsonx.json_text(reply, "reason")
  guard @jsonx.json_text(reply, "kind") is Some(kind) else { return None }
  match kind {
    "up_to_date" => Some(CheckUpToDate)
    "available" => {
      guard @jsonx.json_text(reply, "version") is Some(version) &&
        @jsonx.json_bool(reply, "installable") is Some(installable) else {
        return None
      }
      Some(
        CheckFound(
          version~,
          installable~,
          unavailable_reason=@jsonx.json_text(reply, "unavailable_reason"),
        ),
      )
    }
    "unreachable" => reason.map(reason => CheckUnreachable(reason~))
    "malformed" => reason.map(reason => CheckMalformed(reason~))
    "broken" => {
      guard @jsonx.json_text(reply, "version") is Some(version) &&
        reason is Some(reason) else {
        return None
      }
      Some(CheckBroken(version~, reason~))
    }
    _ => None
  }
}

///|
/// Ask the host to check the channel's manifest. Every outcome lands in
/// `UpdateCheckFinished` carrying the channel it asked — the reply's
/// validity is bound to that channel, not to whichever one is in force when
/// it lands. Op failures (bridge missing, host error) fold into
/// `CheckUnreachable`, so the handler has one shape to route.
fn check_for_updates(
  dispatch : @cmd.Emit[Msg],
  channel : UpdateChannel,
  explicit~ : Bool,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let payload = @js.Object::new()
      payload["channel"] = channel.wire()
      let result = try {
        // Self-update always targets the page's own desktop host, never a
        // focused remote device.
        let reply = @interop.bridge_request(
          Local,
          "update.check",
          payload.to_value(),
        )
        match decode_update_check(@interop.reply_json_text(reply)) {
          Some(result) => result
          None => CheckUnreachable(reason="the host answered unintelligibly")
        }
      } catch {
        error => CheckUnreachable(reason=@interop.bridge_error_text(error))
      }
      scheduler.add(dispatch(UpdateCheckFinished(result~, channel~, explicit~)))
    })
  })
}

///|
/// Drop whatever the update flow knew and quietly ask the channel now in
/// force — the shared tail of every path that voids the old channel's
/// answer (a provider switch, a drained download settling). A browser page
/// only forgets: checking is the desktop window's alone.
fn forget_and_recheck(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> (@cmd.Cmd, Model) {
  (
    if model.is_desktop {
      check_for_updates(
        dispatch,
        model.api_provider.update_channel(),
        explicit=false,
      )
    } else {
      @cmd.none
    },
    { ..model, update_ux: UpdateUnknown },
  )
}

///|
/// The follow-through after any event that can move the authoritative
/// update channel: the first host-settings load, a provider switch in
/// Settings, a remote edit landing, a failed save restoring the old
/// provider. The moment the channel is known — or moves — whatever the old
/// channel's check said no longer applies: forget it and quietly check the
/// channel now in force. Carve-outs, in order: a download in flight keeps
/// the host pump busy, so the flow stays put and merely turns stale (its
/// own channel no longer matches the provider's); its terminal event
/// performs the deferred forget-and-recheck. An apply in flight is past
/// interfering with — the window is about to close either way. A staged
/// release survives a settings reload that kept the channel, but a move
/// voids it: the pump is idle after staging, so the re-check runs at once.
fn recheck_update_channel(
  dispatch : @cmd.Emit[Msg],
  before : Model,
  next : Model,
) -> (@cmd.Cmd, Model) {
  let channel = next.api_provider.update_channel()
  let became_known = !before.host_settings_loaded() &&
    next.host_settings_loaded()
  let moved = channel != before.api_provider.update_channel()
  guard became_known || moved else { return (@cmd.none, next) }
  match next.update_ux {
    DownloadingUpdate(..) | RestartingForUpdate(..) => (@cmd.none, next)
    UpdateReady(..) | ConfirmingRestart(..) =>
      if moved {
        forget_and_recheck(dispatch, next)
      } else {
        (@cmd.none, next)
      }
    _ => forget_and_recheck(dispatch, next)
  }
}

///|
/// Ask the host-owned update actor to download and verify the channel's package.
/// A successful reply only means the work was accepted; `update.downloaded`
/// triggers `UpdateDownloaded` after staging, and `update.download_failed`
/// carries a background failure.
fn download_update(
  dispatch : @cmd.Emit[Msg],
  channel : UpdateChannel,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let payload = @js.Object::new()
      payload["channel"] = channel.wire()
      let _ : @js.Value = @interop.bridge_request(
        Local,
        "update.download",
        payload.to_value(),
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              UpdateFailed(
                message=@interop.bridge_error_text(error),
                channel=Some(channel),
              ),
            ),
          )
          return
        }
      }
    })
  })
}

///|
/// Whether restarting now would cut a conversation off mid-run.
fn Model::any_conversation_busy(self : Model) -> Bool {
  self.conversations
  .iter()
  .any(conv => conv.is_running() || !(conv.compaction is NotCompacting))
}
