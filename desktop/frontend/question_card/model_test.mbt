///|
fn questions() -> Array[@question_card.Question] {
  [
    {
      id: "first",
      title: "First?",
      options: [
        { label: "A", description: "", },
        { label: "B", description: "", },
        { label: " ", description: "", },
      ],
    },
    {
      id: "second",
      title: "Second?",
      options: [{ label: "C", description: "", }],
    },
    { id: "last", title: "Last?", options: [{ label: "D", description: "", }], },
  ]
}

///|
fn apply(
  model : @question_card.Model,
  questions : Array[@question_card.Question],
  action : @question_card.Action,
) -> @question_card.Model raise {
  let once = model.update(questions, action)
  let twice = model.update(questions, action)
  assert_eq(once, twice)
  once
}

///|
test "choosing the current option retains the draft and advances exactly one question" {
  let questions = questions()
  let initial = @question_card.Model()
  let first = apply(initial, questions, Select(question="first", option="A"))
  assert_eq(first.answers().get("first"), Some("A"))
  assert_true(initial.answers().is_empty())
  assert_eq(apply(first, questions, Navigate(index=1)), first)
  assert_eq(
    apply(first, questions, Select(question="first", option="A")),
    first,
  )
  let previous = apply(first, questions, Navigate(index=0))
  assert_eq(
    apply(previous, questions, Select(question="first", option="A")),
    first,
  )
  let second = apply(first, questions, Select(question="second", option="C"))
  assert_eq(second.answers().get("first"), Some("A"))
  assert_eq(second.answers().get("second"), Some("C"))
  assert_eq(first.answers().get("second"), None)
  assert_eq(apply(second, questions, Navigate(index=2)), second)
  assert_false(second.is_sending())
}

///|
test "invalid or stale option events do not advance the current question" {
  let questions = questions()
  let initial = @question_card.Model()
  assert_eq(
    apply(initial, questions, Select(question="first", option="invalid")),
    initial,
  )
  assert_eq(
    apply(initial, questions, Select(question="unknown", option="A")),
    initial,
  )
  let blank = apply(initial, questions, Select(question="first", option=" "))
  assert_eq(apply(blank, questions, Navigate(index=0)), blank)
  assert_false(blank.complete(questions))
  let first = apply(initial, questions, Select(question="first", option="A"))
  let stale = apply(first, questions, Select(question="first", option="B"))
  assert_eq(stale.answers().get("first"), Some("B"))
  assert_eq(apply(stale, questions, Navigate(index=1)), stale)
  let future = apply(first, questions, Select(question="last", option="D"))
  assert_eq(future.answers().get("last"), Some("D"))
  assert_eq(apply(future, questions, Navigate(index=1)), future)
  assert_false(stale.is_sending())
  assert_false(future.is_sending())
}

///|
test "last and single question choices wait for explicit submission" {
  let questions = questions()
  let first = apply(
    @question_card.Model(),
    questions,
    Select(question="first", option="A"),
  )
  let second = apply(first, questions, Select(question="second", option="C"))
  let last = apply(second, questions, Select(question="last", option="D"))
  assert_eq(apply(last, questions, Navigate(index=2)), last)
  assert_true(last.complete(questions))
  assert_false(last.is_sending())
  let sending = apply(last, questions, Submit(skip=false))
  assert_true(sending.is_sending())
  assert_eq(
    apply(sending, questions, Select(question="last", option="D")),
    sending,
  )
  assert_eq(apply(sending, questions, Navigate(index=0)), sending)
  let single : Array[@question_card.Question] = [
    { id: "only", title: "Only?", options: [{ label: "A", description: "", }], },
  ]
  let chosen = apply(
    @question_card.Model(),
    single,
    Select(question="only", option="A"),
  )
  assert_eq(chosen.answers().get("only"), Some("A"))
  assert_eq(apply(chosen, single, Navigate(index=0)), chosen)
  assert_false(chosen.is_sending())
  assert_true(apply(chosen, single, Submit(skip=false)).is_sending())
}
