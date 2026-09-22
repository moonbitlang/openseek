///|
/// Test helper: `should_auto_continue` with every input defaulted to its
/// continuing value, so a case reads as the one condition it flips.
fn auto_continues(
  auto? : Bool = true,
  finished? : Bool = true,
  idle? : Bool = true,
  shutting_down? : Bool = false,
  goal_standing? : Bool = true,
  turns_remaining? : Int = 1,
) -> Bool {
  should_auto_continue(
    auto~,
    finished~,
    idle~,
    shutting_down~,
    goal_standing~,
    turns_remaining~,
  )
}

///|
test "serve commands decode and reject with actionable errors" {
  assert_true(
    decode_serve_command({ "command": "jobs_snapshot", "request_id": "list-1" })
    is Ok(JobsSnapshot(request_id="list-1")),
  )
  assert_true(
    decode_serve_command({
      "command": "job_stop",
      "request_id": "stop-1",
      "generation": "runtime-1",
      "job_id": "bg-1",
    })
    is Ok(JobStop(request_id="stop-1", generation="runtime-1", job_id="bg-1")),
  )
  assert_true(
    decode_serve_command({ "command": "prompt", "text": "hi" })
    is Ok(Prompt("hi", submission_id=None)),
  )
  assert_true(
    decode_serve_command({
      "command": "prompt",
      "text": "hi",
      "submission_id": "page-1-submission-2",
    })
    is Ok(Prompt("hi", submission_id=Some("page-1-submission-2"))),
  )
  assert_true(
    decode_serve_command({ "command": "steer", "text": "left" })
    is Ok(Steer(Prompt("left", submission_id=None))),
  )
  assert_true(
    decode_serve_command({
      "command": "steer",
      "kind": "prompt",
      "text": "right",
      "submission_id": "steer-right",
    })
    is Ok(Steer(Prompt("right", submission_id=Some("steer-right")))),
  )
  assert_true(
    decode_serve_command({
      "command": "steer",
      "kind": "command",
      "text": "<user_shell_command>",
    })
    is Ok(Steer(Command("<user_shell_command>", submission_id=None))),
  )
  assert_true(decode_serve_command({ "command": "compact" }) is Ok(Compact))
  assert_true(decode_serve_command({ "command": "cancel" }) is Ok(Cancel))
  assert_true(
    decode_serve_command({ "command": "approval", "id": "ap-1", "allow": true })
    is Ok(Approval(id="ap-1", allow=true)),
  )
  assert_true(
    decode_serve_command({ "command": "approval", "id": "ap-1", "allow": false })
    is Ok(Approval(id="ap-1", allow=false)),
  )
  guard decode_serve_command({ "command": "steer" }) is Err(message) else {
    fail("textless steer accepted")
  }
  assert_true(message.contains("text"))
  guard decode_serve_command({
      "command": "steer",
      "kind": "runtime",
      "text": "x",
    })
    is Err(message) else {
    fail("unknown steer kind accepted")
  }
  assert_true(message.contains("unknown steer kind: runtime"))
  guard decode_serve_command({ "command": "inject", "text": "x" })
    is Err(message) else {
    fail("inject command accepted")
  }
  assert_true(message.contains("unknown command: inject"))
  guard decode_serve_command({ "command": "reboot" }) is Err(message) else {
    fail("unknown command accepted")
  }
  assert_true(message.contains("unknown command: reboot"))
  guard decode_serve_command("nonsense") is Err(message) else {
    fail("non-object accepted")
  }
  assert_true(message.contains("command"))
  assert_true(
    decode_serve_command({
      "command": "goal",
      "action": "set",
      "text": "port the decoder",
    })
    is Ok(Goal(SetGoal("port the decoder", auto=false))),
  )
  assert_true(
    decode_serve_command({
      "command": "goal",
      "action": "set",
      "text": "grind it out",
      "auto": true,
    })
    is Ok(Goal(SetGoal("grind it out", auto=true))),
  )
  assert_true(
    decode_serve_command({
      "command": "goal",
      "action": "set",
      "text": "grind it out",
      "auto": "yes",
    })
    is Ok(Goal(SetGoal("grind it out", auto=false))),
  )
  assert_true(
    decode_serve_command({ "command": "goal", "action": "clear" })
    is Ok(Goal(ClearGoal)),
  )
  guard decode_serve_command({
      "command": "goal",
      "action": "set",
      "text": "  ",
    })
    is Err(message) else {
    fail("blank goal accepted")
  }
  assert_true(message.contains("blank"))
  guard decode_serve_command({ "command": "goal", "action": "set" })
    is Err(message) else {
    fail("textless goal set accepted")
  }
  assert_true(message.contains("action"))
  guard decode_serve_command({ "command": "goal", "action": "toggle" })
    is Err(message) else {
    fail("unknown goal action accepted")
  }
  assert_true(message.contains("action"))
}

///|
test "pending prompt helpers ignore queued compactions and goals" {
  let pending : Array[PendingWork] = []
  assert_false(has_pending_prompt(pending))
  pending.push(PendingCompact)
  pending.push(PendingGoal("[goal]\nship it", [], false, 1, None))
  assert_false(has_pending_prompt(pending))
  pending.push(PendingPrompt("next", submission_id=None))
  assert_true(has_pending_prompt(pending))
  // Cancel targets the next prompt, never a queued goal update.
  remove_next_pending_prompt(pending)
  assert_false(has_pending_prompt(pending))
  assert_eq(pending.length(), 2)
  assert_true(pending[0] is PendingCompact)
  assert_true(pending[1] is PendingGoal(_, _, _, _, _))
}

///|
test "auto arms only for the exact persisted goal" {
  let session = @agent_session.Session(SessionId("s1"), system_prompt="p").append(
    Runtime(RuntimeNotice("\{@agent_session.GoalPrefix}\nship the feature")),
  )
  let standing = session.current_goal()
  assert_true(goal_auto_armed(standing, Some("ship the feature")))
  // A set whose append failed (or was superseded) never arms.
  assert_false(goal_auto_armed(standing, Some("a different goal")))
  assert_false(goal_auto_armed(standing, None))
  assert_false(goal_auto_armed(None, Some("ship the feature")))
}

///|
test "promotion requires a marker newer than the command baseline" {
  // The goal marker is event 1.
  let session = @agent_session.Session(SessionId("s1"), system_prompt="p").append(
    Runtime(RuntimeNotice("\{@agent_session.GoalPrefix}\nship the feature")),
  )
  let standing = session.current_goal()
  // A set command that arrived when last_sequence was 0 promotes: the
  // marker (sequence 1) is newer than its baseline.
  assert_true(goal_auto_promotable(standing, "ship the feature", 0))
  // The same-text regression: a re-set arriving AFTER that marker existed
  // (baseline 1) whose own append failed must NOT promote off the old
  // marker, even though the text matches.
  assert_false(goal_auto_promotable(standing, "ship the feature", 1))
  assert_false(goal_auto_promotable(standing, "different text", 0))
  assert_false(goal_auto_promotable(None, "ship the feature", 0))
}

///|
test "a context-yield turn chains: finished derivation and standing goal" {
  // The whole PR-B contract in one place: a turn that ended at the context
  // ceiling is durably Terminal(Finished(...)), so serve derives
  // finished=true from the last event exactly as for a real completion —
  // and the goal marker, covered by the checkpoint summary or not, still
  // stands in the raw log. Auto-continue therefore chains one turn per
  // context window with no yield-specific code.
  let session = @agent_session.Session(
      SessionId("yield-chains"),
      system_prompt="system",
    )
    .append(
      Runtime(RuntimeNotice("\{@agent_session.GoalPrefix}\nbig objective")),
    )
    .append(Terminal(Finished("turn one answer")))
    .append(User(UserMessage("continue")))
    .append(
      Summary(
        SessionSummary(content="checkpoint", from_sequence=1, to_sequence=3),
      ),
    )
    .append(
      Terminal(
        Finished(
          "\{@agent_session.ContextYieldAnswerPrefix} continue in a new turn",
        ),
      ),
    )
  let finished = session.events().peek() is Some(event) &&
    event.item() is Terminal(Finished(_))
  assert_true(finished)
  guard session.current_goal() is Some(goal) else {
    fail("the goal must survive the checkpoint")
  }
  assert_eq(goal.text(), "big objective")
  assert_true(
    should_auto_continue(
      auto=true,
      finished~,
      idle=true,
      shutting_down=false,
      goal_standing=true,
      turns_remaining=1,
    ),
  )
}

///|
test "an unblocked goal resumes auto-continuation at the boundary" {
  // serve gates auto-continue on `goal_standing = standing is Some && !blocked`
  // read fresh from current_goal() each TurnDone. A goal blocked then unblocked
  // reads as standing-and-not-blocked, so continuation resumes with no serve
  // change — the whole point of the [goal unblocked] marker.
  let base = @agent_session.Session(SessionId("resume"), system_prompt="system")
    .append(Runtime(RuntimeNotice("\{@agent_session.GoalPrefix}\nobjective")))
    .append(User(UserMessage("work")))
    .append(
      Runtime(RuntimeNotice("\{@agent_session.GoalBlockedPrefix}\nstuck")),
    )
    .append(Terminal(Finished("turn answer")))
  let goal_standing = fn(session : @agent_session.Session) -> Bool {
    session.current_goal() is Some(goal) && !goal.blocked()
  }
  // While blocked, the boundary does NOT auto-continue.
  assert_false(goal_standing(base))
  assert_false(
    should_auto_continue(
      auto=true,
      finished=true,
      idle=true,
      shutting_down=false,
      goal_standing=goal_standing(base),
      turns_remaining=1,
    ),
  )
  // After the unblock marker lands, the same boundary resumes.
  let resumed = base.append(
    Runtime(RuntimeNotice(@agent_session.GoalUnblockedNotice)),
  )
  assert_true(goal_standing(resumed))
  assert_true(
    should_auto_continue(
      auto=true,
      finished=true,
      idle=true,
      shutting_down=false,
      goal_standing=goal_standing(resumed),
      turns_remaining=1,
    ),
  )
}

///|
test "auto-continue requires a finished idle serving turn with budget" {
  assert_true(auto_continues())
  // Any single condition failing pauses for the controller.
  assert_false(auto_continues(auto=false))
  assert_false(auto_continues(finished=false))
  assert_false(auto_continues(idle=false))
  assert_false(auto_continues(shutting_down=true))
  assert_false(auto_continues(goal_standing=false))
  assert_false(auto_continues(turns_remaining=0))
}
