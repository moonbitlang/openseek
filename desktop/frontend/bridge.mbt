// The engine-host bridge: typed access to the ops and events the desktop
// host (`internal/host`) exposes through proton's injected
// `globalThis.__MoonBit__` object. Ops are promise-returning calls on
// `__MoonBit__.openseek`; engine progress arrives as `openseek.*` events on
// `__MoonBit__.events` and is decoded here into messages.

///|
/// Both bridge handles, present only when the surface the frontend relies
/// on is fully injected.
fn bridge_handles() -> (@js.Value, @js.Value)? {
  guard @interop.openseek_api() is Some(api) &&
    @interop.moonbit_bridge_root() is Some(root) &&
    @interop.js_prop(root, "events") is Some(events) &&
    @interop.js_prop(api, "connect") is Some(_) &&
    @interop.js_prop(api, "start") is Some(_) &&
    @interop.js_prop(api, "cancel") is Some(_) &&
    @interop.js_prop(events, "on") is Some(_) else {
    return None
  }
  Some((api, events))
}

///|
let bridge_events_wired : Ref[Bool] = Ref(false)

///|
/// Wait for lepus to inject the bridge (it loads alongside this bundle),
/// wire the engine-host event stream into messages once, and report
/// readiness. The 25ms retries add up to ~3 seconds before the bridge is
/// declared unavailable.
fn install_bridge(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  install_bridge_attempt(dispatch, 0)
}

///|
fn install_bridge_attempt(dispatch : @cmd.Emit[Msg], attempt : Int) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    guard bridge_handles() is Some((api, events)) else {
      if attempt > 120 {
        scheduler.add(dispatch(BridgeUnavailable("Bridge unavailable")))
      } else {
        scheduler.add(
          @cmd.delay(install_bridge_attempt(dispatch, attempt + 1), 25),
        )
      }
      return
    }
    if !bridge_events_wired.val {
      bridge_events_wired.val = true
      wire_engine_events(scheduler, dispatch, events)
      open_engine_host(scheduler, dispatch, api)
    }
  })
}

///|
/// Open the engine host: a single long-lived call whose task group owns the
/// persistent `--serve` engine process. The promise only settles if the
/// host stops; starts then fail with a clear error, so the rejection itself
/// carries no extra signal.
fn open_engine_host(
  scheduler : &@cmd.Scheduler,
  dispatch : @cmd.Emit[Msg],
  api : @js.Value,
) -> Unit {
  @js.async_run(() => {
    let _ : @js.Value = @interop.js_method_promise(
      api,
      "connect",
      @js.Object::new().to_value(),
    ).wait() catch {
      error => {
        scheduler.add(
          dispatch(BridgeUnavailable(@interop.bridge_error_text(error))),
        )
        return
      }
    }
  })
}

///|
fn wire_engine_events(
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

  on("openseek.started", started_msg)
  on("openseek.event", engine_msg)
  on("openseek.error", error_msg)
  on("openseek.finished", finished_msg)
  on("openseek.connected", connected_msg)
  on("openseek.diagnostics", diagnostics_msg)
  on("openseek.fs_changed", fs_changed_msg)
  // Emitted by proton itself (not the openseek extension) when the user
  // clicks a system notification; the payload is the run id the host stamped
  // on the notification.
  on("proton.notification_clicked", notification_clicked_msg)
}

///|
/// A lepus event's payload as JSON fields. Payloads cross the bridge as
/// structured clones of the host's JSON, so the round trip back through
/// JSON is lossless; an event without a decodable payload is dropped.
fn event_payload(event : @js.Value) -> Map[String, Json]? {
  guard @interop.js_prop(event, "payload") is Some(payload) else { return None }
  let json = payload.to_json() catch { _ => return None }
  guard json is Object(fields) else { return None }
  Some(fields)
}

///|
fn started_msg(payload : Map[String, Json]) -> Msg? {
  // `run_id`/`session`/`model`/`max_steps` are unconditional on this event
  // (the app's own start op always names a session); a payload missing one
  // is malformed and dropped. `cwd` is genuinely optional — omitted for a
  // scratch conversation — and the host resolved it itself, so this is the
  // decode boundary where its absolute provenance is collapsed into the type.
  guard @jsonx.json_int(payload, "run_id") is Some(run_id) &&
    @jsonx.json_text(payload, "session") is Some(session) &&
    @jsonx.json_text(payload, "model") is Some(model) &&
    @jsonx.json_int(payload, "max_steps") is Some(max_steps) else {
    return None
  }
  Some(
    Started(
      run_id~,
      session~,
      model~,
      max_steps~,
      cwd=@jsonx.json_text(payload, "cwd").map(path => Absolute(path)),
    ),
  )
}

///|
fn engine_msg(payload : Map[String, Json]) -> Msg? {
  guard @jsonx.json_int(payload, "run_id") is Some(run_id) &&
    payload.get("event") is Some(Object(raw)) else {
    return None
  }
  guard @transcript.decode_engine_event(raw) is Some(event) else { return None }
  Some(Engine(run_id, event, session=@jsonx.json_text(payload, "session")))
}

///|
/// A host error without a run (`run_id` omitted — a pre-run failure)
/// belongs to whatever conversation the user is looking at; `None` routes
/// it there. `diagnostics` rides along only when the host had stderr worth
/// showing. Unlike other events, a malformed error is not dropped: an error
/// must never vanish silently, so a missing or blank `message` still
/// surfaces, labeled generically.
fn error_msg(payload : Map[String, Json]) -> Msg? {
  let message = if @jsonx.json_text(payload, "message") is Some(message) &&
    !message.trim().is_empty() {
    message
  } else {
    "error"
  }
  Some(
    Error(
      run_id=@jsonx.json_int(payload, "run_id"),
      message~,
      diagnostics=@jsonx.json_text(payload, "diagnostics"),
    ),
  )
}

///|
fn finished_msg(payload : Map[String, Json]) -> Msg? {
  // `answer` is present only when the agent finished with one.
  guard @jsonx.json_int(payload, "run_id") is Some(run_id) &&
    @jsonx.json_text(payload, "status") is Some(status) else {
    return None
  }
  Some(Finished(run_id~, status~, answer=@jsonx.json_text(payload, "answer")))
}

///|
fn connected_msg(_payload : Map[String, Json]) -> Msg? {
  Some(BridgeReady)
}

///|
/// A `diagnostics` push: the language server re-analyzed a file. The payload
/// carries the absolute `path` and the raw LSP `diagnostics` array; the update
/// filters it to the file on screen.
fn diagnostics_msg(payload : Map[String, Json]) -> Msg? {
  guard @jsonx.json_text(payload, "path") is Some(path) && !path.is_empty() else {
    return None
  }
  Some(
    FileEditor(
      DiagnosticsPublished(
        absolute=Absolute(path),
        diagnostics=payload.get("diagnostics").unwrap_or([]),
      ),
    ),
  )
}

///|
/// An `fs_changed` push: something under the watched workspace changed. The
/// payload's `root` is not carried — the panel re-checks against whatever
/// conversation is current, so a push that raced a switch stats the right
/// files anyway.
fn fs_changed_msg(_payload : Map[String, Json]) -> Msg? {
  Some(FileEditor(FsChanged))
}

///|
/// A clicked notification's payload is the decimal run id `notify.mbt`
/// stamped on it; anything unparsable is dropped (a stale notification from
/// an older build, or a payload another surface posted).
fn notification_clicked_msg(payload : Map[String, Json]) -> Msg? {
  guard @jsonx.json_text(payload, "payload") is Some(text) else { return None }
  let run_id = @string.parse_int(text) catch { _ => return None }
  Some(NotificationClicked(run_id~))
}

///|
fn start_openseek(
  dispatch : @cmd.Emit[Msg],
  task : String,
  selected_model : String,
  max_steps : String,
  api_key : String,
  api_url : String,
  session : String,
  workspace~ : @pathx.Absolute?,
  wsl_enabled~ : Bool,
  wsl_distro~ : String,
  wsl_engine~ : String,
) -> @cmd.Cmd {
  let payload = start_payload(
    task,
    selected_model,
    max_steps,
    api_key,
    api_url,
    session,
    workspace~,
    wsl_enabled~,
    wsl_distro~,
    wsl_engine~,
  )
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let _ : @js.Value = @interop.bridge_request("start", payload) catch {
        error => {
          scheduler.add(
            dispatch(
              Failed(session~, message=@interop.bridge_error_text(error)),
            ),
          )
          return
        }
      }
    })
  })
}

///|
/// The start payload. Optional fields are trimmed and omitted when blank —
/// the host documents that a present field always carries non-blank text —
/// and it carries no `cwd`: `workspace` (the conversation's attached project,
/// omitted for scratch conversations) is the only placement the host takes;
/// everything else it derives from the session id.
fn start_payload(
  task : String,
  selected_model : String,
  max_steps : String,
  api_key : String,
  api_url : String,
  session : String,
  workspace~ : @pathx.Absolute?,
  wsl_enabled~ : Bool,
  wsl_distro~ : String,
  wsl_engine~ : String,
) -> @js.Value {
  let payload = @js.Object::new()
  payload["task"] = task
  set_engine_settings(
    payload,
    model=selected_model,
    max_steps~,
    api_key~,
    api_url~,
    session~,
    workspace?,
    wsl_enabled~,
    wsl_distro~,
    wsl_engine~,
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
  api_key~ : String,
  api_url~ : String,
  session~ : String,
  workspace? : @pathx.Absolute,
  wsl_enabled~ : Bool,
  wsl_distro~ : String,
  wsl_engine~ : String,
) -> Unit {
  @interop.set_trimmed(payload, "model", model)
  @interop.set_trimmed(payload, "api_key", api_key)
  @interop.set_trimmed(payload, "api_url", api_url)
  @interop.set_trimmed(payload, "session", session)
  @interop.set_workspace(payload, workspace)
  if parsed_max_steps(max_steps) is Some(steps) {
    payload["max_steps"] = steps
  }
  // The presence of `wsl` is the opt-in; blank distro/engine fields are
  // omitted so the host applies its defaults (default distro, `openseek`
  // on the distro's PATH).
  if wsl_enabled {
    let wsl = @js.Object::new()
    @interop.set_trimmed(wsl, "distro", wsl_distro)
    @interop.set_trimmed(wsl, "engine", wsl_engine)
    payload["wsl"] = wsl.to_value()
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
fn fetch_sessions(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => refresh_sessions_into(scheduler, dispatch))
  })
}

///|
/// Fetch the live session list and fold the reply into `scheduler` — the
/// body of `fetch_sessions`, shared with every command whose op changes what
/// that list contains (archive/unarchive moves, workspace add/remove).
async fn refresh_sessions_into(
  scheduler : &@cmd.Scheduler,
  dispatch : @cmd.Emit[Msg],
) -> Unit noraise {
  let reply = @interop.bridge_request(
    "list_sessions",
    @js.Object::new().to_value(),
  ) catch {
    error => {
      scheduler.add(dispatch(SessionsFailed(@interop.bridge_error_text(error))))
      return
    }
  }
  match @transcript.decode_sessions_reply(@interop.reply_json_text(reply)) {
    Some(items) => scheduler.add(dispatch(SessionsLoaded(items)))
    None => scheduler.add(dispatch(SessionsFailed("malformed session list")))
  }
}

///|
/// Load a durable session's transcript so the conversation can be resumed.
/// `workspace` says which store holds it ("" = the default store; the host
/// can also locate it by probing, so a stale value only costs the probe).
fn open_session(
  dispatch : @cmd.Emit[Msg],
  session_id : String,
  workspace~ : String,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let payload = @js.Object::new()
      payload["session"] = session_id
      @interop.set_trimmed(payload, "workspace", workspace)
      let reply = @interop.bridge_request("load_session", payload.to_value()) catch {
        error => {
          scheduler.add(
            dispatch(
              SessionLoadFailed(
                session=session_id,
                message="failed to load session \{session_id}: " +
                  @interop.bridge_error_text(error),
              ),
            ),
          )
          return
        }
      }
      match
        @transcript.transcript_from_session_json(
          @interop.reply_json_text(reply),
        ) {
        Some(items) =>
          scheduler.add(dispatch(SessionLoaded(session=session_id, items~)))
        None =>
          scheduler.add(
            dispatch(
              SessionLoadFailed(
                session=session_id,
                message="failed to load session \{session_id}: malformed data",
              ),
            ),
          )
      }
    })
  })
}

///|
/// Inject steering input into the running turn. Delivery is acknowledged by
/// the engine's own `steer_applied`/`steer_dropped` events; this command only
/// reports the cases where no such event will ever come — the host refused
/// the steer (turn already closed, engine dead) or the bridge call failed —
/// so the pending acknowledgment can settle either way.
fn steer_openseek(
  dispatch : @cmd.Emit[Msg],
  session : String,
  text : String,
  run_id : Int,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let delivered = steer_delivered(text, run_id) catch { _ => false }
      if !delivered {
        scheduler.add(dispatch(SteerUndelivered(session~, text~)))
      }
    })
  })
}

///|
async fn steer_delivered(text : String, run_id : Int) -> Bool {
  let payload = @js.Object::new()
  payload["text"] = text
  payload["run_id"] = run_id
  let reply = @interop.bridge_request("steer", payload.to_value())
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
  session~ : String,
  model~ : String,
  max_steps~ : String,
  api_key~ : String,
  api_url~ : String,
  workspace? : @pathx.Absolute,
  wsl_enabled~ : Bool,
  wsl_distro~ : String,
  wsl_engine~ : String,
) -> @cmd.Cmd {
  let payload = @js.Object::new()
  set_engine_settings(
    payload,
    model~,
    max_steps~,
    api_key~,
    api_url~,
    session~,
    workspace?,
    wsl_enabled~,
    wsl_distro~,
    wsl_engine~,
  )
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let _ : @js.Value = @interop.bridge_request("compact", payload.to_value()) catch {
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
fn cancel_openseek(dispatch : @cmd.Emit[Msg], run_id : Int) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let payload = @js.Object::new()
      payload["run_id"] = run_id
      let _ : @js.Value = @interop.bridge_request("cancel", payload.to_value()) catch {
        error => {
          scheduler.add(
            dispatch(
              Error(
                run_id=Some(run_id),
                message=@interop.bridge_error_text(error),
                diagnostics=None,
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
      let _ : @js.Value = @interop.bridge_request(
        "apply_update",
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
  session : String,
  cwd~ : @pathx.Absolute?,
  path : String,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let payload = @js.Object::new()
      payload["session"] = session
      payload["cwd"] = workspace_token(cwd)
      payload["path"] = path
      let _ : @js.Value = @interop.bridge_request(
        "open_path",
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
