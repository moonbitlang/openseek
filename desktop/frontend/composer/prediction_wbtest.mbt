///|
fn prediction_fixture() -> Input {
  { ..Input::fixture(""), prediction_source: Some(2), }
}

///|
fn prediction_pending(input : Input) -> Model {
  let model = Model(input)
  {
    ..model.with_entry({
      ..model.active(input),
      prediction: Predicting("request", 2),
    }),
    prediction_client: Some("client"),
  }
}

///|
test "late prediction cannot repopulate an edited then cleared draft" {
  let input = prediction_fixture()
  let initial = prediction_pending(input)
  let (edited, _) = initial.update(
    input,
    TextChanged("my text"),
    Msg::test_emit(),
    Action::test_emit(),
  )
  let (again, _) = initial.update(
    input,
    TextChanged("my text"),
    Msg::test_emit(),
    Action::test_emit(),
  )
  assert_true(edited == again)
  assert_true(initial.active(input).prediction is Predicting(_, _))
  let (cleared, _) = edited.update(
    input,
    TextChanged(""),
    Msg::test_emit(),
    Action::test_emit(),
  )
  let (late, _) = cleared.update(
    input,
    PredictionSettled(
      input.identity,
      "request",
      2,
      Ok({
        outcome: Completed(
          text=Some("old suggestion"),
          input_tokens=1,
          output_tokens=1,
        ),
      }),
    ),
    Msg::test_emit(),
    Action::test_emit(),
  )
  assert_eq(late.active(input).draft.task, "")
  assert_eq(late.active(input).prediction_text(input), None)
  assert_true(late.active(input).prediction is Predicted(2, None))
}

///|
test "accept inserts a suggestion into the draft without submitting it" {
  let input = prediction_fixture()
  let initial = prediction_pending(input)
  let (ready, _) = initial.update(
    input,
    PredictionSettled(
      input.identity,
      "request",
      2,
      Ok({
        outcome: Completed(
          text=Some("Run the tests"),
          input_tokens=1,
          output_tokens=1,
        ),
      }),
    ),
    Msg::test_emit(),
    Action::test_emit(),
  )
  assert_eq(ready.active(input).draft.task, "")
  assert_eq(ready.active(input).prediction_text(input), Some("Run the tests"))
  let (accepted, _) = ready.update(
    input,
    PredictionAccepted,
    Msg::test_emit(),
    Action::test_emit(),
  )
  let (again, _) = ready.update(
    input,
    PredictionAccepted,
    Msg::test_emit(),
    Action::test_emit(),
  )
  assert_true(accepted == again)
  assert_eq(accepted.active(input).draft.task, "Run the tests")
  assert_true(accepted.active(input).pending_submission is None)
  assert_eq(accepted.active(input).prediction_text(input), None)
  let (cleared, _) = accepted.update(
    input,
    TextChanged(""),
    Msg::test_emit(),
    Action::test_emit(),
  )
  assert_eq(cleared.active(input).prediction_text(input), Some("Run the tests"))
  assert_eq(cleared.prediction_serial, ready.prediction_serial)
  let newer = { ..input, prediction_source: Some(3), }
  assert_eq(cleared.active(newer).prediction_text(newer), None)
}

///|
test "navigation and a new source reject stale suggestions" {
  let input = prediction_fixture()
  let initial = prediction_pending(input)
  let hidden = { ..input, prediction_source: None, }
  let (away, _) = initial.update(
    hidden,
    PredictionPump,
    Msg::test_emit(),
    Action::test_emit(),
  )
  assert_true(away.active(hidden).prediction is Unrequested)
  let (back, _) = away.update(
    input,
    PredictionPump,
    Msg::test_emit(),
    Action::test_emit(),
  )
  assert_true(back.active(input).prediction is Predicting(_, 2))
  let newer = { ..input, prediction_source: Some(3), }
  let (next, _) = back.update(
    newer,
    PredictionPump,
    Msg::test_emit(),
    Action::test_emit(),
  )
  assert_true(next.active(newer).prediction is Predicting(_, 3))
  let (late, _) = next.update(
    newer,
    PredictionSettled(
      input.identity,
      "request",
      2,
      Ok({
        outcome: Completed(text=Some("stale"), input_tokens=1, output_tokens=1),
      }),
    ),
    Msg::test_emit(),
    Action::test_emit(),
  )
  assert_eq(late.active(newer).prediction_text(newer), None)
}

///|
test "persisted prediction survives navigation and editing without another request" {
  let input = {
    ..prediction_fixture(),
    prediction: Some({
      source_sequence: 2,
      request_id: "persisted",
      outcome: Completed(
        text=Some("Commit the fix"),
        input_tokens=10,
        output_tokens=4,
      ),
    }),
  }
  let initial = { ..Model(input), prediction_client: Some("client"), }
  let (restored, _) = initial.update(
    input,
    PredictionPump,
    Msg::test_emit(),
    Action::test_emit(),
  )
  let (again, _) = initial.update(
    input,
    PredictionPump,
    Msg::test_emit(),
    Action::test_emit(),
  )
  assert_true(restored == again)
  assert_eq(restored.prediction_serial, 0)
  assert_eq(
    restored.active(input).prediction_text(input),
    Some("Commit the fix"),
  )
  let hidden = { ..input, prediction_source: None, }
  let (away, _) = restored.update(
    hidden,
    PredictionPump,
    Msg::test_emit(),
    Action::test_emit(),
  )
  let (back, _) = away.update(
    input,
    PredictionPump,
    Msg::test_emit(),
    Action::test_emit(),
  )
  assert_eq(back.active(input).prediction_text(input), Some("Commit the fix"))
  assert_eq(back.prediction_serial, 0)
  let (edited, _) = back.update(
    input,
    TextChanged("My own request"),
    Msg::test_emit(),
    Action::test_emit(),
  )
  assert_eq(edited.active(input).prediction_text(input), None)
  let (cleared, _) = edited.update(
    input,
    TextChanged(""),
    Msg::test_emit(),
    Action::test_emit(),
  )
  let (pumped, _) = cleared.update(
    input,
    PredictionPump,
    Msg::test_emit(),
    Action::test_emit(),
  )
  assert_eq(pumped.active(input).prediction_text(input), Some("Commit the fix"))
  assert_eq(pumped.prediction_serial, 0)
}

///|
test "persisted empty suggestion does not request again" {
  let input = {
    ..prediction_fixture(),
    prediction: Some({
      source_sequence: 2,
      request_id: "empty",
      outcome: Completed(text=None, input_tokens=1, output_tokens=1),
    }),
  }
  let initial = { ..Model(input), prediction_client: Some("client"), }
  let (next, _) = initial.update(
    input,
    PredictionPump,
    Msg::test_emit(),
    Action::test_emit(),
  )
  assert_eq(next.prediction_serial, 0)
  assert_true(next.active(input).prediction is Predicted(2, None))
}
