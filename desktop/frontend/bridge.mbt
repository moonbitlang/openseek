// The engine-host bridge: typed access to the host's methods and
// notifications (docs/remote-protocol.md). Methods go through
// `@interop.bridge_request`; notifications arrive either as `openseek.*`
// proton events (the desktop window) or as JSON-RPC notifications on the
// page's WebSocket (a browser through the relay), and both feed the same
// decoders below.

///|
/// Decode one host notification into the owner that consumes it. Raw terminal
/// output goes straight to the terminal package's emulator command: it changes
/// neither terminal state nor application state, so sending it through either
/// Rabbita update loop would only redraw unrelated UI. Terminal lifecycle
/// events still use the terminal emitter because they do change its root-owned
/// state; everything else uses the app emitter.
fn host_notification(
  terminal : @cmd.Emit[@terminal.Msg],
  app_emit : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  notification : @protocol.Notification,
) -> @cmd.Cmd {
  match notification {
    TerminalOutput(payload) =>
      @terminal.output(channel, payload.id, payload.sequence, payload.data)
    TerminalExit(payload) =>
      match terminal_exit_msg(channel, payload) {
        Some(msg) => terminal(msg)
        None => @cmd.none
      }
    _ =>
      match bridge_msg(channel, notification) {
        Some(msg) => app_emit(msg)
        None => @cmd.none
      }
  }
}

///|
/// Wire a host's notification stream into messages, once, over the
/// channel's transport.
fn install_bridge(
  app_emit : @cmd.Emit[Msg],
  terminal : @cmd.Emit[@terminal.Msg],
  channel : @interop.ChannelId,
  websocket_epoch : Int,
) -> @cmd.Cmd {
  match channel {
    Local => install_proton_bridge(app_emit, terminal, 0)
    Remote(device) => connect_ws(app_emit, terminal, device, websocket_epoch)
  }
}

///|
/// Route one notification to its decoder, stamped with the channel it
/// arrived on. Device-scoped notifications wrap as `FromDevice`; the rest
/// back page-global or focused-scoped state and stay root messages.
fn bridge_msg(
  channel : @interop.ChannelId,
  notification : @protocol.Notification,
) -> Msg? {
  match notification {
    AuthChanged(payload) =>
      // The desktop window's own relay registration (Settings → Remote
      // access). A remote device's auth changes are its host's business,
      // never this page's UI.
      if channel is Local {
        Some(RemoteStatusLoaded(RemoteAccess::from_status(payload)))
      } else {
        None
      }
    LspDiagnostics(payload) =>
      diagnostics_msg(channel, payload).map(msg => {
        FromDevice(channel, FilePanel(msg))
      })
    FsChanged(payload) => {
      guard @resource.of_path(channel, payload.root) is Some(root) else {
        return None
      }
      let changes : Array[@fileeditor.FileChange]? = if payload.baseline {
        None
      } else {
        let decoded : Array[@fileeditor.FileChange] = []
        for item in payload.events {
          match item.kind_ {
            "modify" =>
              decoded.push(@fileeditor.Modified(@pathx.Relative(item.path)))
            "create" =>
              decoded.push(@fileeditor.Created(@pathx.Relative(item.path)))
            "remove" =>
              decoded.push(@fileeditor.Removed(@pathx.Relative(item.path)))
            "rename" =>
              if item.old_path is Some(old) {
                decoded.push(
                  @fileeditor.Renamed(
                    old=@pathx.Relative(old),
                    new=@pathx.Relative(item.path),
                  ),
                )
              }
            _ => ()
          }
        }
        Some(decoded)
      }
      Some(
        FromDevice(
          channel,
          FilePanel(FsChanged(root~, generation=payload.generation, changes~)),
        ),
      )
    }
    FsWatchFailed(payload) => {
      guard @resource.of_path(channel, payload.root) is Some(root) else {
        return None
      }
      Some(
        FromDevice(
          channel,
          FilePanel(
            FileWatchFailed(
              channel~,
              root~,
              generation=payload.generation,
              message=payload.message,
            ),
          ),
        ),
      )
    }
    // Terminal notifications go straight to the terminal component emitter
    // and never enter the application message enum.
    TerminalOutput(_) | TerminalExit(_) => None
    UpdateDownloaded(_) =>
      if channel is Local {
        Some(UpdateDownloaded)
      } else {
        None
      }
    UpdateDownloadProgress(payload) =>
      if channel is Local && payload.downloaded_bytes >= 0 {
        let total_bytes = match payload.total_bytes {
          Some(total) if total > 0 => Some(total)
          _ => None
        }
        Some(
          UpdateDownloadProgress(
            downloaded_bytes=payload.downloaded_bytes,
            total_bytes~,
          ),
        )
      } else {
        None
      }
    UpdateDownloadFailed(payload) =>
      if channel is Local {
        Some(UpdateFailed(message=payload.message))
      } else {
        None
      }
    // The Desktop process owns one Codex app-server. The shell wraps these
    // notifications, while the Codex package decodes and applies their state.
    CodexStatusChanged(payload) =>
      Some(Codex(channel~, @codex.Msg::status_changed(payload)))
    CodexNotification(payload) =>
      if payload is Object(fields) &&
        @jsonx.json_text(fields, "method") is Some(method_) &&
        fields.get("params") is Some(params) &&
        @jsonx.json_int(fields, "generation") is Some(generation) {
        Some(
          Codex(channel~, @codex.Msg::notification(method_, params, generation)),
        )
      } else {
        None
      }
    CodexServerRequest(payload) =>
      if payload is Object(fields) &&
        fields.get("request_id") is Some(request_id) &&
        @jsonx.json_text(fields, "method") is Some(method_) &&
        fields.get("params") is Some(params) &&
        @jsonx.json_int(fields, "generation") is Some(generation) {
        Some(
          Codex(
            channel~,
            @codex.Msg::server_request(request_id, method_, params, generation),
          ),
        )
      } else {
        None
      }
    _ => device_msg(channel, notification).map(msg => FromDevice(channel, msg))
  }
}

///|
/// A device-scoped notification's decoder. `agent.connected` is the
/// readiness/resync signal on both transports: it re-fires on every
/// reconnect (and engine-pump restart), and the refetches BridgeReady
/// triggers — including `agent.runs` — rebuild whatever was missed.
fn device_msg(
  channel : @interop.ChannelId,
  notification : @protocol.Notification,
) -> DeviceMsg? {
  match notification {
    // The payload's stage says how much of the host is up; every stage asks
    // this client for the same resync, so the signal alone is the message.
    AgentConnected(_) => Some(BridgeReady)
    AgentStarted(payload) => started_msg(channel, payload)
    AgentEvent(payload) => engine_msg(payload)
    AgentError(payload) => error_msg(payload)
    AgentFinished(payload) => finished_msg(payload)
    SessionEvent(payload) => session_event_msg(channel, payload)
    SubrunProgress(payload) =>
      Some(
        SubrunProgressed(
          id=payload.id,
          session=payload.session,
          steps=payload.steps,
          activity=payload.activity,
        ),
      )
    SessionChanged(payload) => session_changed_msg(channel, payload)
    WorkspaceChanged(payload) => {
      let paths : Array[@common.Uri] = []
      // The wire contract still calls registered projects `workspaces`.
      for path in payload.workspaces {
        guard @resource.of_path(channel, path) is Some(resource) else {
          return None
        }
        paths.push(resource)
      }
      Some(ProjectsChanged(paths))
    }
    WorkspaceSettingsChanged(payload) =>
      workspace_settings_changed_msg(channel, payload)
    WorktreeChanged(payload) => worktree_changed_msg(channel, payload)
    SettingsChanged(payload) =>
      Some(
        HostSettingsLoaded(
          HostSettings::from_status(payload),
          connection_generation=None,
        ),
      )
    // The payload is intentionally empty: the installed library is the
    // source of truth, so every client re-reads it instead of applying a
    // requester-specific install/uninstall guess.
    SkillsChanged => Some(SkillsChanged)
    _ => None
  }
}

///|
/// Decode archive invalidation synchronously. A fresh id is allocated at the
/// event boundary (outside `update`) so archiving or deleting the active
/// conversation can switch without a render where Send targets the stale id.
fn session_changed_msg(
  channel : @interop.ChannelId,
  payload : @protocol.SessionChangedPayload,
) -> DeviceMsg? {
  guard ArchiveRecordKey::from_protocol(
      channel,
      payload.session,
      payload.workspace,
    )
    is Some(key) else {
    return None
  }
  Some(
    SessionsChanged(
      change=payload.change,
      key~,
      fresh_session=if payload.change == "archived" ||
        payload.change == "deleted" {
        Some(generated_session_id())
      } else {
        None
      },
    ),
  )
}

// ---------------------------------------------------------------------------
// The desktop window: the injected proton bridge.

///|
let bridge_events_wired : Ref[Bool] = Ref(false)

///|
/// Wait for proton to inject the bridge (it loads alongside this bundle),
/// wire the notification events into messages once, and open the host
/// connection. The 25ms retries add up to ~3 seconds before the bridge is
/// declared unavailable.
fn install_proton_bridge(
  dispatch : @cmd.Emit[Msg],
  terminal : @cmd.Emit[@terminal.Msg],
  attempt : Int,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    // The request API and the two event actors are separate injected objects.
    // Do not wire a partially initialized page; retry until every method used
    // below is available.
    guard @interop.openseek_api() is Some(request_api) &&
      @interop.moonbit_bridge_root() is Some(root) &&
      @interop.js_prop(root, "events") is Some(extension_events) &&
      @interop.js_prop(root, "app") is Some(application_events) &&
      @interop.js_prop(request_api, "host.connect") is Some(_) &&
      @interop.js_prop(request_api, "agent.start") is Some(_) &&
      @interop.js_prop(extension_events, "on") is Some(_) &&
      @interop.js_prop(application_events, "on") is Some(_) else {
      if attempt > 120 {
        scheduler.add(
          dispatch(FromDevice(Local, BridgeUnavailable("Bridge unavailable"))),
        )
      } else {
        scheduler.add(
          @cmd.delay(install_proton_bridge(dispatch, terminal, attempt + 1), 25),
        )
      }
      return
    }
    if !bridge_events_wired.val {
      bridge_events_wired.val = true
      wire_proton_events(
        scheduler, dispatch, terminal, extension_events, application_events,
      )
      open_host_connection(scheduler, dispatch, request_api)
    }
  })
}

///|
/// Attach this page to the host's app-lifetime notification actor. The call
/// resolves once the actor has emitted its readiness event; a rejection means
/// the page could not attach to the native bridge.
fn open_host_connection(
  scheduler : &@cmd.Scheduler,
  dispatch : @cmd.Emit[Msg],
  api : @js.Value,
) -> Unit {
  @js.async_run(() => {
    let _ : @js.Value = @interop.js_method_promise(
      api,
      "host.connect",
      @js.Object::new().to_value(),
    ).wait() catch {
      error => {
        scheduler.add(
          dispatch(
            FromDevice(
              Local,
              BridgeUnavailable(@interop.bridge_error_text(error)),
            ),
          ),
        )
        return
      }
    }
  })
}

///|
/// Notification kinds exposed by the host extension. Proton requires an
/// explicit listener for each one, unlike the WebSocket transport's generic
/// notification callback, so the listeners derive from the shared catalog.
fn proton_event_methods() -> Array[@protocol.NotificationKind] {
  @protocol.NotificationKind::all()
}

///|
test "proton subscribes to all Codex app-server events" {
  assert_true(
    proton_event_methods().contains(
      @protocol.NotificationKind::CodexStatusChanged,
    ),
  )
  assert_true(
    proton_event_methods().contains(
      @protocol.NotificationKind::CodexNotification,
    ),
  )
  assert_true(
    proton_event_methods().contains(
      @protocol.NotificationKind::CodexServerRequest,
    ),
  )
  assert_true(
    bridge_msg(
      Local,
      @protocol.Notification::CodexNotification({
        "method": "turn/completed",
        "params": { "threadId": "t1" },
        "generation": 1,
      }),
    )
    is Some(Codex(channel=Local, _)),
  )
}

///|
test "proton subscribes to remote-access status changes" {
  assert_true(proton_event_methods().contains(AuthChanged))
}

///|
test "skill invalidations are device-scoped catalog events" {
  assert_true(proton_event_methods().contains(SkillsChanged))
  assert_true(
    bridge_msg(Remote("d1"), @protocol.Notification::SkillsChanged)
    is Some(FromDevice(Remote("d1"), SkillsChanged)),
  )
}

///|
test "update download notifications control only the local desktop flow" {
  assert_true(proton_event_methods().contains(UpdateDownloadProgress))
  assert_true(proton_event_methods().contains(UpdateDownloaded))
  assert_true(proton_event_methods().contains(UpdateDownloadFailed))
  assert_true(
    bridge_msg(
      Local,
      @protocol.Notification::UpdateDownloadProgress({
        downloaded_bytes: 42,
        total_bytes: Some(100),
      }),
    )
    is Some(UpdateDownloadProgress(downloaded_bytes=42, total_bytes=Some(100))),
  )
  assert_true(
    bridge_msg(
      Local,
      @protocol.Notification::UpdateDownloaded({ version: "test" }),
    )
    is Some(UpdateDownloaded),
  )
  assert_true(
    bridge_msg(
      Local,
      @protocol.Notification::UpdateDownloadFailed({
        message: "digest mismatch",
      }),
    )
    is Some(UpdateFailed(message="digest mismatch")),
  )
  assert_true(
    bridge_msg(
      Local,
      @protocol.Notification::UpdateDownloadProgress({
        downloaded_bytes: -1,
        total_bytes: None,
      }),
    )
    is None,
  )
  assert_true(
    bridge_msg(
      Remote("d1"),
      @protocol.Notification::UpdateDownloadProgress({
        downloaded_bytes: 42,
        total_bytes: None,
      }),
    )
    is None,
  )
  assert_true(
    bridge_msg(
      Remote("d1"),
      @protocol.Notification::UpdateDownloaded({ version: "test" }),
    )
    is None,
  )
}

///|
test "file-panel pushes carry their channel; auth.changed is Local-only" {
  let channel : @interop.ChannelId = Remote("d1")
  assert_true(
    bridge_msg(
      channel,
      @protocol.Notification::FsChanged({
        root: "/work/project",
        baseline: true,
        events: [],
        generation: "page-a:7",
      }),
    )
    is Some(
      FromDevice(
        Remote("d1"),
        FilePanel(FsChanged(root=_, generation="page-a:7", changes=None))
      )
    ),
  )
  assert_true(
    bridge_msg(
      channel,
      @protocol.Notification::FsChanged({
        root: "/work/project",
        baseline: false,
        events: [
          { kind_: "modify", path: "src/main.mbt", old_path: None },
          {
            kind_: "rename",
            path: "src/new.mbt",
            old_path: Some("src/old.mbt"),
          },
        ],
        generation: "page-a:7",
      }),
    )
    is Some(
      FromDevice(
        Remote("d1"),
        FilePanel(
          FsChanged(
            root=_,
            generation="page-a:7",
            changes=Some(
              [
                Modified(Relative("src/main.mbt")),
                Renamed(
                  old=Relative("src/old.mbt"),
                  new=Relative("src/new.mbt")
                ),
              ]
            )
          )
        )
      )
    ),
  )
  assert_true(proton_event_methods().contains(FsWatchFailed))
  assert_true(
    bridge_msg(
      channel,
      @protocol.Notification::FsWatchFailed({
        root: "/work/project",
        message: "File watching stopped",
        generation: "page-a:7",
      }),
    )
    is Some(
      FromDevice(
        Remote("d1"),
        FilePanel(
          FileWatchFailed(
            channel=Remote("d1"),
            root=_,
            generation="page-a:7",
            message="File watching stopped"
          )
        )
      )
    ),
  )
  // A remote device's relay registration is its host's business.
  assert_true(
    bridge_msg(
      channel,
      @protocol.Notification::AuthChanged({
        connected: false,
        server_url: None,
        managed_by_env: None,
        user: None,
        device: None,
      }),
    )
    is None,
  )
}

///|
test "terminal lifecycle pushes retain the channel that owns their host session" {
  let payload : @protocol.TerminalExitPayload = { id: 1, code: 0 }
  assert_true(
    terminal_exit_msg(Local, payload)
    is Some(SessionExited(channel=Local, id=1, code=0)),
  )
  assert_true(
    terminal_exit_msg(Remote("d1"), payload)
    is Some(SessionExited(channel=Remote("d1"), id=1, code=0)),
  )
}

///|
fn wire_proton_events(
  scheduler : &@cmd.Scheduler,
  dispatch : @cmd.Emit[Msg],
  terminal : @cmd.Emit[@terminal.Msg],
  extension_events : @js.Value,
  application_events : @js.Value,
) -> Unit {
  fn on(name : String, decode : (Map[String, Json]) -> Msg?) -> Unit {
    let handler = (event : @js.Value) => {
      guard event_payload(event) is Some(payload) else { return }
      guard decode(payload) is Some(msg) else { return }
      scheduler.add(dispatch(msg))
    }
    let _ : @js.Value = extension_events.apply_with_string("on", [
      @js.Value::cast_from(name),
      @js.Value::cast_from(handler),
    ])
  }

  for kind_ in proton_event_methods() {
    let method_ = kind_.wire_name()
    let handler = (event : @js.Value) => {
      guard event_payload(event) is Some(payload) &&
        @protocol.Notification::from_wire(method_, Json::object(payload))
        is Some(notification) else {
        return
      }
      scheduler.add(host_notification(terminal, dispatch, Local, notification))
    }
    let _ : @js.Value = extension_events.apply_with_string("on", [
      @js.Value::cast_from("openseek." + method_),
      @js.Value::cast_from(handler),
    ])
  }
  // Native view events describe this window's own browser tabs. Like
  // `notification.click` below, the event is window-local: it has no
  // `NotificationKind` because the shared wire catalog must never carry it
  // to a relay client, which has no native views.
  on("openseek.browser.event", browser_event_msg)
  // Proton forwards native menu commands as application events.
  // Application events use `__MoonBit__.app.on`; the shared event hub above
  // is reserved for extension events. Ignore unknown ids so another menu
  // item cannot accidentally map to developer tools.
  let menu_handler = (event : @js.Value) => {
    guard event_payload(event) is Some(payload) &&
      @jsonx.json_text(payload, "command_id") ==
      Some(@commands.app_open_devtools.name()) else {
      return
    }
    scheduler.add(dispatch(AppDeveloperToolsRequested))
  }
  let _ : @js.Value = application_events.apply_with_string("on", [
    @js.Value::cast_from("menu.command"),
    @js.Value::cast_from(menu_handler),
  ])
  // Emitted by the notification extension when the user clicks a system
  // notification; the payload is the run id this frontend stamped on it.
  // Desktop-only by nature.
  on("notification.click", notification_clicked_msg)
}

///|
/// A proton event's payload as JSON fields. Payloads cross the bridge as
/// structured clones of the host's JSON, so the round trip back through
/// JSON is lossless; an event without a decodable payload is dropped —
/// except a payload-less notification, which reads as empty fields
/// and is then accepted only if that notification's typed payload permits it.
fn event_payload(event : @js.Value) -> Map[String, Json]? {
  guard @interop.js_prop(event, "payload") is Some(payload) else {
    return Some(Map([]))
  }
  let json = payload.to_json() catch { _ => return None }
  guard json is Object(fields) else { return None }
  Some(fields)
}

// ---------------------------------------------------------------------------
// A browser: JSON-RPC over the page's WebSocket, with reconnection.

///|
/// Consecutive connection losses before the user is told the host is
/// unreachable. The loop keeps reconnecting regardless; the next
/// `agent.connected` restores the UI.
const WsLostAfter = 3

///|
/// Open a device's WebSocket once. Reconnection is model-driven: the socket
/// closing dispatches `ChannelDown`, whose handler counts the loss and
/// schedules `ReconnectDue` with backoff — so a device dropped from the
/// model (revoked, signed out) stops reconnecting by itself, and a
/// successful connection (the host's `agent.connected`) resets the count.
fn connect_ws(
  dispatch : @cmd.Emit[Msg],
  terminal : @cmd.Emit[@terminal.Msg],
  device : String,
  websocket_epoch : Int,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    let channel : @interop.ChannelId = Remote(device)
    @interop.ws_connect(
      device,
      on_notification=notification => {
        scheduler.add(
          host_notification(terminal, dispatch, channel, notification),
        )
      },
      on_down=() => {
        scheduler.add(
          dispatch(FromDevice(channel, ChannelDown(websocket_epoch~))),
        )
      },
    )
  })
}

///|
/// Close a channel's socket and forget it, as a command — the roster
/// reconcile retires channels from inside `update`, which stays pure.
fn close_channel(channel : @interop.ChannelId) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => @interop.ws_close(channel))
}

///|
/// Reconnect backoff: quick first retries, settling at 15s so an
/// overnight-idle page keeps probing without hammering.
fn reconnect_delay(failures : Int) -> Int {
  match failures {
    0 | 1 => 1_000
    2 => 2_000
    3 => 4_000
    4 => 8_000
    _ => 15_000
  }
}

///|
/// Resync the in-flight runs after a (re)connect: `agent.runs` returns each
/// live run's `agent.started` params, replayed through the same decoder, so
/// a page that joined mid-run learns the run's identity and can cancel or
/// steer it. The reply is the complete in-flight set, so it also settles the
/// other direction — `RunsSettled` follows with every live id, and any run
/// this client still shows that the host no longer has ended while the
/// client was away. Nothing is dispatched when the op fails: a missing
/// answer says nothing about the runs.
fn fetch_runs(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  frontier : Array[RunSnapshotFrontier],
  connection_generation : Int,
) -> @cmd.Cmd {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  let payload = runs_payload(frontier)
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(
        channel, @commands.agent_runs, payload,
      ) catch {
        _ => return
      }
      let live : Array[String] = []
      let recovered : Array[RecoveredRun] = []
      for item in reply.runs {
        live.push(item.run_id)
        if RecoveredRun::from_started(channel, item) is Some(run) {
          recovered.push(run)
        }
      }
      let recovered_settlements : Array[RecoveredSettlement] = []
      for item in reply.settled {
        if RecoveredSettlement::from_reply(item) is Some(settlement) {
          recovered_settlements.push(settlement)
        }
      }
      scheduler.add(
        dispatch(
          RunsLoaded(
            runs=recovered,
            settled=recovered_settlements,
            live~,
            frontier~,
            connection_generation~,
          ),
        ),
      )
    })
  })
}

///|
/// Encode only lifecycle owners this page can still identify. The host uses
/// these selectors to return matching process-lifetime settlements without
/// exposing an unbounded completion history or guessing which local input a
/// same-text prompt belonged to.
fn runs_payload(frontier : Array[RunSnapshotFrontier]) -> @protocol.RunsPayload {
  let known : Array[@protocol.KnownRunPayload] = []
  for captured in frontier {
    let lifecycle_submission : String? = match captured.state {
      SnapshotStarting(submission_id~) => {
        known.push({
          session: captured.session,
          run_id: None,
          submission_id: Some(submission_id),
        })
        Some(submission_id)
      }
      SnapshotOpen(run_id~) | SnapshotIdle(last_run_id=Some(run_id)) => {
        known.push({
          session: captured.session,
          run_id: Some(run_id),
          submission_id: None,
        })
        None
      }
      SnapshotIdle(last_run_id=None) => None
    }
    for submission_id in captured.initial_ids {
      if lifecycle_submission != Some(submission_id) {
        known.push({
          session: captured.session,
          run_id: None,
          submission_id: Some(submission_id),
        })
      }
    }
  }
  { known: Some(known) }
}

///|
fn started_msg(
  channel : @interop.ChannelId,
  payload : @protocol.StartedPayload,
) -> DeviceMsg? {
  // `run_id`/`session`/`model`/`max_steps` are unconditional on this event
  // (the app's own start op always names a session); a payload missing one
  // — a blank model included, since no run ever ran on no model — is
  // malformed and dropped. The durable `session_root` is genuinely optional,
  // and the host resolved it itself, so this is the decode boundary where its
  // absolute provenance is collapsed into the type.
  let session = payload.session
  guard !session.is_empty() &&
    payload.model is Some(model) &&
    EngineModel::parse(model) is Some(model) &&
    payload.max_steps is Some(max_steps) else {
    return None
  }
  let session_root = match payload.session_root {
    Some(path) => {
      guard @resource.of_path(channel, path) is Some(absolute) else {
        return None
      }
      Some(absolute)
    }
    None => None
  }
  Some(
    Started(
      run_id=payload.run_id,
      session~,
      model~,
      max_steps~,
      session_root~,
      submission_id=payload.submission_id,
    ),
  )
}

///|
/// Project the common `agent.started` / `agent.runs` row shape without
/// dispatching it. Snapshot rows remain plain data until `update` accepts the
/// reply's connection generation.
fn RecoveredRun::from_started(
  channel : @interop.ChannelId,
  payload : @protocol.StartedPayload,
) -> RecoveredRun? {
  let session = payload.session
  guard !session.is_empty() &&
    payload.model is Some(model) &&
    EngineModel::parse(model) is Some(model) &&
    payload.max_steps is Some(max_steps) else {
    return None
  }
  let session_root = match payload.session_root {
    Some(path) => {
      guard @resource.of_path(channel, path) is Some(absolute) else {
        return None
      }
      Some(absolute)
    }
    None => None
  }
  Some({
    run_id: payload.run_id,
    session,
    model,
    max_steps,
    session_root,
    submission_id: payload.submission_id,
  })
}

///|
/// Decode one selector-matched completion from `agent.runs`. Every settlement
/// the host kept is the outcome it published for a run this caller owns, so
/// there is nothing to withhold: how much the run committed is a question the
/// transcript read answers, not one this reply has to prove.
fn RecoveredSettlement::from_reply(
  payload : @protocol.RunSettlementPayload,
) -> RecoveredSettlement? {
  Some({
    run_id: payload.run_id,
    session: payload.session,
    submission_id: payload.submission_id,
    status: payload.status,
  })
}

///|
/// One typed `session.event` commit. The durable sequence is duplicated in
/// the outer notification for routing; the typed item enum is what the
/// transcript projector consumes, with raw unknown items retained for newer
/// Desktop versions.
fn session_event_msg(
  channel : @interop.ChannelId,
  payload : @protocol.SessionCommitPayload,
) -> DeviceMsg? {
  // The store root is half of the commit's durable identity; an event whose
  // root does not bind to the channel is malformed and dropped.
  guard @resource.of_path(channel, payload.session_root) is Some(session_root) else {
    return None
  }
  Some(
    SessionCommitted(
      session=payload.session,
      sequence=payload.sequence,
      ts=payload.event.ts,
      item=payload.event.item,
      session_root~,
    ),
  )
}

///|
fn engine_msg(payload : @protocol.AgentEventPayload) -> DeviceMsg? {
  guard !payload.session.is_empty() else { return None }
  guard @transcript.decode_engine_event(payload.event) is Some(event) else {
    return None
  }
  // `run_id` is absent for events the engine emits before any run of its
  // process lifetime (a compaction on a freshly spawned engine); those still
  // route by `session`.
  Some(Engine(payload.run_id, event, session=Some(payload.session)))
}

///|
/// A host error without a run (`run_id` omitted — a pre-run failure)
/// belongs to whatever conversation the user is looking at; `None` routes
/// it there. `diagnostics` rides along only when the host had stderr worth
/// showing. Unlike other events, a malformed error is not dropped: an error
/// must never vanish silently, so a missing or blank `message` still
/// surfaces, labeled generically.
fn error_msg(payload : @protocol.AgentErrorPayload) -> DeviceMsg? {
  let message = match payload.message {
    Some(message) if !message.is_blank() => message
    _ => "error"
  }
  Some(
    Error(
      run_id=payload.run_id,
      message~,
      diagnostics=payload.diagnostics,
      exit_code=payload.exit_code,
    ),
  )
}

///|
fn finished_msg(payload : @protocol.FinishedPayload) -> DeviceMsg? {
  // `answer` is present only when the agent finished with one.
  Some(
    Finished(
      run_id=payload.run_id,
      status=payload.status,
      answer=payload.answer,
    ),
  )
}

///|
/// A `diagnostics` push: the host re-checked a file's module. The payload
/// carries an absolute root, a root-relative path, and the LSP-shaped
/// `diagnostics` array; the update filters it to the file on screen.
fn diagnostics_msg(
  channel : @interop.ChannelId,
  payload : @protocol.DiagnosticsPayload,
) -> @fileeditor.Msg? {
  guard @resource.of_path(channel, payload.root) is Some(root) else {
    return None
  }
  let absolute = @resource.join_relative(root, @pathx.Relative(payload.path))
  Some(
    DiagnosticsPublished(channel~, absolute~, diagnostics=payload.diagnostics),
  )
}

///|
fn terminal_exit_msg(
  channel : @interop.ChannelId,
  payload : @protocol.TerminalExitPayload,
) -> @terminal.Msg? {
  Some(SessionExited(channel~, id=payload.id, code=payload.code))
}

///|
/// A clicked notification's payload is the run id `system_notification.mbt`
/// stamped on it; an empty payload is dropped (a stale notification from an
/// older build, or a payload another surface posted).
fn notification_clicked_msg(payload : Map[String, Json]) -> Msg? {
  guard @jsonx.json_text(payload, "payload") is Some(run_id) &&
    !run_id.is_empty() else {
    return None
  }
  Some(NotificationClicked(run_id~))
}

///|
fn start_openseek(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  task : String,
  submission_id : String,
  selected_model : EngineModel,
  max_steps : String,
  session : String,
  workspace~ : @common.Uri,
) -> @cmd.Cmd {
  guard @resource.belongs_to(workspace, channel) else { return @cmd.none }
  let payload = start_payload(
    task,
    selected_model,
    max_steps,
    session,
    submission_id,
    workspace~,
  )
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      // Behind anything already out for this session: the host serves one
      // command per session, so a prompt issued after a goal must not reach
      // the engine first and start its turn without it.
      @interop.in_ordered_lane(
        @interop.session_command_lane(channel, session),
        () => {
          request_agent_start(
            scheduler, dispatch, channel, payload, session, submission_id,
          )
        },
      ) catch {
        // Unreachable: the lane only ever wakes its waiters, never fails
        // them, and the work it runs is `noraise`. The type cannot say so.
        _ => ()
      }
    })
  })
}

///|
/// Fire one `agent.start` and settle its reply (or failure) through the
/// session's Start* messages — shared by the plain submit and the
/// create-then-start worktree chain.
async fn request_agent_start(
  scheduler : &@cmd.Scheduler,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  payload : @protocol.StartPayload,
  session : String,
  submission_id : String,
) -> Unit noraise {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  let reply = @interop.bridge_request(channel, @commands.agent_start, payload) catch {
    error => {
      let message = @interop.bridge_error_text(error)
      scheduler.add(
        dispatch(
          if @interop.bridge_error_is_definite(error) {
            StartRejected(session~, submission_id~, message~)
          } else {
            StartUndelivered(session~, submission_id~, message~)
          },
        ),
      )
      return
    }
  }
  scheduler.add(
    dispatch(
      StartResponded(
        session~,
        submission_id~,
        run_id=reply.run_id,
        status=reply.status,
        exit_code=reply.exit_code,
      ),
    ),
  )
}

///|
/// The start payload. Optional fields are trimmed and omitted when blank.
/// `session` is required: every frontend conversation is minted with a
/// durable id before it can submit a prompt, and the host rejects a blank id.
/// It carries no `cwd` (`workspace`, the conversation's attached project,
/// is the only placement the host takes; everything else it derives from
/// the session id) and no credentials — the endpoint is
/// resolved host-side from the settings store.
fn start_payload(
  task : String,
  selected_model : EngineModel,
  max_steps : String,
  session : String,
  submission_id : String,
  workspace~ : @common.Uri,
) -> @protocol.StartPayload {
  let session = session.trim().to_owned()
  {
    task,
    submission_id: Some(submission_id),
    model: Some(selected_model.wire()),
    max_steps: parsed_max_steps(max_steps),
    session,
    workspace: Some(workspace.path),
  }
}

///|
/// The max-steps composer field as a positive step count. The field is
/// free-form text; anything that does not read as a sensible positive
/// number is omitted so the engine applies its default.
fn parsed_max_steps(text : String) -> Int? {
  let value = @string.parse_double(text.trim()) catch { _ => return None }
  if value >= 1.0 && value <= 1_000_000_000.0 {
    Some(value.to_int())
  } else {
    None
  }
}

///|
/// Refresh the sidebar's session list from the engine's durable store.
fn fetch_sessions(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  connection_generation : Int,
  request_generation : Int,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      refresh_sessions_into(
        scheduler, dispatch, channel, connection_generation, request_generation,
      )
    })
  })
}

///|
/// Fetch the live session list and fold the reply into `scheduler` — the
/// body of `fetch_sessions`, shared with every command whose op changes what
/// that list contains (archive/unarchive moves, workspace add/remove).
async fn refresh_sessions_into(
  scheduler : &@cmd.Scheduler,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  connection_generation : Int,
  request_generation : Int,
) -> Unit noraise {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  let reply = @interop.bridge_request(
    channel,
    @commands.session_list,
    @protocol.EmptyPayload::NoPayload,
  ) catch {
    error => {
      scheduler.add(dispatch(SessionsFailed(@interop.bridge_error_text(error))))
      return
    }
  }
  scheduler.add(
    dispatch(
      SessionsLoaded(
        @transcript.sessions_from_reply(reply, channel),
        connection_generation~,
        request_generation~,
      ),
    ),
  )
}

///|
/// Load a durable session's transcript so the conversation can be resumed.
/// `workspace` says which registered store holds it; `None` selects the
/// default store. The protocol conversion happens only in `load_session_cmd`.
fn open_session(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session_id : String,
  workspace~ : @common.Uri?,
  generation~ : Int,
  archived? : Bool = false,
) -> @cmd.Cmd {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  load_session_cmd(
    channel,
    session_id,
    workspace~,
    archived~,
    on_loaded=view => {
      dispatch(
        SessionLoaded(
          session=session_id,
          items=view.items,
          watermark=view.watermark,
          goal=view.goal,
          goal_markers=view.goal_markers,
          generation~,
        ),
      )
    },
    on_failed=detail => {
      dispatch(
        SessionLoadFailed(
          session=session_id,
          message=if archived {
            "failed to load archived conversation \{session_id}: " + detail
          } else {
            "failed to load session \{session_id}: " + detail
          },
          generation~,
        ),
      )
    },
  )
}

///|
/// Re-read a conversation's durable record in the background — a commit-gap
/// resync, or catching up on a foreign run — without activating it or
/// stealing the screen.
fn refresh_session(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session_id : String,
  workspace~ : @common.Uri?,
  generation~ : Int,
  archived? : Bool = false,
) -> @cmd.Cmd {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  load_session_cmd(
    channel,
    session_id,
    workspace~,
    archived~,
    on_loaded=view => {
      dispatch(
        SessionRefreshed(
          session=session_id,
          items=view.items,
          watermark=view.watermark,
          goal=view.goal,
          goal_markers=view.goal_markers,
          generation~,
        ),
      )
    },
    on_failed=_ => {
      dispatch(SessionRefreshFailed(session=session_id, generation~))
    },
  )
}

///|
fn load_session_cmd(
  channel : @interop.ChannelId,
  session_id : String,
  workspace~ : @common.Uri?,
  archived~ : Bool,
  on_loaded~ : (@transcript.SessionLoadView) -> @cmd.Cmd,
  on_failed~ : (String) -> @cmd.Cmd,
) -> @cmd.Cmd {
  match workspace {
    Some(resource) if !@resource.belongs_to(resource, channel) =>
      return @cmd.none
    _ => ()
  }
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = try {
        if archived {
          @interop.bridge_request(channel, @commands.session_load_archived, {
            session: session_id,
            workspace: workspace.map(path => path.path),
          })
        } else {
          @interop.bridge_request(channel, @commands.session_load, {
            session: session_id,
            workspace: workspace.map(path => path.path),
          })
        }
      } catch {
        error => {
          scheduler.add(on_failed(@interop.bridge_error_text(error)))
          return
        }
      }
      scheduler.add(on_loaded(@transcript.session_from_reply(reply)))
    })
  })
}

///|
/// Inject steering input into the running turn. Delivery is acknowledged by
/// the engine's own `steer_applied`/`steer_dropped` events; this command only
/// distinguishes a definitive host refusal from an indeterminate transport
/// failure: only the latter may still be followed by an exact engine receipt.
fn steer_openseek(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session : String,
  submission_id : String,
  text : String,
  run_id : String,
) -> @cmd.Cmd {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let delivered = steer_delivered(channel, text, submission_id, run_id) catch {
        error => {
          scheduler.add(
            dispatch(
              if @interop.bridge_error_is_definite(error) {
                SteerRejected(session~, submission_id~, run_id~)
              } else {
                SteerUndelivered(session~, submission_id~, text~, run_id~)
              },
            ),
          )
          return
        }
      }
      if !delivered {
        scheduler.add(
          dispatch(SteerRejected(session~, submission_id~, run_id~)),
        )
      }
    })
  })
}

///|
async fn steer_delivered(
  channel : @interop.ChannelId,
  text : String,
  submission_id : String,
  run_id : String,
) -> Bool {
  let reply = @interop.bridge_request(channel, @commands.agent_steer, {
    text,
    run_id: Some(run_id),
    submission_id: Some(submission_id),
  })
  reply.steered
}

///|
/// Ask a conversation's engine to compact (summarize and shrink) its history,
/// carrying the same engine settings as a start: a conversation with no live
/// serve process (resumed after a restart) gets one spawned on the durable
/// session first. The engine reports the real progress through `compaction_*`
/// events; this command only surfaces the immediate failure — the spawn
/// failing, or the bridge call itself rejecting — as an error in the
/// conversation on screen.
fn compact_openseek(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session~ : String,
  model~ : EngineModel,
  max_steps~ : String,
  workspace~ : @common.Uri,
) -> @cmd.Cmd {
  guard @resource.belongs_to(workspace, channel) else { return @cmd.none }
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      // Compaction claims the same per-session slot as start and goal, so it
      // waits behind them rather than colliding.
      ignore(
        @interop.bridge_request_in_order(
          channel,
          @commands.agent_compact,
          {
            session,
            model: Some(model.wire()),
            max_steps: parsed_max_steps(max_steps),
            workspace: Some(workspace.path),
          },
          lane=@interop.session_command_lane(channel, session),
        ) catch {
          error => {
            // Routed by session, not as a generic Error: the rejection must
            // also clear the conversation's queued/compacting notice, which
            // no compaction event will ever settle now.
            scheduler.add(
              dispatch(
                CompactRejected(
                  session~,
                  message=@interop.bridge_error_text(error),
                ),
              ),
            )
            return
          }
        },
      )
    })
  })
}

///|
/// Set or clear a conversation's standing goal, carrying the same engine
/// settings as a start: a conversation with no live serve process (resumed
/// after a restart) gets one spawned on the durable session first. The
/// durable `[goal]` marker commit is the confirmation that moves the UI;
/// this command only surfaces the immediate failure — the spawn failing, or
/// the bridge call rejecting — as an error in the conversation on screen.
fn goal_openseek(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session~ : String,
  model~ : EngineModel,
  max_steps~ : String,
  workspace~ : @common.Uri,
  command : String,
  text : String?,
) -> @cmd.Cmd {
  guard @resource.belongs_to(workspace, channel) else { return @cmd.none }
  let payload = goal_payload(session, model, max_steps, workspace, text)
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      @interop.in_ordered_lane(
        @interop.session_command_lane(channel, session),
        () => {
          request_agent_goal(
            scheduler, dispatch, channel, payload, session, command, text,
          )
        },
      ) catch {
        // Unreachable: the lane only ever wakes its waiters, never fails
        // them, and the work it runs is `noraise`. The type cannot say so.
        _ => ()
      }
    })
  })
}

///|
/// The `agent.goal` payload. `auto` is sent only when arming: an absent field
/// is the manual default every host understands, including one that predates
/// the toggle.
fn goal_payload(
  session : String,
  model : EngineModel,
  max_steps : String,
  workspace : @common.Uri,
  text : String?,
) -> @protocol.GoalPayload {
  {
    session,
    text,
    // Always manual. `auto` arms the engine's autonomous continuation, and
    // the desktop cannot yet see the turns that continuation starts: serve
    // announces them with `GoalContinue`, which this client drops, so the
    // composer would offer Send during an autonomous turn and a prompt sent
    // then would be settled by that turn's terminal event. Arming waits for
    // the lifecycle work.
    auto: None,
    model: Some(model.wire()),
    max_steps: parsed_max_steps(max_steps),
    workspace: Some(workspace.path),
  }
}

///|
/// Send one `agent.goal`. A refusal and a call that never left both mean
/// nothing landed, so both come back as `GoalRejected` carrying the text for
/// the composer to hand back; only a command that went out unanswered is
/// `GoalUndelivered`, which cannot say that.
async fn request_agent_goal(
  scheduler : &@cmd.Scheduler,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  payload : @protocol.GoalPayload,
  session : String,
  command : String,
  text : String?,
) -> Unit noraise {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  // The caller holds this session's goal lane across the whole chain, so the
  // request goes out plainly here — see `set_goal_in_new_worktree`, where the
  // ordering has to cover the worktree preflight too.
  ignore(
    @interop.bridge_request(channel, @commands.agent_goal, payload) catch {
      error => {
        let message = @interop.bridge_error_text(error)
        scheduler.add(
          dispatch(
            match @interop.bridge_failure(error) {
              Refused | Unsent =>
                GoalRejected(session~, command~, draft=text, message~)
              Unknown =>
                GoalUndelivered(session~, command~, draft=text, message~)
            },
          ),
        )
        return
      }
    },
  )
}

///|
/// Ask the host to cancel `run_id`. Only a failure is worth reporting: the
/// host raises when the cancellation could not be delivered, and answers
/// normally otherwise — including for a turn that ended on its own just
/// before the request landed, which is a race the user cannot see and does
/// not need to. The run itself ends through its `agent.finished`.
fn cancel_openseek(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  run_id : String,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let _ : @protocol.CancelReply = @interop.bridge_request(
        channel,
        @commands.agent_cancel,
        { run_id: Some(run_id) },
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              HostActionFailed(
                "Failed to cancel the run: " + @interop.bridge_error_text(error),
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
/// Ask the host to swap the staged update into place. Success means the
/// bundle on disk is already the new version; the follow-up `UpdateApplied`
/// closes the window so `main` can relaunch it. A failure pops an error
/// toast and the app keeps running the current version.
fn apply_update(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      // Self-update always targets the page's own desktop host, never a
      // focused remote device.
      ignore(
        @interop.bridge_request(
          Local,
          @commands.update_apply,
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
      scheduler.add(dispatch(UpdateApplied))
    })
  })
}

///|
/// Close the window through the normal close path — the same teardown as
/// the user clicking the close button, so engines and the host unwind
/// before `main` relaunches the swapped bundle.
fn close_window() -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    let _ : @js.Value = @js.globalThis.apply_with_string(
      "close",
      ([] : Array[@js.Value]),
    )
  })
}

///|
/// Ask the host to ensure and open the Codex home's `config.toml` with the
/// platform opener. Success needs no reply handling; a failure surfaces as
/// an error toast.
fn open_codex_config(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let _ : @protocol.EmptyReply = @interop.bridge_request(
        channel,
        @commands.codex_config_open,
        @protocol.EmptyPayload::NoPayload,
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              CodexConfigOpenFailed(
                "Codex config: " + @interop.bridge_error_text(error),
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
/// Ask the host to route a transcript-referenced path. Viewer-sized UTF-8 text
/// inside the checkout returns an editor target, checkout-local directories
/// return a Files-tree target, and other existing paths use the system default
/// app. A relative path is taken against the conversation's working directory.
/// Missing paths and outside text surface as errors.
fn open_file(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session : String,
  generation : Int,
  cwd~ : @common.Uri?,
  path : String,
) -> @cmd.Cmd {
  match cwd {
    Some(resource) if !@resource.belongs_to(resource, channel) =>
      return @cmd.none
    _ => ()
  }
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(channel, @commands.host_open_path, {
        session,
        cwd: cwd.map(resource => resource.path),
        path,
      }) catch {
        error => {
          scheduler.add(
            dispatch(
              OpenFileFailed(
                owner={ channel, session },
                generation~,
                message=@interop.bridge_error_text(error),
              ),
            ),
          )
          return
        }
      }
      match reply {
        Editor(target) =>
          scheduler.add(
            dispatch(
              OpenFileAt(
                owner={ channel, session },
                generation~,
                path=target.path,
                line=target.line,
                column=target.column,
              ),
            ),
          )
        Directory(target) =>
          scheduler.add(
            dispatch(
              OpenDirectoryAt(
                owner={ channel, session },
                generation~,
                path=target.path,
              ),
            ),
          )
        Refused(message) =>
          scheduler.add(
            dispatch(
              OpenFileFailed(owner={ channel, session }, generation~, message~),
            ),
          )
        // The host already handed the path to the system opener.
        Opened => ()
      }
    })
  })
}
