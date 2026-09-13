///|
fn goal_set_notice(text : String) -> @agent_session.SessionItem {
  Goal(GoalSet("\{text}", baseline=Unavailable))
}

///|
test "current_goal is none without markers" {
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
    .append(User(UserMessage("hello")))
    .append(
      Runtime(RuntimeNotice("\{@agent_session.PlanReminderPrefix}\nplan")),
    )
  assert_true(session.current_goal() is None)
}

///|
test "current_goal returns the last set marker" {
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
    .append(goal_set_notice("port the decoder"))
    .append(User(UserMessage("start with the parser")))
  guard session.current_goal() is Some(goal) else { fail("expected a goal") }
  assert_eq(goal.text(), "port the decoder")
  assert_false(goal.answered_since_set())
}

///|
test "current_goal marks goals the model has answered since" {
  let assistant_first = @agent_session.Session(
      SessionId("s1"),
      system_prompt="system",
    )
    .append(goal_set_notice("port the decoder"))
    .append(Assistant(AssistantMessage("on it")))
  guard assistant_first.current_goal() is Some(goal) else {
    fail("expected a goal")
  }
  assert_true(goal.answered_since_set())
  let terminal_only = @agent_session.Session(
      SessionId("s2"),
      system_prompt="system",
    )
    .append(goal_set_notice("port the decoder"))
    .append(Terminal(Finished("done for now")))
  guard terminal_only.current_goal() is Some(goal) else {
    fail("expected a goal")
  }
  assert_true(goal.answered_since_set())
}

///|
test "cleared tombstone hides earlier goals and a later set revives" {
  let cleared = @agent_session.Session(SessionId("s1"), system_prompt="system")
    .append(goal_set_notice("first objective"))
    .append(Goal(GoalCleared))
  assert_true(cleared.current_goal() is None)
  let revived = cleared.append(goal_set_notice("second objective"))
  guard revived.current_goal() is Some(goal) else { fail("expected a goal") }
  assert_eq(goal.text(), "second objective")
}

///|
test "reminder and check notices are not set markers" {
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
    .append(goal_set_notice("real goal"))
    .append(Goal(GoalCleared))
    .append(
      Runtime(
        RuntimeNotice("\{@agent_session.GoalReminderPrefix}\nstale reminder"),
      ),
    )
    .append(
      Runtime(RuntimeNotice("\{@agent_session.GoalCheckPrefix}\nstale check")),
    )
  // The cleared tombstone stays authoritative: reminder/check tags after it
  // must not resurrect the goal.
  assert_true(session.current_goal() is None)
}

///|
test "multiline goal text survives the scan" {
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system").append(
    goal_set_notice("line one\nline two"),
  )
  guard session.current_goal() is Some(goal) else { fail("expected a goal") }
  assert_eq(goal.text(), "line one\nline two")
}

///|
test "a compaction summary covering the set marker does not hide the goal" {
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system")
    .append(goal_set_notice("long objective"))
    .append(User(UserMessage("work on it")))
    .append(Assistant(AssistantMessage("progress")))
    .compact(content="summary of the work", from_sequence=1, to_sequence=3)
  guard session.current_goal() is Some(goal) else { fail("expected a goal") }
  assert_eq(goal.text(), "long objective")
  assert_true(goal.answered_since_set())
}

///|
test "goal baseline belongs to its set through interleaving and compaction" {
  let baseline : @agent_session.GoalBaseline = { sha: "abc123", dirty: true, }
  let session = @agent_session.Session(SessionId("b1"), system_prompt="sys")
    .append(Goal(GoalSet("ship it", baseline=Captured(baseline))))
    .append(User(UserMessage("interleaved")))
    .append(Runtime(RuntimeNotice("[goal baseline] sha=wrong dirty=false")))
    .compact(content="summary", from_sequence=1, to_sequence=3)
  assert_eq(session.current_goal_baseline(), Some(baseline))
  let replacement = session.append(Goal(GoalSet("next", baseline=Unavailable)))
  assert_true(replacement.current_goal().unwrap().baseline() is Unavailable)
  assert_true(replacement.current_goal_baseline() is None)
  assert_true(session.append(Goal(GoalCleared)).current_goal_baseline() is None)
}

///|
test "lookalike text never changes goal state" {
  let session = @agent_session.Session(SessionId("b2"), system_prompt="sys").append(
    Runtime(RuntimeNotice("[goal]\nnot a goal")),
  )
  assert_true(session.current_goal() is None)
  let session = session
    .append(Goal(GoalSet("real", baseline=Unavailable)))
    .append(Runtime(RuntimeNotice("[goal cleared]")))
    .append(Runtime(RuntimeNotice("[goal blocked]\nnot blocked")))
  assert_eq(session.current_goal().unwrap().text(), "real")
  assert_false(session.current_goal().unwrap().blocked())
}
