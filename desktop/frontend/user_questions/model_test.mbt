///|
fn snapshot(generation~ : Int32 = 1) -> @protocol.UserQuestionSnapshot {
  {
    generation,
    requests: [
      {
        id: "r",
        session: "s",
        questions: [{ id: "q", title: "Question?", options: Some(["A", "B"]), }],
      },
    ],
  }
}

///|
fn apply(
  model : @user_questions.Model,
  msg : @user_questions.Msg,
) -> @user_questions.Model raise {
  let emit : @cmd.Emit[@user_questions.Msg] = Emit(_ => @cmd.none)
  let (_, once) = model.update(msg, Local, emit)
  let (_, twice) = model.update(msg, Local, emit)
  assert_eq(once, twice)
  once
}

///|
test "all question updates are pure and stale snapshots cannot revive answered requests" {
  let empty = @user_questions.Model()
  let pending = apply(empty, Snapshot(snapshot()))
  assert_false(empty == pending)
  assert_eq(apply(pending, Interact(request="r", Submit(skip=false))), pending)
  let edited = apply(
    pending,
    Interact(request="r", Edit(question="q", text="My answer")),
  )
  assert_false(edited == pending)
  assert_eq(apply(edited, Snapshot(snapshot())), edited)
  assert_eq(
    apply(edited, Interact(request="r", Edit(question="unknown", text="bad"))),
    edited,
  )
  let sending = apply(edited, Interact(request="r", Submit(skip=false)))
  assert_false(sending == edited)
  assert_eq(
    apply(sending, Interact(request="r", Edit(question="q", text="late"))),
    sending,
  )
  assert_eq(apply(sending, Interact(request="r", Submit(skip=false))), sending)
  let failed = apply(sending, Failed(request="r", error="Offline"))
  assert_false(failed == sending)
  let retry = apply(failed, Interact(request="r", Submit(skip=false)))
  assert_eq(retry, sending)
  let resolved = apply(sending, Snapshot({ generation: 2, requests: [], }))
  assert_eq(apply(resolved, Snapshot(snapshot())), resolved)
  assert_eq(apply(resolved, Failed(request="r", error="late error")), resolved)
  assert_false(
    apply(pending, Interact(request="r", Submit(skip=true))) == pending,
  )
  // A restarted host can reset its revision. Text drafts survive a reconnect
  // to the same host/request; a new host's empty snapshot clears the card.
  assert_eq(apply(edited.reconnecting(), Snapshot(snapshot())), edited)
  assert_eq(
    apply(sending.reconnecting(), Snapshot({ generation: 0, requests: [], })),
    apply(empty, Snapshot({ generation: 0, requests: [], })),
  )
}

///|
test "question pages retain distinct choice and written drafts without mutating prior state" {
  let request = snapshot()
  let multi = {
    ..request,
    requests: [
      {
        ..request.requests[0],
        questions: [
          { id: "q", title: "First?", options: Some(["A", "B"]), },
          { id: "q2", title: "Second?", options: None, },
        ],
      },
    ],
  }
  let initial = apply(@user_questions.Model(), Snapshot(multi))
  assert_eq(apply(initial, Interact(request="r", Navigate(index=-1))), initial)
  assert_eq(apply(initial, Interact(request="r", Navigate(index=2))), initial)
  let second = apply(initial, Interact(request="r", Navigate(index=1)))
  assert_false(second == initial)
  assert_eq(apply(second, Interact(request="r", Navigate(index=0))), initial)
  assert_eq(apply(second.reconnecting(), Snapshot(multi)), second)
  assert_eq(
    apply(
      initial,
      Interact(request="r", Select(question="q", option="invalid")),
    ),
    initial,
  )
  let chosen = apply(
    initial,
    Interact(request="r", Select(question="q", option="A")),
  )
  let written = apply(
    initial,
    Interact(request="r", Edit(question="q", text="A")),
  )
  assert_eq(apply(chosen, Interact(request="r", Navigate(index=1))), chosen)
  let chosen_back = apply(chosen, Interact(request="r", Navigate(index=0)))
  assert_false(chosen_back == written)
  assert_eq(
    apply(chosen_back, Interact(request="r", Edit(question="q", text="A"))),
    written,
  )
  assert_eq(
    apply(written, Interact(request="r", Select(question="q", option="A"))),
    chosen,
  )
  assert_eq(apply(chosen, Interact(request="r", Submit(skip=false))), chosen)
  let complete = apply(
    chosen,
    Interact(request="r", Edit(question="q2", text="Details")),
  )
  let sending = apply(complete, Interact(request="r", Submit(skip=false)))
  assert_false(sending == complete)
  assert_eq(apply(sending, Interact(request="r", Navigate(index=1))), sending)
  assert_eq(
    apply(sending, Interact(request="r", Select(question="q", option="B"))),
    sending,
  )
}
