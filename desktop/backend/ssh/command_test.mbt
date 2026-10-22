///|
test "SSH command preserves quoted identity and jump host arguments" {
  let args = @ssh.arguments(
    "ssh -p 2222 -i '/tmp/key with spaces' -J jump user@host",
  )
  assert_eq(args[args.length() - 7:], [
    "-p", "2222", "-i", "/tmp/key with spaces", "-J", "jump", "user@host",
  ])
}

///|
test "SSH command refuses remote commands and stdio ownership flags" {
  for
    command in [
      "", "host", "ssh", "ssh -p host", "ssh host touch /tmp/file", "ssh -tt host",
      "ssh -N host", "ssh -L 8080:host:80 host", "ssh -i 'unfinished host", "ssh host\nsecond",
    ] {
    let rejected = try {
      ignore(@ssh.arguments(command))
      false
    } catch {
      _ => true
    }
    assert_true(rejected, msg=command)
  }
}

///|
async test "unconnected requests are unsent regardless of supplied epoch" {
  let connection = @ssh.Connection(
    { id: "ssh-test", command: "ssh host", projects: None, display_name: None, },
    7,
  )
  for epoch in [6, 7] {
    assert_true(
      connection.request({
        host_id: "ssh-test",
        epoch,
        method_: "agent.start",
        params: {},
      })
      is @protocol.SshUnsent(_),
    )
  }
}

///|
async test "saved SSH profiles survive an existing directory and subsequent additions" {
  let directory = @fs.tmpdir(prefix="ssh-profiles-")
  defer @fs.rmdir(directory, recursive=true)
  let previous = @env.get_env_var("SEEKMOON_SSH_PROFILES")
  defer (match previous {
    Some(value) => @env.set_env_var("SEEKMOON_SSH_PROFILES", value)
    None => @env.unset_env_var("SEEKMOON_SSH_PROFILES")
  })
  @env.set_env_var("SEEKMOON_SSH_PROFILES", directory + "/profiles.json")
  let first = @ssh.save({
    id: "",
    command: "ssh first",
    projects: None,
    display_name: None,
  })
  let second = @ssh.save({
    id: "",
    command: "ssh second",
    projects: None,
    display_name: None,
  })
  let loaded = @ssh.profiles()
  assert_eq(loaded.hosts.length(), 2)
  assert_true(loaded.hosts.contains(first) && loaded.hosts.contains(second))
  assert_true(first.id != second.id)
  let projects = ["openseek://remote." + first.id + "/tmp/project"]
  @ssh.remember_projects({ id: first.id, projects, })
  assert_eq(@ssh.profiles().hosts[0].projects, Some(projects))
  // The rename request predates the registry snapshot; it must preserve it.
  let renamed = @ssh.save({ ..first, display_name: Some("Build machine"), })
  let reloaded = @ssh.profiles()
  assert_true(reloaded.hosts == [renamed, second])
  assert_eq(renamed.id, first.id)
  assert_eq(renamed.command, first.command)
  assert_eq(renamed.projects, Some(projects))
  @ssh.remember_projects({ id: first.id, projects: [], })
  assert_eq(@ssh.profiles().hosts[0].projects, Some([]))
  // Keep profile mutations in one fixture: the storage override is process-wide.
  @ssh.remove(first.id)
  @ssh.remove(first.id)
  @ssh.remember_projects({ id: first.id, projects, })
  assert_true(@ssh.profiles().hosts == [second])
  @ssh.remove(second.id)
  assert_true(@ssh.profiles().hosts.is_empty())
}
