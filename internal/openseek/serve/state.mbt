///|
/// One decoded command from the serve-mode controller (e.g. the TUI) on
/// stdin.
priv enum ServeCommand {
  Prompt(@agent_session.Content, submission_id~ : String?)
  Steer(@agent_runtime.SteerInput)
  Compact
  Cancel
  JobsSnapshot(request_id~ : String)
  JobStop(request_id~ : String, generation~ : String, job_id~ : String)
  Goal(GoalAction)
  /// The answer to an `approval_requested` event: which question, and whether
  /// it is granted. Both labelled, because a bare positional pair reads as
  /// nothing at a call site and the second field is the decision itself.
  ///
  /// Unlike every other command here it does not schedule work. It releases a
  /// tool that is already running and blocked, which is why it is dispatched
  /// from the loop but never queues behind active work.
  Approval(id~ : String, allow~ : Bool)
}

///|
/// A goal command's payload: set/replace the standing goal or clear it.
/// `auto` opts the engine into continuing toward the goal on its own after
/// each finished turn (headless controllers; the TUI composes /loop instead).
/// Arming never self-starts work: continuation fires only off a finishing
/// turn, so the controller still sends the first prompt.
priv enum GoalAction {
  SetGoal(String, auto~ : Bool)
  ClearGoal
}

///|
/// Turns the engine will start on its own toward one standing goal before
/// pausing for input — the same order as /loop's default fire budget. Reset
/// whenever a goal is set with auto continuation.
const GoalAutoContinueMaxTurns : Int = 20

///|
/// The prompt that opens an auto-continuation turn. Defined with the goal
/// vocabulary in `agent_session` because the visualizer has to recognize the
/// resulting `User` event as engine-injected rather than something the user
/// said, and a second copy of the text here would let the two drift.
const GoalContinuePrompt : String = @agent_session.GoalContinuePrompt

///|
/// Whether a pending auto intent may be promoted to armed: the persisted
/// standing goal must carry the intent's exact text AND a set marker newer
/// than the sequence baseline recorded when the command arrived. Text alone
/// cannot distinguish "this exact set persisted" from "an identical-text
/// goal was already standing when the new set's append failed" (codex
/// review), so promotion keys on marker identity.
fn goal_auto_promotable(
  current : @agent_session.StandingGoal?,
  text : String,
  baseline : Int,
) -> Bool {
  current is Some(goal) && goal.text() == text && goal.set_sequence() > baseline
}

///|
/// Whether auto-continue is armed for the persisted standing goal. `target`
/// is only ever set by promotion (goal_auto_promotable), so this is the
/// cheap per-decision recheck that the armed goal still stands unchanged.
fn goal_auto_armed(
  current : @agent_session.StandingGoal?,
  target : String?,
) -> Bool {
  current is Some(goal) && target is Some(text) && goal.text() == text
}

///|
/// Whether the engine should start another turn toward the standing goal.
/// Pure so the policy is unit-testable: only a cleanly finished turn on a
/// fully idle, still-serving engine with a standing goal and budget left
/// continues — failures, aborts, interruptions, queued work, and shutdown
/// all pause for the controller.
fn should_auto_continue(
  auto~ : Bool,
  finished~ : Bool,
  idle~ : Bool,
  shutting_down~ : Bool,
  goal_standing~ : Bool,
  turns_remaining~ : Int,
) -> Bool {
  auto &&
  finished &&
  idle &&
  !shutting_down &&
  goal_standing &&
  turns_remaining > 0
}

///|
/// A queued serve-mode operation that must wait for active work to finish.
priv enum PendingWork {
  PendingPrompt(@agent_session.Content, submission_id~ : String?)
  PendingCompact
  // A goal marker holding its wire-order position behind a compaction: a
  // pending compaction must not cover a goal that arrived after the compact
  // command.
  // The marker plus the command context that PRECEDED it at arrival: the
  // drain replays true wire order — context arriving later stays in the
  // runtime queue and lands after the goal.
  // marker, arrival-context snapshot, whether THIS command carried auto
  // (promotion fires only on the auto entry's own durable append), the
  // command serial, and the baseline notice captured at command receipt —
  // appended immediately before the marker at drain, preserving the
  // adjacency contract Session::current_goal_baseline pairs by.
  PendingGoal(String, Array[@agent_runtime.SteerInput], Bool, Int, String?)
  // Context that arrived AFTER a queued goal: fenced into the ordered
  // queue so it cannot overtake the goal via the runtime steer queue (an
  // earlier pending prompt would otherwise drain it first).
  PendingContext(@agent_runtime.SteerInput)
}

///|
/// The one operation currently occupying the serve loop. Compaction is a
/// non-steerable active operation, but it is still cancellable like a turn.
priv enum ActiveWork {
  ActiveTurn(@async.Task[Unit])
  ActiveCompact(@async.Task[Unit])
}

///|
/// One unit of work for the serve loop's single consumer: a wire command in
/// arrival order, the completion of active work, or the stdin-EOF shutdown
/// marker. Funneling all three through one queue is what makes
/// command handling race-free against turn lifecycle.
priv enum ServeStep {
  Wire(ServeCommand)
  TurnDone(finished~ : Bool)
  CompactDone(@agent_session.Session)
  // A background job finished; wake the loop to drain and surface its notice
  // even when no turn is active.
  BackgroundNotice
  Shutdown
}

///|
/// Decode one JSONL command line from the controller.
/// `jobs_snapshot` and `job_stop` are correlated controls handled outside turns.
///
/// `prompt` starts a turn, `steer` supplies typed step-boundary input, `compact`
/// summarizes the current conversation once no work is active, and `cancel`
/// interrupts the active or next queued prompt. A `steer` with missing `kind` is
/// prompt steering for compatibility; `kind="command"` is user-shell context
/// that may be appended while idle without starting a model turn. Anything else
/// is an `Err` whose text is emitted as a `command_error` event — a controller
/// bug must be visible on the wire, not silently swallowed, but it must not kill
/// the session either.
/// Map one controller line onto the loop's own command type.
///
/// `@protocol.Command` owns the wire — the same type the TUI and the desktop
/// now encode with, so the engine's reader and its controllers cannot spell a
/// command differently. They did: the desktop sent `steer` without a `kind` and
/// worked only because this decoder happened to default it.
///
/// The mapping stays here because `SteerInput` is the runtime's, and the
/// protocol is a leaf module that must not depend on the engine — the same
/// reason every client keeps its own view model.
///
/// So is the blank-goal refusal. `{"action":"set","text":"  "}` is a
/// well-formed command that this engine will not stand: the shape is the
/// protocol's to read, whether it is acceptable is this loop's to say. Keeping
/// the check in `parse` would have made `GoalSet(text="  ")` a value the
/// protocol's own type holds and `to_json` writes but `parse` rejects.
fn decode_serve_command(json : Json) -> Result[ServeCommand, String] {
  let command = match @protocol.Command::parse(json) {
    Ok(command) => command
    Err(message) => return Err(message)
  }
  match command {
    Prompt(content~, submission_id~) => Ok(Prompt(content, submission_id~))
    Steer(kind~, content~, submission_id~) => {
      if kind is Command && !content.is_text_only() {
        return Err("command steering does not accept images")
      }
      Ok(
        Steer(
          match kind {
            Prompt => Prompt(content, submission_id~)
            Command => Command(content.text(), submission_id~)
          },
        ),
      )
    }
    JobsSnapshot(request_id~) => Ok(JobsSnapshot(request_id~))
    JobStop(request_id~, generation~, job_id~) =>
      Ok(JobStop(request_id~, generation~, job_id~))
    Compact => Ok(Compact)
    Cancel => Ok(Cancel)
    GoalSet(text~, auto~) =>
      if text.is_blank() {
        Err("goal text must not be blank")
      } else {
        Ok(Goal(SetGoal(text, auto~)))
      }
    GoalClear => Ok(Goal(ClearGoal))
    ApprovalDecision(id~, allow~) => Ok(Approval(id~, allow~))
  }
}

///|
fn remove_next_pending_prompt(pending : Array[PendingWork]) -> Unit {
  if pending.search_by(work => work is PendingPrompt(_, ..)) is Some(index) {
    ignore(pending.remove(index))
  }
}

///|
fn has_pending_prompt(pending : Array[PendingWork]) -> Bool {
  pending.any(work => work is PendingPrompt(_, ..))
}

///|
fn has_pending_goal(pending : Array[PendingWork]) -> Bool {
  pending.any(work => work is PendingGoal(_, _, _, _, _))
}
