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
  assert_eq(apply(pending, Submit(request="r", skip=false)), pending)
  let edited = apply(pending, Edit(request="r", question="q", text="My answer"))
  assert_false(edited == pending)
  assert_eq(apply(edited, Snapshot(snapshot())), edited)
  assert_eq(
    apply(edited, Edit(request="r", question="unknown", text="bad")),
    edited,
  )
  let sending = apply(edited, Submit(request="r", skip=false))
  assert_false(sending == edited)
  assert_eq(
    apply(sending, Edit(request="r", question="q", text="late")),
    sending,
  )
  assert_eq(apply(sending, Submit(request="r", skip=false)), sending)
  let failed = apply(sending, Failed(request="r", error="Offline"))
  assert_false(failed == sending)
  let retry = apply(failed, Submit(request="r", skip=false))
  assert_eq(retry, sending)
  let resolved = apply(sending, Snapshot({ generation: 2, requests: [], }))
  assert_eq(apply(resolved, Snapshot(snapshot())), resolved)
  assert_eq(apply(resolved, Failed(request="r", error="late error")), resolved)
  assert_false(apply(pending, Submit(request="r", skip=true)) == pending)
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
  assert_eq(apply(initial, Navigate(request="r", index=-1)), initial)
  assert_eq(apply(initial, Navigate(request="r", index=2)), initial)
  let second = apply(initial, Navigate(request="r", index=1))
  assert_false(second == initial)
  assert_eq(apply(second, Navigate(request="r", index=0)), initial)
  assert_eq(apply(second.reconnecting(), Snapshot(multi)), second)
  assert_eq(
    apply(initial, Select(request="r", question="q", option="invalid")),
    initial,
  )
  let chosen = apply(initial, Select(request="r", question="q", option="A"))
  let written = apply(initial, Edit(request="r", question="q", text="A"))
  assert_false(chosen == written)
  assert_eq(apply(chosen, Edit(request="r", question="q", text="A")), written)
  assert_eq(
    apply(written, Select(request="r", question="q", option="A")),
    chosen,
  )
  assert_eq(apply(chosen, Submit(request="r", skip=false)), chosen)
  let complete = apply(chosen, Edit(request="r", question="q2", text="Details"))
  let sending = apply(complete, Submit(request="r", skip=false))
  assert_false(sending == complete)
  assert_eq(apply(sending, Navigate(request="r", index=1)), sending)
  assert_eq(
    apply(sending, Select(request="r", question="q", option="B")),
    sending,
  )
}
