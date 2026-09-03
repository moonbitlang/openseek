// The native endpoint catalog behind both Desktop transports. Each entry
// pairs one typed command descriptor with its typed operation once; Proton
// binds the captured types directly, while remote JSON-RPC invokes the JSON
// closure retained by the same endpoint.

///|
/// Everything the methods operate on: the app-lifetime engine actor and its
/// request-side manager (one serve process per conversation), the host-op
/// state (LSP pool and updates), and the notification hub. One per host
/// process; each transport connection supplies its own `HostConnection` when
/// dispatching filesystem watch methods.
struct ApiState {
  // One Codex app-server process for this Desktop process. It is independent
  // of the OpenSeek engine actor and owns Codex account/thread state through
  // Codex's own data directory.
  codex : @codex.Actor
  // App-server returns each thread cwd but not its owning local project. Keep
  // Git's worktree relationship beside the Codex actor and reuse it across
  // list/read/start replies instead of making the browser infer path names.
  codex_projects : @codex.ProjectCatalog
  // A successful thread/start is remembered under Desktop's draft id until
  // the frontend closes that draft. If the relay loses the typed reply, the
  // same Send returns this exact task instead of creating an orphan sibling.
  codex_draft_threads : CodexDraftThreads
  engine : @engine.EngineActor
  manager : @engine.EngineManager
  host : @host.HostState
  hub : Hub
  // The host's relay sign-in state, shared with the relay actor.
  auth : @auth.AuthStore
  // Installed package version read from Proton's generated package manifest.
  app_version : String
  // Called for every finished run, alongside the notification fan-out — the
  // desktop posts its system notification here.
  on_finished : ((@protocol.FinishedPayload) -> Unit)?
}

///|
priv struct CodexDraftThreadEntry {
  cwd : String?
  reply : @protocol.CodexThreadReply
}

///|
/// Process-lifetime idempotency records for Desktop-created Codex drafts. The
/// app-server has no creation key of its own, so this native boundary must keep
/// a successful result across a lost relay reply.
priv struct CodexDraftThreads {
  entries : Map[String, CodexDraftThreadEntry]
}

///|
fn CodexDraftThreads::CodexDraftThreads() -> CodexDraftThreads {
  { entries: Map([]), }
}

///|
fn CodexDraftThreads::cached(
  self : CodexDraftThreads,
  request : @protocol.CodexThreadStartPayload,
) -> @protocol.CodexThreadReply? raise {
  guard request.draft_id is Some(draft_id) else { return None }
  guard self.entries.get(draft_id) is Some(entry) else { return None }
  if entry.cwd != request.cwd {
    raise @host.PayloadError(
      "Codex draft id was reused with a different working directory",
    )
  }
  Some(entry.reply)
}

///|
fn CodexDraftThreads::remember(
  self : CodexDraftThreads,
  request : @protocol.CodexThreadStartPayload,
  reply : @protocol.CodexThreadReply,
) -> Unit {
  if request.draft_id is Some(draft_id) {
    self.entries[draft_id] = { cwd: request.cwd, reply, }
  }
}

///|
fn CodexDraftThreads::forget(
  self : CodexDraftThreads,
  draft_id : String,
) -> Unit {
  self.entries.remove(draft_id)
}

///|
/// The one filesystem authority extracted from a successful app-server
/// thread reply. It is never decoded from a Files or Terminal request: only
/// the native Codex actor's reply can establish this exact thread/cwd pair.
priv struct CodexWorkspaceBinding {
  session : String
  workspace : String?
}

///|
/// Desktop adds `force` to Codex's archive command because app-server does
/// not know about SeekMoon-owned worktree checkouts. This value validates the
/// extended request once and can then produce app-server's narrower payload.
priv struct CodexArchiveRequest {
  thread_id : String
  force : Bool
}

///|
fn CodexArchiveRequest::decode(params : Json) -> CodexArchiveRequest? {
  guard params is Object(fields) &&
    fields.get("threadId") is Some(String(thread_id)) &&
    !thread_id.trim().is_empty() else {
    return None
  }
  Some({ thread_id, force: fields.get("force") is Some(True), })
}

///|
fn CodexArchiveRequest::app_server_params(self : CodexArchiveRequest) -> Json {
  { "threadId": self.thread_id }
}

///|
fn CodexArchiveRequest::needs_force(
  _self : CodexArchiveRequest,
  refusal : @protocol.ArchiveNeedsForceReply,
) -> Json {
  {
    "kind": "needs_force",
    "worktree": refusal.worktree,
    "dirty_paths": refusal.dirty_paths,
    "dirty_path_count": refusal.dirty_path_count,
  }
}

///|
fn CodexArchiveRequest::retained_worktree(
  _self : CodexArchiveRequest,
  refusal : @protocol.ArchiveNeedsForceReply,
) -> Json {
  {
    "kind": "archived_worktree_retained",
    "worktree": refusal.worktree,
    "dirty_paths": refusal.dirty_paths,
    "dirty_path_count": refusal.dirty_path_count,
  }
}

///|
/// Desktop-owned Codex worktree placements captured from the same registry
/// used by OpenSeek conversations. App-server still owns thread data; this
/// catalog adds only the placement that SeekMoon itself created.
priv struct CodexWorktreeCatalog {
  bindings : Array[@worktree.CodexWorktreeBinding]
}

///|
fn CodexWorktreeCatalog::CodexWorktreeCatalog(
  bindings : Array[@worktree.CodexWorktreeBinding],
) -> CodexWorktreeCatalog {
  { bindings, }
}

///|
fn CodexWorktreeCatalog::annotate_thread(
  self : CodexWorktreeCatalog,
  value : Json,
) -> Json {
  guard value is Object(thread) && thread.get("id") is Some(String(thread_id)) else {
    return value
  }
  guard self.bindings
    .iter()
    .find_first(binding => binding.thread_id == thread_id)
    is Some(binding) else {
    return value
  }
  let annotated : Map[String, Json] = Map([])
  for key, field in thread {
    annotated[key] = field
  }
  // The registry retains the owning project even after its checkout is gone;
  // Git cannot recover that relationship from a deleted cwd.
  annotated["projectRoot"] = Json(binding.workspace)
  annotated["openseekWorktree"] = binding.worktree.to_json()
  Json(annotated)
}

///|
fn CodexWorktreeCatalog::annotate(
  self : CodexWorktreeCatalog,
  reply : Json,
) -> Json {
  guard reply is Object(fields) else { return reply }
  let annotated : Map[String, Json] = Map([])
  for key, field in fields {
    annotated[key] = field
  }
  if fields.get("data") is Some(Array(threads)) {
    let data : Array[Json] = []
    for thread in threads {
      data.push(self.annotate_thread(thread))
    }
    annotated["data"] = Json(data)
  }
  if fields.get("thread") is Some(thread) {
    annotated["thread"] = self.annotate_thread(thread)
  }
  Json(annotated)
}

///|
fn CodexWorkspaceBinding::decode_reply(value : Json) -> CodexWorkspaceBinding? {
  guard value is Object(fields) &&
    fields.get("thread") is Some(Object(thread)) &&
    thread.get("id") is Some(String(session)) else {
    return None
  }
  // A Desktop registry annotation is more authoritative than app-server's
  // persisted cwd. A retained missing placement must revoke host access;
  // otherwise opening an archived-and-restored task would authorize a path
  // whose checkout no longer exists.
  let workspace = match thread.get("openseekWorktree") {
    Some(Object(worktree)) if worktree.get("present") is Some(True) =>
      match worktree.get("path") {
        Some(String(path)) => Some(path)
        _ => None
      }
    Some(Object(_)) => None
    _ =>
      match thread.get("cwd") {
        Some(String(cwd)) => Some(cwd)
        _ => None
      }
  }
  Some({ session, workspace, })
}

///|
/// Apply the app-server reply before it reaches the page, so a Files or
/// Terminal request caused by that render can resolve the cwd immediately.
async fn CodexWorkspaceBinding::authorize(self : CodexWorkspaceBinding) -> Unit {
  match self.workspace {
    Some(workspace) if !workspace.trim().is_empty() =>
      @work_dir.authorize_host_workspace(self.session, workspace)
    _ => @work_dir.revoke_host_workspace(self.session)
  }
}

///|
/// `engine` is the engine executable; `executable` is the host's own
/// binary, which self-update uses to locate the running .app bundle (absent
/// or non-bundle layouts only lose the in-app install, never the
/// announcement).
pub fn ApiState::ApiState(
  engine~ : String,
  codex? : @codex.CodexSettings = @codex.CodexSettings::default(),
  runtime_dir? : @pathx.Path,
  executable? : String,
  auth? : @auth.AuthStore,
  app_version? : String = "development",
  on_finished? : (@protocol.FinishedPayload) -> Unit,
) -> ApiState {
  let engine_actor = @engine.new_engine_actor(engine, runtime_dir?)
  {
    codex: Actor(codex),
    codex_projects: ProjectCatalog(),
    codex_draft_threads: CodexDraftThreads(),
    engine: engine_actor,
    manager: engine_actor.manager(),
    host: @host.new_host_state(engine, runtime_dir?, executable?, app_version~),
    hub: Hub(),
    auth: match auth {
      Some(store) => store
      None => @auth.AuthStore::empty(app_version~)
    },
    app_version,
    on_finished,
  }
}

///|
/// The app-lifetime owner of the Codex app-server child process.
pub fn ApiState::codex_actor(self : ApiState) -> @codex.Actor {
  self.codex
}

///|
/// The app-lifetime engine actor. Its `run` task owns all serve processes and
/// per-session follower children.
pub fn ApiState::engine_actor(self : ApiState) -> @engine.EngineActor {
  self.engine
}

///|
/// The sign-in store used by the relay actor running beside this dispatcher.
pub fn ApiState::auth_store(self : ApiState) -> @auth.AuthStore {
  self.auth
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
pub fn ApiState::subscribe(
  self : ApiState,
) -> @async.Queue[@protocol.Notification] {
  self.hub.subscribe()
}

///|
pub fn ApiState::unsubscribe(
  self : ApiState,
  queue : @async.Queue[@protocol.Notification],
) -> Unit {
  self.hub.unsubscribe(queue)
}

///|
/// Publish one notification to every subscriber — shared host pumps such as
/// `lsp.diagnostics` go through here. Connection-owned `fs.changed` events
/// bypass the hub and return only to their owning connection.
pub fn ApiState::publish(
  self : ApiState,
  notification : @protocol.Notification,
) -> Unit {
  self.hub.publish(notification)
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
/// The commands shared by the embedded page and remote WebSocket. A generic
/// Endpoint constructor checks each payload/reply pair, then erases those
/// types only inside the two transport closures it creates.
pub fn endpoints(
  state : ApiState,
  connection : @host.HostConnection,
) -> Array[@endpoint.Endpoint] {
  let endpoints = [
    @endpoint.Endpoint::codex_sync(@commands.codex_status, _ => {
      let reply : @protocol.CodexStatusReply = @json.from_json(
        state.codex.status(),
      )
      reply
    }),
    @endpoint.Endpoint::codex(@commands.codex_config_open, async fn(_) {
      @host.open_codex_config(state.codex.config_home())
      Acknowledged
    }),
    @endpoint.Endpoint::codex(@commands.codex_draft_open, async fn(payload) {
      state.open_codex_draft(payload)
    }),
    @endpoint.Endpoint::codex(@commands.codex_draft_close, async fn(payload) {
      guard payload.validated_id() is Some(draft_id) else {
        raise @host.PayloadError("invalid Codex draft id")
      }
      @work_dir.revoke_host_workspace(draft_id)
      state.codex_draft_threads.forget(draft_id)
      Acknowledged
    }),
    @endpoint.Endpoint::codex(@commands.codex_server_request_list, async fn(_) {
      let reply : @protocol.CodexServerRequestsReply = @json.from_json(
        state.codex.requests(),
      )
      reply
    }),
    @endpoint.Endpoint::codex(@commands.codex_server_request_respond, async fn(
      payload,
    ) {
      ignore(
        state.codex.respond(
          request_id=payload.request_id,
          result=payload.result,
        ),
      )
      Acknowledged
    }),
    @endpoint.Endpoint::codex(@commands.codex_file_search, async fn(payload) {
      state.codex_file_search(payload)
    }),
    @endpoint.Endpoint::codex(@commands.codex_skills_list, async fn(payload) {
      state.codex_skills_list(payload)
    }),
    state.codex_endpoint(@commands.codex_account_read),
    state.codex_endpoint(@commands.codex_account_login_start),
    state.codex_endpoint(@commands.codex_account_login_cancel),
    state.codex_endpoint(@commands.codex_account_logout),
    state.codex_endpoint(@commands.codex_model_list),
    @endpoint.Endpoint::codex(@commands.codex_thread_start, async fn(payload) {
      state.codex_thread_start(payload)
    }),
    @endpoint.Endpoint::codex(@commands.codex_thread_resume, async fn(payload) {
      state.codex_thread_resume(payload)
    }),
    state.codex_endpoint(@commands.codex_thread_read),
    @endpoint.Endpoint::codex(@commands.codex_thread_history_read, async fn(
      payload,
    ) {
      state.codex_thread_history(payload)
    }),
    state.codex_endpoint(@commands.codex_thread_list),
    state.codex_endpoint(@commands.codex_thread_archive),
    state.codex_endpoint(@commands.codex_thread_unarchive),
    state.codex_endpoint(@commands.codex_thread_compact),
    state.codex_endpoint(@commands.codex_review_start),
    @endpoint.Endpoint::codex(@commands.codex_turn_start, async fn(payload) {
      state.codex_turn_start(payload)
    }),
    state.codex_endpoint(@commands.codex_turn_steer),
    state.codex_endpoint(@commands.codex_turn_interrupt),
    @endpoint.Endpoint::remote(@commands.agent_start, async fn(payload) {
      @engine.start_run(state.sink(), state.manager, payload)
    }),
    @endpoint.Endpoint::remote_sync(@commands.agent_cancel, payload => {
      @engine.cancel_run(state.manager, payload)
    }),
    @endpoint.Endpoint::remote(@commands.agent_steer, fn(payload) {
      @engine.steer_run(state.manager, payload)
    }),
    @endpoint.Endpoint::remote(@commands.agent_compact, async fn(payload) {
      @engine.compact_run(state.manager, payload)
    }),
    @endpoint.Endpoint::remote(@commands.agent_goal, async fn(payload) {
      @engine.goal_run(state.manager, payload)
    }),
    // Synchronous like cancel: it hands one line to the engine's writer and
    // reports whether there was still a question to answer. Nothing here waits
    // on the engine — what the decision releases is reported by the run's own
    // events.
    @endpoint.Endpoint::remote_sync(@commands.agent_approval, payload => {
      @engine.approve_run(state.manager, payload)
    }),
    @endpoint.Endpoint::remote_sync(@commands.agent_runs, payload => {
      state.hub.runs(known?=payload.known)
    }),
    @endpoint.Endpoint::remote(@commands.session_list, async fn(_) {
      @engine.list_sessions(state.manager)
    }),
    @endpoint.Endpoint::remote(@commands.session_load, async fn(payload) {
      @engine.load_session(state.manager, payload)
    }),
    @endpoint.Endpoint::remote(@commands.session_load_archived, async fn(
      payload,
    ) {
      @engine.load_archived_session(state.manager, payload)
    }),
    @endpoint.Endpoint::remote(@commands.session_list_archived, async fn(_) {
      @engine.archived_sessions(state.manager)
    }),
    @endpoint.Endpoint::remote(@commands.session_archive, async fn(payload) {
      let session = payload.canonical_session()
      // The callback runs inside the rename's cancellation shield. Every
      // other client learns the canonical id before any cancellable list
      // reply, so a cancelled requester cannot suppress invalidation. The
      // worktree callback publishes the retained placement with
      // `present: false` before the archived identity becomes visible.
      @engine.archive_session(
        state.manager,
        session,
        (moved, workspace) => {
          publish_session_changed(state, "archived", moved, workspace)
        },
        force=payload.force == Some(true),
        on_worktree_changed=(workspace, worktrees) => {
          publish_worktree_changed(state, workspace, worktrees)
        },
      )
    }),
    @endpoint.Endpoint::remote(@commands.session_unarchive, async fn(payload) {
      let session = payload.canonical_session()
      @engine.unarchive_session(state.manager, session, (moved, workspace) => {
        publish_session_changed(state, "unarchived", moved, workspace)
      })
    }),
    @endpoint.Endpoint::remote(@commands.session_delete_archived, async fn(
      payload,
    ) {
      let session = payload.canonical_session()
      @engine.delete_archived_session(
        state.manager,
        session,
        payload.workspace,
        (deleted, workspace) => {
          publish_session_changed(state, "deleted", deleted, workspace)
        },
        on_worktree_changed=(workspace, worktrees) => {
          publish_worktree_changed(state, workspace, worktrees)
        },
      )
    }),
    @endpoint.Endpoint::remote(@commands.settings_get, async fn(_) {
      @engine.settings_status(state.manager)
    }),
    @endpoint.Endpoint::remote_sync(@commands.app_info, _ => {
      version: state.app_version,
      windows: @sysplatform.win32 || @sysplatform.win64,
    }),
    @endpoint.Endpoint::remote(@commands.settings_set, async fn(payload) {
      // The store commit and its broadcast are one finite cancellation-
      // shielded linearization point. `update_settings` invokes the callback
      // while its manager-owned lock is still held, preserving revision order
      // across concurrent clients even if the requester disconnects.
      @async.protect_from_cancel(() => {
        let status = @engine.update_settings(
          state.manager,
          payload.to_patch(),
          legacy_migration=payload.legacy_migration == Some(true),
          on_committed=fn(status) {
            // Every client renders these settings; clients that did not ask
            // must learn about the committed revision too.
            state.hub.publish(SettingsChanged(status))
          },
        )
        // Credentials belong to the server that issued them. Clear stale
        // credentials before this request can complete or be cancelled.
        sign_out_after_server_switch(state)
        status
      })
    }),
    @endpoint.Endpoint::remote(@commands.workspace_list, async fn(_) {
      @engine.list_workspaces()
    }),
    @endpoint.Endpoint::remote(@commands.workspace_add, async fn(payload) {
      // A refusal travels inside the reply: the local bridge would flatten
      // a raised error to "op ext:openseek/workspace.add failed".
      @engine.attach_workspace(payload.path, workspaces => {
        state.hub.publish(WorkspaceChanged({ workspaces, }))
      }) catch {
        error if @async.is_being_cancelled() => raise error
        @engine.EngineError(message) => WorkspaceError(message)
        @workspaces.WorkspaceError(message) => WorkspaceError(message)
        error => raise error
      }
    }),
    @endpoint.Endpoint::remote(@commands.workspace_remove, async fn(payload) {
      @engine.detach_workspace(state.manager, payload.path, workspaces => {
        state.hub.publish(WorkspaceChanged({ workspaces, }))
      }) catch {
        error if @async.is_being_cancelled() => raise error
        @engine.EngineError(message) => WorkspaceError(message)
        @workspaces.WorkspaceError(message) => WorkspaceError(message)
        error => raise error
      }
    }),
    @endpoint.Endpoint::remote(@commands.workspace_settings_get, async fn(
      payload,
    ) {
      @workspaces.settings(payload.workspace)
    }),
    @endpoint.Endpoint::remote(@commands.workspace_settings_set, async fn(
      payload,
    ) {
      // The store commit and its broadcast are one shielded linearization
      // point inside the engine, the `workspace.add` pattern.
      let worktree_mode = payload.worktree_mode
      let checkout_submodules = payload.checkout_submodules
      let submodule_checkout_timeout_seconds = payload.submodule_checkout_timeout_seconds
      @workspaces.update_settings(
        payload.workspace,
        settings => state.hub.publish(WorkspaceSettingsChanged(settings)),
        worktree_mode?,
        checkout_submodules?,
        submodule_checkout_timeout_seconds?,
      )
    }),
    @endpoint.Endpoint::remote(@commands.worktree_list, async fn(payload) {
      @worktree.list(payload.workspace)
    }),
    @endpoint.Endpoint::remote(@commands.worktree_create, async fn(payload) {
      let owner = match (payload.session, payload.codex_thread) {
        (Some(session), None) => @worktree.WorktreeOwner::openseek(session)
        (None, Some(thread_id)) => {
          let workspace = state.codex_worktree_project(
            thread_id,
            payload.workspace,
          )
          // Codex-only projects need not already appear in OpenSeek's
          // workspace registry. Choosing Worktree on first Send is the user's
          // explicit request to attach that main checkout and create beneath
          // it, so perform both operations in this host command.
          ignore(
            @engine.attach_workspace(workspace, workspaces => {
              state.hub.publish(WorkspaceChanged({ workspaces, }))
            }),
          )
          @worktree.WorktreeOwner::codex(thread_id)
        }
        _ =>
          raise @host.PayloadError(
            "worktree.create requires exactly one conversation owner",
          )
      }
      let reply = @worktree.create(
        state.manager.worktree_host(),
        payload.workspace,
        owner,
        worktrees => {
          publish_worktree_changed(state, payload.workspace, worktrees)
        },
      ) catch {
        error if @async.is_being_cancelled() => raise error
        @worktree.WorktreeError(message) => return WorktreeCreateError(message)
        @engine.EngineError(message) => return WorktreeCreateError(message)
        error => raise error
      }
      // A Codex worktree path is safe to authorize because this operation
      // just created or recovered it under a registered workspace. Never
      // derive this grant from the browser's later `turn/start.cwd` field.
      if payload.codex_thread is Some(thread_id) &&
        reply.worktrees
        .iter()
        .find_first(info => {
          info.codex_thread == Some(thread_id) && info.name == reply.name
        })
        is Some(info) {
        @work_dir.authorize_host_workspace(thread_id, info.path)
      }
      WorktreeCreatedReply(reply)
    }),
    @endpoint.Endpoint::remote(@commands.worktree_remove, async fn(payload) {
      @worktree.remove(
        state.manager.worktree_host(),
        payload.workspace,
        payload.name,
        payload.force == Some(true),
        worktrees => {
          publish_worktree_changed(state, payload.workspace, worktrees)
        },
      )
    }),
    @endpoint.Endpoint::remote(@commands.auth_status, async fn(_) {
      auth_status(state)
    }),
    @endpoint.Endpoint::remote(@commands.auth_connect, async fn(_) {
      auth_connect(state)
    }),
    @endpoint.Endpoint::remote(@commands.auth_disconnect, async fn(_) {
      auth_disconnect(state)
    }),
    @endpoint.Endpoint::remote(@commands.auth_cancel, async fn(_) {
      auth_cancel(state)
    }),
  ]
  for
    endpoint in @host.endpoints(state.host, connection, () => {
      state.publish(SkillsChanged)
    }) {
    endpoints.push(endpoint)
  }
  endpoints
}

///|
/// Pair one reviewed Codex command identity with the app-server forwarding
/// method. The command name is the Desktop method name used by
/// `codex_request`; no second catalog can drift from the registered endpoint.
fn[Payload : FromJson + ToJson, Reply : FromJson + ToJson] ApiState::codex_endpoint(
  self : ApiState,
  command : @commands.Command[Payload, @protocol.CodexCommandReply[Reply]],
) -> @endpoint.Endpoint {
  let desktop_method = command.name()
  @endpoint.Endpoint::codex(command, async fn(payload) {
    let value = self.codex_request(desktop_method, ToJson::to_json(payload))
    @json.from_json(value)
  })
}

///|
test "remote endpoint catalog has one entry per command name" {
  let state = ApiState::ApiState(engine="unused")
  let connection = @host.HostConnection()
  let names : Array[String] = []
  for endpoint in endpoints(state, connection) {
    let name = endpoint.name()
    if names.contains(name) {
      fail("duplicate endpoint: " + name)
    }
    names.push(name)
  }
  assert_true(names.contains("codex.config.open"))
  assert_true(names.contains("codex.draft.open"))
  assert_true(names.contains("codex.draft.close"))
  assert_true(names.contains("codex.file.search"))
  assert_true(names.contains("codex.skills.list"))
  assert_true(names.contains("codex.review.start"))
  assert_true(names.contains("codex.thread.history.read"))
  assert_true(names.contains("codex.thread.list"))
  assert_true(names.contains("agent.start"))
  assert_true(names.contains("agent.goal"))
  assert_true(names.contains("session.load_archived"))
  assert_true(names.contains("session.delete_archived"))
  assert_true(names.contains("workspace.settings_get"))
  assert_true(names.contains("workspace.settings_set"))
  assert_true(names.contains("app.info"))
  assert_true(names.contains("git.changes"))
  assert_true(names.contains("git.history"))
  assert_true(names.contains("git.commit_changes"))
  assert_true(names.contains("git.pull_request"))
  assert_true(names.contains("git.original_file"))
  assert_true(names.contains("terminal.close"))
  assert_true(names.contains("fs.search_files"))
  assert_true(names.contains("fs.cancel_search_files"))
  assert_true(names.contains("fs.clear_file_search_cache"))
  assert_true(names.contains("fs.create_directory"))
  assert_true(names.contains("fs.search_text"))
  assert_true(names.contains("fs.cancel_search_text"))
  assert_true(names.contains("moonide.references"))
  assert_false(names.contains("host.connect"))
  assert_false(names.contains("shell.open_external"))
}

///|
/// Return one complete read-only thread snapshot across both app-server
/// history modes. Metadata says which store owns the turns, avoiding an
/// expected JSON-RPC failure on every paginated task. Legacy threads then take
/// the stable inline read; a task awaiting its first user message legitimately
/// has only the summary and is returned as an empty conversation. Paginated
/// threads load every page in ascending order with full items and rebuild the
/// same `{ thread }` shape the browser decodes.
async fn ApiState::codex_thread_history(
  self : ApiState,
  payload : @protocol.CodexThreadPayload,
) -> @protocol.CodexThreadReply {
  let thread_id = payload.thread_id
  let metadata = self.codex_request("codex.thread.read", {
    "threadId": thread_id,
    "includeTurns": false,
  })
  guard metadata is Object(reply_fields) &&
    reply_fields.get("thread") is Some(Object(thread_fields)) else {
    raise @host.PayloadError("malformed Codex thread metadata reply")
  }
  let paginated = thread_fields.get("historyMode") is Some(String("paginated"))
  if !paginated {
    let value = try
      self.codex_request("codex.thread.read", {
        "threadId": thread_id,
        "includeTurns": true,
      })
    catch {
      @codex.JsonRpc(..) as error if error.is_unmaterialized_thread_history() =>
        // The summary already identifies the task and its cwd. The frontend
        // decodes an omitted `turns` field as an empty transcript, matching
        // the task's real state before its first prompt is sent.
        metadata
      error => raise error
    } noraise {
      value => value
    }
    return @json.from_json(value)
  }
  let turns : Array[Json] = []
  let mut cursor : String? = None
  for ;; {
    let page_fields : Map[String, Json] = {
      "threadId": Json(thread_id),
      "limit": Json(100.0),
      "sortDirection": Json("asc"),
      "itemsView": Json("full"),
    }
    if cursor is Some(cursor) {
      page_fields["cursor"] = Json(cursor)
    }
    let page = self.codex.call(
      method_="thread/turns/list",
      params=Json(page_fields),
    )
    guard page is Object(page_fields) &&
      page_fields.get("data") is Some(Array(data)) else {
      raise @host.PayloadError("malformed Codex turn history page")
    }
    for turn in data {
      turns.push(turn)
    }
    match page_fields.get("nextCursor") {
      Some(String(next)) if !next.is_empty() => cursor = Some(next)
      _ => break
    }
  }
  let thread : Map[String, Json] = Map([])
  for key, value in thread_fields {
    thread[key] = value
  }
  thread["turns"] = Json(turns)
  let reply : Map[String, Json] = Map([])
  for key, value in reply_fields {
    reply[key] = value
  }
  reply["thread"] = Json(thread)
  @json.from_json(Json(reply))
}

///|
/// Search only the exact cwd authorized by an app-server thread reply. The
/// public method does not accept app-server `roots` directly, so a remote page
/// cannot use Codex's file index as an arbitrary filesystem search.
async fn ApiState::codex_file_search(
  self : ApiState,
  payload : @protocol.CodexFileSearchPayload,
) -> @protocol.CodexFileSearchReply {
  guard @work_dir.resolve_in_workspace(
      payload.thread_id,
      "",
      workspace=payload.cwd,
    )
    is Some(root) else {
    raise @host.HostError("Codex workspace is not authorized")
  }
  let value = self.codex.call(method_="fuzzyFileSearch", params={
    "query": payload.query,
    "roots": [Json(root.to_string())],
  })
  { value, }
}

///|
/// Give a fresh Codex draft the same exact cwd-scoped host authority as an
/// OpenSeek scratch conversation, without persisting a workspace or creating
/// an app-server thread. Only a generated Desktop id and the main project row
/// selected by the add button are accepted.
async fn ApiState::open_codex_draft(
  self : ApiState,
  payload : @protocol.CodexDraftOpenPayload,
) -> @protocol.CodexDraftOpenReply {
  let draft_id = payload.draft_id.trim().to_owned()
  let registered = if @pathx.Absolute::from_uri_path(
      payload.cwd.trim().to_owned(),
    )
    is Some(requested) {
    let normalized = requested.normalize()
    if @workspaces.registered().contains(normalized) {
      Some(normalized.to_string())
    } else {
      None
    }
  } else {
    None
  }
  let project_root = match self.codex_projects.main_project(payload.cwd) {
    Some(project) => Some(project)
    None => registered
  }
  guard draft_id == payload.draft_id &&
    draft_id.has_prefix("desktop-") &&
    !draft_id.contains("/") &&
    !draft_id.contains("\\") &&
    project_root is Some(project_root) else {
    raise @host.PayloadError("invalid Codex draft project")
  }
  @work_dir.authorize_host_workspace(draft_id, project_root)
  { draft_id, cwd: project_root, project_root, }
}

///|
/// Start a thread only from the exact draft cwd already authorized by
/// `codex.draft.open`. The browser chooses one Desktop permission mode; the
/// native boundary expands it to the matching app-server reviewer and named
/// permission profile instead of accepting arbitrary sandbox JSON.
async fn ApiState::codex_thread_start(
  self : ApiState,
  request : @protocol.CodexThreadStartPayload,
) -> @protocol.CodexThreadReply {
  match (request.cwd, request.draft_id) {
    (Some(cwd), Some(draft_id)) => {
      guard @protocol.CodexDraftClosePayload::{ draft_id, }.validated_id()
        is Some(validated) &&
        @work_dir.resolve_host_workspace_authorization(validated, cwd)
        is Some(authorized) &&
        @pathx.Absolute::from_uri_path(cwd) is Some(requested) &&
        authorized.normalize() == requested.normalize() else {
        raise @host.HostError("Codex draft workspace is not authorized")
      }
    }
    (None, Some(draft_id)) =>
      if @protocol.CodexDraftClosePayload::{ draft_id, }.validated_id() is None {
        raise @host.PayloadError("invalid Codex draft id")
      }
    (None, None) => ()
    _ => raise @host.PayloadError("Codex thread cwd requires its draft id")
  }
  if self.codex_draft_threads.cached(request) is Some(reply) {
    return reply
  }
  let reply : @protocol.CodexThreadReply = @json.from_json(
    self.codex_request("codex.thread.start", request.app_server_params()),
  )
  self.codex_draft_threads.remember(request, reply)
  reply
}

///|
/// Claim the stored task writer and install the permission mode atomically.
/// Opening history remains read-only and never reaches this path.
async fn ApiState::codex_thread_resume(
  self : ApiState,
  request : @protocol.CodexThreadResumePayload,
) -> @protocol.CodexThreadReply {
  @json.from_json(
    self.codex_request("codex.thread.resume", request.app_server_params()),
  )
}

///|
/// A worktree first turn may override cwd, but only with the exact checkout
/// the native worktree operation just authorized for this thread.
async fn ApiState::codex_turn_start(
  self : ApiState,
  request : @protocol.CodexTurnStartPayload,
) -> @protocol.CodexTurnReply {
  if request.cwd is Some(cwd) {
    guard @work_dir.resolve_host_workspace_authorization(request.thread_id, cwd)
      is Some(authorized) &&
      @pathx.Absolute::from_uri_path(cwd) is Some(requested) &&
      authorized.normalize() == requested.normalize() else {
      raise @host.HostError("Codex turn workspace is not authorized")
    }
  }
  @json.from_json(
    self.codex_request("codex.turn.start", request.app_server_params()),
  )
}

///|
/// Revalidate a Codex first-send worktree request from app-server's own empty
/// thread metadata. The browser-supplied project must equal both the thread's
/// cwd and the Git-derived main project, so a stale or fabricated request
/// cannot bind an existing task to a different checkout.
async fn ApiState::codex_worktree_project(
  self : ApiState,
  thread_id : String,
  requested : String,
) -> String {
  let metadata = self.codex_request("codex.thread.read", {
    "threadId": thread_id,
    "includeTurns": false,
  })
  guard metadata is Object(reply_fields) &&
    reply_fields.get("thread") is Some(Object(thread)) &&
    thread.get("id") == Some(Json(thread_id)) &&
    thread.get("projectRoot") == Some(Json(requested)) else {
    raise @host.HostError(
      "Codex worktree requires an empty task at its main project root",
    )
  }
  // A durable owner binding makes `worktree.create` the rebuild/idempotency
  // operation as well as first creation. Existing tasks can have turns and an
  // app-server cwd at the missing checkout; the registry's exact owner/project
  // pair is the authority needed to recreate that same placement.
  if @worktree.list_codex_worktree_bindings()
    .iter()
    .any(binding => {
      binding.thread_id == thread_id && binding.workspace == requested
    }) {
    return requested
  }
  guard thread.get("cwd") == Some(Json(requested)) else {
    raise @host.HostError(
      "Codex worktree requires an empty task at its main project root",
    )
  }
  let page = try
    self.codex.call(method_="thread/turns/list", params={
      "threadId": thread_id,
      "limit": 1,
      "sortDirection": "desc",
      "itemsView": "summary",
    })
  catch {
    @codex.JsonRpc(..) as error if error.is_unmaterialized_thread_turns() =>
      Json({ "data": Json(([] : Array[Json])) })
    error => raise error
  } noraise {
    value => value
  }
  guard page is Object(fields) &&
    fields.get("data") is Some(Array(turns)) &&
    turns.is_empty() else {
    raise @host.HostError(
      "Codex worktree can only be chosen before the first turn",
    )
  }
  requested
}

///|
/// Ask app-server for the skill catalog belonging to one authorized Codex
/// cwd. Unlike the generic Codex endpoints, the browser supplies no raw `cwds`
/// array that could escape the selected thread's filesystem authority.
async fn ApiState::codex_skills_list(
  self : ApiState,
  payload : @protocol.CodexSkillsListPayload,
) -> @protocol.CodexDataReply {
  guard @work_dir.resolve_in_workspace(
      payload.thread_id,
      "",
      workspace=payload.cwd,
    )
    is Some(root) else {
    raise @host.HostError("Codex workspace is not authorized")
  }
  @json.from_json(
    self.codex.call(method_="skills/list", params={
      "cwds": [Json(root.to_string())],
      "forceReload": payload.force_reload,
    }),
  )
}

///|
/// Map the Desktop's explicit Codex catalog onto the stable app-server method
/// names. There is deliberately no arbitrary method proxy: a relay browser can
/// invoke only the same reviewed surface as the local Proton page.
async fn ApiState::codex_request(
  self : ApiState,
  desktop_method : String,
  params : Json,
) -> Json {
  let app_server_method = match desktop_method {
    "codex.account.read" => "account/read"
    "codex.account.login.start" => "account/login/start"
    "codex.account.login.cancel" => "account/login/cancel"
    "codex.account.logout" => "account/logout"
    "codex.model.list" => "model/list"
    "codex.thread.start" => "thread/start"
    "codex.thread.resume" => "thread/resume"
    "codex.thread.read" => "thread/read"
    "codex.thread.list" => "thread/list"
    "codex.thread.archive" => "thread/archive"
    "codex.thread.unarchive" => "thread/unarchive"
    "codex.thread.compact" => "thread/compact/start"
    "codex.review.start" => "review/start"
    "codex.turn.start" => "turn/start"
    "codex.turn.steer" => "turn/steer"
    "codex.turn.interrupt" => "turn/interrupt"
    _ => raise @host.PayloadError("unknown Codex method: " + desktop_method)
  }
  let archive = if desktop_method == "codex.thread.archive" {
    match CodexArchiveRequest::decode(params) {
      Some(request) => Some(request)
      None => raise @host.PayloadError("malformed Codex archive payload")
    }
  } else {
    None
  }
  // Do not archive app-server's task until the user has answered Desktop's
  // dirty-checkout confirmation. A refusal here is an ordinary reply, not a
  // failed bridge command, so the frontend can keep the task selected.
  if archive is Some(request) &&
    !request.force &&
    @worktree.WorktreeOwner::codex(request.thread_id).archive_check()
    is Some(refusal) {
    return request.needs_force(refusal)
  }
  let scoped_params = match (desktop_method, params) {
    // Custom app-server clients currently persist ordinary interactive
    // threads as `vscode`, while older/newer records may use `appServer`.
    // Preserve the caller's source filter (or Codex's interactive default)
    // instead of hiding threads that OpenSeek itself just created.
    ("codex.thread.list", Object(fields)) => {
      let scoped : Map[String, Json] = Map([])
      for key, value in fields {
        scoped[key] = value
      }
      // JSONL scan-and-repair can exceed the Proton request deadline on a
      // long-lived Codex home. The Desktop catalog is an interactive state
      // query, so read the app-server state database without that repair pass.
      scoped["useStateDbOnly"] = true
      Json(scoped)
    }
    ("codex.thread.list", _) => { "useStateDbOnly": true }
    // The dedicated thread/start endpoint has already reduced this object to
    // cwd, model, and Desktop's fixed service name.
    ("codex.thread.start", Object(fields)) => {
      let scoped : Map[String, Json] = Map([])
      for key, value in fields {
        scoped[key] = value
      }
      scoped["serviceName"] = "openseek_desktop"
      Json(scoped)
    }
    ("codex.thread.start", _) => { "serviceName": "openseek_desktop" }
    ("codex.thread.archive", _) => archive.unwrap().app_server_params()
    _ => params
  }
  let reply = self.codex.call(method_=app_server_method, params=scoped_params)
  let reply = match desktop_method {
    "codex.thread.start"
    | "codex.thread.resume"
    | "codex.thread.read"
    | "codex.thread.list" => self.codex_projects.annotate(reply)
    _ => reply
  }
  let reply = match desktop_method {
    "codex.thread.start"
    | "codex.thread.resume"
    | "codex.thread.read"
    | "codex.thread.list" =>
      CodexWorktreeCatalog(@worktree.list_codex_worktree_bindings()).annotate(
        reply,
      )
    _ => reply
  }
  // App-server is the Codex task's writer and therefore archives first. Only
  // its success permits Desktop to remove the associated checkout. The final
  // dirty check repeats after that write boundary; if new files appeared in
  // the small interval, retain the checkout and report the partial result.
  if archive is Some(request) {
    let refusal = @worktree.WorktreeOwner::codex(request.thread_id).archive_checkout(
      request.force,
      on_committed=(workspace, worktrees) => {
        publish_worktree_changed(self, workspace, worktrees)
      },
    )
    @work_dir.revoke_host_workspace(request.thread_id)
    if refusal is Some(refusal) {
      return request.retained_worktree(refusal)
    }
  }
  match desktop_method {
    "codex.thread.start" | "codex.thread.resume" | "codex.thread.read" =>
      if CodexWorkspaceBinding::decode_reply(reply) is Some(binding) {
        binding.authorize()
      }
    _ => ()
  }
  reply
}

///|
test "Codex workspace bindings decode only authoritative thread replies" {
  let archive = CodexArchiveRequest::decode({
    "threadId": "codex-thread-1",
    "force": true,
  }).unwrap()
  assert_true(archive.force)
  assert_eq(archive.app_server_params(), { "threadId": "codex-thread-1" })
  assert_true(CodexArchiveRequest::decode({ "force": true }) is None)
  let binding = CodexWorkspaceBinding::decode_reply({
    "thread": { "id": "codex-thread-1", "cwd": "/work/project", "turns": [] },
  })
  assert_true(
    binding
    is Some({ session: "codex-thread-1", workspace: Some("/work/project"), }),
  )
  let worktree = CodexWorkspaceBinding::decode_reply({
    "thread": {
      "id": "codex-thread-1",
      "cwd": "/stale/path",
      "openseekWorktree": {
        "path": "/work/project/.worktrees/wt-1",
        "present": true,
      },
    },
  })
  assert_true(
    worktree
    is Some(
      {
        session: "codex-thread-1",
        workspace: Some("/work/project/.worktrees/wt-1"),
      }
    ),
  )
  let missing = CodexWorkspaceBinding::decode_reply({
    "thread": {
      "id": "codex-thread-1",
      "cwd": "/stale/path",
      "openseekWorktree": {
        "path": "/work/project/.worktrees/wt-1",
        "present": false,
      },
    },
  })
  assert_true(missing is Some({ session: "codex-thread-1", workspace: None, }))
  assert_true(CodexWorkspaceBinding::decode_reply({ "thread": {} }) is None)
  assert_true(CodexWorkspaceBinding::decode_reply({}) is None)
}

///|
test "Codex draft creation reuses a successful native reply until close" {
  let drafts = CodexDraftThreads()
  let request : @protocol.CodexThreadStartPayload = {
    cwd: Some("/work/project"),
    model: Some("gpt-test"),
    draft_id: Some("desktop-draft-1"),
    permission_mode: AutoReview,
  }
  let reply : @protocol.CodexThreadReply = {
    thread: { "id": "thread-1", "cwd": "/work/project" },
  }
  assert_true(drafts.cached(request) is None)
  drafts.remember(request, reply)
  assert_eq(drafts.cached(request), Some(reply))
  // Model and permission selection belong to the eventual turn. Changing
  // either after an ambiguous thread/start reply must still adopt the one
  // created task; turn/start installs the current selection.
  assert_eq(
    drafts.cached({ ..request, model: Some("gpt-other"), }),
    Some(reply),
  )
  assert_eq(
    drafts.cached({ ..request, permission_mode: FullAccess, }),
    Some(reply),
  )
  drafts.forget("desktop-draft-1")
  assert_true(drafts.cached(request) is None)
}

///|
/// Tell every client a conversation moved between stores or was permanently
/// deleted, so clients that did not ask re-read both lists and drop stale
/// state for the named record.
fn publish_session_changed(
  state : ApiState,
  change : String,
  session : String,
  workspace : String,
) -> Unit {
  state.hub.publish(SessionChanged({ change, session, workspace, }))
}

///|
/// Tell every client a workspace's worktree list changed, so sidebars
/// re-join their name chips and pickers refresh — the `workspace.changed`
/// pattern, keyed by the workspace the list belongs to.
fn publish_worktree_changed(
  state : ApiState,
  workspace : String,
  worktrees : Array[@protocol.WorktreeInfo],
) -> Unit {
  state.hub.publish(
    WorktreeChanged({ workspace: workspace.trim().to_owned(), worktrees, }),
  )
}
