///|
test "cancel codec distinguishes absent run from a malformed run" {
  for raw in ([{}, { "run_id": null, "future": true }] : Array[Json]) {
    let value : @protocol.CancelPayload = @json.from_json(raw)
    assert_eq(value.run_id, None)
    @debug.assert_eq(value.to_json(), {})
  }
  let value : @protocol.CancelPayload = @json.from_json({ "run_id": "r1" })
  @debug.assert_eq(value.to_json(), { "run_id": "r1" })
  for raw in ([null, [], { "run_id": 7 }] : Array[Json]) {
    assert_true(
      refused(() => {
        let _ : @protocol.CancelPayload = @json.from_json(raw)
      }),
    )
  }
}

///|
test "worktree removal codec requires identity and preserves explicit false" {
  let minimal : Json = { "workspace": "/work/demo", "name": "topic" }
  let value : @protocol.WorktreeRemovePayload = @json.from_json(minimal)
  assert_eq(value.force, None)
  @debug.assert_eq(value.to_json(), minimal)
  let value : @protocol.WorktreeRemovePayload = @json.from_json({
    "workspace": "/work/demo",
    "name": "topic",
    "force": false,
    "future": true,
  })
  assert_eq(value.force, Some(false))
  @debug.assert_eq(value.to_json(), {
    "workspace": "/work/demo",
    "name": "topic",
    "force": false,
  })
  for
    raw in (
      [
        { "name": "topic" },
        { "workspace": null, "name": "topic" },
        { "workspace": "/work/demo", "name": 7 },
        { "workspace": "/work/demo", "name": "topic", "force": "false" },
      ] : Array[Json]) {
    assert_true(
      refused(() => {
        let _ : @protocol.WorktreeRemovePayload = @json.from_json(raw)
      }),
    )
  }
}

///|
test "run reconciliation codec validates nested optional records" {
  let value : @protocol.RunsPayload = @json.from_json({
    "known": [
      { "session": "s1", "run_id": null, "submission_id": "q1", "future": true },
    ],
  })
  @debug.assert_eq(value.to_json(), {
    "known": [{ "session": "s1", "submission_id": "q1" }],
  })
  for
    raw in (
      [
        { "known": {} },
        { "known": [null] },
        { "known": [{}] },
        { "known": [{ "session": "s1", "submission_id": false }] },
      ] : Array[Json]) {
    assert_true(
      refused(() => {
        let _ : @protocol.RunsPayload = @json.from_json(raw)
      }),
    )
  }
}

///|
test "browser bounds codec keeps numeric geometry and rejects wrong types" {
  let raw : Json = { "id": 17, "x": 1, "y": -2, "width": 640, "height": 480 }
  let value : @protocol.BrowserBoundsPayload = @json.from_json(raw)
  @debug.assert_eq(value.to_json(), raw)
  for
    bad in (
      [
        { "id": 17, "x": 1, "y": 2, "width": 640 },
        { "id": 17, "x": 1, "y": 2, "width": "640", "height": 480 },
      ] : Array[Json]) {
    assert_true(
      refused(() => {
        let _ : @protocol.BrowserBoundsPayload = @json.from_json(bad)
      }),
    )
  }
}
