///|
/// Start the shared backend before serving embedded clients. Headless hosts
/// retain their explicitly selected workspace registry.
pub async fn[G] ApiState::start_services(
  self : ApiState,
  group : @async.TaskGroup[G],
) -> Unit {
  if self.config.mode is Embedded {
    prepare_workspaces()
  }
  group.spawn_bg(() => self.run())
}
