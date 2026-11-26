///|
fn ApiState::question_tools(self : ApiState) -> Array[@mcp.Tool] {
  [
    self.questions.tool(
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
