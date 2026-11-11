///|
test "schedule codecs reject malformed timing and preserve optional absence" {
  let invalid_timings : Array[Json] = [
    { "kind": "every", "minutes": 0 },
    { "kind": "every", "minutes": 1.5 },
    { "kind": "once", "at": -1 },
    { "kind": "cron" },
  ]
  for timing in invalid_timings {
    let rejected = try {
      let _ : @protocol.ScheduleTiming = @json.from_json(timing)
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  let spec : @protocol.ScheduleSpec = @json.from_json({
    "name": "Check",
    "workspace": "/workspace",
    "task": "check",
    "timing": { "kind": "every", "minutes": 30 },
    "timeout_minutes": 10,
  })
  assert_eq(spec.model, None)
  let roundtrip : @protocol.ScheduleSpec = @json.from_json(spec.to_json())
  assert_eq(spec, roundtrip)
  let invalid : Json = {
    "name": "Check",
    "workspace": "/workspace",
    "task": "check",
    "model": 123,
    "timing": { "kind": "every", "minutes": 30 },
    "timeout_minutes": 10,
  }
  let rejected = try {
    let _ : @protocol.ScheduleSpec = @json.from_json(invalid)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "one-time schedule roundtrips millisecond timestamps" {
  let timing : @protocol.ScheduleTiming = Once(1770000000000L)
  let decoded : @protocol.ScheduleTiming = @json.from_json(timing.to_json())
  assert_eq(timing, decoded)
  let state : @protocol.SchedulesReply = {
    entries: [
      {
        id: "p",
        spec: {
          name: "task",
          task: "check",
          workspace: Some("/workspace"),
          model: None,
          timing,
          timeout_minutes: 30,
        },
        enabled: true,
        run_requested: false,
        skipped: None,
        next_at: Some(1770000000000L),
      },
    ],
    runs: [
      {
        id: "r",
        schedule_id: "p",
        name: "task",
        workspace: "/workspace",
        session: "scheduled-r",
        started_at: 1770000000000L,
        finished_at: Some(1770000005000L),
        status: Succeeded,
        log_path: "/runtime/r.log",
      },
    ],
  }
  let restored : @protocol.SchedulesReply = @json.from_json(
    @json.parse(state.to_json().stringify()),
  )
  assert_eq(state, restored)
}

///|
test "automatic schedule workspace and immediate save have explicit codecs" {
  let payload : @protocol.ScheduleSavePayload = @json.from_json({
    "spec": {
      "name": "community",
      "task": "check",
      "workspace": null,
      "timing": { "kind": "every", "minutes": 30 },
      "timeout_minutes": 10,
    },
    "run_now": true,
  })
  assert_eq(payload.spec.workspace, None)
  assert_true(payload.run_now)
  let restored : @protocol.ScheduleSavePayload = @json.from_json(
    payload.to_json(),
  )
  assert_eq(payload, restored)
  for workspace in (["", 123] : Array[Json]) {
    let rejected = try {
      let _ : @protocol.ScheduleSpec = @json.from_json({
        "name": "community",
        "task": "check",
        "workspace": workspace,
        "timing": { "kind": "every", "minutes": 30 },
        "timeout_minutes": 10,
      })
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "schedule change replies, actions and skips have explicit codecs" {
  let refused : @protocol.ScheduleChangeReply = Refused(AlreadyQueued)
  assert_eq(refused.to_json(), {
    "status": "refused",
    "reason": "already_queued",
  })
  let changed : @protocol.ScheduleChangeReply = Changed({
    entries: [],
    runs: [],
  })
  assert_eq(changed.to_json(), {
    "status": "changed",
    "state": { "entries": [], "runs": [] },
  })
  for reply in [refused, changed] {
    let decoded : @protocol.ScheduleChangeReply = @json.from_json(
      reply.to_json(),
    )
    assert_eq(decoded, reply)
  }
  // The action keeps the wire strings it had as free text.
  let payload : @protocol.ScheduleActionPayload = @json.from_json({
    "id": "plan",
    "action": "resume",
  })
  assert_eq(payload.action, Resume)
  assert_eq(payload.to_json(), { "id": "plan", "action": "resume" })
  let unknown : Array[Json] = [
    { "id": "plan", "action": "restart" },
    { "status": "refused", "reason": "busy" },
    { "status": "pending" },
  ]
  let rejected = unknown.map(json => {
    try {
      if json is { "action": _, .. } {
        let _ : @protocol.ScheduleActionPayload = @json.from_json(json)
      } else {
        let _ : @protocol.ScheduleChangeReply = @json.from_json(json)
      }
      false
    } catch {
      _ => true
    }
  })
  assert_eq(rejected, [true, true, true])
  // An entry saved before skip reasons existed loses only its free text.
  let entry : @protocol.ScheduleEntry = @json.from_json({
    "id": "plan",
    "spec": {
      "name": "Check",
      "task": "check",
      "timing": { "kind": "every", "minutes": 30 },
      "timeout_minutes": 10,
    },
    "enabled": true,
    "run_requested": false,
    "notice": "Skipped: the previous run is still active",
  })
  assert_eq(entry.skipped, None)
  let skipped = { ..entry, skipped: Some(CapacityFull), }
  guard skipped.to_json() is { "skipped": "capacity_full", .. } else {
    fail("a skip reason is encoded as its wire tag")
  }
  let decoded : @protocol.ScheduleEntry = @json.from_json(skipped.to_json())
  assert_eq(decoded, skipped)
}
