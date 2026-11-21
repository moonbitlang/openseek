///|
/// A proposal being started stays listed, answered, until its start is
/// carried out (see `run_session_messages`), so every client stops offering
/// the decision at once.
fn ApiState::answer_session_message(
  self : ApiState,
  id : String,
  allow : Bool,
) -> Bool {
  guard self.messages.decide(id, allow) else { return false }
  match self.hub.message_approvals.get(id) {
    Some({ tool_name: SessionStartTool, .. } as card) if allow =>
      self.hub.message_approvals[id] = { ..card, answered: true, }
    _ => self.hub.message_approvals.remove(id)
  }
  self.hub.publish_approvals()
  true
}

///|
/// The approval kind of a proposed conversation. Clients answer it from its
/// own row, never as the turn's question. Unanswered, it is open; answered,
/// it is being started. It is no longer listed once its conversation exists,
/// or when it was dismissed, withdrawn or failed.
const SessionStartTool : String = "session.start"

///|
async fn ApiState::run_session_messages(self : ApiState) -> Unit {
  self.messages.run(
    (session, text, id) => self.deliver_session_input(session, text, id),
    (session, message) => {
      self.publish(
        AgentEvent({
          run_id: None,
          session,
          event: SessionError(error=message),
        }),
      )
    },
    start=(entry, request) => {
      defer {
        self.hub.message_approvals.remove(entry.id)
        self.hub.publish_approvals()
      }
      self.start_conversation(entry, request)
    },
  )
}

///|
/// Carry out a started proposal: a new worktree of the sender's workspace
/// owned by the minted conversation, then its first turn with the brief as
/// the prompt and the settings the sender proposed it with. The start
/// succeeds once the conversation's first event is durable, which is when a
/// record exists to open and to hold the title; a run that ends before that
/// fails the start. A start that fails after the worktree exists gives the
/// worktree back.
async fn ApiState::start_conversation(
  self : ApiState,
  entry : @session_messages.Message,
  request : @session_messages.StartRequest,
) -> Unit {
  let { workspace, title, brief, settings, } = request
  let session = entry.target
  let host = self.manager.worktree_host()
  let root = @pathx.Absolute::parse_resource_path(workspace)
  let created = @worktree.create(
    host,
    root,
    @worktree.WorktreeOwner::openseek(session),
    worktrees => publish_worktree_changed(self, workspace, worktrees),
  )
  // The engine reports a failure after admission (an exit, a failed prompt
  // write) only by ending the run, and a restarted engine ends none. Either
  // can come before the first event's commit reaches this host.
  let recorded : @async.Queue[StartOutcome] = Queue(kind=Blocking(1))
  let run : Ref[String?] = Ref(None)
  let subscription = self.subscribe(
    recorded,
    map=notification => {
      match notification {
        SessionEvent(commit) if commit.session == session => Some(Recorded)
        AgentStarted(started) if started.session == session => {
          run.val = Some(started.run_id)
          None
        }
        AgentFinished(finished) if run.val is Some(id) && finished.run_id == id =>
          Some(Stopped)
        AgentConnected(_) if run.val is Some(_) => Some(Stopped)
        _ => None
      }
    },
    // The first outcome is all this waits for; a full inbox already holds it.
    on_lag=_ => (),
  )
  defer subscription.close()
  let payload : @protocol.StartPayload = {
    system_prompt: settings.bind(settings => settings.system_prompt),
    images: [],
    task: brief,
    submission_id: Some(entry.id),
    model: settings.map(settings => settings.model),
    thinking: settings.map(settings => settings.thinking),
    approval: settings.map(settings => settings.approval),
    max_steps: None,
    session,
    workspace: Some(workspace),
  }
  // A start that failed gives its worktree back: its conversation was never
  // saved, so nothing else owns it. A start cancelled because the host is
  // closing leaves both alone, like every other running conversation: the
  // closing engine settles the run, and whether its prompt was saved is not
  // known yet.
  try {
    ignore(@engine.start_run(self.sink(), self.manager, payload))
    // A run that stopped may still have saved its prompt: the record says
    // whether the conversation exists.
    if recorded.get() is Stopped {
      let loaded = @engine.load_session(self.manager, {
        session,
        workspace: Some(workspace),
      })
      guard message_committed(loaded.session, entry.id) else {
        fail("the conversation stopped before its first message was saved")
      }
    }
  } catch {
    error =>
      self.give_back_worktree(
        host,
        root,
        workspace,
        created.name,
        session,
        error,
      )
  }
  @engine.rename_session(self.manager, { session, workspace, title, }) catch {
    error => {
      @xlog.warn() <?
        {
          "event": "desktop_session_start_title_save_failed",
          "session": session,
          "error": error.to_string(),
        }
      return
    }
  }
  publish_session_changed(self, "renamed", session, workspace)
}

///|
/// Remove the worktree a failed start created, then fail with `error`. A
/// worktree that cannot be removed is logged and left in the list, where the
/// person can remove it.
async fn ApiState::give_back_worktree(
  self : ApiState,
  host : @worktree.WorktreeHost,
  root : @pathx.Absolute,
  workspace : String,
  name : String,
  session : String,
  error : Error,
) -> Unit {
  ignore(
    @worktree.remove(host, root, name, false, worktrees => {
      publish_worktree_changed(self, workspace, worktrees)
    }),
  ) catch {
    cleanup =>
      @xlog.warn() <?
        {
          "event": "desktop_session_start_worktree_cleanup_failed",
          "session": session,
          "worktree": name,
          "error": cleanup.to_string(),
        }
  }
  raise error
}

///|
/// How the wait for a started conversation's first durable event ended: the
/// event arrived, or its run ended or lost its engine first.
priv enum StartOutcome {
  Recorded
  Stopped
}

///|
/// The registered workspace `session` is saved in, which is where a
/// conversation it starts gets its worktree. A live engine's `session_root`
/// says which store holds it when several projects have a conversation of
/// that id. A store that cannot be listed leaves that unknown, which is a
/// failure rather than an absence.
async fn session_workspace(session : String, session_root? : String) -> String? {
  let mut unavailable : String? = None
  for group in @engine.list_sessions().groups {
    if session_root is Some(root) && group.session_root != root {
      continue
    }
    if group.sessions.iter().any(entry => entry.id == session) {
      return Some(group.workspace)
    }
    if !group.error.is_empty() && unavailable is None {
      unavailable = Some(
        "Cannot list conversations in \{group.workspace}: \{group.error}",
      )
    }
  }
  if unavailable is Some(error) {
    fail(error)
  }
  None
}

///|
fn message_string(args : Json, key : String) -> String raise @mcp.ToolError {
  guard args is Object(fields) &&
    fields.get(key) is Some(String(value)) &&
    !value.is_blank() else {
    raise ToolError("session needs a nonempty string `\{key}`")
  }
  value
}

///|
/// One tool per action, so tool search can match each by name and description.
/// All share the `session` prefix, which is their `X-SeekMoon-Tool-Groups` group.
fn ApiState::session_tools(self : ApiState) -> Array[@mcp.Tool] {
  let id_schema : Json = {
    "type": "object",
    "properties": {
      "id": {
        "type": "string",
        "description": "Request id returned by session_send or session_start.",
      },
    },
    "required": ["id"],
    "additionalProperties": false,
  }
  [
    {
      name: "session_list",
      description: "List OpenSeek chats on this host. Returns flat sessions (id, title, workspace) and next_offset; follow next_offset until null to see every chat. offset defaults to 0; limit defaults to 20 (maximum 50). No title search is supported: if the intended chat is absent after all pages, ask the user to select or create it. Read-only.",
      input_schema: {
        "type": "object",
        "properties": {
          "offset": { "type": "integer", "minimum": 0 },
          "limit": { "type": "integer", "minimum": 1, "maximum": 50 },
        },
        "required": [],
        "additionalProperties": false,
      },
      call: call => {
        let page : @session_catalog.ListPage = @json.from_json(call.arguments)
        [Text(page.page(@engine.list_sessions()).stringify())]
      },
    },
    {
      name: "session_read",
      description: "Read the saved history of one OpenSeek chat on this host, by a session id from session_list. Read-only.",
      input_schema: {
        "type": "object",
        "properties": { "session": { "type": "string" } },
        "required": ["session"],
        "additionalProperties": false,
      },
      call: call => {
        let session = message_string(call.arguments, "session")
          .trim()
          .to_owned()
        let loaded = @engine.load_session(self.manager, {
          session,
          workspace: None,
        })
        [Text(loaded.to_json().stringify())]
      },
    },
    {
      name: "session_send",
      description: "Send a message to another OpenSeek chat on this host after the user approves it. The user reviews the exact target and text. Give a unique request_id; reuse it only to retry the identical message. Waits up to 30 seconds for approval; timely approval waits up to 30 more seconds for confirmed delivery, otherwise returns delivering. Unanswered approval returns pending_approval with an id. Pending requests continue in the host after the call returns or times out, and the final result is delivered to this chat. Only sent confirms delivery. Requests last for this host process, not past app shutdown.",
      input_schema: {
        "type": "object",
        "properties": {
          "target": {
            "type": "string",
            "description": "Session id of the receiving chat.",
          },
          "text": { "type": "string" },
          "request_id": { "type": "string" },
        },
        "required": ["target", "text", "request_id"],
        "additionalProperties": false,
      },
      call: call => {
        let args = call.arguments
        let result = self.send_session_message(
          call.session,
          target=message_string(args, "target").trim().to_owned(),
          text=message_string(args, "text"),
          request_id=message_string(args, "request_id"),
        )
        [Text(result.stringify())]
      },
    },
    {
      name: "session_start",
      description: "Propose a new OpenSeek chat in a new git worktree of this chat's workspace, with your model and approval settings and the brief as its first prompt. Use it for separate, self-contained work the user will follow on its own; do quick things here. Returns proposed at once and never waits: the user sees the proposal above this chat's composer and may start or dismiss it whenever they like, so do not ask them to approve it or to tell you, and do not poll session_status. When the user starts it, a result naming the new chat (target) is delivered to this chat; follow it with session_read and session_send. Give a unique request_id; reuse it only to retry the identical proposal.",
      input_schema: {
        "type": "object",
        "properties": {
          "title": {
            "type": "string",
            "description": "Short title of the new chat.",
          },
          "text": {
            "type": "string",
            "description": "The complete brief: the task, the files or area, and what done looks like, written for a reader who has not seen this chat.",
          },
          "request_id": { "type": "string" },
        },
        "required": ["title", "text", "request_id"],
        "additionalProperties": false,
      },
      call: call => {
        let args = call.arguments
        let result = self.propose_session(
          call.session,
          title=message_string(args, "title").trim().to_owned(),
          brief=message_string(args, "text"),
          request_id=message_string(args, "request_id"),
        )
        [Text(result.stringify())]
      },
    },
    {
      name: "session_status",
      description: "Read the current status of a session_send or session_start request by the id it returned.",
      input_schema: id_schema,
      call: call => {
        let id = message_string(call.arguments, "id")
        [Text(self.messages.get(call.session, id).status().stringify())]
      },
    },
    {
      name: "session_cancel",
      description: "Withdraw a session_send request that is still awaiting the user's approval, or a session_start proposal the user has not started, by the id it returned. Returns its status.",
      input_schema: id_schema,
      call: call => {
        let id = message_string(call.arguments, "id")
        let entry = self.messages.get(call.session, id)
        self.messages.cancel(call.session, id)
        self.hub.message_approvals.remove(id)
        self.hub.publish_approvals()
        [Text(entry.status().stringify())]
      },
    },
  ]
}

///|
async fn ApiState::send_session_message(
  self : ApiState,
  sender : String,
  target~ : String,
  text~ : String,
  request_id~ : String,
) -> Json {
  guard target != sender else {
    raise @mcp.ToolError("choose a different conversation as the target")
  }
  // Validate both records before asking. In particular, sending must not
  // silently create a new conversation for a mistyped target id.
  for session in [sender, target] {
    let loaded = @engine.load_session(self.manager, {
      session,
      workspace: None,
    })
    guard loaded.session.events is Some(events) && !events.is_empty() else {
      raise @mcp.ToolError("conversation \{session} has no saved history")
    }
  }
  let (entry, created) = self.messages.request_send(
    sender, target, text, request_id,
  )
  if !created {
    return entry.status()
  }
  self.hub.message_approvals[entry.id] = {
    id: entry.id,
    session: entry.sender,
    run_id: None,
    tool_name: "session.send",
    detail: target,
    body: Some(text),
    answered: false,
  }
  self.hub.publish_approvals()
  self.messages.wait(entry)
}

///|
async fn ApiState::propose_session(
  self : ApiState,
  sender : String,
  title~ : String,
  brief~ : String,
  request_id~ : String,
) -> Json {
  let engine = @engine.run_settings(self.manager, sender)
  guard session_workspace(
      sender,
      session_root?=engine.bind(engine => engine.session_root),
    )
    is Some(workspace) else {
    raise @mcp.ToolError(
      "this conversation is not saved in a workspace, so there is no repository to start a worktree in",
    )
  }
  let (entry, created) = self.messages.request_start(
    sender,
    workspace~,
    title~,
    brief~,
    request_id~,
    settings?=engine.map(engine => {
      system_prompt: engine.system_prompt,
      model: engine.model,
      thinking: engine.thinking,
      approval: engine.approval,
    }),
  )
  if !created {
    return entry.status()
  }
  self.hub.message_approvals[entry.id] = {
    id: entry.id,
    session: entry.sender,
    run_id: None,
    tool_name: SessionStartTool,
    detail: title,
    body: Some(brief),
    answered: false,
  }
  self.hub.publish_approvals()
  entry.status()
}
