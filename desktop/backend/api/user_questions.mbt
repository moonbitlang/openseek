///|
fn ApiState::question_tools(self : ApiState) -> Array[@mcp.Tool] {
  [
    ask_user_tool(
      self.questions,
      session => {
        let loaded = @engine.load_session(self.manager, {
          session,
          workspace: None,
        })
        guard loaded.session.events is Some(events) && !events.is_empty() else {
          raise @mcp.ToolError("conversation has no saved history")
        }
      },
      () => self.publish(UserQuestions(self.questions.snapshot())),
    ),
  ]
}

///|
fn ask_user_tool(
  questions : @user_questions.Service,
  validate : async (String) -> Unit,
  changed : () -> Unit,
) -> @mcp.Tool {
  {
    name: "ask_user",
    description: "Ask the user questions in this conversation. Supply unique question ids, clear titles, and optional suggested choices; the user can always type their own answer. This is for information and preferences, not permission approval. Waits up to 30 seconds. A pending result means the questions remain open: continue independent work without assuming an answer or asking the same questions again. Later answers (or a skip) are actively delivered to this conversation. Questions survive tool/turn completion and frontend reconnects, but not host shutdown.",
    input_schema: {
      "type": "object",
      "additionalProperties": false,
      "required": ["questions"],
      "properties": {
        "questions": {
          "type": "array",
          "minItems": 1,
          "items": {
            "type": "object",
            "additionalProperties": false,
            "required": ["id", "title"],
            "properties": {
              "id": { "type": "string", "minLength": 1 },
              "title": { "type": "string", "minLength": 1 },
              "options": {
                "type": "array",
                "items": { "type": "string", "minLength": 1 },
              },
            },
          },
        },
      },
    },
    call: call => {
      let payload : @protocol.AskUserPayload = @json.from_json(call.arguments)
      validate(call.session)
      let entry = questions.request(call.session, payload)
      changed()
      defer changed()
      [Text(questions.wait(entry).stringify())]
    },
  }
}

///|
async fn ApiState::run_user_questions(self : ApiState) -> Unit {
  self.questions.run(
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
