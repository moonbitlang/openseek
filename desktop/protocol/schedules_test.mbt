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
        notice: None,
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
