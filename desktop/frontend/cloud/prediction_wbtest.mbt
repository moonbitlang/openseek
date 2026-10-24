///|
fn prediction_document(sequence : Int32) -> @protocol.SessionDocument {
  {
    version: None,
    id: None,
    system_prompt: None,
    events: Some([
      {
        sequence,
        ts: None,
        item: @protocol.Terminal(@protocol.Finished("Done")),
      },
    ]),
  }
}

///|
fn prediction_record(sequence : Int32) -> @wire.PredictionRecord {
  {
    source_sequence: sequence,
    outcome: Completed(
      text=Some("Commit the fix"),
      input_tokens=8,
      output_tokens=4,
    ),
  }
}

///|
fn prediction_watch() -> (State, StreamLease) {
  let base = controls_fixture()
  let base = base.replace("session", {
    ..base.conversations["session"],
    document: prediction_document(12),
    generating: false,
  })
  let (state, stream) = watch_fixture(base)
  let control = state.conversations["session"].control.unwrap()
  (
    watch_snapshot(state, stream, Some("current-task"), 900, {
      ..control,
      active_task_id: None,
      status: Idle,
    }),
    stream,
  )
}

///|
test "Cloud prediction metadata is nullable and cannot break history loading" {
  let base : Json = {
    "messages": [],
    "session": { "events": [] },
    "generating": false,
  }
  let history = decode_history(base)
  assert_true(history.prediction is None)
  for
    value in [null, ({ "version": 99 } : Json), prediction_record(12).to_json()] {
    guard base is Object(fields) else { fail("fixture") }
    let fields = fields.copy()
    fields["prediction"] = value
    let history = decode_history(Json(fields))
    if value == prediction_record(12).to_json() {
      assert_eq(history.prediction, Some(prediction_record(12)))
    } else {
      assert_true(history.prediction is None)
    }
    assert_false(history.generating)
  }
}

///|
test "Cloud prediction validity uses native records independently of task and SSE sequence" {
  let (base, stream) = prediction_watch()
  let received = native_event(
    base,
    stream,
    Some("old-task"),
    901,
    @wire.PredictionResult(
      source_sequence=12,
      outcome=prediction_record(12).outcome,
    ),
  )
  let conversation = received.conversations["session"]
  assert_eq(conversation.prediction, Some(prediction_record(12)))
  assert_eq(
    conversation.prediction_source(ready=received.can_send("session")),
    Some(12),
  )
  let stale = native_event(
    received,
    stream,
    None,
    902,
    @wire.PredictionResult(
      source_sequence=11,
      outcome=prediction_record(11).outcome,
    ),
  )
  assert_eq(
    stale.conversations["session"].prediction,
    Some(prediction_record(12)),
  )
  for
    outcome in [
      @wire.PredictionOutcome::Skipped,
      @wire.PredictionOutcome::Cancelled,
      @wire.PredictionOutcome::Failed("unavailable"),
    ] {
    let failed = native_event(
      base,
      stream,
      None,
      901,
      @wire.PredictionResult(source_sequence=12, outcome~),
    )
    assert_true(failed.conversations["session"].prediction is None)
    assert_true(failed.conversations["session"].notice is None)
    assert_true(failed.can_send("session"))
  }
}

///|
test "Cloud predictions ahead of history wait for the exact frontier and survive missing metadata" {
  let (base, stream) = prediction_watch()
  let received = native_event(
    base,
    stream,
    None,
    901,
    @wire.PredictionResult(
      source_sequence=20,
      outcome=prediction_record(20).outcome,
    ),
  )
  let conversation = received.conversations["session"]
  assert_eq(conversation.prediction, Some(prediction_record(20)))
  // This source is 12, not the future prediction's 20 or SSE's 901.
  assert_eq(conversation.prediction_source(ready=true), Some(12))
  let loaded = metadata_update(
    received,
    Loaded(1, "session", conversation.request, {
      session: prediction_document(20),
      messages: [],
      generating: false,
      prediction: None,
    }),
  )
  assert_eq(
    loaded.conversations["session"].prediction,
    Some(prediction_record(20)),
  )
  assert_eq(
    loaded.conversations["session"].prediction_source(ready=true),
    Some(20),
  )
  let advanced = metadata_update(
    loaded,
    Loaded(1, "session", conversation.request, {
      session: prediction_document(21),
      messages: [],
      generating: false,
      prediction: Some(prediction_record(20)),
    }),
  )
  assert_true(advanced.conversations["session"].prediction is None)
  let late = native_event(
    advanced,
    stream,
    Some("old-task"),
    902,
    @wire.PredictionResult(
      source_sequence=20,
      outcome=prediction_record(20).outcome,
    ),
  )
  assert_true(late.conversations["session"].prediction is None)
}

///|
test "Cloud queued input goal edits and compaction suppress prediction eligibility" {
  let (state, _) = prediction_watch()
  let base = {
    ..state.conversations["session"],
    prediction: Some(prediction_record(12)),
  }
  assert_eq(base.prediction_source(ready=true), Some(12))
  for
    conversation in [
      {
        ..base,
        controls: { ..base.controls, edit: Some({ draft: "Goal", }), },
      },
      { ..base, controls: { ..base.controls, compaction: Queued, }, },
      { ..base, queue_edit: Some("queue"), },
      {
        ..base,
        control: base.control.map(control => {
          ..control,
          queue: [{ id: "q", content: @wire.Content([Text("Next")]), }],
        }),
      },
      {
        ..base,
        control: base.control.map(control => {
          ..control,
          steers: [{ submission_id: "s", status: Pending, }],
        }),
      },
    ] {
    assert_true(conversation.prediction_source(ready=true) is None)
  }
  assert_true(base.prediction_source(ready=false) is None)
}
