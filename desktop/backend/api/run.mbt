///|
/// Own the working host for one process lifetime, independent of any client.
/// Cancelling this task joins its actors and their children before returning.
/// An instance is single-use: engine shutdown closes its command mailbox.
pub async fn ApiState::run(self : ApiState) -> Unit {
  self.prepare()
  @async.with_task_group(group => {
    group.spawn_bg(() => self.admission.run())
    group.spawn_bg(() => self.run_session_messages())
    group.spawn_bg(() => self.run_user_questions())
    if self.host_mcp is Some(server) {
      server.add_tools(self.session_tools())
      server.add_tools(self.question_tools())
      @xlog.info() <?
        { "event": "desktop_host_tools_serving", "url": server.url() }
      group.spawn_bg(allow_failure=true, () => server.run())
    }
    group.spawn_bg(allow_failure=true, () => {
      self.codex.run((method_, params) => {
        if @protocol.HostNotification::from_wire(method_, params) is Some(event) {
          self.publish(event)
        }
      })
    })
    group.spawn_bg(allow_failure=true, () => {
      self.engine.run(self.sink(), message => {
        self.publish(
          AgentError({
            run_id: None,
            message: Some(message),
            exit_code: None,
            diagnostics: None,
          }),
        )
      })
    })
    group.spawn_bg(allow_failure=true, () => self.run_schedules())
    @host.spawn_host_pumps(group, self.host, event => self.publish(event))
  })
}
