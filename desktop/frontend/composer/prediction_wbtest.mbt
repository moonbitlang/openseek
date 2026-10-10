///|
fn prediction_fixture() -> Input {
  {
    ..Input::fixture(""),
    prediction_source: Some(2),
    prediction: Some({
      source_sequence: 2,
      outcome: Completed(
        text=Some("Commit the fix"),
        input_tokens=8,
        output_tokens=4,
      ),
    }),
  }
}

///|
test "blank drafts cannot submit or accept an invisible prediction" {
  let input = prediction_fixture()
  let empty = Model(input)
  assert_true(empty.active(input).draft.is_empty())
  assert_true(empty.active(input).draft.is_blank())
  for text in [" ", "\n", "\t"] {
    let (model, _) = empty.update(
      input,
      TextChanged(text),
      Msg::test_emit(),
      Action::test_emit(),
    )
    let entry = model.active(input)
    assert_true(!entry.draft.is_empty())
    assert_true(entry.draft.is_blank())
    assert_eq(entry.prediction_text(input), None)
    let (submitted, _) = model.update(
      input,
      SubmitRequested,
      Msg::test_emit(),
      Action::test_emit(),
    )
    assert_true(submitted == model)
    let (accepted, _) = model.update(
      input,
      PredictionAccepted,
      Msg::test_emit(),
      Action::test_emit(),
    )
    assert_true(accepted == model)
  }
}

///|
test "broadcast suggestions react to input without a composer message" {
  let input = prediction_fixture()
  let before = { ..input, prediction: None, }
  let model = Model(before)
  assert_eq(model.active(before).prediction_text(before), None)
  assert_eq(model.active(input).prediction_text(input), Some("Commit the fix"))
  let newer = { ..input, prediction_source: Some(3), }
  assert_eq(model.active(newer).prediction_text(newer), None)
  let hidden = { ..input, prediction_source: None, }
  assert_eq(model.active(hidden).prediction_text(hidden), None)
  assert_eq(model.active(input).prediction_text(input), Some("Commit the fix"))
}

///|
test "accept and edit are pure local changes and clearing restores the broadcast" {
  let input = prediction_fixture()
  let model = Model(input)
  let (accepted, _) = model.update(
    input,
    PredictionAccepted,
    Msg::test_emit(),
    Action::test_emit(),
  )
  let (again, _) = model.update(
    input,
    PredictionAccepted,
    Msg::test_emit(),
    Action::test_emit(),
  )
  assert_true(accepted == again)
  assert_eq(accepted.active(input).draft.task, "Commit the fix")
  assert_true(accepted.active(input).pending_submission is None)
  assert_eq(accepted.active(input).prediction_text(input), None)
  // A second client keeps its independent empty draft and the same suggestion.
  assert_eq(model.active(input).prediction_text(input), Some("Commit the fix"))
  let (edited, _) = accepted.update(
    input,
    TextChanged("my text"),
    Msg::test_emit(),
    Action::test_emit(),
  )
  let (edited_again, _) = accepted.update(
    input,
    TextChanged("my text"),
    Msg::test_emit(),
    Action::test_emit(),
  )
  assert_true(edited == edited_again)
  assert_eq(edited.active(input).prediction_text(input), None)
  let (cleared, _) = edited.update(
    input,
    TextChanged(""),
    Msg::test_emit(),
    Action::test_emit(),
  )
  assert_eq(
    cleared.active(input).prediction_text(input),
    Some("Commit the fix"),
  )
}

///|
test "empty outcomes and a mismatched conversation never show suggestions" {
  let input = prediction_fixture()
  let model = Model(input)
  let empty = {
    ..input,
    prediction: Some({
      source_sequence: 2,
      outcome: Completed(text=None, input_tokens=1, output_tokens=1),
    }),
  }
  assert_eq(model.active(empty).prediction_text(empty), None)
  let other = {
    ..input,
    identity: {
      ..input.identity,
      owner: { ..input.identity.owner, session: "other", },
    },
  }
  assert_eq(model.active(input).prediction_text(other), None)
}
