///|
test "SSH labels respect explicit names and never expose connection options" {
  for
    (command, label, address) in [
      ("ssh -F '/tmp/config file' build", "build", "build"),
      (
        "ssh -p 2222 -i '/tmp/key with spaces' -J jump user@host", "host", "user@host · Port 2222",
      ),
      ("ssh -l ci -p 2200 build", "build", "ci@build · Port 2200"),
      ("ssh user@[2001:db8::1]", "[2001:db8::1]", "user@[2001:db8::1]"),
    ] {
    let profile : @protocol.SshProfile = {
      id: "id",
      command,
      server: "openseek-app-server",
      display_name: None,
    }
    assert_eq(profile.display_label(), label)
    assert_eq(profile.connection_label(), address)
    assert_eq(
      { ..profile, display_name: Some("  Build server  "), }.display_label(),
      "Build server",
    )
    assert_eq({ ..profile, display_name: Some("  "), }.display_label(), label)
  }
}

///|
test "SSH profiles without display names still load and renamed profiles round trip" {
  let old : @protocol.SshProfile = @json.from_json({
    "id": "legacy",
    "command": "ssh build",
    "server": "openseek-app-server",
  })
  assert_eq(old.display_name, None)
  assert_eq(old.display_label(), "build")
  let null_name : @protocol.SshProfile = @json.from_json({
    "id": "legacy",
    "command": "ssh build",
    "server": "openseek-app-server",
    "display_name": null,
  })
  assert_true(null_name == old)
  let renamed = { ..old, display_name: Some("Build server"), }
  assert_true(@json.from_json(renamed.to_json()) == renamed)
  assert_true(@json.from_json(old.to_json()) == old)
}
