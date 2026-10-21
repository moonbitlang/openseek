///|
async test "a delayed SSH cancel cannot close a replacement connection" {
  let bridge = DesktopBridgeActor(ApiState(engine="unused"))
  let profile : @protocol.SshProfile = {
    id: "host",
    command: "ssh demo",
    server: "openseek-app-server",
    display_name: None,
  }
  let current = @ssh.Connection(profile, 7, attempt=2)
  bridge.routes[profile.id] = current
  let tasks : Map[String, @async.Task[Unit]] = Map([])
  bridge.disconnect_ssh({ id: profile.id, attempt: 1, }, tasks)
  assert_true(current.active())
  assert_true(bridge.routes.contains(profile.id))
  bridge.disconnect_ssh({ id: profile.id, attempt: 2, }, tasks)
  assert_false(current.active())
  assert_false(bridge.routes.contains(profile.id))
  bridge.disconnect_ssh({ id: profile.id, attempt: 2, }, tasks)
}
