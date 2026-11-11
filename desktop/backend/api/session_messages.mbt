///|
fn ApiState::answer_session_message(
  self : ApiState,
  id : String,
  allow : Bool,
) -> Bool {
  guard self.messages.decide(id, allow) else { return false }
  self.hub.message_approvals.remove(id)
  self.hub.publish_approvals()
  true
}

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
  )
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
        "description": "Request id returned by session_send.",
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
      name: "session_status",
      description: "Read the current status of a session_send request by the id it returned.",
      input_schema: id_schema,
      call: call => {
        let id = message_string(call.arguments, "id")
        [Text(self.messages.get(call.session, id).status().stringify())]
      },
    },
    {
      name: "session_cancel",
      description: "Withdraw a session_send request that is still awaiting the user's approval, by the id it returned. Returns its status.",
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
  let (entry, created) = self.messages.request(sender, target, text, request_id)
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
