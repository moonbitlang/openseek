///|
test "turn completion before start reply does not resurrect draining work" {
  let actor = Actor(CodexSettings::default())
  actor.pending_starts = 1
  assert_true(actor.has_active_work())
  actor.track_turn_event("turn/started", { "turn": { "id": "turn-1" } })
  actor.track_turn_event("turn/completed", { "turn": { "id": "turn-1" } })
  actor.track_started_reply({
    "turn": { "id": "turn-1", "status": "inProgress" },
  })
  actor.pending_starts = 0
  assert_false(actor.has_active_work())
  actor.track_started_reply({
    "turn": { "id": "turn-2", "status": "inProgress" },
  })
  assert_true(actor.has_active_work())
  actor.track_turn_event("turn/completed", { "turn": { "id": "turn-2" } })
  assert_false(actor.has_active_work())
}

///|
test "unrecognized accepted start remains busy instead of claiming settlement" {
  let actor = Actor(CodexSettings::default())
  actor.track_started_reply(Json::empty_object())
  actor.track_turn_event("turn/completed", { "turn": { "id": "unrelated" } })
  assert_true(actor.has_active_work())
}
