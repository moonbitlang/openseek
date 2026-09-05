// The engine-host bridge: typed access to the host's methods and
// notifications (docs/remote-protocol.md). Methods go through
// `@interop.bridge_request`; notifications arrive either as `openseek.*`
// proton events (the desktop window) or as JSON-RPC notifications on the
// page's WebSocket (a browser through the relay). `frontend/bridge` owns both
// transports; both feed the same decoders below.

///|
/// Purely decode one non-terminal host notification, retaining the channel it
/// arrived on. Device-scoped notifications wrap as `FromDevice`; page-global
/// and focused-scoped notifications stay root messages. Terminal notifications
/// return `None` because `bridge_event` sends their commands directly.
fn notification_msg(
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
    // A long semantic scan streams partial hits while the final reply is
    // still running. The Search reducer fences the stream by
    // session_key/generation and the final reply replaces these rows, so a
    // dropped frame only delays a paint — never corrupts the result set.
    SemanticSearchProgress(payload) =>
      Some(
        FromDevice(
          channel,
          FilePanel(
            @fileeditor.Msg::Search(
              @grep_search.Msg::SemanticProgress(
                root=payload.root,
                session_key=payload.session_key,
                generation=payload.generation,
                matches=payload.matches,
                match_count=payload.match_count,
                file_count=payload.file_count,
              ),
            ),
          ),
        ),
      )
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
    WorkflowEntry(payload) =>
      Some(
        WorkflowEntryArrived(channel, {
          workflow: payload.workflow,
          session: payload.session,
          child: payload.child,
          kind: payload.kind,
          label: payload.label,
          phase: payload.phase,
          status: payload.status,
          steps: payload.steps,
          prompt_tokens: payload.prompt_tokens,
          completion_tokens: payload.completion_tokens,
          cost_usd: payload.cost_usd,
          started_at: payload.started_at,
          finished_at: payload.finished_at,
        }),
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
/// Decode one store-qualified session change synchronously. A fresh id is
/// allocated at the event boundary (outside `update`) so archiving or deleting
/// the active conversation can switch without a render where Send targets the
/// stale id; rename only drives the shared list refresh.
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
// Adapt the bridge package's transport-neutral events into this application's
// root messages and direct terminal commands.

///|
/// Turn one event emitted by a local or remote bridge subscription into a
/// command understood by the root application. Raw terminal output bypasses
/// application dispatch to avoid an unrelated redraw; other notifications are
/// decoded into root messages here alongside connection and window events.
fn bridge_event(dispatch : @cmd.Emit[Msg], event : @bridge.Event) -> @cmd.Cmd {
  match event {
    @bridge.Event::Notification(channel~, notification~) =>
      match notification {
        TerminalOutput(payload) =>
          @terminal.output(channel, payload.id, payload.sequence, payload.data)
        TerminalExit(payload) =>
          @terminal.SessionExited(channel~, id=payload.id, code=payload.code)
          |> Terminal
          |> dispatch
        _ =>
          if notification_msg(channel, notification) is Some(msg) {
            dispatch(msg)
          } else {
            @cmd.none
          }
      }
    @bridge.Event::Unavailable(channel~, message~) =>
      dispatch(FromDevice(channel, BridgeUnavailable(message)))
    @bridge.Event::ChannelDown(channel~, websocket_epoch~) =>
      dispatch(FromDevice(channel, ChannelDown(websocket_epoch~)))
    @bridge.Event::BrowserEvent(payload~) =>
      if browser_event_msg(payload) is Some(msg) {
        dispatch(msg)
      } else {
        @cmd.none
      }
    @bridge.Event::MenuCommand(command_id~) =>
      if command_id == @commands.app_open_devtools.name() {
        dispatch(AppDeveloperToolsRequested)
      } else if command_id == @commands.CloseFocusedMenuCommand {
        close_focused(dispatch)
      } else {
        @cmd.none
      }
    @bridge.Event::NotificationClicked(run_id~) =>
      dispatch(NotificationClicked(run_id~))
  }
}

///|
fn DeviceState::bridge_subscription(
  self : DeviceState,
  dispatch : @cmd.Emit[Msg],
) -> @sub.Sub {
  let bridge_dispatch : @cmd.Emit[@bridge.Event] = event => {
    bridge_event(dispatch, event)
  }
  match self.channel {
    Local => @bridge.local_connection(bridge_dispatch)
    Remote(device) =>
      @bridge.remote_connection(
        device_id=device,
        websocket_epoch=self.websocket_epoch,
        reconnect_attempt=self.reconnect_attempt,
        dispatch=bridge_dispatch,
      )
  }
}

///|
/// Declare one host notification source per device in the model. Rabbita
/// owns installation and cleanup from here; request/reply commands remain
/// independent one-shot effects.
fn Model::bridge_subscriptions(
  self : Model,
  dispatch : @cmd.Emit[Msg],
) -> @sub.Sub {
  @sub.batch(self.devices.map(dev => dev.bridge_subscription(dispatch)))
}

///|
test "Codex app-server notifications route to Codex state" {
  assert_true(
    notification_msg(
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
test "skill invalidations are device-scoped catalog events" {
  assert_true(
    notification_msg(Remote("d1"), @protocol.Notification::SkillsChanged)
    is Some(FromDevice(Remote("d1"), SkillsChanged)),
  )
}

///|
test "update download notifications control only the local desktop flow" {
  assert_true(
    notification_msg(
      Local,
      @protocol.Notification::UpdateDownloadProgress({
        downloaded_bytes: 42,
        total_bytes: Some(100),
      }),
    )
    is Some(UpdateDownloadProgress(downloaded_bytes=42, total_bytes=Some(100))),
  )
  assert_true(
    notification_msg(
      Local,
      @protocol.Notification::UpdateDownloaded({ version: "test", }),
    )
    is Some(UpdateDownloaded),
  )
  assert_true(
    notification_msg(
      Local,
      @protocol.Notification::UpdateDownloadFailed({
        message: "digest mismatch",
      }),
    )
    is Some(UpdateFailed(message="digest mismatch")),
  )
  assert_true(
    notification_msg(
      Local,
      @protocol.Notification::UpdateDownloadProgress({
        downloaded_bytes: -1,
        total_bytes: None,
      }),
    )
    is None,
  )
  assert_true(
    notification_msg(
      Remote("d1"),
      @protocol.Notification::UpdateDownloadProgress({
        downloaded_bytes: 42,
        total_bytes: None,
      }),
    )
    is None,
  )
  assert_true(
    notification_msg(
      Remote("d1"),
      @protocol.Notification::UpdateDownloaded({ version: "test", }),
    )
    is None,
  )
}

///|
test "file-panel pushes carry their channel; auth.changed is Local-only" {
  let channel : @interop.ChannelId = Remote("d1")
  assert_true(
    notification_msg(
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
    notification_msg(
      channel,
      @protocol.Notification::FsChanged({
        root: "/work/project",
        baseline: false,
        events: [
          { kind_: "modify", path: "src/main.mbt", old_path: None, },
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
  assert_true(
    notification_msg(
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
    notification_msg(
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

// ---------------------------------------------------------------------------
// A browser: JSON-RPC over the page's WebSocket, with reconnection.

///|
/// Consecutive connection losses before the user is told the host is
/// unreachable. The loop keeps reconnecting regardless; the next
/// `agent.connected` restores the UI.
const WsLostAfter = 3

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
      // Standing questions come back unfiltered: unlike a settlement, which is
      // history only its owner wants, a blocked turn is stopped right now and
      // whoever is looking at that session should be able to unblock it.
      let recovered_approvals : Array[RecoveredApproval] = []
      for item in reply.approvals {
        recovered_approvals.push({
          session: item.session,
          approval: {
            id: item.id,
            run_id: item.run_id,
            tool_name: item.tool_name,
            detail: item.detail,
            body: item.body,
            // Replayed to a page that never sent a decision for it, so the
            // card comes back answerable. A decision this page sent before it
            // reloaded either reached the engine — and the question is gone
            // from the host, so there is nothing here to replay — or it did
            // not, and offering it again is the point.
            answered: false,
          },
        })
      }
      scheduler.add(
        dispatch(
          RunsLoaded(
            runs=recovered,
            settled=recovered_settlements,
            approvals=recovered_approvals,
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
  { known: Some(known), }
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
fn start_openseek(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  task : String,
  submission_id : String,
  selected_model : EngineModel,
  reasoning : OpenSeekReasoning,
  max_steps : String,
  session : String,
  workspace~ : @common.Uri,
) -> @cmd.Cmd {
  guard @resource.belongs_to(workspace, channel) else { return @cmd.none }
  let payload = start_payload(
    task,
    selected_model,
    reasoning,
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
  reasoning : OpenSeekReasoning,
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
    thinking: selected_model.thinking(reasoning),
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
/// Everything a topbar export click needs after the view that created it is
/// gone. Keeping the source channel and workspace together prevents a delayed
/// command from being redirected by a later device or conversation switch.
priv struct SessionExport {
  channel : @interop.ChannelId
  session : String
  workspace : @common.Uri
  title : String
  archived : Bool
}

///|
/// Open the native save dialog and ask the local host to freeze this exact
/// durable conversation into a standalone visualizer document. A saved file
/// that the platform cannot open is reported separately from an export error.
fn SessionExport::command(
  self : SessionExport,
  dispatch : @cmd.Emit[Msg],
) -> @cmd.Cmd {
  guard self.channel is Local &&
    @resource.belongs_to(self.workspace, self.channel) else {
    return @cmd.none
  }
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply : @protocol.SessionExportReply = @interop.bridge_request(
        self.channel,
        @commands.session_export,
        {
          session: self.session,
          workspace: self.workspace.path,
          title: self.title,
          archived: self.archived,
        },
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              HostActionFailed(
                "Failed to export conversation: \{@interop.bridge_error_text(error)}",
              ),
            ),
          )
          return
        }
      }
      if reply.path is Some(path) && !reply.opened {
        scheduler.add(dispatch(SessionExportOpenFailed(path~)))
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
fn queue_openseek(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session : String,
  action : @protocol.QueueAction,
  run_id : String,
) -> @cmd.Cmd {
  let root_dispatch = dispatch
  let dispatch = dispatch.map((msg : DeviceMsg) => FromDevice(channel, msg))
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let accepted = try {
        let reply = @interop.bridge_request(channel, @commands.agent_queue, {
          action,
          run_id,
        })
        reply.accepted
      } catch {
        error => {
          scheduler.add(
            match action {
              QueueAdd(id~, ..) =>
                dispatch(QueueAddRejected(session~, submission_id=id, run_id~))
              QueueSteer(id~) =>
                dispatch(
                  QueueSteerRejected(
                    session~,
                    submission_id=id,
                    run_id~,
                    message="Queue action failed: \{@interop.bridge_error_text(error)}",
                  ),
                )
              QueueEdit(..) | QueueWithdraw(..) =>
                root_dispatch(
                  HostActionFailed(
                    "Queue action failed: \{@interop.bridge_error_text(error)}",
                  ),
                )
            },
          )
          return
        }
      }
      if !accepted {
        scheduler.add(
          match action {
            QueueAdd(id~, ..) =>
              dispatch(QueueAddRejected(session~, submission_id=id, run_id~))
            QueueSteer(id~) =>
              dispatch(
                QueueSteerRejected(
                  session~,
                  submission_id=id,
                  run_id~,
                  message="The queued message is no longer available.",
                ),
              )
            QueueEdit(..) | QueueWithdraw(..) =>
              root_dispatch(
                HostActionFailed("The queued message is no longer available."),
              )
          },
        )
      } else {
        scheduler.add(dispatch(QueueAccepted(session~, action~, run_id~)))
      }
    })
  })
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
  reasoning~ : OpenSeekReasoning,
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
            thinking: model.thinking(reasoning),
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
  reasoning~ : OpenSeekReasoning,
  max_steps~ : String,
  workspace~ : @common.Uri,
  command : String,
  text : String?,
) -> @cmd.Cmd {
  guard @resource.belongs_to(workspace, channel) else { return @cmd.none }
  let payload = goal_payload(
    session, model, reasoning, max_steps, workspace, text,
  )
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
  reasoning : OpenSeekReasoning,
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
    thinking: model.thinking(reasoning),
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
/// Ask the host to cancel `run_id`. A matching reply leaves the run in
/// Cancelling until its `agent.finished`. An empty reply means the turn had
/// already ended; report that boundary explicitly because the Finished push
/// may be the very notification this page missed. Failures are likewise tied
/// to the exact run so the optimistic Cancelling phase can be made retryable.
fn cancel_openseek(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  run_id : String,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply : @protocol.CancelReply = @interop.bridge_request(
        channel,
        @commands.agent_cancel,
        { run_id: Some(run_id), },
      ) catch {
        error => {
          scheduler.add(
            dispatch(
              FromDevice(
                channel,
                CancelFailed(
                  run_id~,
                  message="Failed to cancel the run: " +
                    @interop.bridge_error_text(error),
                ),
              ),
            ),
          )
          return
        }
      }
      if reply.run_id is None {
        scheduler.add(dispatch(FromDevice(channel, CancelNotOpen(run_id~))))
      }
    })
  })
}

///|
/// Answer the permission question `id`, which a tool in `run_id` is blocked
/// on.
///
/// A successful send does not retire the card. What retires it is the engine's
/// own `approval_resolved`, which is the only evidence the decision actually
/// reached the tool — a reply saying the host wrote the line is not the same as
/// the engine having read it.
///
/// A FAILED send must put the card back, though, and that is not symmetric with
/// the above. The decision never left this page, so no settlement is coming for
/// it, and there is no deadline behind the question either: leaving the card
/// marked answered would strand it reading "Sending…" forever with the engine
/// still blocked, and cancelling the run would be the only way out.
fn approve_openseek(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session : String,
  id : String,
  run_id : String?,
  allow~ : Bool,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply : @protocol.ApprovalReply = @interop.bridge_request(
        channel,
        @commands.agent_approval,
        { id, allow, run_id, },
      ) catch {
        error => {
          scheduler.add(dispatch(ApprovalAnswerFailed(channel~, session~, id~)))
          scheduler.add(
            dispatch(
              HostActionFailed(
                "Failed to answer the approval request: " +
                @interop.bridge_error_text(error),
              ),
            ),
          )
          return
        }
      }
      if !reply.delivered {
        // The host had no live engine to hand it to. Restore it anyway: being
        // refused a second time is a better end than a card that cannot be
        // pressed at all.
        scheduler.add(dispatch(ApprovalAnswerFailed(channel~, session~, id~)))
        scheduler.add(
          dispatch(
            HostActionFailed(
              "That approval request is no longer waiting — the turn it belonged to has ended.",
            ),
          ),
        )
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
      let _ : @protocol.EmptyReply = @interop.codex_request(
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
                owner={ channel, session, },
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
                owner={ channel, session, },
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
                owner={ channel, session, },
                generation~,
                path=target.path,
              ),
            ),
          )
        Refused(message) =>
          scheduler.add(
            dispatch(
              OpenFileFailed(owner={ channel, session, }, generation~, message~),
            ),
          )
        // The host already handed the path to the system opener.
        Opened => ()
      }
    })
  })
}

///|
/// Ask the local conversation host to show one referenced path in the system
/// file manager. Unlike `open_file`, this never changes the editor panel.
fn reveal_file(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  session : String,
  cwd : @common.Uri,
  path : String,
) -> @cmd.Cmd {
  guard channel is Local && @resource.belongs_to(cwd, channel) else {
    return @cmd.none
  }
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let reply : @protocol.RevealPathReply = @interop.bridge_request(
        channel,
        @commands.host_reveal_path,
        { session, cwd: Some(cwd.path), path, },
      ) catch {
        error => {
          scheduler.add(
            dispatch(HostActionFailed(@interop.bridge_error_text(error))),
          )
          return
        }
      }
      if reply is RevealRefused(message) {
        scheduler.add(dispatch(HostActionFailed(message)))
      }
    })
  })
}
