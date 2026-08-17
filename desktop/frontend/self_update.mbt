// The self-update flow, driven from this side: the app asks `check_update`
// once at startup (and whenever the user asks in Settings), shows an accent
// Update button while a release is installable, and on click walks
// `download_update` → `apply_update` → window close, confirming first when
// a conversation would be interrupted. The update manifest lives on the
// SeekMoon origin; there is one release stream, so the requests carry no
// parameters (the update channel went with the Settings server selector).

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
  // A newer release; `installable` gates the accent Update button — a dev
  // binary or a platform without a package only gets the announcement.
  UpdateAvailable(version~ : String, installable~ : Bool)
  // The modal asking to interrupt running conversations is up.
  ConfirmingRestart(version~ : String)
  DownloadingUpdate(version~ : String, progress~ : UpdateDownloadProgress)
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
fn UpdateCheck::from_reply(reply : @protocol.CheckUpdateReply) -> UpdateCheck {
  match reply {
    @protocol.UpToDate => CheckUpToDate
    @protocol.Available(version~, installable~, unavailable_reason~) =>
      CheckFound(version~, installable~, unavailable_reason~)
    @protocol.Unreachable(reason~) => CheckUnreachable(reason~)
    @protocol.Malformed(reason~) => CheckMalformed(reason~)
    @protocol.Broken(version~, reason~) => CheckBroken(version~, reason~)
  }
}

///|
/// Read immutable installed-package metadata from the desktop host. This is a
/// separate operation from settings because changing a preference must never
/// change the version shown by the application.
fn Model::fetch_app_info(self : Model, dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  guard self.is_desktop else { return @cmd.none }
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(
        Local,
        @commands.app_info,
        @protocol.EmptyPayload::NoPayload,
      ) catch {
        _ => return
      }
      scheduler.add(dispatch(AppInfoLoaded(reply.version)))
    })
  })
}

///|
/// Ask the host to check the release manifest. Every outcome lands in
/// `UpdateCheckFinished`: op failures (bridge missing, host error) fold
/// into `CheckUnreachable`, so the handler has one shape to route.
fn check_for_updates(dispatch : @cmd.Emit[Msg], explicit~ : Bool) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let result = try {
        // Self-update always targets the page's own desktop host, never a
        // focused remote device.
        let reply = @interop.bridge_request(
          Local,
          @commands.update_check,
          @protocol.EmptyPayload::NoPayload,
        )
        UpdateCheck::from_reply(reply)
      } catch {
        error => CheckUnreachable(reason=@interop.bridge_error_text(error))
      }
      scheduler.add(dispatch(UpdateCheckFinished(result~, explicit~)))
    })
  })
}

///|
/// Ask the host-owned update actor to download and verify the release
/// package. A successful reply only means the work was accepted;
/// `update.downloaded` triggers `UpdateDownloaded` after staging, and
/// `update.download_failed` carries a background failure.
fn download_update(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      ignore(
        @interop.bridge_request(
          Local,
          @commands.update_download,
          @protocol.EmptyPayload::NoPayload,
        ) catch {
          error => {
            scheduler.add(
              dispatch(UpdateFailed(message=@interop.bridge_error_text(error))),
            )
            return
          }
        },
      )
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
