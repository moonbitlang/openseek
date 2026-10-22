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
      projects: None,
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
  })
  assert_eq(old.display_name, None)
  assert_eq(old.projects, None)
  assert_eq(old.display_label(), "build")
  let null_name : @protocol.SshProfile = @json.from_json({
    "id": "legacy",
    "command": "ssh build",
    "display_name": null,
    "projects": null,
  })
  assert_true(null_name == old)
  let renamed = { ..old, display_name: Some("Build server"), }
  assert_true(
    renamed.to_json() ==
    { "id": "legacy", "command": "ssh build", "display_name": "Build server" },
  )
  assert_true(@json.from_json(renamed.to_json()) == renamed)
  assert_true(@json.from_json(old.to_json()) == old)
  let cached = {
    ..renamed,
    projects: Some(["openseek://remote.legacy/tmp/project"]),
  }
  assert_true(@json.from_json(cached.to_json()) == cached)
  let empty = { ..renamed, projects: Some([]), }
  assert_true(@json.from_json(empty.to_json()) == empty)
  for projects in [Json("not a list"), Json([1])] {
    assert_true(
      try {
        let _ : @protocol.SshProfile = @json.from_json({
          "id": "legacy",
          "command": "ssh build",
          "projects": projects,
        })
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "SSH authentication codecs distinguish empty input confirmation cancellation and malformed payloads" {
  let base : Json = {
    "host_id": "host",
    "attempt": 2,
    "epoch": 3,
    "request_id": 4,
    "answer": { "action": "value", "value": "" },
  }
  let decoded : @protocol.SshAuthResponse = @json.from_json(base)
  assert_true(decoded.answer is Value(""))
  assert_true(decoded.to_json() == base)
  for action in ["accept", "cancel"] {
    let answer : @protocol.SshAuthAnswer = @json.from_json({
      "action": action,
      "extension": true,
    })
    assert_true(answer.to_json() == { "action": action })
  }
  let request : @protocol.SshAuthRequest = @json.from_json({
    "request_id": 1,
    "kind": "challenge",
    "prompt": "OTP:",
    "target": null,
    "retry": false,
    "extension": true,
  })
  assert_eq(request.target, None)
  assert_true(
    request.to_json() ==
    { "request_id": 1, "kind": "challenge", "prompt": "OTP:", "retry": false },
  )
  for
    invalid in (
      [
        { "action": "value" },
        { "action": "value", "value": null },
        { "action": "value", "value": 1 },
        { "action": "unknown" },
        {},
      ] : Array[Json]) {
    let rejected = try {
      let _ : @protocol.SshAuthAnswer = @json.from_json(invalid)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  for
    invalid in (
      [
        { "request_id": 1, "kind": "unknown", "prompt": "p", "retry": false },
        {
          "request_id": 1,
          "kind": "password",
          "prompt": "p",
          "retry": false,
          "target": 1,
        },
        { "request_id": 1, "kind": "password", "prompt": "p" },
        { "request_id": 1, "kind": "password", "prompt": null, "retry": false },
      ] : Array[Json]) {
    let rejected = try {
      let _ : @protocol.SshAuthRequest = @json.from_json(invalid)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  for
    invalid in (
      [
        {
          "host_id": "host",
          "epoch": 3,
          "request_id": 4,
          "answer": { "action": "cancel" },
        },
        {
          "host_id": "host",
          "attempt": "2",
          "epoch": 3,
          "request_id": 4,
          "answer": { "action": "cancel" },
        },
      ] : Array[Json]) {
    let rejected = try {
      let _ : @protocol.SshAuthResponse = @json.from_json(invalid)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}
