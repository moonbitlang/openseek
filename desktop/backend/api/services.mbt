///|
/// Start the app-lifetime owners behind this state on the caller's task
/// group: the Codex app-server and engine supervisors, the schedule runner,
/// and the host pumps. Every host of the backend runs exactly these, so a
/// client finds the same backend behind any of them. They feed every page and
/// client rather than borrowing one request's task as their owner, and stop
/// when `group` ends.
pub fn[G] ApiState::spawn_services(
  self : ApiState,
  group : @async.TaskGroup[G],
) -> Unit {
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
}
