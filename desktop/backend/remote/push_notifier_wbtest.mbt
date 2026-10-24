///|
fn started(run_id : String, session : String) -> @protocol.Notification {
  AgentStarted({
    run_id,
    submission_id: None,
    engine: None,
    model: None,
    max_steps: None,
    session,
    session_root: None,
  })
}

///|
fn finished(
  run_id : String,
  status : String,
  answer? : String,
) -> @protocol.Notification {
  AgentFinished({ run_id, status, answer, exit_code: None, })
}

///|
fn approval(
  session : String,
  id : String,
  answered~ : Bool = false,
) -> @protocol.PendingApprovalPayload {
  {
    answered,
    id,
    session,
    run_id: Some("r-\{session}"),
    tool_name: "mbtx",
    detail: "run a snippet",
    body: None,
  }
}

///|
fn approvals(
  generation : Int32,
  items : Array[@protocol.PendingApprovalPayload],
) -> @protocol.Notification {
  AgentApprovals({ generation, approvals: items, })
}

///|
fn empty_seed() -> @protocol.RunsReply {
  { approval_generation: 0, runs: [], settled: [], approvals: [], }
}

///|
test "a settled run pushes once with its session, and cancelling stays quiet" {
  let notifier = PushNotifier(empty_seed())
  assert_true(notifier.observe(started("r1", "s1")) is [])
  assert_true(
    notifier.observe(finished("r1", "finished", answer="  Done.  "))
    is [Finished(session="s1", status="finished", answer=Some("Done."))],
  )
  // The hub can repeat a settlement; the run is already gone.
  assert_true(notifier.observe(finished("r1", "finished")) is [])
  notifier.observe(started("r2", "s1")) |> ignore
  assert_true(notifier.observe(finished("r2", "cancelled")) is [])
  notifier.observe(started("r3", "s1")) |> ignore
  assert_true(
    notifier.observe(finished("r3", "failed", answer="   "))
    is [Finished(status="failed", answer=None, ..)],
  )
}

///|
test "runs without a known session push nothing" {
  let notifier = PushNotifier(empty_seed())
  // Started before this subscription and absent from its seed.
  assert_true(notifier.observe(finished("r-old", "finished")) is [])
  // Not a durable conversation.
  notifier.observe(started("r-bare", "")) |> ignore
  assert_true(notifier.observe(finished("r-bare", "finished")) is [])
}

///|
test "the seed carries runs in flight and standing approvals" {
  guard started("r1", "s1") is AgentStarted(run) else { fail("not a start") }
  let notifier = PushNotifier({
    ..empty_seed(),
    runs: [run],
    approvals: [approval("s1", "ap-1")],
  })
  assert_true(
    notifier.observe(finished("r1", "max_steps_exhausted"))
    is [Finished(session="s1", status="max_steps_exhausted", answer=None)],
  )
  // Standing at connect time: raised before this connection.
  assert_true(notifier.observe(approvals(1, [approval("s1", "ap-1")])) is [])
}

///|
test "only approvals new to the snapshot and still unanswered push" {
  let notifier = PushNotifier(empty_seed())
  assert_true(
    notifier.observe(approvals(1, [approval("s1", "ap-1")]))
    is [Approval(session="s1", tool="mbtx", detail="run a snippet")],
  )
  // Republished with a second question: only that one is new.
  assert_true(
    notifier.observe(
      approvals(2, [approval("s1", "ap-1"), approval("s2", "ap-1")]),
    )
    is [Approval(session="s2", ..)],
  )
  // An accepted answer is not a question to announce.
  assert_true(
    notifier.observe(approvals(3, [approval("s3", "ap-9", answered=true)]))
    is [],
  )
  // Resolved and asked again later under the same id: new again.
  notifier.observe(approvals(4, [])) |> ignore
  assert_true(
    notifier.observe(approvals(5, [approval("s1", "ap-1")]))
    is [Approval(session="s1", ..)],
  )
}

///|
test "push text is trimmed and cut to the banner length on a character" {
  assert_eq(push_text("  ok \n"), "ok")
  assert_eq(push_text("月".repeat(200)), "月".repeat(180) + "…")
  assert_eq(push_text("😀".repeat(181)), "😀".repeat(180) + "…")
  assert_eq(push_text("a".repeat(180)), "a".repeat(180))
}
