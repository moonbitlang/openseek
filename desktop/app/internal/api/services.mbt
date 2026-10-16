///|
/// Start the working-host service before accepting local or relay clients.
pub async fn[G] DesktopState::start_services(
  self : DesktopState,
  group : @async.TaskGroup[G],
) -> Unit {
  self.service.start_services(group)
  @host.spawn_host_pumps(group, self.host, notification => {
    self.publish(notification)
  })
}
