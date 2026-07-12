///|
/// The turn-start reminder is a DECISION POINT, not just an alignment
/// note: each turn — under auto-continue, each context-window cycle —
/// opens with a brief three-way assessment. Catching "already met" or
/// "cannot proceed" here saves a whole window of work; the finish check
/// still gates the exit so a completion cannot slip out unverified.
fn goal_reminder_text(goal : String, tool_registered~ : Bool) -> String {
  let met_action = if tool_registered {
    "record that by calling the goal tool with status \"met\", then finish"
  } else {
    "finish and say so"
  }
  (
    $|\{@agent_session.GoalReminderPrefix}
    $|The standing goal for this session:
    $|\{goal}
    $|Assess it briefly at this turn boundary:
    $|- Fully met? Verify per the goal's own criteria first, then
    $|  \{met_action}.
    $|- Truly cannot proceed — progress needs user action or an external
    $|  change (access, a decision only the user can make, an unrecoverable
    $|  dependency), or the goal is superseded? Record that with status
    $|  "blocked" and a reason, then finish; the user decides what is next.
    $|  Do NOT block for a problem you can work around yourself (a failed
    $|  command, a tool error, a file you can rewrite).
    $|- Otherwise continue working toward it. If the current task conflicts
    $|  with the goal, the current task wins; note the conflict briefly.
  )
}

///|
fn goal_check_text(goal : String, tool_registered~ : Bool) -> String {
  if tool_registered {
    (
      $|\{@agent_session.GoalCheckPrefix}
      $|The standing goal for this session:
      $|\{goal}
      $|You attempted to finish. If the goal is fully met, record that by
      $|calling the goal tool with status "met", then finish. If this task
      $|is complete but the goal is not, call the goal tool with status
      $|"continuing" and what remains, then finish (this also clears a prior
      $|"blocked" status and resumes autonomous continuation). Only if real
      $|progress is impossible without user action or an external change, or
      $|the goal is superseded, call the goal tool with status "blocked" and
      $|a reason, then finish — the user decides what is next; do not block
      $|for a problem you can work around yourself. Otherwise continue
      $|working toward the goal.
    )
  } else {
    (
      $|\{@agent_session.GoalCheckPrefix}
      $|The standing goal for this session:
      $|\{goal}
      $|You attempted to finish. If the goal is fully met, finish again and
      $|say so. If this task is complete but the goal is not, finish with a
      $|one-line status of what remains. Otherwise continue working toward
      $|the goal.
    )
  }
}

///|
/// The block/unblock marker a batch will land at its next batch-safe
/// boundary. At most one such transition is pending per batch, so this is a
/// single field rather than two independent flags: `continuing` after a block
/// in the same batch rewrites it, never leaving a stale half-state.
priv enum PendingBlockTransition {
  NoBlockTransition
  /// A goal(blocked) verdict awaiting its durable `[goal blocked]` marker.
  PendingBlock(String)
  /// A goal(continuing) that resumes a durably blocked goal, awaiting its
  /// durable `[goal unblocked]` marker.
  PendingUnblock
}

///|
/// Standing-goal tracking for one turn, parallel to `PlanCadence`. Seeded
/// from the durable log at loop construction; a mid-turn goal set/clear
/// steer updates it live through `observe_notice`. Turn-local by design — a
/// fresh loop re-derives the goal from the session.
///
/// `remind_now` starts true only when the model has already answered since
/// the goal was set: a fresh set marker still rides the next request, so a
/// turn-start reminder would only duplicate it. `finish_checked` caps the
/// finish-time goal check at one per turn — the model may end the turn
/// immediately after answering the check, so a turn is never held hostage.
priv struct GoalCadence {
  /// Whether the goal status tool is in this turn's registry: selects the
  /// tool-aware finish-check text and enables the structured met/continuing
  /// protocol.
  tool_registered : Bool
  mut goal : String?
  mut remind_now : Bool
  mut finish_checked : Bool
  /// Cache of the DURABLE blocked state (whether a live `[goal blocked]`
  /// stands in the log). Seeded from the standing goal and updated only after
  /// a marker durably lands (flush) or a durable notice is observed — never
  /// optimistically from an unflushed batch verdict, so `continuing` can tell
  /// a prior-batch block (which needs an unblock marker) from a same-batch one
  /// (which just cancels).
  mut durably_blocked : Bool
  /// The block/unblock marker awaiting the next batch-safe boundary.
  mut pending_block : PendingBlockTransition
  /// A goal(met) call was recorded mid-batch; the durable [goal cleared]
  /// tombstone must land only at a batch-safe boundary (next step start or
  /// turn finish) — a mid-batch runtime notice would make replay synthesize
  /// exited-errors for the batch's remaining tool calls.
  mut pending_tombstone : Bool
}

///|
fn GoalCadence::GoalCadence(
  session : @agent_session.Session,
  tool_registered~ : Bool,
) -> GoalCadence {
  let standing = session.current_goal()
  {
    tool_registered,
    goal: standing.map(goal => goal.text()),
    remind_now: standing.map(goal => goal.answered_since_set()).unwrap_or(false),
    finish_checked: false,
    durably_blocked: standing.map(goal => goal.blocked()).unwrap_or(false),
    pending_block: NoBlockTransition,
    pending_tombstone: false,
  }
}

///|
/// The goal text when a finish attempt should be answered with a goal check
/// instead of ending the turn.
fn GoalCadence::due_finish_check(self : GoalCadence) -> String? {
  if self.finish_checked {
    None
  } else {
    self.goal
  }
}

///|
/// A structured goal(met) call: the goal stops standing immediately (the
/// finish check disarms) and the durable tombstone is deferred to the next
/// batch-safe boundary. Any pending block/unblock is abandoned — the goal is
/// going away, so its blocked state is moot.
fn GoalCadence::record_goal_met(self : GoalCadence) -> Unit {
  self.goal = None
  self.pending_block = NoBlockTransition
  self.pending_tombstone = true
}

///|
/// A structured goal(continuing) call answers the finish check (disarming it
/// for the rest of the turn) and, if the goal is durably blocked, resumes
/// auto-continuation by scheduling a `[goal unblocked]` marker. Keying off
/// `durably_blocked` (not the pending field) is what makes a continue after a
/// PRIOR-batch block emit the marker, while a block+continue within one batch
/// simply cancels to nothing durable.
fn GoalCadence::record_goal_continuing(self : GoalCadence) -> Unit {
  self.finish_checked = true
  if self.durably_blocked {
    self.pending_block = PendingUnblock
  } else if self.pending_block is PendingBlock(_) {
    self.pending_block = NoBlockTransition
  }
}

///|
/// A structured goal(blocked) call: pauses auto-continuation. Like a finish
/// check answer it disarms the turn's finish check, and it schedules a durable
/// `[goal blocked]` marker (superseding any same-batch pending unblock).
fn GoalCadence::record_goal_blocked(
  self : GoalCadence,
  reason : String,
) -> Unit {
  self.finish_checked = true
  self.pending_block = PendingBlock(reason)
}

///|
fn GoalCadence::record_finish_check(self : GoalCadence) -> Unit {
  self.finish_checked = true
  // The check restates the goal, so it counts as the turn's reminder:
  // without the reset, a pending turn-start reminder could fire right
  // after the check, burying the confirmation ask it just injected.
  self.remind_now = false
}

///|
/// The goal text when a reminder is due: once per turn, at the start. No
/// mid-turn re-reminders — since turns became context-bounded, nothing
/// ever leaves the model's context within a turn, so the turn-start
/// reminder (or the goal marker itself) stays visible throughout; the
/// finish check is the enforcement point, and under auto-continue each
/// context-window cycle starts a fresh turn that re-surfaces the goal
/// right after the checkpoint.
fn GoalCadence::due_reminder(self : GoalCadence) -> String? {
  if self.remind_now {
    self.goal
  } else {
    None
  }
}

///|
fn GoalCadence::record_reminder(self : GoalCadence) -> Unit {
  self.remind_now = false
}

///|
/// Track a durably applied notice steer. A goal set/clear marker updates the
/// live cadence and reports the new state as a `goal_updated` event. The
/// event is emitted here — after the durable append, never at queue time —
/// so a controller can only learn a goal that was actually persisted.
fn GoalCadence::observe_notice(self : GoalCadence, content : String) -> Unit {
  match @agent_session.goal_marker(content) {
    Some(GoalSet(text)) => {
      self.goal = Some(text)
      self.remind_now = false
      // A NEW goal deserves its own finish check: without this reset, a
      // goal set after an earlier check in the same turn would let the
      // next finish attempt end the turn unconfirmed.
      self.finish_checked = false
      // A deferred tombstone belonged to the goal this set supersedes;
      // flushing it after the new marker would wipe the new goal (last
      // marker wins in the scan).
      self.pending_tombstone = false
      // Same for a deferred block/unblock verdict: it belonged to the goal
      // this set supersedes; a new goal starts unblocked.
      self.pending_block = NoBlockTransition
      self.durably_blocked = false
      @xlog.info() <? { "event": "goal_updated", "goal": text }
    }
    Some(GoalCleared) => {
      self.goal = None
      // A durable clear just landed; a second tombstone would be noise.
      self.pending_tombstone = false
      self.pending_block = NoBlockTransition
      self.durably_blocked = false
      @xlog.info() <? { "event": "goal_updated", "goal": (None : String?) }
    }
    // A block/unblock marker landing durably (this loop's own flush, or a
    // steer observed after its append) toggles the cached durable state; the
    // goal still stands, so the rest of the cadence is untouched.
    Some(GoalBlocked(_)) => self.durably_blocked = true
    Some(GoalUnblocked) => self.durably_blocked = false
    None => ()
  }
}

///|
/// Flush the goal markers a batch deferred, at a batch-safe boundary: the
/// `[goal blocked]` / `[goal unblocked]` transition, then the `[goal cleared]`
/// tombstone. Each is appended through the loop's persistence seam and its
/// pending flag cleared only AFTER the append succeeds — a failed append must
/// leave the flag set so the error-path retry re-lands the marker, otherwise
/// a durable goal-tool result would coexist with a stale standing state on
/// resume. The two markers cannot both be pending (met abandons a pending
/// block, and a set/clear supersedes it), so their order does not conflict.
async fn AgentLoop::flush_goal_tombstone(
  self : Self,
  session : @agent_session.Session,
) -> @agent_session.Session {
  let session = match self.goal_cadence.pending_block {
    PendingBlock(reason) => {
      let next = self.append_runtime_notice(
        session,
        "\{@agent_session.GoalBlockedPrefix}\n\{reason}",
      )
      self.goal_cadence.pending_block = NoBlockTransition
      self.goal_cadence.durably_blocked = true
      @xlog.info() <? { "event": "goal_blocked", "reason": reason }
      next
    }
    // A continue that resumes a durably blocked goal: land the unblock marker
    // so serve's next auto-continue check reads the goal as no longer blocked.
    PendingUnblock if self.goal_cadence.durably_blocked => {
      let next = self.append_runtime_notice(
        session,
        @agent_session.GoalUnblockedNotice,
      )
      self.goal_cadence.pending_block = NoBlockTransition
      self.goal_cadence.durably_blocked = false
      @xlog.info() <? { "event": "goal_unblocked" }
      next
    }
    // A no-op unblock (the goal was not durably blocked): nothing to rescind.
    PendingUnblock => {
      self.goal_cadence.pending_block = NoBlockTransition
      session
    }
    NoBlockTransition => session
  }
  if !self.goal_cadence.pending_tombstone {
    return session
  }
  let next = self.append_runtime_notice(
    session,
    @agent_session.GoalClearedNotice,
  )
  self.goal_cadence.pending_tombstone = false
  @xlog.info() <? { "event": "goal_updated", "goal": (None : String?) }
  next
}

///|
/// Handle a `goal` status tool call in place of executing the registry
/// entry: only the loop knows whether a goal currently stands, and the
/// durable clear must be sequenced at a batch-safe boundary. `met` clears
/// the standing goal (tombstone deferred via `record_goal_met`);
/// `continuing` records the structured remainder and stands in for the
/// finish check. Either with no standing goal is an error result — a
/// semantic assertion against missing state should read as model confusion
/// in the transcript, not success.
async fn AgentLoop::handle_goal_tool_call(
  self : Self,
  session : @agent_session.Session,
  native_call : @deepseek.ToolCall,
  tool_call : @agent_tool.AgentToolCall,
) -> ToolCallOutcome {
  let verdict = (
    @goal.decode_status(tool_call.arguments),
    self.goal_cadence.goal,
  )
  // A continue that resumes a durably blocked goal reports the resume, so the
  // transcript shows auto-continuation coming back rather than silently.
  let resumes_block = self.goal_cadence.durably_blocked
  let (content, is_error) = match verdict {
    (Err(message), _) => ("error: \{message}", true)
    (Ok(_), None) => ("error: no standing goal is set", true)
    (Ok(Met), Some(_)) =>
      ("goal recorded as met; the standing goal is now cleared", false)
    (Ok(Continuing(remaining)), Some(_)) =>
      if resumes_block {
        (
          "goal status recorded as continuing: \{remaining}. The goal is no longer blocked; auto-continuation resumes",
          false,
        )
      } else {
        ("goal status recorded as continuing: \{remaining}", false)
      }
    (Ok(Blocked(reason)), Some(_)) =>
      (
        "goal recorded as blocked: \{reason}. The goal still stands; auto-continuation is paused for the user",
        false,
      )
  }
  let session = self.record_tool_result(
    session,
    tool_call_id=native_call.id,
    tool_name=tool_call.name,
    content~,
    is_error~,
  )
  // Cadence updates only after the result append succeeded: a rejected
  // append must not leave a pending tombstone (the error-path flush would
  // then durably clear a goal whose met verdict was never persisted).
  match verdict {
    (Ok(Met), Some(_)) => self.goal_cadence.record_goal_met()
    // Continuing answers the finish check and, if the goal is durably
    // blocked, schedules a `[goal unblocked]` marker so serve resumes.
    (Ok(Continuing(_)), Some(_)) => self.goal_cadence.record_goal_continuing()
    // Blocked answers the check and schedules a durable `[goal blocked]`
    // marker so serve pauses auto-continuation while the goal stands.
    (Ok(Blocked(reason)), Some(_)) =>
      self.goal_cadence.record_goal_blocked(reason)
    _ => ()
  }
  @xlog.info() <?
    {
      "event": "tool_result",
      "tool_call_id": native_call.id,
      "tool_name": tool_call.name,
      "is_error": is_error,
      "content": content,
    }
  ContinueToolBatch(session)
}

///|
test "a new goal observed after met drops the stale tombstone" {
  let session = @agent_session.Session(SessionId("s1"), system_prompt="system").append(
    Runtime(RuntimeNotice("\{@agent_session.GoalPrefix}\nold objective")),
  )
  let cadence = GoalCadence(session, tool_registered=true)
  cadence.record_goal_met()
  assert_true(cadence.pending_tombstone)
  // A steered-in set supersedes the met verdict: flushing the old
  // tombstone after the new marker would wipe the new goal.
  cadence.observe_notice("\{@agent_session.GoalPrefix}\nnew objective")
  assert_false(cadence.pending_tombstone)
  assert_true(cadence.goal is Some("new objective"))
  // A durable clear also settles a pending tombstone.
  cadence.record_goal_met() |> ignore
  cadence.observe_notice(@agent_session.GoalClearedNotice)
  assert_false(cadence.pending_tombstone)
  assert_true(cadence.goal is None)
}

///|
/// A session whose standing goal is durably blocked: `[goal]` then a
/// `[goal blocked]` marker, so `current_goal().blocked()` is true and a fresh
/// cadence seeds `durably_blocked = true`.
fn blocked_goal_session() -> @agent_session.Session {
  @agent_session.Session(SessionId("blocked"), system_prompt="sys")
  .append(Runtime(RuntimeNotice("\{@agent_session.GoalPrefix}\nship it")))
  .append(User(UserMessage("work")))
  .append(Runtime(RuntimeNotice("\{@agent_session.GoalBlockedPrefix}\nstuck")))
}

///|
/// A session with a plain standing goal (never blocked).
fn open_goal_session() -> @agent_session.Session {
  @agent_session.Session(SessionId("open"), system_prompt="sys").append(
    Runtime(RuntimeNotice("\{@agent_session.GoalPrefix}\nship it")),
  )
}

///|
/// goal(blocked) disarms the turn's finish check (like continuing) and
/// schedules a `[goal blocked]` marker.
test "blocked answers the finish check and schedules a block marker" {
  let cadence = GoalCadence(open_goal_session(), tool_registered=true)
  assert_true(cadence.due_finish_check() is Some(_))
  cadence.record_goal_blocked("stuck")
  assert_true(cadence.due_finish_check() is None)
  assert_true(cadence.pending_block is PendingBlock("stuck"))
}

///|
/// continue after a PRIOR-batch (durable) block schedules the unblock marker
/// that resumes auto-continuation — the case the naive design missed.
test "continue after a durable block schedules an unblock marker" {
  let cadence = GoalCadence(blocked_goal_session(), tool_registered=true)
  assert_true(cadence.durably_blocked)
  cadence.record_goal_continuing()
  assert_true(cadence.pending_block is PendingUnblock)
}

///|
/// Batch orderings, both starting durable states. `continue` keys off the
/// durable state, so a same-batch block+continue cancels when the goal was
/// open but resolves to an unblock when it was already blocked.
test "block/continue batch orderings resolve to the right pending marker" {
  // open + block -> continue  ==> nothing durable (block cancelled)
  let a = GoalCadence(open_goal_session(), tool_registered=true)
  a.record_goal_blocked("x")
  a.record_goal_continuing()
  assert_true(a.pending_block is NoBlockTransition)

  // blocked + block -> continue  ==> unblock (the durable block is rescinded)
  let b = GoalCadence(blocked_goal_session(), tool_registered=true)
  b.record_goal_blocked("x")
  b.record_goal_continuing()
  assert_true(b.pending_block is PendingUnblock)

  // blocked + block -> continue -> block  ==> block wins (stays blocked)
  let c = GoalCadence(blocked_goal_session(), tool_registered=true)
  c.record_goal_blocked("x")
  c.record_goal_continuing()
  c.record_goal_blocked("y")
  assert_true(c.pending_block is PendingBlock("y"))

  // blocked + continue -> block -> continue  ==> unblock
  let d = GoalCadence(blocked_goal_session(), tool_registered=true)
  d.record_goal_continuing()
  d.record_goal_blocked("x")
  d.record_goal_continuing()
  assert_true(d.pending_block is PendingUnblock)

  // open + continue -> block -> continue  ==> nothing durable
  let e = GoalCadence(open_goal_session(), tool_registered=true)
  e.record_goal_continuing()
  e.record_goal_blocked("x")
  e.record_goal_continuing()
  assert_true(e.pending_block is NoBlockTransition)
}

///|
/// met abandons a pending block/unblock (the goal is going away) and a new
/// goal or clear resets the durable-blocked cache.
test "met and a superseding set/clear reset the block state" {
  let cadence = GoalCadence(blocked_goal_session(), tool_registered=true)
  cadence.record_goal_continuing()
  assert_true(cadence.pending_block is PendingUnblock)
  cadence.record_goal_met()
  assert_true(cadence.pending_block is NoBlockTransition)
  assert_true(cadence.pending_tombstone)
  // A superseding set clears the durable-blocked cache for the new goal.
  let other = GoalCadence(blocked_goal_session(), tool_registered=true)
  assert_true(other.durably_blocked)
  other.observe_notice("\{@agent_session.GoalPrefix}\nnew objective")
  assert_false(other.durably_blocked)
  assert_true(other.pending_block is NoBlockTransition)
}

///|
test "a goal set after an earlier check re-arms the finish check" {
  let session = @agent_session.Session(
    SessionId("goal-recheck"),
    system_prompt="sys",
  )
  let cadence = GoalCadence(session, tool_registered=false)
  cadence.observe_notice("\{@agent_session.GoalPrefix}\nfirst objective")
  cadence.record_finish_check()
  assert_true(cadence.due_finish_check() is None)
  // A NEW goal deserves its own check — the earlier one confirmed a
  // different objective.
  cadence.observe_notice("\{@agent_session.GoalPrefix}\nsecond objective")
  assert_true(cadence.due_finish_check() is Some("second objective"))
}
