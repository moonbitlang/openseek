///|
fn ended_subagent() -> @openseek_protocol.SubagentInfo {
  {
    kind: "explore",
    label: "scout: callers",
    session: "parent-sr-3",
    launch: Script(program="p-1", call=4),
    outcome: Some(Captured),
    usage: Some(
      Known(
        steps=Some(12),
        prompt_tokens=180000,
        completion_tokens=2340,
        cost_usd=Some(0.25),
        source=Result,
        unaccounted=None,
      ),
    ),
    report: Some(Stored),
    workspace: InPlace,
  }
}

///|
test "a subagent job record roundtrips, live and ended" {
  let live : @openseek_protocol.SubagentInfo = {
    ..ended_subagent(),
    launch: Direct,
    outcome: None,
    usage: None,
    report: None,
  }
  for info in [live, ended_subagent()] {
    let job = { ..sample_job(), subagent: Some(info), }
    let decoded : @openseek_protocol.JobRecord = @json.from_json(job.to_json())
    assert_eq(decoded, job)
  }
  // A live child carries no outcome, usage or report on the wire.
  assert_true(
    live.to_json()
    is { "outcome"? : None, "usage"? : None, "report"? : None, .. },
  )
  // An ordinary job carries no subagent part.
  assert_true(sample_job().to_json() is { "subagent"? : None, .. })
}

///|
test "every subagent outcome, usage and report roundtrips" {
  let outcomes : Array[@openseek_protocol.SubagentOutcome] = [
    Captured,
    NoReport,
    MaxSteps,
    ContextYield,
    TimedOut,
    Stopped,
    Failed("request not delivered"),
  ]
  let usages : Array[@openseek_protocol.SubagentUsage] = [
    Known(
      steps=None,
      prompt_tokens=2,
      completion_tokens=3,
      cost_usd=None,
      source=Transcript,
      unaccounted=Some("the child died mid-response"),
    ),
    Unavailable("no result and no transcript"),
  ]
  let reports : Array[@openseek_protocol.SubagentReport] = [
    Stored,
    StoreFailed("disk full"),
  ]
  for outcome in outcomes {
    for usage in usages {
      for report in reports {
        let info = {
          ..ended_subagent(),
          outcome: Some(outcome),
          usage: Some(usage),
          report: Some(report),
        }
        let decoded : @openseek_protocol.SubagentInfo = @json.from_json(
          info.to_json(),
        )
        assert_eq(decoded, info)
      }
    }
  }
}

///|
test "a subagent session may be any id the store accepts" {
  let info = { ..ended_subagent(), session: "my task ✓-sr-2", }
  let decoded : @openseek_protocol.SubagentInfo = @json.from_json(
    info.to_json(),
  )
  assert_eq(decoded, info)
}

///|
test "the subagent decoder rejects malformed parts" {
  for
    (key, value) in [
      ("session", Json("../other")),
      ("session", Json("..")),
      ("kind", Json("")),
      ("launch", { "kind": "script", "program": "", "call": 1 }),
      ("launch", { "kind": "script", "program": "p", "call": -1 }),
      ("outcome", { "kind": "failed", "reason": "" }),
      ("outcome", { "kind": "finished" }),
      ("usage", { "kind": "known", "source": "result", "steps": 1.5 }),
      ("usage", { "kind": "unavailable", "reason": "" }),
      ("report", { "kind": "stored_elsewhere" }),
      ("workspace", { "kind": "worktree" }),
    ] {
    guard ended_subagent().to_json() is Object(fields) else {
      fail("expected object")
    }
    fields[key] = value
    try @json.from_json(Json(fields)) catch {
      _ => ()
    } noraise {
      (_ : @openseek_protocol.SubagentInfo) =>
        fail("accepted invalid \{key}: \{value.stringify()}")
    }
  }
}

///|
test "a worker's worktree roundtrips in every state, on its record and in its event" {
  let states : Array[@openseek_protocol.WorktreeState] = [
    Working,
    Committed(commit="c0ffee"),
    NoChanges,
    Unmergeable(defects=["changed other/b.txt outside lib"]),
    Conflicted(commit="c0ffee"),
    Integrated,
    Discarded,
  ]
  for state in states {
    let worktree : @openseek_protocol.Worktree = {
      name: "fix-lib",
      path: "/repo/.worktrees/fix-lib",
      branch: "openseek/fix-lib--sr-3",
      base: "ba5e",
      allowed_paths: ["lib"],
      state,
    }
    let info = { ..ended_subagent(), workspace: Worktree(worktree), }
    let decoded : @openseek_protocol.SubagentInfo = @json.from_json(
      info.to_json(),
    )
    assert_eq(decoded, info)
    let event : @openseek_protocol.Event = WorkerChanged(
      session="parent-sr-3",
      worktree~,
    )
    assert_eq(@openseek_protocol.parse(event.to_json()), Some(event))
  }
  // A committed state names its commit.
  let decoded : @openseek_protocol.WorktreeState? = Some(
    @json.from_json({ "kind": "committed" }),
  ) catch {
    _ => None
  }
  assert_eq(decoded, None)
}
