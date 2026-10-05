///|
fn Input::history_fixture(task : String) -> Input {
  { ..Input::fixture(task), history: ["first", "second", "third"], }
}

///|
fn Model::moved(self : Model, input : Input, delta : Int) -> Model {
  let (next, _) = self.update(
    input,
    HistoryMoved(delta),
    Msg::test_emit(),
    Action::test_emit(),
  )
  next
}

///|
test "Up recalls the latest prompt, then older ones, and stops at the oldest" {
  let input = Input::history_fixture("")
  let mut model = Model(input)
  let tasks : Array[String] = []
  for _ in 0..<4 {
    model = model.moved(input, -1)
    tasks.push(model.active(input).draft.task)
  }
  assert_eq(tasks, ["third", "second", "first", "first"])
  assert_eq(
    model.active(input).history_label(English, input),
    Some("History 1/3"),
  )
}

///|
test "Down walks back to the empty draft Up started from" {
  let input = Input::history_fixture("")
  let model = Model(input).moved(input, -1).moved(input, -1).moved(input, 1)
  assert_eq(model.active(input).draft.task, "third")
  let model = model.moved(input, 1)
  let entry = model.active(input)
  assert_eq(entry.draft.task, "")
  assert_true(entry.history_back is None)
  assert_true(entry.history_label(English, input) is None)
}

///|
test "a draft the user typed is never replaced by Up" {
  let input = Input::history_fixture("half-written")
  let model = Model(input).moved(input, -1)
  assert_eq(model.active(input).draft.task, "half-written")
  assert_true(!model.active(input).can_recall_history(input))
}

///|
test "editing a recalled prompt makes it an ordinary draft" {
  let input = Input::history_fixture("")
  let (edited, _) = Model(input)
    .moved(input, -1)
    .update(
      input,
      TextChanged("third, amended"),
      Msg::test_emit(),
      Action::test_emit(),
    )
  let entry = edited.active(input)
  assert_true(entry.history_back is None)
  assert_eq(edited.moved(input, -1).active(input).draft.task, "third, amended")
}

///|
test "an empty history leaves the draft alone" {
  let input = Input::fixture("")
  let model = Model(input).moved(input, -1)
  assert_eq(model.active(input).draft.task, "")
  assert_true(!model.active(input).can_recall_history(input))
}

///|
test "submitting a recalled prompt starts the next recall from the latest" {
  let input = Input::history_fixture("")
  let recalled = Model(input).moved(input, -1).moved(input, -1)
  let (submitted, _) = recalled.update(
    input,
    SubmitRequested,
    Msg::test_emit(),
    Action::test_emit(),
  )
  let accepted = {
    ..input,
    draft: { task: "", mentions: [], images: [], },
    history: [..input.history, "second"],
    submission_sequence: 1,
  }
  let entry = submitted.active(accepted)
  assert_true(entry.history_back is None)
  assert_eq(submitted.moved(accepted, -1).active(accepted).draft.task, "second")
}

///|
test "a recalled draft that changed underneath is no longer a recall" {
  let input = Input::history_fixture("")
  let entry = Model(input).moved(input, -1).active(input)
  // The root recovered a different draft over the recalled one.
  let recovered = {
    ..input,
    draft: { task: "other", mentions: [], images: [], },
  }
  let entry = { ..entry, draft: recovered.draft, }
  assert_true(entry.recalled_back(recovered) is None)
  assert_true(entry.history_label(English, recovered) is None)
  assert_true(!entry.can_recall_history(recovered))
}

///|
test "a goal being edited has no prompt history" {
  let input = {
    ..Input::history_fixture(""),
    goal: { draft: Some("goal"), standing: None, pending: None, },
  }
  assert_true(!Model(input).active(input).can_recall_history(input))
}
