///|
/// One decoded command from the serve-mode controller (e.g. the TUI) on
/// stdin.
priv enum ServeCommand {
  Prompt(String)
  Steer(@agent_runtime.SteerInput)
  Compact
  Cancel
  Goal(GoalAction)
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
const GoalContinuePrompt : String =
  #|Continue working toward the standing goal. When it is fully met, record
  #|that by calling the goal tool with status "met".

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
  PendingPrompt(String)
  PendingCompact
  // A goal marker holding its wire-order position behind a compaction: a
  // pending compaction must not cover a goal that arrived after the compact
  // command.
  // The marker plus the command context that PRECEDED it at arrival: the
  // drain replays true wire order — context arriving later stays in the
  // runtime queue and lands after the goal.
  // marker, arrival-context snapshot, and whether THIS command carried
  // auto: promotion fires only on the auto entry's own durable append.
  PendingGoal(String, Array[@agent_runtime.SteerInput], Bool, Int)
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
///
/// `prompt` starts a turn, `steer` supplies typed step-boundary input, `compact`
/// summarizes the current conversation once no work is active, and `cancel`
/// interrupts the active or next queued prompt. A `steer` with missing `kind` is
/// prompt steering for compatibility; `kind="command"` is user-shell context
/// that may be appended while idle without starting a model turn. Anything else
/// is an `Err` whose text is emitted as a `command_error` event — a controller
/// bug must be visible on the wire, not silently swallowed, but it must not kill
/// the session either.
fn decode_serve_command(json : Json) -> Result[ServeCommand, String] {
  match json {
    { "command": "prompt", "text": String(text), .. } => Ok(Prompt(text))
    { "command": "steer", .. } =>
      decode_steer_input(json).map(input => Steer(input))
    { "command": "prompt", .. } => Err("expected a string \"text\" field")
    { "command": "compact", .. } => Ok(Compact)
    { "command": "cancel", .. } => Ok(Cancel)
    { "command": "goal", "action": "set", "text": String(text), .. } =>
      if text.trim().is_empty() {
        Err("goal text must not be blank")
      } else {
        Ok(Goal(SetGoal(text, auto=json is { "auto": True, .. })))
      }
    { "command": "goal", "action": "clear", .. } => Ok(Goal(ClearGoal))
    { "command": "goal", .. } =>
      Err(
        "expected {\"action\": \"set\", \"text\": ...} or {\"action\": \"clear\"}",
      )
    { "command": String(other), .. } => Err("unknown command: \{other}")
    _ => Err("expected a {\"command\": ...} object")
  }
}

///|
fn decode_steer_input(json : Json) -> Result[@agent_runtime.SteerInput, String] {
  match json {
    { "kind": String(kind), "text": String(text), .. } =>
      match kind {
        "prompt" => Ok(Prompt(text))
        "command" => Ok(Command(text))
        other => Err("unknown steer kind: \{other}")
      }
    { "kind": _, "text": String(_), .. } =>
      Err("expected a string \"kind\" field")
    { "text": String(text), .. } => Ok(Prompt(text))
    _ => Err("expected a string \"text\" field")
  }
}

///|
test "serve commands decode and reject with actionable errors" {
  assert_true(
    decode_serve_command({ "command": "prompt", "text": "hi" })
    is Ok(Prompt("hi")),
  )
  assert_true(
    decode_serve_command({ "command": "steer", "text": "left" })
    is Ok(Steer(Prompt("left"))),
  )
  assert_true(
    decode_serve_command({
      "command": "steer",
      "kind": "prompt",
      "text": "right",
    })
    is Ok(Steer(Prompt("right"))),
  )
  assert_true(
    decode_serve_command({
      "command": "steer",
      "kind": "command",
      "text": "<user_shell_command>",
    })
    is Ok(Steer(Command("<user_shell_command>"))),
  )
  assert_true(decode_serve_command({ "command": "compact" }) is Ok(Compact))
  assert_true(decode_serve_command({ "command": "cancel" }) is Ok(Cancel))
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
fn remove_next_pending_prompt(pending : Array[PendingWork]) -> Unit {
  if pending.search_by(work => work is PendingPrompt(_)) is Some(index) {
    ignore(pending.remove(index))
  }
}

///|
fn has_pending_prompt(pending : Array[PendingWork]) -> Bool {
  pending.any(work => work is PendingPrompt(_))
}

///|
fn has_pending_goal(pending : Array[PendingWork]) -> Bool {
  pending.any(work => work is PendingGoal(_, _, _, _))
}

///|
test "pending prompt helpers ignore queued compactions and goals" {
  let pending : Array[PendingWork] = []
  assert_false(has_pending_prompt(pending))
  pending.push(PendingCompact)
  pending.push(PendingGoal("[goal]\nship it", [], false, 1))
  assert_false(has_pending_prompt(pending))
  pending.push(PendingPrompt("next"))
  assert_true(has_pending_prompt(pending))
  // Cancel targets the next prompt, never a queued goal update.
  remove_next_pending_prompt(pending)
  assert_false(has_pending_prompt(pending))
  assert_eq(pending.length(), 2)
  assert_true(pending[0] is PendingCompact)
  assert_true(pending[1] is PendingGoal(_, _, _, _))
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
  assert_true(
    should_auto_continue(
      auto=true,
      finished=true,
      idle=true,
      shutting_down=false,
      goal_standing=true,
      turns_remaining=1,
    ),
  )
  // Any single condition failing pauses for the controller.
  assert_false(
    should_auto_continue(
      auto=false,
      finished=true,
      idle=true,
      shutting_down=false,
      goal_standing=true,
      turns_remaining=1,
    ),
  )
  assert_false(
    should_auto_continue(
      auto=true,
      finished=false,
      idle=true,
      shutting_down=false,
      goal_standing=true,
      turns_remaining=1,
    ),
  )
  assert_false(
    should_auto_continue(
      auto=true,
      finished=true,
      idle=false,
      shutting_down=false,
      goal_standing=true,
      turns_remaining=1,
    ),
  )
  assert_false(
    should_auto_continue(
      auto=true,
      finished=true,
      idle=true,
      shutting_down=true,
      goal_standing=true,
      turns_remaining=1,
    ),
  )
  assert_false(
    should_auto_continue(
      auto=true,
      finished=true,
      idle=true,
      shutting_down=false,
      goal_standing=false,
      turns_remaining=1,
    ),
  )
  assert_false(
    should_auto_continue(
      auto=true,
      finished=true,
      idle=true,
      shutting_down=false,
      goal_standing=true,
      turns_remaining=0,
    ),
  )
}

///|
/// Run the engine as a long-lived session server: read JSONL commands from
/// stdin, run turns sequentially against one shared session, and write the
/// usual JSONL event stream to stdout. This is the engine half of the
/// persistent-engine design — one process per conversation instead of one
/// per prompt.
///
/// The runtime and the tool registry are built once and shared by every turn,
/// so any registry-local tool state can survive turn boundaries. `steer` rides
/// the runtime's lossless steering queue into the running (or already
/// submitted) turn; with no turn to land in it is rejected with a
/// `steer_dropped` event — that only happens by racing the terminal event
/// through the pipes, and an engine must never start a turn the controller
/// did not ask for. `cancel` interrupts the current active work but never the
/// process. stdin EOF is the shutdown signal: the running work finishes
/// first, then the loop drains and exits.
async fn run_serve(
  matches : @argparse.Matches,
  workspace_root~ : String,
) -> Unit {
  let (model, thinking, api_url) = agent_settings(matches)
  let api_key = @agentcli.api_key(matches, model)
  let max_steps = max_steps(matches)
  let session_id = match matches {
    {
      values: {
        "session"? : Some([session, ..])
        | (Some([])
        | None) with session = "",
        ..
      },
      ..,
    } =>
      match session.trim() {
        "" => None
        session => Some(@agent_session.SessionId("\{session}"))
      }
  }
  let (store, initial_session) = match session_id {
    Some(id) => {
      let store = @store.SessionStore(session_root(matches, workspace_root~))
      (
        Some(store),
        load_or_new_session(store, id, matches, model, workspace_root~),
      )
    }
    // No durable session requested: the conversation still spans every
    // prompt of this process's lifetime, it just leaves nothing behind.
    None =>
      (
        None,
        Session(
          SessionId("serve"),
          system_prompt=configured_system_prompt(
            matches,
            model,
            workspace_root~,
          ),
        ),
      )
  }
  // The live conversation value. `append_item` updates it on every appended
  // event, so even a turn that raises leaves `session` reflecting all the
  // events it recorded before failing.
  let mut session = initial_session
  @async.with_task_group(group => {
    let runtime = @agent_runtime.AgentRuntime(workspace_root~)
    let scope = @agent_runtime.AgentTaskScope(group)
    // All scheduling flows through one ordered queue with one consumer:
    // wire commands from the reader, plus the internal turn-completion and
    // shutdown markers. A second scheduler (e.g. acting on commands inside
    // the reader) would race the consumer's view of the active turn — a
    // controller writing `prompt\nsteer\n` in one buffer must have its
    // steer land in that prompt's turn, exactly as the wire order says.
    let steps : @async.Queue[ServeStep] = Queue(kind=Unbounded)
    // Built once so registry-local tool state can survive turn boundaries (see
    // @agent.build_tools). A background job finishing wakes this loop with a
    // `BackgroundNotice` step, so even a fully idle engine surfaces the
    // completion instead of leaving it queued until the next prompt.
    // Tools from any configured MCP servers, connected once per engine (their
    // reader/writer tasks live on this group) and reused across turns.
    let extra_tools = resolve_mcp_tools(matches, scope, workspace_root~)
    let tools = @agent.build_tools(
      runtime,
      scope,
      on_background_wake=() => {
        ignore(steps.try_put(BackgroundNotice) catch { _ => false })
      },
      extra_tools~,
    )
    group.spawn_bg(no_wait=true) <| () => {
      @jsonl.each(@stdio.stdin, json => {
        match decode_serve_command(json) {
          Ok(command) => steps.try_put(Wire(command)) |> ignore
          Err(message) =>
            @xlog.error() <? { "event": "command_error", "error": message }
        }
      }) catch {
        error if @async.is_being_cancelled() ||
          @async.is_cancellation_error(error) => raise error
        // A malformed (non-JSON) line is a controller bug: report it and
        // stop reading commands, which shuts the server down gracefully.
        error =>
          @xlog.error() <?
            { "event": "command_error", "error": "command stream: \{error}" }
      }
      steps.try_put(Shutdown) |> ignore
    }
    let pending : Array[PendingWork] = []
    let mut active_work : ActiveWork? = None
    let mut shutting_down = false
    // Auto-continue bookkeeping. A set with "auto": true records a PENDING
    // intent (text + the last_sequence baseline at command receipt); the
    // intent is promoted to the armed target — and the budget granted — only
    // once a matching set marker NEWER than the baseline is durably standing
    // (goal_auto_promotable), so neither a failed append nor an
    // identical-text goal that was already standing can arm the loop.
    let mut goal_auto_pending : (String, Int)? = None
    let mut goal_auto_target : String? = None
    let mut goal_turns_remaining = 0
    let mut goal_promoted_this_boundary = false
    // Monotonic serial over goal-affecting commands (set/clear/cancel): a
    // queued auto entry arms only if NO later command superseded it.
    let mut goal_command_serial = 0
    // Arm the autonomous loop for a durably standing goal. Local closures
    // cannot take labelled args: the Bool is defer_continue — true only
    // when the marker landed AFTER the turn ended (the PendingGoal drain
    // and the idle drain): that turn never saw the goal, so its first turn
    // belongs to the controller. A goal steered INTO the finishing turn
    // was already worked under — continue it.
    fn arm_goal_auto(text : String, defer_continue : Bool) -> Unit {
      goal_auto_target = Some(text)
      goal_turns_remaining = GoalAutoContinueMaxTurns
      goal_auto_pending = None
      if defer_continue {
        goal_promoted_this_boundary = true
      }
    }

    fn maybe_promote_goal_auto(defer_continue : Bool) -> Unit {
      if goal_auto_pending is Some((text, baseline)) &&
        goal_auto_promotable(session.current_goal(), text, baseline) {
        arm_goal_auto(text, defer_continue)
      }
    }
    async fn compact_and_report(
      current : @agent_session.Session,
    ) -> @agent_session.Session {
      @compact.compact_session(store?, current, api_key~, model~, api_url?) catch {
        error if @async.is_being_cancelled() ||
          @async.is_cancellation_error(error) => raise error
        error => {
          @xlog.error() <? { "event": "compaction_failed", "error": "\{error}" }
          current
        }
      }
    }

    // Append one idle-time item to the session, durably when a store is wired.
    // Returns false (after logging a session_error naming `what`) when the
    // durable append fails, so the caller skips its success log; cancellation
    // still propagates.
    async fn append_idle_item(
      item : @agent_session.SessionItem,
      what : String,
    ) -> Bool {
      session = if store is Some(store) {
        store.append(session, item) catch {
          error if @async.is_being_cancelled() ||
            @async.is_cancellation_error(error) => raise error
          error => {
            @xlog.error() <?
              {
                "event": "session_error",
                "error": "failed to append \{what}: \{error}",
              }
            return false
          }
        }
      } else {
        session.append(item)
      }
      true
    }

    async fn append_command_context(text : String, kind : String) -> Unit {
      if append_idle_item(User(UserMessage(text)), "command context") {
        @xlog.info() <?
          { "event": "steer_applied", "kind": kind, "content": text }
      }
    }

    // Report a durably appended goal marker to the controller. Called only
    // after the append succeeded — never at queue time, when the marker could
    // still be lost with a dying turn — so the TUI can only learn a goal that
    // was actually persisted.
    fn report_goal_update(content : String) -> Unit {
      match @agent_session.goal_marker(content) {
        Some(GoalSet(text)) =>
          @xlog.info() <? { "event": "goal_updated", "goal": text }
        Some(GoalCleared) =>
          @xlog.info() <? { "event": "goal_updated", "goal": (None : String?) }
        // Block/unblock markers change auto-continuation policy but not the
        // goal itself; they are reported by the loop's own goal_blocked /
        // goal_unblocked events, not as goal_updated.
        Some(GoalBlocked(_)) | Some(GoalUnblocked) | None => ()
      }
    }

    // Persist a goal marker at the session's current boundary and report it.
    // The report happens only after the durable append succeeded — never at
    // queue time — so a controller can only learn a goal that was actually
    // persisted; callers gate their promotion tails on the returned Bool for
    // the same reason.
    async fn append_goal_marker(marker : String) -> Bool {
      if append_idle_item(Runtime(RuntimeNotice(marker)), "goal update") {
        report_goal_update(marker)
        true
      } else {
        false
      }
    }

    // Surface a background-job completion notice while the engine is idle
    // (between turns). Persist it as a `Runtime` item — on resume it renders as a
    // notice, not user input — and log it untagged: the TUI drops run-tagged
    // events once a turn closes, so a between-turns notice must ride an untagged
    // event.
    async fn append_background_notice(text : String) -> Unit {
      if append_idle_item(Runtime(RuntimeNotice(text)), "background notice") {
        @xlog.info() <? { "event": "background_notice", "content": text }
      }
    }

    // Steers still queued when work ends: prompt steering must not leak into a
    // later turn, but command context is durable local output, so persist it at
    // the session's current boundary. Called whenever the loop returns to idle
    // (turn or compaction done), so a `!` delivered mid-work is never left
    // orphaned in the steer queue to be lost or applied to an unrelated prompt.
    async fn apply_idle_context_input(
      input : @agent_runtime.SteerInput,
    ) -> Unit {
      match input {
        Prompt(text) =>
          @xlog.warn() <? { "event": "steer_dropped", "content": text }
        Command(text) => append_command_context(text, "command")
        Notice(text) =>
          match @agent_session.goal_marker(text) {
            // A goal marker deferred behind a live turn lands here when the
            // turn ends before its next step boundary. Its notice leg is
            // transport: persist and report it as a goal update, so no
            // controller ever sees it dressed as a background notice.
            Some(_) =>
              if append_goal_marker(text) {
                // Drained at idle: the finished turn never saw this marker,
                // so its first turn belongs to the controller.
                maybe_promote_goal_auto(true)
              }
            None => append_background_notice(text)
          }
      }
    }

    async fn drain_command_context() -> Unit {
      for input in runtime.drain_steers() {
        apply_idle_context_input(input)
      }
    }

    // Snapshot the command context PRECEDING a goal at its ARRIVAL:
    // everything from the first Prompt onward belongs to a pending prompt
    // turn and is re-queued in order, never dropped. The snapshot rides the
    // PendingGoal entry so the eventual drain replays true wire order.
    fn take_context_before_goal() -> Array[@agent_runtime.SteerInput] {
      let inputs = runtime.drain_steers()
      let boundary = inputs
        .search_by(input => input is Prompt(_))
        .unwrap_or(inputs.length())
      for input in inputs[boundary:] {
        runtime.queue_steer(input)
      }
      [..inputs[:boundary]]
    }

    fn start_turn(task_text : String) -> @async.Task[Unit] {
      group.spawn() <| () => {
        let _ = @agent.run_turn_in_scope(
          runtime~,
          scope~,
          api_key~,
          model~,
          session~,
          task=task_text,
          append_item=(current, item) => {
            let next = match store {
              Some(store) => store.append(current, item)
              None => current.append(item)
            }
            session = next
            next
          },
          max_steps?,
          thinking~,
          api_url?,
          tools~,
        ) catch {
          error => {
            // The turn died but the session server must not: a cancelled
            // turn already appended its Interrupted terminal inside the
            // loop, and any other failure is reported as a terminal wire
            // event so the controller can close the run.
            if @async.is_being_cancelled() ||
              @async.is_cancellation_error(error) {
              @xlog.warn() <?
                { "event": "agent_aborted", "reason": "interrupted" }
            } else {
              @xlog.error() <? { "event": "turn_failed", "error": "\{error}" }
            }
            ignore(steps.try_put(TurnDone(finished=false)) catch { _ => false })
            return
          }
        }
        // The auto-continue policy keys off a cleanly finished turn; the live
        // `session` var already holds every append this turn made.
        let finished = session.events().peek() is Some(event) &&
          event.item() is Terminal(Finished(_))
        ignore(steps.try_put(TurnDone(finished~)) catch { _ => false })
      }
    }

    fn start_compaction(current : @agent_session.Session) -> @async.Task[Unit] {
      group.spawn() <| () => {
        let next = compact_and_report(current) catch {
          error if @async.is_being_cancelled() ||
            @async.is_cancellation_error(error) => {
            @xlog.warn() <?
              { "event": "compaction_failed", "error": "cancelled" }
            current
          }
          error => {
            @xlog.error() <?
              { "event": "compaction_failed", "error": "\{error}" }
            current
          }
        }
        ignore(steps.try_put(CompactDone(next)) catch { _ => false })
      }
    }

    async fn start_next_pending() -> Unit {
      // Starting work makes the condition false on the recheck; instant-work
      // arms (context, goal markers) keep draining in arrival order.
      while active_work is None && pending.length() > 0 {
        match pending.remove(0) {
          PendingPrompt(text) =>
            active_work = Some(ActiveTurn(start_turn(text)))
          PendingCompact =>
            active_work = Some(ActiveCompact(start_compaction(session)))
          // Instant work: append the goal at its ordered position and keep
          // draining the queue. A command context produced BEFORE the goal
          // was queued lands first — the goal may depend on that output,
          // and durable order must match arrival order.
          // Fenced context: apply at its ordered position and keep draining.
          PendingContext(input) => apply_idle_context_input(input)
          PendingGoal(marker, context, is_auto, serial) => {
            for input in context {
              apply_idle_context_input(input)
            }
            // Promotion tied to THIS entry's durable append: with two
            // same-text goals queued, an earlier append must not arm an
            // auto command whose own marker is not durable yet.
            if append_goal_marker(marker) &&
              is_auto &&
              serial == goal_command_serial &&
              @agent_session.goal_marker(marker) is Some(GoalSet(text)) {
              arm_goal_auto(text, true)
            }
          }
        }
      }
    }

    serve~: for ;; {
      let step = steps.get() catch {
        error if @async.is_being_cancelled() ||
          @async.is_cancellation_error(error) => raise error
        _ => break serve~
      }
      match step {
        Wire(Prompt(text)) =>
          match active_work {
            // One turn at a time: extra prompts wait their wire-order turn.
            Some(_) => pending.push(PendingPrompt(text))
            None => active_work = Some(ActiveTurn(start_turn(text)))
          }
        Wire(Steer(input)) =>
          match input {
            Prompt(text) =>
              match active_work {
                // A turn is running, or a prompt is queued ahead of this steer:
                // the lossless steering queue delivers it at that turn's next
                // step boundary (or its first, if it has not started yet).
                Some(ActiveTurn(_)) => runtime.queue_steer(Prompt(text))
                Some(ActiveCompact(_)) | None =>
                  if has_pending_prompt(pending) {
                    runtime.queue_steer(Prompt(text))
                  } else {
                    // An idle (or merely compacting) engine never converts
                    // prompt steering into a prompt: the only way it arrives
                    // here is racing a turn's terminal event through the pipes.
                    // Reject it so the controller can ask for a resubmit.
                    @xlog.warn() <?
                      { "event": "steer_dropped", "content": text }
                  }
              }
            Command(text) =>
              // Defer to the steering queue whenever any work is active (a turn
              // or a compaction) or a prompt is queued, so the context is
              // appended at the next turn's drain — never written straight into
              // a session a running compaction is about to replace. Only a fully
              // idle engine appends it immediately.
              if has_pending_goal(pending) {
                // Fenced behind the queued goal: wire order must stay
                // goal-then-context for context sent after the goal.
                pending.push(PendingContext(Command(text)))
              } else if active_work is Some(_) || has_pending_prompt(pending) {
                runtime.queue_steer(Command(text))
              } else {
                append_command_context(text, "command")
              }
            // A notice is engine-internal and never actually arrives over the
            // wire; queue it losslessly for completeness.
            Notice(text) =>
              if has_pending_goal(pending) {
                pending.push(PendingContext(Notice(text)))
              } else {
                runtime.queue_steer(Notice(text))
              }
          }
        Wire(Cancel) => {
          // A user interrupt stops the autonomous loop, not just one turn —
          // including any auto intent still queued behind pending work.
          goal_command_serial += 1
          goal_auto_pending = None
          goal_auto_target = None
          goal_turns_remaining = 0
          match active_work {
            Some(ActiveTurn(task)) => task.cancel()
            Some(ActiveCompact(task)) => task.cancel()
            None =>
              // No active work: in wire order the cancel targets the next
              // submitted prompt, so withdraw it before it starts.
              remove_next_pending_prompt(pending)
          }
        }
        Wire(Compact) =>
          if active_work is Some(_) {
            pending.push(PendingCompact)
          } else {
            active_work = Some(ActiveCompact(start_compaction(session)))
          }
        Wire(Goal(action)) => {
          // Any new goal command supersedes the previous auto state; a set
          // with auto only records a PENDING intent against the current
          // sequence baseline — arming happens at promotion, after the
          // marker durably lands.
          // For a QUEUED goal the promotion is tied to its own append (see
          // the PendingGoal drain); the baseline mechanism covers the
          // steer/idle paths where the append happens elsewhere.
          goal_auto_pending = match action {
            SetGoal(text, auto=true) => Some((text, session.last_sequence()))
            SetGoal(_, ..) | ClearGoal => None
          }
          goal_auto_target = None
          goal_turns_remaining = 0
          let marker = match action {
            SetGoal(text, ..) => "\{@agent_session.GoalPrefix}\n\{text}"
            ClearGoal => @agent_session.GoalClearedNotice
          }
          if pending.length() > 0 || active_work is Some(ActiveCompact(_)) {
            // ANY queued work ahead in wire order — a pipelined prompt as
            // much as a compaction — must precede this goal, or a pending
            // prompt would start under a goal sent after it. A running
            // compaction's session snapshot must also not be invalidated by
            // a mid-flight append: hold the ordered queue position.
            let is_auto = action is SetGoal(_, auto=true)
            goal_command_serial += 1
            // The entry OWNS the auto intent: promotion happens only on
            // its own successful append (drain arm), never via the
            // baseline path — an earlier same-text marker must not arm it.
            goal_auto_pending = None
            // Snapshot the preceding context ONLY when nothing else owns
            // the runtime queue: with a live turn or a prompt queued ahead,
            // those steers belong to the earlier consumer — stealing them
            // into this entry would drag earlier wire items behind it.
            let context = if active_work is Some(ActiveTurn(_)) ||
              has_pending_prompt(pending) {
              []
            } else {
              take_context_before_goal()
            }
            pending.push(
              PendingGoal(marker, context, is_auto, goal_command_serial),
            )
          } else if active_work is Some(ActiveTurn(_)) {
            // A live turn: the lossless steer queue makes the marker
            // model-visible at the next step boundary (reporting after the
            // durable append); if the turn ends first, the TurnDone drain
            // persists it before any queued prompt starts, so the next turn
            // still sees it.
            runtime.queue_steer(Notice(marker))
          } else if append_goal_marker(marker) {
            maybe_promote_goal_auto(false)
          }
        }
        // A background job finished. If a turn is active, its next step boundary
        // drains and applies the queued notice live; only drain here when idle,
        // so an idle engine still surfaces the completion.
        BackgroundNotice => if active_work is None { drain_command_context() }
        TurnDone(finished~) => {
          goal_promoted_this_boundary = false
          drain_command_context()
          active_work = None
          start_next_pending()
          // Promotion here covers the steer path: a goal set applied inside
          // a live turn is only observable to serve through the session.
          maybe_promote_goal_auto(false)
          let standing = session.current_goal()
          let armed = goal_auto_armed(standing, goal_auto_target) &&
            !goal_promoted_this_boundary
          if should_auto_continue(
              auto=armed,
              finished~,
              idle=active_work is None && pending.length() == 0,
              shutting_down~,
              // A durably blocked goal stands for the user but must not
              // relaunch declared-impossible work.
              goal_standing=standing is Some(goal) && !goal.blocked(),
              turns_remaining=goal_turns_remaining,
            ) {
            goal_turns_remaining -= 1
            @xlog.info() <?
              { "event": "goal_continue", "remaining": goal_turns_remaining }
            active_work = Some(ActiveTurn(start_turn(GoalContinuePrompt)))
          } else if armed &&
            finished &&
            !shutting_down &&
            active_work is None &&
            pending.length() == 0 &&
            goal_turns_remaining == 0 {
            // The loop ran its full budget without the goal being met:
            // disarm and tell the controller, once.
            goal_auto_target = None
            @xlog.warn() <?
              {
                "event": "goal_budget_exhausted",
                "turns": GoalAutoContinueMaxTurns,
              }
          }
          if active_work is None && pending.length() == 0 && shutting_down {
            break serve~
          }
        }
        CompactDone(next) => {
          session = next
          active_work = None
          start_next_pending()
          // Only drain if compaction left the engine idle: a command context
          // deferred during compaction then has no turn to drain it, so persist
          // it onto the compacted session now. If a pending prompt started
          // instead, leave the queue for its first step — that turn drains both
          // the command context and the prompt steers aimed at it, which
          // (unlike the raced-turn-end leftovers at TurnDone) must not be
          // dropped.
          if active_work is None {
            drain_command_context()
          }
          if active_work is None && pending.length() == 0 && shutting_down {
            break serve~
          }
        }
        Shutdown => {
          shutting_down = true
          if active_work is None && pending.length() == 0 {
            break serve~
          }
        }
      }
    }
  })
}
