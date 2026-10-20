///|
/// Bring the backend up on the caller's task group. The first-launch and
/// migration work on the workspace registry finishes first, before anything
/// here can serve a client; then the app-lifetime owners start: the Codex
/// app-server and engine supervisors, the schedule runner, the host pumps,
/// and the host's tool server when it has one. Every host of the backend
/// starts through this one call, so none can serve a workspace list it has
/// not prepared, and a client finds the same backend behind any of them. The
/// owners feed every page and client rather than borrowing one request's
/// task as their owner, and stop when `group` ends.
pub async fn[G] ApiState::start_services(
  self : ApiState,
  group : @async.TaskGroup[G],
) -> Unit {
  prepare_workspaces()
  group.spawn_bg(() => self.run_session_messages())
  group.spawn_bg(() => self.run_user_questions())
  group.spawn_bg(allow_failure=true, () => {
    self.codex.run((method_, params) => {
      if @protocol.Notification::from_wire(method_, params)
        is Some(notification) {
        self.publish(notification)
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
  @host.spawn_host_pumps(group, self.host, notification => {
    self.publish(notification)
  })
  // Engines are granted this server from their first spawn, so it serves
  // from the same moment they can exist.
  if self.host_mcp is Some(server) {
    server.add_tools(self.session_tools())
    server.add_tools(self.question_tools())
    server.add_tools(self.artifact_tools())
    @xlog.info() <?
      { "event": "desktop_host_tools_serving", "url": server.url() }
    group.spawn_bg(allow_failure=true, () => server.run())
  }
}
