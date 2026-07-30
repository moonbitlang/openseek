// The engine-host bridge: typed access to the host's methods and
// notifications (docs/remote-protocol.md). Methods go through
// `@interop.bridge_request`; notifications arrive either as `openseek.*`
// proton events (the desktop window) or as JSON-RPC notifications on the
// page's WebSocket (a browser through the relay), and both feed the same
// decoders below.

///|
/// Wire a host's notification stream into messages, once, over the
/// channel's transport.
fn install_bridge(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  websocket_epoch : Int,
) -> @cmd.Cmd {
  match channel {
    Local => install_proton_bridge(dispatch, 0)
    Remote(device) => connect_ws(dispatch, device, websocket_epoch)
  }
}

///|
/// Route one notification to its decoder, stamped with the channel it
/// arrived on. Device-scoped notifications wrap as `FromDevice`; the rest
/// back page-global or focused-scoped state and stay root messages.
fn bridge_msg(
  channel : @interop.ChannelId,
  method_ : String,
  payload : Map[String, Json],
) -> Msg? {
  match method_ {
    "auth.changed" =>
      // The desktop window's own relay registration (Settings → Remote
      // access). A remote device's auth changes are its host's business,
      // never this page's UI.
      if channel is Local {
        decode_remote_access(payload).map(status => RemoteStatusLoaded(status))
      } else {
        None
      }
    "lsp.diagnostics" =>
      diagnostics_msg(channel, payload).map(msg => {
        FromDevice(channel, FilePanel(msg))
      })
    "fs.changed" => Some(FromDevice(channel, FilePanel(FsChanged)))
    _ => device_msg(method_, payload).map(msg => FromDevice(channel, msg))
  }
}

///|
/// A device-scoped notification's decoder. `agent.connected` is the
/// readiness/resync signal on both transports: it re-fires on every
/// reconnect (and engine-pump restart), and the refetches BridgeReady
/// triggers — including `agent.runs` — rebuild whatever was missed.
fn device_msg(method_ : String, payload : Map[String, Json]) -> DeviceMsg? {
  match method_ {
    "agent.connected" => Some(BridgeReady)
    "agent.started" => started_msg(payload)
    "agent.event" => engine_msg(payload)
    "agent.error" => error_msg(payload)
    "agent.finished" => finished_msg(payload)
    "agent.durable" => durable_boundary_msg(payload)
    "session.event" => session_event_msg(payload)
    "session.changed" => session_changed_msg(payload)
    "workspace.changed" =>
      workspaces_from_fields(payload).map(paths => WorkspacesChanged(paths))
    "settings.changed" =>
      decode_host_settings(payload).map(settings => {
        HostSettingsLoaded(settings, connection_generation=None)
      })
    // The payload is intentionally empty: the installed library is the
    // source of truth, so every client re-reads it instead of applying a
    // requester-specific install/uninstall guess.
    "skills.changed" => Some(SkillsChanged)
    _ => None
  }
}

///|
/// Decode archive invalidation synchronously. A fresh id is allocated at the
/// event boundary (outside `update`) so archiving the active conversation can
/// switch immediately without a render where Send still targets the stale id.
fn session_changed_msg(payload : Map[String, Json]) -> DeviceMsg? {
  guard @jsonx.json_text(payload, "change") is Some(change) &&
    @jsonx.json_text(payload, "session") is Some(session) else {
    return None
  }
  Some(
    SessionsChanged(
      change~,
      session~,
      fresh_session=if change == "archived" {
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
/// Both bridge handles, present only when the surface the frontend relies
/// on is fully injected.
fn bridge_handles() -> (@js.Value, @js.Value)? {
  guard @interop.openseek_api() is Some(api) &&
    @interop.moonbit_bridge_root() is Some(root) &&
    @interop.js_prop(root, "events") is Some(events) &&
    @interop.js_prop(api, "host.connect") is Some(_) &&
    @interop.js_prop(api, "agent.start") is Some(_) &&
    @interop.js_prop(events, "on") is Some(_) else {
    return None
  }
  Some((api, events))
}

///|
/// Wait for proton to inject the bridge (it loads alongside this bundle),
/// wire the notification events into messages once, and open the host
/// connection. The 25ms retries add up to ~3 seconds before the bridge is
/// declared unavailable.
fn install_proton_bridge(dispatch : @cmd.Emit[Msg], attempt : Int) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    guard bridge_handles() is Some((api, events)) else {
      if attempt > 120 {
        scheduler.add(
          dispatch(FromDevice(Local, BridgeUnavailable("Bridge unavailable"))),
        )
      } else {
        scheduler.add(
          @cmd.delay(install_proton_bridge(dispatch, attempt + 1), 25),
        )
      }
      return
    }
    if !bridge_events_wired.val {
      bridge_events_wired.val = true
      wire_proton_events(scheduler, dispatch, events)
      open_host_connection(scheduler, dispatch, api)
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
/// Notification methods exposed by the host extension. Proton requires an
/// explicit listener for each one, unlike the WebSocket transport's generic
/// notification callback.
fn proton_event_methods() -> Array[String] {
  [
    "agent.connected", "agent.started", "agent.event", "agent.error", "agent.finished",
    "agent.durable", "session.event", "session.changed", "workspace.changed", "settings.changed",
    "skills.changed", "auth.changed", "lsp.diagnostics", "fs.changed",
  ]
}

///|
test "proton subscribes to remote-access status changes" {
  assert_true(
    proton_event_methods().iter().any(method_ => method_ == "auth.changed"),
  )
}

///|
test "skill invalidations are device-scoped catalog events" {
  assert_true(proton_event_methods().contains("skills.changed"))
  assert_true(
    bridge_msg(Remote("d1"), "skills.changed", Map([]))
    is Some(FromDevice(Remote("d1"), SkillsChanged)),
  )
}

///|
test "file-panel pushes carry their channel; auth.changed is Local-only" {
  let channel : @interop.ChannelId = Remote("d1")
  assert_true(
    bridge_msg(channel, "fs.changed", Map([]))
    is Some(FromDevice(Remote("d1"), FilePanel(_))),
  )
  // A remote device's relay registration is its host's business.
  assert_true(bridge_msg(channel, "auth.changed", Map([])) is None)
}

///|
fn wire_proton_events(
  scheduler : &@cmd.Scheduler,
  dispatch : @cmd.Emit[Msg],
  events : @js.Value,
) -> Unit {
  fn on(name : String, decode : (Map[String, Json]) -> Msg?) -> Unit {
    let handler = (event : @js.Value) => {
      guard event_payload(event) is Some(payload) else { return }
      guard decode(payload) is Some(msg) else { return }
      scheduler.add(dispatch(msg))
    }
    let _ : @js.Value = events.apply_with_string("on", [
      @js.Value::cast_from(name),
      @js.Value::cast_from(handler),
    ])
  }

  for method_ in proton_event_methods() {
    on("openseek." + method_, payload => bridge_msg(Local, method_, payload))
  }
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
/// (`agent.connected` carries none).
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
  device : String,
  websocket_epoch : Int,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    let channel : @interop.ChannelId = Remote(device)
    @interop.ws_connect(
      device,
      on_notification=(method_, params) => {
        if bridge_msg(channel, method_, params) is Some(msg) {
          scheduler.add(dispatch(msg))
        }
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
      let reply = @interop.bridge_request(channel, "agent.runs", payload) catch {
        _ => return
      }
      let json = @json.parse(@interop.reply_json_text(reply)) catch {
        _ => return
      }
      guard json is Object(fields) && fields.get("runs") is Some(Array(runs)) else {
        return
      }
      let live : Array[String] = []
      let recovered : Array[RecoveredRun] = []
      for item in runs {
        guard item is Object(fields) else { continue }
        if @jsonx.json_text(fields, "run_id") is Some(run_id) {
          live.push(run_id)
        }
        if recovered_run(fields) is Some(run) {
          recovered.push(run)
        }
      }
      let settled : Array[RecoveredSettlement] = []
      if fields.get("settled") is Some(Array(items)) {
        for item in items {
          if item is Object(fields) &&
            recovered_settlement(fields) is Some(settlement) {
            settled.push(settlement)
          }
        }
      }
      scheduler.add(
        dispatch(
          RunsLoaded(
            runs=recovered,
            settled~,
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
fn runs_payload(frontier : Array[RunSnapshotFrontier]) -> @js.Value {
  let known : Array[@js.Value] = []
  for captured in frontier {
    let lifecycle_submission : String? = match captured.state {
      SnapshotStarting(submission_id~) => {
        let selector = @js.Object::new()
        selector["session"] = captured.session
        selector["submission_id"] = submission_id
        known.push(selector.to_value())
        Some(submission_id)
      }
      SnapshotOpen(run_id~) | SnapshotIdle(last_run_id=Some(run_id)) => {
        let selector = @js.Object::new()
        selector["session"] = captured.session
        selector["run_id"] = run_id
        known.push(selector.to_value())
        None
      }
      SnapshotIdle(last_run_id=None) => None
    }
    for submission_id in captured.initial_ids {
      if lifecycle_submission != Some(submission_id) {
        let selector = @js.Object::new()
        selector["session"] = captured.session
        selector["submission_id"] = submission_id
        known.push(selector.to_value())
      }
    }
  }
  let payload = @js.Object::new()
  payload["known"] = known
  payload.to_value()
}

///|
/// Ask the host what it is: today only whether it can run the engine inside
/// WSL (a Windows host). The page's own user agent says nothing about the
/// host, so the capability must come over the wire. A failed or malformed
/// reply leaves the default (no WSL) in place.
fn fetch_host_meta(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
) -> @cmd.Cmd {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply = @interop.bridge_request(
        channel,
        "host.meta",
        @js.Object::new().to_value(),
      ) catch {
        _ => return
      }
      let json = @json.parse(@interop.reply_json_text(reply)) catch {
        _ => return
      }
      scheduler.add(dispatch(HostMetaLoaded(wsl=json is { "wsl": true, .. })))
    })
  })
}

///|
fn started_msg(payload : Map[String, Json]) -> DeviceMsg? {
  // `run_id`/`session`/`model`/`max_steps` are unconditional on this event
  // (the app's own start op always names a session); a payload missing one
  // is malformed and dropped. `cwd` and the durable `session_root` are
  // genuinely optional, and the host resolved both itself, so this is the
  // decode boundary where their absolute provenance is collapsed into the
  // type.
  recovered_run(payload).map(run => {
    Started(
      run_id=run.run_id,
      session=run.session,
      model=run.model,
      max_steps=run.max_steps,
      cwd=run.cwd,
      session_root=run.session_root,
      task=run.task,
      submission_id=run.submission_id,
    )
  })
}

///|
/// Decode the common `agent.started` / `agent.runs` row shape without
/// dispatching it. Snapshot rows remain plain data until `update` accepts the
/// reply's connection generation.
fn recovered_run(payload : Map[String, Json]) -> RecoveredRun? {
  guard @jsonx.json_text(payload, "run_id") is Some(run_id) &&
    @jsonx.json_text(payload, "session") is Some(session) &&
    @jsonx.json_text(payload, "model") is Some(model) &&
    @jsonx.json_int(payload, "max_steps") is Some(max_steps) else {
    return None
  }
  Some({
    run_id,
    session,
    model,
    max_steps,
    cwd: @jsonx.json_text(payload, "cwd").map(path => Absolute(path)),
    session_root: @jsonx.json_text(payload, "session_root").map(path => {
      Absolute(path)
    }),
    task: @jsonx.json_text(payload, "task"),
    submission_id: @jsonx.json_text(payload, "submission_id"),
  })
}

///|
/// Decode one selector-matched completion from `agent.runs`. A normal
/// terminal-backed status is durable by construction; every abnormal or
/// future status requires the host's exact EOF sequence before it is safe to
/// replay. This keeps a malformed/older host from turning an absence into a
/// false zero-durable conclusion.
fn recovered_settlement(payload : Map[String, Json]) -> RecoveredSettlement? {
  guard @jsonx.json_text(payload, "run_id") is Some(run_id) &&
    @jsonx.json_text(payload, "session") is Some(session) &&
    @jsonx.json_text(payload, "status") is Some(status) else {
    return None
  }
  let durable_sequence = @jsonx.json_int(payload, "durable_sequence")
  let terminal_backed = status == "finished" ||
    status == "context_yield" ||
    status == "max_steps_exhausted"
  guard terminal_backed || durable_sequence is Some(_) else { return None }
  Some({
    run_id,
    session,
    submission_id: @jsonx.json_text(payload, "submission_id"),
    status,
    durable_sequence,
  })
}

///|
/// One `session.event` commit: the store event rides in `event` verbatim
/// (`{"sequence", "ts", "item"}`), and the item's `{kind, payload}` is what
/// the transcript projector consumes. A payload missing any of it is
/// malformed and dropped — the watermark gap it leaves behind is answered by
/// a reload, so nothing is lost silently.
fn session_event_msg(payload : Map[String, Json]) -> DeviceMsg? {
  guard @jsonx.json_text(payload, "session") is Some(session) &&
    @jsonx.json_int(payload, "sequence") is Some(sequence) &&
    payload.get("event") is Some(Object(event)) &&
    event.get("item") is Some(Object(item)) &&
    @jsonx.json_text(item, "kind") is Some(kind) &&
    item.get("payload") is Some(Object(item_payload)) else {
    return None
  }
  Some(SessionCommitted(session~, sequence~, kind~, payload=item_payload))
}

///|
fn engine_msg(payload : Map[String, Json]) -> DeviceMsg? {
  guard payload.get("event") is Some(Object(raw)) else { return None }
  guard @transcript.decode_engine_event(raw) is Some(event) else { return None }
  // `run_id` is absent for events the engine emits before any run of its
  // process lifetime (a compaction on a freshly spawned engine); those still
  // route by `session`.
  Some(
    Engine(
      @jsonx.json_text(payload, "run_id"),
      event,
      session=@jsonx.json_text(payload, "session"),
    ),
  )
}

///|
/// A host error without a run (`run_id` omitted — a pre-run failure)
/// belongs to whatever conversation the user is looking at; `None` routes
/// it there. `diagnostics` rides along only when the host had stderr worth
/// showing. Unlike other events, a malformed error is not dropped: an error
/// must never vanish silently, so a missing or blank `message` still
/// surfaces, labeled generically.
fn error_msg(payload : Map[String, Json]) -> DeviceMsg? {
  let message = if @jsonx.json_text(payload, "message") is Some(message) &&
    !message.trim().is_empty() {
    message
  } else {
    "error"
  }
  Some(
    Error(
      run_id=@jsonx.json_text(payload, "run_id"),
      message~,
      diagnostics=@jsonx.json_text(payload, "diagnostics"),
      exit_code=@jsonx.json_int(payload, "exit_code"),
    ),
  )
}

///|
fn finished_msg(payload : Map[String, Json]) -> DeviceMsg? {
  // `answer` is present only when the agent finished with one.
  guard @jsonx.json_text(payload, "run_id") is Some(run_id) &&
    @jsonx.json_text(payload, "status") is Some(status) else {
    return None
  }
  Some(
    Finished(
      run_id~,
      status~,
      answer=@jsonx.json_text(payload, "answer"),
      durable_sequence=@jsonx.json_int(payload, "durable_sequence"),
    ),
  )
}

///|
fn durable_boundary_msg(payload : Map[String, Json]) -> DeviceMsg? {
  guard @jsonx.json_text(payload, "run_id") is Some(run_id) &&
    @jsonx.json_text(payload, "session") is Some(session) &&
    @jsonx.json_int(payload, "sequence") is Some(sequence) else {
    return None
  }
  Some(DurableBoundary(run_id~, session~, sequence~))
}

///|
/// A `diagnostics` push: the language server re-analyzed a file. The payload
/// carries the absolute `path` and the raw LSP `diagnostics` array; the update
/// filters it to the file on screen.
fn diagnostics_msg(
  channel : @interop.ChannelId,
  payload : Map[String, Json],
) -> @fileeditor.Msg? {
  guard @jsonx.json_text(payload, "path") is Some(path) && !path.is_empty() else {
    return None
  }
  Some(
    DiagnosticsPublished(
      channel~,
      absolute=Absolute(path),
      diagnostics=payload.get("diagnostics").unwrap_or([]),
    ),
  )
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
  selected_model : String,
  max_steps : String,
  session : String,
  workspace~ : @pathx.Absolute?,
) -> @cmd.Cmd {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
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
      let reply = @interop.bridge_request(channel, "agent.start", payload) catch {
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
      let json = @json.parse(@interop.reply_json_text(reply)) catch {
        _ => {
          scheduler.add(
            dispatch(
              StartUndelivered(
                session~,
                submission_id~,
                message="malformed agent.start reply",
              ),
            ),
          )
          return
        }
      }
      guard json is Object(fields) &&
        @jsonx.json_text(fields, "run_id") is Some(run_id) &&
        @jsonx.json_text(fields, "status") is Some(status) &&
        @jsonx.json_int(fields, "exit_code") is Some(exit_code) else {
        scheduler.add(
          dispatch(
            StartUndelivered(
              session~,
              submission_id~,
              message="malformed agent.start reply",
            ),
          ),
        )
        return
      }
      scheduler.add(
        dispatch(
          StartResponded(session~, submission_id~, run_id~, status~, exit_code~),
        ),
      )
    })
  })
}

///|
/// The start payload. Optional fields are trimmed and omitted when blank —
/// the host documents that a present field always carries non-blank text.
/// It carries no `cwd` (`workspace`, the conversation's attached project,
/// is the only placement the host takes; everything else it derives from
/// the session id) and no credentials or WSL preference — the endpoint is
/// resolved host-side from the settings store.
fn start_payload(
  task : String,
  selected_model : String,
  max_steps : String,
  session : String,
  submission_id : String,
  workspace~ : @pathx.Absolute?,
) -> @js.Value {
  let payload = @js.Object::new()
  payload["task"] = task
  payload["submission_id"] = submission_id
  set_engine_settings(
    payload,
    model=selected_model,
    max_steps~,
    session~,
    workspace?,
  )
  payload.to_value()
}

///|
/// Fill `payload` with the engine settings shared by `start` and `compact` —
/// everything the host needs to spawn a serve engine, minus the task.
fn set_engine_settings(
  payload : @js.Object,
  model~ : String,
  max_steps~ : String,
  session~ : String,
  workspace? : @pathx.Absolute,
) -> Unit {
  @interop.set_trimmed(payload, "model", model)
  @interop.set_trimmed(payload, "session", session)
  @interop.set_workspace(payload, workspace)
  if parsed_max_steps(max_steps) is Some(steps) {
    payload["max_steps"] = steps
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
    "session.list",
    @js.Object::new().to_value(),
  ) catch {
    error => {
      scheduler.add(dispatch(SessionsFailed(@interop.bridge_error_text(error))))
      return
    }
  }
  match @transcript.decode_sessions_reply(@interop.reply_json_text(reply)) {
    Some(items) =>
      scheduler.add(
        dispatch(
          SessionsLoaded(items, connection_generation~, request_generation~),
        ),
      )
    None => scheduler.add(dispatch(SessionsFailed("malformed session list")))
  }
}

///|
/// Load a durable session's transcript so the conversation can be resumed.
/// `workspace` says which store holds it ("" = the default store; the host
/// can also locate it by probing, so a stale value only costs the probe).
fn open_session(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session_id : String,
  workspace~ : String,
  generation~ : Int,
) -> @cmd.Cmd {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  load_session_cmd(
    channel,
    session_id,
    workspace~,
    on_loaded=view => {
      dispatch(
        SessionLoaded(
          session=session_id,
          items=view.items,
          watermark=view.watermark,
          event_boundaries=view.event_boundaries,
          generation~,
        ),
      )
    },
    on_failed=detail => {
      dispatch(
        SessionLoadFailed(
          session=session_id,
          message="failed to load session \{session_id}: " + detail,
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
  workspace~ : String,
  generation~ : Int,
) -> @cmd.Cmd {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  load_session_cmd(
    channel,
    session_id,
    workspace~,
    on_loaded=view => {
      dispatch(
        SessionRefreshed(
          session=session_id,
          items=view.items,
          watermark=view.watermark,
          event_boundaries=view.event_boundaries,
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
  workspace~ : String,
  on_loaded~ : (@transcript.SessionLoadView) -> @cmd.Cmd,
  on_failed~ : (String) -> @cmd.Cmd,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let payload = @js.Object::new()
      payload["session"] = session_id
      @interop.set_trimmed(payload, "workspace", workspace)
      let reply = @interop.bridge_request(
        channel,
        "session.load",
        payload.to_value(),
      ) catch {
        error => {
          scheduler.add(on_failed(@interop.bridge_error_text(error)))
          return
        }
      }
      match
        @transcript.decode_session_load_reply(@interop.reply_json_text(reply)) {
        Some(view) => scheduler.add(on_loaded(view))
        None => scheduler.add(on_failed("malformed data"))
      }
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
                SteerRejected(session~, submission_id~, text~, run_id~)
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
          dispatch(SteerRejected(session~, submission_id~, text~, run_id~)),
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
  let payload = @js.Object::new()
  payload["text"] = text
  payload["submission_id"] = submission_id
  payload["run_id"] = run_id
  let reply = @interop.bridge_request(
    channel,
    "agent.steer",
    payload.to_value(),
  )
  @interop.js_prop(reply, "steered") is Some(flag) &&
  (@js.Cast::into(flag) : Bool?) is Some(true)
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
  model~ : String,
  max_steps~ : String,
  workspace? : @pathx.Absolute,
) -> @cmd.Cmd {
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  let payload = @js.Object::new()
  set_engine_settings(payload, model~, max_steps~, session~, workspace?)
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let _ : @js.Value = @interop.bridge_request(
        channel,
        "agent.compact",
        payload.to_value(),
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
      }
    })
  })
}

///|
fn cancel_openseek(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  run_id : String,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let payload = @js.Object::new()
      payload["run_id"] = run_id
      let _ : @js.Value = @interop.bridge_request(
        channel,
        "agent.cancel",
        payload.to_value(),
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
      let _ : @js.Value = @interop.bridge_request(
        Local,
        "update.apply",
        @js.Object::new().to_value(),
      ) catch {
        error => {
          scheduler.add(
            dispatch(UpdateFailed(message=@interop.bridge_error_text(error))),
          )
          return
        }
      }
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
/// Ask the host to open a transcript-referenced file in the system's default
/// app. A relative `path` is taken against the conversation's working
/// directory — `cwd` when known, else derived by the host from `session`. A
/// failure (no opener, missing file) pops an error toast.
fn open_file(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session : String,
  cwd~ : @pathx.Absolute?,
  path : String,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let payload = @js.Object::new()
      payload["session"] = session
      @interop.set_trimmed(payload, "cwd", workspace_token(cwd))
      payload["path"] = path
      let _ : @js.Value = @interop.bridge_request(
        channel,
        "host.open_path",
        payload.to_value(),
      ) catch {
        error => {
          scheduler.add(
            dispatch(HostActionFailed(@interop.bridge_error_text(error))),
          )
          return
        }
      }
    })
  })
}
