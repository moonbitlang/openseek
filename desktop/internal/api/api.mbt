// The one method dispatcher behind every transport. The proton bridge and
// each remote WebSocket feed the same catalog (docs/remote-protocol.md)
// through `dispatch`; they differ only in envelope. Errors stay typed so
// each transport maps them to its own vocabulary: `@host.PayloadError` =
// malformed params, `@engine.EngineError` / `@host.HostError` = the op
// failed, `UnknownMethod` = a name outside the catalog.

///|
/// A method name this host does not serve.
pub(all) suberror UnknownMethod {
  UnknownMethod(String)
}

///|
impl Show for UnknownMethod with fn output(self, logger) {
  match self {
    UnknownMethod(method_) => logger.write_string("unknown method '\{method_}'")
  }
}

///|
/// Everything the methods operate on: the app-lifetime engine actor and its
/// request-side manager (one serve process per conversation), the host-op
/// state (LSP pool and updates), and the notification hub. One per host
/// process; each transport connection supplies its own `HostConnection` when
/// dispatching filesystem watch methods.
struct ApiState {
  engine : @engine.EngineActor
  manager : @engine.EngineManager
  host : @host.HostState
  hub : Hub
  // Called for every finished run, alongside the notification fan-out — the
  // desktop posts its system notification here.
  on_finished : ((@engine.FinishedPayload) -> Unit)?
}

///|
/// `engine` is the engine executable; `executable` is the host's own
/// binary, which self-update uses to locate the running .app bundle (absent
/// or non-bundle layouts only lose the in-app install, never the
/// announcement).
pub fn ApiState::new(
  engine~ : String,
  runtime_dir? : @path.Path,
  executable? : String,
  on_finished? : (@engine.FinishedPayload) -> Unit,
) -> ApiState {
  let engine_actor = @engine.new_engine_actor(engine, runtime_dir?)
  {
    engine: engine_actor,
    manager: engine_actor.manager(),
    host: @host.new_host_state(engine, runtime_dir?, executable?),
    hub: Hub::new(),
    on_finished,
  }
}

///|
/// The app-lifetime engine actor. Its `run` task owns all serve processes and
/// per-session follower children.
pub fn ApiState::engine_actor(self : ApiState) -> @engine.EngineActor {
  self.engine
}

///|
/// The engine event sink: fan out to every subscriber, and hand finished
/// runs to the notification hook.
pub fn ApiState::sink(self : ApiState) -> @engine.EventSink {
  self.hub.sink(on_finished?=self.on_finished)
}

///|
/// Register a notification subscriber: a bounded queue the hub pushes every
/// notification into. The caller drains it with `get` and MUST `unsubscribe`
/// when done (a defer next to the subscribe). A subscriber that stops
/// draining is kicked by the hub: its queue is closed, which ends the
/// drain loop.
pub fn ApiState::subscribe(self : ApiState) -> @async.Queue[Notification] {
  self.hub.subscribe()
}

///|
pub fn ApiState::unsubscribe(
  self : ApiState,
  queue : @async.Queue[Notification],
) -> Unit {
  self.hub.unsubscribe(queue)
}

///|
/// Publish one notification to every subscriber — shared host pumps such as
/// `lsp.diagnostics` go through here. Connection-owned `fs.changed` events
/// bypass the hub and return only to their owning connection.
pub fn ApiState::publish(
  self : ApiState,
  method_ : String,
  params : Json,
) -> Unit {
  self.hub.publish(method_, params)
}

///|
/// The host-op state, for the pumps spawned beside the dispatcher.
pub fn ApiState::host_state(self : ApiState) -> @host.HostState {
  self.host
}

///|
/// The request-side engine coordination handle.
pub fn ApiState::manager(self : ApiState) -> @engine.EngineManager {
  self.manager
}

///|
fn[T : @json.FromJson] decode(params : Json) -> T raise {
  @json.from_json(params) catch {
    _ => raise @host.PayloadError("malformed request payload")
  }
}

///|
/// Serve one method call. Every transport funnels through here.
pub async fn dispatch(
  state : ApiState,
  connection : @host.HostConnection,
  method_ : String,
  params : Json,
) -> Json {
  match method_ {
    "agent.start" => {
      let payload : StartPayload = decode(params)
      @engine.start_run(state.sink(), state.manager, payload.to_request()).to_json()
    }
    "agent.cancel" => {
      let payload : CancelPayload = decode(params)
      @engine.cancel_run(state.manager, payload.to_request()).to_json()
    }
    "agent.steer" => {
      let payload : SteerPayload = decode(params)
      @engine.steer_run(state.manager, payload.to_request()).to_json()
    }
    "agent.compact" => {
      let payload : CompactPayload = decode(params)
      @engine.compact_run(state.manager, payload.to_request()).to_json()
    }
    "agent.runs" => {
      let payload : RunsPayload = decode(params)
      state.hub.runs(known?=payload.known)
    }
    "session.list" => @engine.list_sessions(state.manager).to_json()
    "session.load" => {
      let payload : LoadSessionPayload = decode(params)
      @engine.load_session(state.manager, payload.to_request()).to_json()
    }
    "session.list_archived" =>
      @engine.archived_sessions(state.manager, session => {
        publish_session_changed(state, "archived", session)
      }).to_json()
    "session.archive" => {
      let payload : SessionPayload = decode(params)
      let session = payload.canonical_session()
      // The callback runs inside the rename's cancellation shield. Every
      // other client learns the canonical id before any cancellable list
      // reply, so a cancelled requester cannot suppress invalidation.
      @engine.archive_session(state.manager, session, () => {
        publish_session_changed(state, "archived", session)
      }).to_json()
    }
    "session.unarchive" => {
      let payload : SessionPayload = decode(params)
      let session = payload.canonical_session()
      @engine.unarchive_session(state.manager, session, () => {
        publish_session_changed(state, "unarchived", session)
      }).to_json()
    }
    "settings.get" => @engine.settings_status(state.manager)
    "settings.set" => {
      let payload : SettingsSetPayload = decode(params)
      // The store commit and its broadcast are one finite cancellation-
      // shielded linearization point. `update_settings` invokes the callback
      // while its manager-owned lock is still held, preserving revision order
      // across concurrent clients even if the requester disconnects.
      @async.protect_from_cancel(() => {
        @engine.update_settings(state.manager, payload.to_patch(), on_committed=fn(
          status,
        ) {
          // Every client renders these settings (the Settings page, the
          // composer's ready gate); clients that did not ask must learn too.
          state.hub.publish("settings.changed", status)
        })
      })
    }
    "workspace.list" => @engine.list_workspaces().to_json()
    "workspace.add" => {
      let payload : WorkspacePayload = decode(params)
      @engine.attach_workspace(payload.path, workspaces => {
        state.hub.publish("workspace.changed", {
          "workspaces": workspaces.to_json(),
        })
      }).to_json()
    }
    "workspace.remove" => {
      let payload : WorkspacePayload = decode(params)
      @engine.detach_workspace(state.manager, payload.path, workspaces => {
        state.hub.publish("workspace.changed", {
          "workspaces": workspaces.to_json(),
        })
      }).to_json()
    }
    "host.meta" =>
      // `wsl` is the host's own capability: the engine runs here, so the
      // client must not guess it from the page's user agent (a phone browser
      // may drive a Windows host, a Windows browser a Mac one).
      {
        "protocol": 2,
        "name": "openseek-host",
        "wsl": Json::boolean(HostWslCapable),
      }
    _ =>
      match
        @host.host_op(state.host, connection, method_, params, (method_, params) => {
          state.hub.publish(method_, params)
        }) {
        Some(reply) => reply
        None => raise UnknownMethod(method_)
      }
  }
}

///|
/// Whether this host can run the engine inside WSL — a Windows host.
#cfg(platform="windows")
const HostWslCapable = true

///|
#cfg(not(platform="windows"))
const HostWslCapable = false

///|
/// Tell every client a conversation moved between the live and archived
/// stores, so the ones that did not ask re-read both lists and drop live
/// state for the moved record.
fn publish_session_changed(
  state : ApiState,
  change : String,
  session : String,
) -> Unit {
  state.hub.publish("session.changed", {
    "change": Json::string(change),
    "session": Json::string(session),
  })
}

///|
/// Every method in the catalog — the transport adapters register exactly
/// this set.
pub fn method_names() -> Array[String] {
  [
    "agent.start", "agent.cancel", "agent.steer", "agent.compact", "agent.runs",
    "session.list", "session.load", "session.list_archived", "session.archive", "session.unarchive",
    "settings.get", "settings.set", "workspace.list", "workspace.add", "workspace.remove",
    "host.meta",
  ] +
  @host.host_method_names()
}
