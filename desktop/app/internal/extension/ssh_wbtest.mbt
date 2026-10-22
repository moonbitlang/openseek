///|
async test "a delayed SSH cancel cannot close a replacement connection" {
  let bridge = DesktopBridgeActor(ApiState(engine="unused"))
  let profile : @protocol.SshProfile = {
    id: "host",
    command: "ssh demo",
    projects: None,
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

///|
async test "SSH removal closes the route only after profile persistence succeeds" {
  let directory = @fs.tmpdir(prefix="ssh-remove-owner-")
  defer @fs.rmdir(directory, recursive=true)
  let path = directory + "/profiles.json"
  let previous = @env.get_env_var("SEEKMOON_SSH_PROFILES")
  defer (match previous {
    Some(value) => @env.set_env_var("SEEKMOON_SSH_PROFILES", value)
    None => @env.unset_env_var("SEEKMOON_SSH_PROFILES")
  })
  @env.set_env_var("SEEKMOON_SSH_PROFILES", path)
  let profile = @ssh.save({
    id: "",
    command: "ssh demo",
    projects: None,
    display_name: None,
  })
  let bridge = DesktopBridgeActor(ApiState(engine="unused"))
  let route = @ssh.Connection(profile, 7, attempt=2)
  bridge.routes[profile.id] = route
  let tasks : Map[String, @async.Task[Unit]] = Map([])
  let stored = @fs.read_file(path)
  @fs.write_file(path, "invalid JSON")
  assert_true(bridge.remove_ssh(profile.id, tasks) is SshRefused(_))
  assert_true(route.active())
  assert_true(bridge.routes.contains(profile.id))
  @fs.write_file(path, stored)
  assert_true(bridge.remove_ssh(profile.id, tasks) is SshSuccess(_))
  assert_false(route.active())
  assert_false(bridge.routes.contains(profile.id))
  assert_true(@ssh.profiles().hosts.is_empty())
}
