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
priv enum SessionToolRequest {
  List(@session_catalog.ListPage)
  Read(String)
  Send(target~ : String, text~ : String, request_id~ : String)
  Status(String)
  Cancel(String)
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
fn session_tool_request(args : Json) -> SessionToolRequest raise {
  match message_string(args, "action") {
    "list" => List(@json.from_json(args))
    "read" => Read(message_string(args, "session").trim().to_owned())
    "send" =>
      Send(
        target=message_string(args, "target").trim().to_owned(),
        text=message_string(args, "text"),
        request_id=message_string(args, "request_id"),
      )
    "status" => Status(message_string(args, "id"))
    "cancel" => Cancel(message_string(args, "id"))
    _ => raise @mcp.ToolError("unknown session action")
  }
}

///|
fn ApiState::session_tools(self : ApiState) -> Array[@mcp.Tool] {
  [
    {
      name: "session",
      description: "Find/read OpenSeek chats on this host and request user-approved cross-chat messages. list returns flat sessions (id, title, workspace) and next_offset. It accepts offset (default 0) and limit (default 20, maximum 50); follow next_offset until null to finish listing. No title search is supported. If the intended chat is absent after all pages, ask the user to select or create it. read needs session. send needs target, text, and a unique request_id (reuse it for retries of the identical message). The user reviews the exact target and text. Waits up to 30 seconds for approval. Timely approval waits up to 30 more seconds for confirmed delivery; otherwise returns delivering. Unanswered approval returns pending_approval. Pending results continue in the host after the tool returns or times out. Only sent confirms delivery. Final background results are actively delivered to this chat. status/cancel need the returned id; cancel only withdraws an unapproved request. Reading/listing is read-only. Requests last for this host process; they survive tool/turn completion, not app shutdown.",
      input_schema: {
        "type": "object",
        "properties": {
          "action": {
            "type": "string",
            "enum": ["list", "read", "send", "status", "cancel"],
          },
          "offset": { "type": "integer", "minimum": 0 },
          "limit": { "type": "integer", "minimum": 1, "maximum": 50 },
          "session": { "type": "string" },
          "target": { "type": "string" },
          "text": { "type": "string" },
          "request_id": { "type": "string" },
          "id": { "type": "string" },
        },
        "required": ["action"],
        "additionalProperties": false,
      },
      call: call => self.call_session_tool(call).stringify(),
    },
  ]
}

///|
async fn ApiState::call_session_tool(
  self : ApiState,
  call : @mcp.ToolCall,
) -> Json {
  match session_tool_request(call.arguments) {
    List(page) => page.page(@engine.list_sessions())
    Read(session) =>
      @engine.load_session(self.manager, { session, workspace: None, }).to_json()
    Send(target~, text~, request_id~) => {
      guard target != call.session else {
        raise @mcp.ToolError("choose a different conversation as the target")
      }
      // Validate both records before asking. In particular, sending must not
      // silently create a new conversation for a mistyped target id.
      for session in [call.session, target] {
        let loaded = @engine.load_session(self.manager, {
          session,
          workspace: None,
        })
        guard loaded.session.events is Some(events) && !events.is_empty() else {
          raise @mcp.ToolError("conversation \{session} has no saved history")
        }
      }
      let (entry, created) = self.messages.request(
        call.session,
        target,
        text,
        request_id,
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
    Status(id) | Cancel(id) as request => {
      let entry = self.messages.get(call.session, id)
      if request is Cancel(_) {
        self.messages.cancel(call.session, id)
        self.hub.message_approvals.remove(id)
        self.hub.publish_approvals()
      }
      entry.status()
    }
  }
}
