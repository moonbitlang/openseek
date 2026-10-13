///|
test "start reply codec requires completion fields and preserves a zero exit" {
  let raw : Json = { "run_id": "r1", "status": "finished", "exit_code": 0 }
  let value : @protocol.StartReply = @json.from_json(raw)
  @debug.assert_eq(value.to_json(), raw)
  for
    bad in (
      [
        {},
        { "run_id": "r1", "status": "finished" },
        { "run_id": "r1", "status": "finished", "exit_code": null },
        { "run_id": "r1", "status": "finished", "exit_code": "0" },
      ] : Array[Json]) {
    assert_true(
      refused(() => {
        let _ : @protocol.StartReply = @json.from_json(bad)
      }),
    )
  }
}

///|
test "steer reply codec keeps false distinct from missing and omits absent run" {
  for
    raw in (
      [
        { "steered": false },
        { "steered": false, "run_id": null, "future": true },
      ] : Array[Json]) {
    let value : @protocol.SteerReply = @json.from_json(raw)
    assert_false(value.steered)
    assert_eq(value.run_id, None)
    @debug.assert_eq(value.to_json(), { "steered": false })
  }
  for
    raw in (
      [
        {},
        { "steered": null },
        { "steered": "false" },
        { "steered": true, "run_id": 7 },
      ] : Array[Json]) {
    assert_true(
      refused(() => {
        let _ : @protocol.SteerReply = @json.from_json(raw)
      }),
    )
  }
}

///|
test "session groups codec preserves row tolerance inside strict envelopes" {
  let value : @protocol.SessionsReply = @json.from_json({
    "groups": [
      {
        "workspace": "/work/demo",
        "name": "Demo",
        "session_root": "/work/demo/.openseek",
        "error": "",
        "sessions": [{ "id": "s1", "title": null, "updated_at_ms": "old" }],
        "future": true,
      },
    ],
  })
  @debug.assert_eq(value.to_json(), {
    "groups": [
      {
        "workspace": "/work/demo",
        "name": "Demo",
        "session_root": "/work/demo/.openseek",
        "error": "",
        "sessions": [{ "id": "s1" }],
      },
    ],
  })
  for raw in ([{}, { "groups": null }, { "groups": [{}] }] : Array[Json]) {
    assert_true(
      refused(() => {
        let _ : @protocol.SessionsReply = @json.from_json(raw)
      }),
    )
  }
}

///|
test "session document codec preserves unknown events and validates their envelope" {
  let item : Json = { "kind": "future", "payload": { "data": [1, 2] } }
  let raw : Json = { "events": [{ "sequence": 1, "item": item }] }
  let value : @protocol.SessionDocument = @json.from_json(raw)
  @debug.assert_eq(value.to_json(), raw)
  let empty : @protocol.SessionDocument = @json.from_json({
    "events": null,
    "id": null,
    "future": true,
  })
  @debug.assert_eq(empty.to_json(), {})
  for
    bad in (
      [
        { "events": {} },
        { "events": [{ "item": item }] },
        { "events": [{ "sequence": 1, "ts": "today", "item": item }] },
      ] : Array[Json]) {
    assert_true(
      refused(() => {
        let _ : @protocol.SessionDocument = @json.from_json(bad)
      }),
    )
  }
}
