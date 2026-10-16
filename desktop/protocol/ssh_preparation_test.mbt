///|
test "SSH preparation codecs distinguish targets and reject malformed fields" {
  let request : @protocol.SshPreparationRequest = {
    target: New(name="构建", destination="qa", data_dir="/data/独立"),
    directory: "/local/package",
  }
  let decoded : @protocol.SshPreparationRequest = @json.from_json(
    request.to_json(),
  )
  assert_true(decoded == request)
  let existing : @protocol.SshPreparationRequest = {
    ..request,
    target: Existing(id="ssh_existing"),
  }
  let decoded : @protocol.SshPreparationRequest = @json.from_json(
    existing.to_json(),
  )
  assert_true(decoded == existing)
  for
    value in [
      ({ "directory": "/package" } : Json),
      { "directory": null, "target": { "kind": "existing", "id": "ssh_a" } },
      { "directory": "/package", "target": { "kind": "existing", "id": null } },
      {
        "directory": "/package",
        "target": { "kind": "new", "name": "a", "destination": "qa" },
      },
      { "directory": "/package", "target": { "kind": "unknown" } },
    ] {
    let rejected = try {
      let _ : @protocol.SshPreparationRequest = @json.from_json(value)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  for value in [({} : Json), { "stage": null, "extra": true }] {
    let progress : @protocol.SshPreparationProgress = @json.from_json(value)
    assert_eq(progress.stage, None)
    assert_eq(progress.to_json(), {})
  }
  let malformed = try {
    let _ : @protocol.SshPreparationProgress = @json.from_json({ "stage": 3 })
    false
  } catch {
    _ => true
  }
  assert_true(malformed)
  let reply : @protocol.SshOperation[@protocol.SshPreparationToken] = @json.from_json({
      "status": "failed",
      "message": "Permission denied",
      "extra": true,
    },
  )
  assert_true(reply is SshFailed("Permission denied"))
  let reply : @protocol.SshOperation[@protocol.SshPreparationToken] = @json.from_json({
      "status": "completed",
      "value": { "id": "attempt" },
    },
  )
  assert_true(reply is SshCompleted({ id: "attempt", }))
}
