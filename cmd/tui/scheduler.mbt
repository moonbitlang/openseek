///|
/// `/loop` — a recurring scheduled prompt, driven entirely by the TUI (the
/// engine never knows a scheduler exists; fires are ordinary prompt turns).
///
/// The whole scheduler lives here: the interval/argument grammar, the armed
/// `Schedule` and its bookkeeping (`scheduler_tick` on the 1/s heartbeat,
/// `scheduler_on_run_end` at run terminals — nothing touches wall-clock
/// time), the `/loop` command handler, and the single dispatch choke point
/// `scheduler_maybe_fire`, which the message loop invokes once per drained
/// batch and which fires only at a provably idle moment.

///|
/// The floor for `/loop` intervals: an accidental `/loop 1 …` must not turn the
/// agent into a hot loop of unattended model calls.
const MinLoopIntervalSecs = 10

///|
/// Fires before a loop auto-disarms unless the user raises it with `--max`.
/// An unattended recurring task should run out, not run forever.
const DefaultMaxLoopFires = 20

///|
/// Intervals a week and beyond are almost certainly typos, and the bound keeps
/// the digit accumulator far from overflow.
const MaxLoopIntervalSecs = 604_800

///|
/// A parsed `/loop` invocation.
priv enum LoopCommand {
  Arm(interval_secs~ : Int, max_fires~ : Int, prompt~ : String)
  Off
  Status
  Pause
  Resume
}

///|
/// An armed `/loop`. Mutated only by the bookkeeping helpers below
/// (`scheduler_tick`, `scheduler_on_run_end`, `handle_loop_command`); the
/// fire itself is dispatched at the single post-update choke point,
/// `scheduler_maybe_fire`.
priv struct Schedule {
  prompt : String
  interval_secs : Int
  max_fires : Int
  // Seconds until due; 0 means due (and possibly deferred while busy). Held
  // un-counted while the loop's own run is in flight — re-armed to a full
  // interval when that run finishes, so cadence is fixed-delay-from-completion
  // and a run longer than the interval never overlaps the next fire.
  mut remaining_secs : Int
  mut fires : Int
  // Armed but not counting: set by `/loop pause` or automatically when a
  // loop-fired run ends in anything but success (repeating a failing task
  // unattended helps nobody). `/loop resume` restarts a full interval.
  mut paused : Bool
  // The `run_id` of the loop's own run in flight, if any — the key that ties
  // scheduler bookkeeping to the existing monotonic run-ownership scheme, so
  // user-initiated runs never re-arm or pause the loop.
  mut fired_run_id : Int?
}

///|
/// How a loop-fired run ended, reduced to what the scheduler cares about.
priv enum LoopRunOutcome {
  LoopRunFinished
  // Carries a short human label ("was interrupted", "failed", …) for the
  // pause notice.
  LoopRunFailed(String)
}

///|
/// One countdown step, driven by the 1/s `Tick` heartbeat. Pure bookkeeping:
/// never dispatches (that is `scheduler_maybe_fire`'s job, which has access to
/// the composer state `update` cannot see).
fn scheduler_tick(state : State) -> Unit {
  guard state.schedule is Some(schedule) else { return }
  if !schedule.paused &&
    schedule.fired_run_id is None &&
    schedule.remaining_secs > 0 {
    schedule.remaining_secs -= 1
  }
}

///|
/// Settle scheduler bookkeeping at a terminal transition of the run that is
/// ending right now (the update loop's stale-message guard has already
/// established ownership, so `state.run_id` names that run). A no-op unless
/// the ending run is the loop's own fire.
fn scheduler_on_run_end(
  state : State,
  outcome : LoopRunOutcome,
  cmds : Array[Cmd],
) -> Unit {
  guard state.schedule is Some(schedule) else { return }
  guard schedule.fired_run_id is Some(fired) && fired == state.run_id else {
    return
  }
  schedule.fired_run_id = None
  match outcome {
    LoopRunFinished => {
      schedule.fires += 1
      if schedule.fires >= schedule.max_fires {
        state.schedule = None
        cmds.push(
          AppendItem(
            command_notice(
              "⟳ loop done: ran \{schedule.fires} of \{schedule.max_fires} times; disarmed",
            ),
          ),
        )
      } else {
        schedule.remaining_secs = schedule.interval_secs
      }
    }
    LoopRunFailed(reason) => {
      schedule.paused = true
      cmds.push(
        AppendItem(
          command_notice(
            "⟳ loop paused: the last run \{reason}. Use /loop resume to continue or /loop off to stop.",
          ),
        ),
      )
    }
  }
}

///|
/// The single dispatch choke point: invoked by the message loop after **every**
/// `update` returns — after lifecycle changes have been applied and any queued
/// user input has been drained — so every idle boundary (Tick, agent terminals,
/// foreground `!` terminals, background-command completions) is covered with no
/// per-site fire logic. `input_idle` is the one gate `update` cannot see —
/// the composer state and any submission still in flight toward the message
/// queue are private to the UI; the caller passes `ui.input_idle()`.
///
/// A due schedule fires only at a fully idle moment: no run in flight, nothing
/// queued, no unconfirmed steers, no background `!` command whose context is
/// still owed to the engine, and no user interaction on the input surface
/// (draft text, shell mode, or a just-submitted event still in flight).
/// Anything less defers — the fire stays due and dispatches at the next idle
/// boundary.
fn scheduler_maybe_fire(
  state : State,
  input_idle~ : Bool,
  cmds : Array[Cmd],
) -> Unit {
  guard state.schedule is Some(schedule) else { return }
  guard !schedule.paused &&
    schedule.remaining_secs == 0 &&
    schedule.fired_run_id is None else {
    return
  }
  guard state.run is Idle &&
    state.queued.is_empty() &&
    state.pending_steers.is_empty() &&
    state.background_commands == 0 &&
    input_idle else {
    return
  }
  // Never fire into a batch that is tearing something down or still carrying
  // the user's voice. A drained batch can hold a second Ctrl-C's KillEngine
  // (or a Quit) together with the dying run's terminal event, leaving `run`
  // idle here — but a StartAgent appended now would execute right after the
  // kill and prompt a dead engine (or an exiting TUI). Likewise a
  // prompt steer emitted earlier in this batch, with the turn's terminal
  // behind it having already cleared `pending_steers`: that steer is about to
  // bounce off the closed turn and come back as a resubmit notice, and firing
  // now would put the loop's run in front of the user's still-unsettled text.
  // Command-context steers are the designed exception — the fire is
  // deliberately ordered after them. Either way the fire stays due for the
  // next batch.
  for cmd in cmds {
    if cmd is (CancelAgent | KillEngine | Quit | SteerAgent(Prompt(_))) {
      return
    }
  }
  let run_id = state.start_run(@env.now().reinterpret_as_int64())
  schedule.fired_run_id = Some(run_id)
  // Attribution lives in the notice; the prompt itself is echoed — and reaches
  // the engine — verbatim, so the model sees exactly what the user stored and
  // a resumed session replays a plain user message (documented trade-off).
  cmds.push(
    AppendItem(
      command_notice(
        "⟳ loop fire \{schedule.fires + 1} of \{schedule.max_fires}",
      ),
    ),
  )
  cmds.push(AppendItem(Input(Prompt(schedule.prompt))))
  cmds.push(StartAgent(run_id~, schedule.prompt))
}

///|
/// Render seconds in the interval grammar's own units — `45s`, `5m`, `2h` —
/// composing where needed (`1m30s`, `2h5m`).
fn format_loop_interval(seconds : Int) -> String {
  let hours = seconds / 3600
  let minutes = seconds % 3600 / 60
  let secs = seconds % 60
  let parts : Array[String] = []
  if hours > 0 {
    parts.push("\{hours}h")
  }
  if minutes > 0 {
    parts.push("\{minutes}m")
  }
  if secs > 0 || parts.is_empty() {
    parts.push("\{secs}s")
  }
  parts.join("")
}

///|
/// The `/loop status` phrase for where the schedule stands. A due-but-deferred
/// fire is reported as exactly that — inventing a "next in 1s" would conflict
/// with the status bar's `⟳ due` and could stay false indefinitely while the
/// loop waits out a long run.
fn loop_status_position(schedule : Schedule) -> String {
  if schedule.fired_run_id is Some(_) {
    "running now"
  } else if schedule.paused {
    "paused"
  } else if schedule.remaining_secs == 0 {
    "due, waiting for an idle moment"
  } else {
    "next in \{format_loop_interval(schedule.remaining_secs)}"
  }
}

///|
/// Handle a `/loop` invocation. Arming (or replacing) a schedule never starts
/// work by itself — the first fire happens a full interval later, and only at
/// an idle moment.
fn handle_loop_command(
  state : State,
  arguments : String,
  cmds : Array[Cmd],
) -> Unit {
  match parse_loop_command(arguments) {
    Err(message) => cmds.push(AppendItem(Error(message)))
    Ok(Arm(interval_secs~, max_fires~, prompt~)) => {
      let verb = if state.schedule is Some(_) { "replaced" } else { "armed" }
      state.schedule = Some({
        prompt,
        interval_secs,
        max_fires,
        remaining_secs: interval_secs,
        fires: 0,
        paused: false,
        fired_run_id: None,
      })
      cmds.push(
        AppendItem(
          command_notice(
            "⟳ loop \{verb}: every \{format_loop_interval(interval_secs)}, up to \{max_fires} runs — \{prompt}",
          ),
        ),
      )
    }
    Ok(Off) =>
      match state.schedule {
        Some(_) => {
          state.schedule = None
          cmds.push(AppendItem(command_notice("⟳ loop off")))
        }
        None => cmds.push(AppendItem(Error("No loop is armed.")))
      }
    Ok(Status) =>
      match state.schedule {
        Some(schedule) => {
          let position = loop_status_position(schedule)
          cmds.push(
            AppendItem(
              command_notice(
                "⟳ loop: every \{format_loop_interval(schedule.interval_secs)}, \{position}, ran \{schedule.fires} of \{schedule.max_fires} — \{schedule.prompt}",
              ),
            ),
          )
        }
        None => cmds.push(AppendItem(Error("No loop is armed.")))
      }
    Ok(Pause) =>
      match state.schedule {
        Some(schedule) =>
          if schedule.paused {
            cmds.push(AppendItem(Error("The loop is already paused.")))
          } else {
            schedule.paused = true
            cmds.push(AppendItem(command_notice("⟳ loop paused")))
          }
        None => cmds.push(AppendItem(Error("No loop is armed.")))
      }
    Ok(Resume) =>
      match state.schedule {
        Some(schedule) =>
          if schedule.paused {
            schedule.paused = false
            schedule.remaining_secs = schedule.interval_secs
            cmds.push(
              AppendItem(
                command_notice(
                  "⟳ loop resumed: next in \{format_loop_interval(schedule.interval_secs)}",
                ),
              ),
            )
          } else {
            cmds.push(AppendItem(Error("The loop is not paused.")))
          }
        None => cmds.push(AppendItem(Error("No loop is armed.")))
      }
  }
}

///|
/// Parse a bare positive decimal, bounded by `MaxLoopIntervalSecs` (which also
/// keeps the accumulator far from overflow). `None` for anything else.
fn parse_loop_number(digits : StringView) -> Int? {
  guard !digits.is_empty() else { return None }
  let mut value = 0
  for ch in digits {
    guard ch is ('0'..='9') else { return None }
    value = value * 10 + (ch.to_int() - '0'.to_int())
    if value > MaxLoopIntervalSecs {
      return None
    }
  }
  if value == 0 {
    None
  } else {
    Some(value)
  }
}

///|
/// Parse an interval token: bare seconds (`300`) or a single `s`/`m`/`h`
/// suffix (`30s`, `5m`, `2h`). `None` for anything else, zero, or beyond
/// `MaxLoopIntervalSecs`. The `MinLoopIntervalSecs` floor is enforced by the
/// caller so it can name the limit in its error message.
fn parse_loop_interval(text : StringView) -> Int? {
  let (digits, unit) = match text {
    [.. digits, 's'] => (digits, 1)
    [.. digits, 'm'] => (digits, 60)
    [.. digits, 'h'] => (digits, 3600)
    _ => (text, 1)
  }
  guard parse_loop_number(digits) is Some(value) else { return None }
  // Bound before multiplying: `604800h * 3600` would overflow Int and wrap
  // negative, dodging a post-multiplication ceiling check entirely.
  if value > MaxLoopIntervalSecs / unit {
    None
  } else {
    Some(value * unit)
  }
}

///|
/// Split the leading whitespace-delimited word off `text`, returning the word
/// and the remainder with surrounding whitespace trimmed.
fn split_loop_word(text : StringView) -> (StringView, StringView) {
  match text.split_once(" ") {
    Some((word, rest)) => (word, rest.trim())
    None => (text, "")
  }
}

///|
const LoopUsage = "usage: /loop [--max <n>] <interval> <prompt> — or /loop off | status | pause | resume"

///|
/// Parse the `/loop` argument string. The grammar keeps prompts unambiguous:
/// `--max <n>` is only recognized *before* the interval token, so a prompt
/// containing `--max` later is passed through verbatim.
fn parse_loop_command(arguments : String) -> Result[LoopCommand, String] {
  let trimmed = arguments.trim()
  match trimmed {
    "" => return Err(LoopUsage)
    "off" => return Ok(Off)
    "status" => return Ok(Status)
    "pause" => return Ok(Pause)
    "resume" => return Ok(Resume)
    _ => ()
  }
  let mut rest = trimmed
  let mut max_fires = DefaultMaxLoopFires
  let (head, tail) = split_loop_word(rest)
  if head is "--max" {
    let (count_word, after_count) = split_loop_word(tail)
    guard parse_loop_number(count_word) is Some(count) else {
      return Err("expected a positive count after --max. \{LoopUsage}")
    }
    max_fires = count
    rest = after_count
  }
  let (interval_word, prompt) = split_loop_word(rest)
  guard parse_loop_interval(interval_word) is Some(interval_secs) else {
    return Err(
      "invalid interval '\{interval_word}' (use seconds, or 30s/5m/2h). \{LoopUsage}",
    )
  }
  if interval_secs < MinLoopIntervalSecs {
    return Err("interval must be at least \{MinLoopIntervalSecs}s")
  }
  if prompt.is_empty() {
    return Err("a prompt is required. \{LoopUsage}")
  }
  Ok(Arm(interval_secs~, max_fires~, prompt=prompt.to_owned()))
}

///|
test "loop interval grammar" {
  // Bare seconds and unit suffixes.
  assert_true(parse_loop_interval("300") is Some(300))
  assert_true(parse_loop_interval("30s") is Some(30))
  assert_true(parse_loop_interval("5m") is Some(300))
  assert_true(parse_loop_interval("2h") is Some(7200))
  assert_true(parse_loop_interval("10") is Some(10))
  // Rejected: empty, zero, garbage, mixed, negative-looking, over the bound.
  assert_true(parse_loop_interval("") is None)
  assert_true(parse_loop_interval("0") is None)
  assert_true(parse_loop_interval("0s") is None)
  assert_true(parse_loop_interval("abc") is None)
  assert_true(parse_loop_interval("5m3") is None)
  assert_true(parse_loop_interval("-5") is None)
  assert_true(parse_loop_interval("m") is None)
  assert_true(parse_loop_interval("999999999") is None)
  assert_true(parse_loop_interval("200h") is None)
  // Would overflow Int if multiplied before the ceiling check.
  assert_true(parse_loop_interval("604800h") is None)
  assert_true(parse_loop_interval("604800m") is None)
  // The exact ceiling itself is accepted.
  assert_true(parse_loop_interval("604800") is Some(604_800))
  assert_true(parse_loop_interval("168h") is Some(604_800))
}

///|
test "loop command grammar: arm forms" {
  guard parse_loop_command("5m check CI status")
    is Ok(Arm(interval_secs~, max_fires~, prompt~)) else {
    fail("expected Arm")
  }
  assert_eq(interval_secs, 300)
  assert_eq(max_fires, DefaultMaxLoopFires)
  assert_eq(prompt, "check CI status")

  // --max before the interval is an option…
  guard parse_loop_command("--max 5 30s do the thing")
    is Ok(Arm(interval_secs=interval2, max_fires=max2, prompt=prompt2)) else {
    fail("expected Arm with --max")
  }
  assert_eq(interval2, 30)
  assert_eq(max2, 5)
  assert_eq(prompt2, "do the thing")

  // …but after the interval it is literal prompt text.
  guard parse_loop_command("30s run --max 5 times")
    is Ok(Arm(prompt=prompt3, ..)) else {
    fail("expected Arm with literal --max in prompt")
  }
  assert_eq(prompt3, "run --max 5 times")
}

///|
test "loop command grammar: subcommands" {
  assert_true(parse_loop_command("off") is Ok(Off))
  assert_true(parse_loop_command("status") is Ok(Status))
  assert_true(parse_loop_command("pause") is Ok(Pause))
  assert_true(parse_loop_command("resume") is Ok(Resume))
  assert_true(parse_loop_command("  off  ") is Ok(Off))
}

///|
fn armed_state(arguments : String) -> State {
  let state = drain_test_state()
  let _ = update(state, UiInput(SlashCommand(name="loop", arguments~)))
  state
}

///|
fn notice_count(cmds : Array[Cmd]) -> Int {
  cmds.count_if(cmd => cmd is AppendItem(Notice(_)))
}

///|
test "loop arm/off/status/pause/resume lifecycle" {
  let state = drain_test_state()
  // Arm: schedule set, notice appended, full countdown.
  let armed = update(
    state,
    UiInput(SlashCommand(name="loop", arguments="5m check CI")),
  )
  assert_eq(notice_count(armed), 1)
  guard state.schedule is Some(schedule) else { fail("expected a schedule") }
  assert_eq(schedule.remaining_secs, 300)
  assert_eq(schedule.fires, 0)
  assert_false(schedule.paused)
  // Re-arm replaces.
  let replaced = update(
    state,
    UiInput(SlashCommand(name="loop", arguments="30s other task")),
  )
  assert_eq(notice_count(replaced), 1)
  guard state.schedule is Some(second) else { fail("expected a schedule") }
  assert_eq(second.interval_secs, 30)
  // Status reports without mutating.
  let status = update(
    state,
    UiInput(SlashCommand(name="loop", arguments="status")),
  )
  assert_eq(notice_count(status), 1)
  assert_eq(second.remaining_secs, 30)
  // Pause stops the countdown; resume restarts a full interval.
  let _ = update(state, UiInput(SlashCommand(name="loop", arguments="pause")))
  assert_true(second.paused)
  let _ = update(state, Tick)
  assert_eq(second.remaining_secs, 30)
  let _ = update(state, UiInput(SlashCommand(name="loop", arguments="resume")))
  assert_false(second.paused)
  // Off clears; off again errors.
  let _ = update(state, UiInput(SlashCommand(name="loop", arguments="off")))
  assert_true(state.schedule is None)
  let again = update(state, UiInput(SlashCommand(name="loop", arguments="off")))
  assert_eq(error_item_count(again), 1)
}

///|
test "loop countdown ticks only while armed, unpaused, and not mid-fire" {
  let state = armed_state("30s do x")
  guard state.schedule is Some(schedule) else { fail("expected a schedule") }
  let _ = update(state, Tick)
  let _ = update(state, Tick)
  assert_eq(schedule.remaining_secs, 28)
  // A fire in flight holds the countdown even at zero.
  schedule.remaining_secs = 0
  schedule.fired_run_id = Some(41)
  let _ = update(state, Tick)
  assert_eq(schedule.remaining_secs, 0)
  // Held at zero once due (never negative).
  schedule.fired_run_id = None
  let _ = update(state, Tick)
  assert_eq(schedule.remaining_secs, 0)
}

///|
test "loop re-arms after its own run finishes and pauses on failures" {
  let state = armed_state("30s do x")
  guard state.schedule is Some(schedule) else { fail("expected a schedule") }
  // Simulate the choke point having fired: the loop owns the run in flight.
  let run_id = state.start_run(0)
  schedule.remaining_secs = 0
  schedule.fired_run_id = Some(run_id)
  // Success re-arms a full interval and counts the fire.
  let done = update(state, AgentProgress(run_id~, AgentFinished("ok")))
  assert_eq(schedule.remaining_secs, 30)
  assert_eq(schedule.fires, 1)
  assert_true(schedule.fired_run_id is None)
  assert_false(schedule.paused)
  ignore(done)
  // A failing fire pauses instead of re-arming.
  let run2 = state.start_run(0)
  schedule.fired_run_id = Some(run2)
  let failed = update(state, AgentProgress(run_id=run2, AgentError("boom")))
  assert_true(schedule.paused)
  assert_true(schedule.fired_run_id is None)
  assert_eq(notice_count(failed), 1)
  // An interrupt of a resumed fire also pauses.
  schedule.paused = false
  let run3 = state.start_run(0)
  schedule.fired_run_id = Some(run3)
  let _ = update(state, AgentCancelled(run_id=run3))
  assert_true(schedule.paused)
}

///|
test "loop cap disarms after the last fire" {
  let state = armed_state("--max 2 30s do x")
  guard state.schedule is Some(schedule) else { fail("expected a schedule") }
  schedule.fires = 1
  let run_id = state.start_run(0)
  schedule.fired_run_id = Some(run_id)
  let done = update(state, AgentProgress(run_id~, AgentFinished("ok")))
  assert_true(state.schedule is None)
  assert_eq(notice_count(done), 1)
}

///|
test "user runs never touch the schedule" {
  let state = armed_state("30s do x")
  guard state.schedule is Some(schedule) else { fail("expected a schedule") }
  // A user prompt runs and fails; the schedule is not the owner, so nothing
  // pauses and nothing re-arms.
  let _ = update(state, UiInput(Steer(Prompt("user task"))))
  guard state.run is Running(_) else { fail("expected a user run") }
  let before = schedule.remaining_secs
  let _ = update(state, AgentProgress(run_id=state.run_id, AgentError("boom")))
  assert_false(schedule.paused)
  assert_eq(schedule.remaining_secs, before)
  assert_eq(schedule.fires, 0)
}

///|
test "background command counter tracks spawn and completion" {
  let state = drain_test_state()
  // Start a user run, then a background `!` alongside it.
  let _ = update(state, UiInput(Steer(Prompt("task"))))
  let cmds = update(state, UiInput(Steer(Command("ls"))))
  assert_eq(run_background_command_count(cmds), 1)
  assert_eq(state.background_commands, 1)
  let _ = update(
    state,
    CommandResult(command="ls", run_id=None, Err(Failure::Failure("boom"))),
  )
  assert_eq(state.background_commands, 0)
}

///|
/// Drive the countdown to due and invoke the choke point once, mirroring the
/// message loop's `update`-then-`scheduler_maybe_fire` shape for a `Tick`.
fn tick_and_fire(state : State, input_idle~ : Bool) -> Array[Cmd] {
  let cmds = update(state, Tick)
  scheduler_maybe_fire(state, input_idle~, cmds)
  cmds
}

///|
test "a due loop fires exactly once at an idle tick" {
  let state = armed_state("30s do the rounds")
  guard state.schedule is Some(schedule) else { fail("expected a schedule") }
  // 29 ticks: armed but not due; the choke point stays silent.
  for _ in 0..<29 {
    let cmds = tick_and_fire(state, input_idle=true)
    assert_eq(start_agent_count(cmds), 0)
  }
  assert_eq(schedule.remaining_secs, 1)
  // The 30th tick fires: notice + verbatim prompt echo + StartAgent.
  let fired = tick_and_fire(state, input_idle=true)
  assert_eq(start_agent_count(fired), 1)
  assert_eq(notice_count(fired), 1)
  let echoes = [
    for cmd in fired if cmd is AppendItem(Input(Prompt("do the rounds"))) => cmd
  ]
  assert_eq(echoes.length(), 1)
  guard fired[fired.length() - 1] is StartAgent(run_id~, "do the rounds") else {
    fail("expected the fire's StartAgent last")
  }
  assert_true(schedule.fired_run_id is Some(fired_id) && fired_id == run_id)
  guard state.run is Running(_) else {
    fail("expected the fired run in flight")
  }
  // Still due-held, not counting, while its own run is in flight.
  let during = tick_and_fire(state, input_idle=true)
  assert_eq(start_agent_count(during), 0)
}

///|
test "a due loop defers while anything is busy and fires at the idle boundary" {
  let state = armed_state("30s do x")
  guard state.schedule is Some(schedule) else { fail("expected a schedule") }
  // A user prompt occupies the run slot; the countdown reaches due beneath it.
  let _ = update(state, UiInput(Steer(Prompt("user work"))))
  schedule.remaining_secs = 1
  let held = tick_and_fire(state, input_idle=true)
  assert_eq(start_agent_count(held), 0)
  assert_eq(schedule.remaining_secs, 0)
  // More ticks while busy: still exactly zero fires (no accumulation).
  for _ in 0..<5 {
    assert_eq(start_agent_count(tick_and_fire(state, input_idle=true)), 0)
  }
  // The user run's terminal is an idle boundary: the deferred fire dispatches
  // in the very same update cycle, no Tick needed.
  let boundary = update(
    state,
    AgentProgress(run_id=state.run_id, AgentFinished("done")),
  )
  scheduler_maybe_fire(state, input_idle=true, boundary)
  assert_eq(start_agent_count(boundary), 1)
  assert_true(schedule.fired_run_id is Some(id) && id == state.run_id)
}

///|
test "each busy source individually holds a due fire" {
  // Draft text under the cursor.
  let drafting = armed_state("30s do x")
  guard drafting.schedule is Some(draft_schedule) else { fail("no schedule") }
  draft_schedule.remaining_secs = 0
  let held = update(drafting, Tick)
  scheduler_maybe_fire(drafting, input_idle=false, held)
  assert_eq(start_agent_count(held), 0)
  scheduler_maybe_fire(drafting, input_idle=true, held)
  assert_eq(start_agent_count(held), 1)

  // A background `!` command whose context is still owed to the engine.
  let waiting = armed_state("30s do x")
  guard waiting.schedule is Some(wait_schedule) else { fail("no schedule") }
  let _ = update(waiting, UiInput(Steer(Prompt("user work"))))
  let _ = update(waiting, UiInput(Steer(Command("ls"))))
  let _ = update(
    waiting,
    AgentProgress(run_id=waiting.run_id, AgentFinished("done")),
  )
  wait_schedule.remaining_secs = 0
  // Run slot idle, but the background command is still out.
  assert_eq(waiting.background_commands, 1)
  let blocked = tick_and_fire(waiting, input_idle=true)
  assert_eq(start_agent_count(blocked), 0)
  // Its completion is itself an idle boundary: the fire rides the same cycle,
  // ordered after the command-context steer.
  let after = update(
    waiting,
    CommandResult(command="ls", run_id=None, Err(Failure::Failure("x"))),
  )
  scheduler_maybe_fire(waiting, input_idle=true, after)
  assert_eq(start_agent_count(after), 1)
  guard after.search_by(cmd => cmd is SteerAgent(_)) is Some(steer_index) else {
    fail("expected the command-context steer")
  }
  guard after.search_by(cmd => cmd is StartAgent(_, ..)) is Some(start_index) else {
    fail("expected the fire's StartAgent")
  }
  assert_true(steer_index < start_index)

  // A paused loop never fires, even when due and idle.
  let paused = armed_state("30s do x")
  guard paused.schedule is Some(pause_schedule) else { fail("no schedule") }
  pause_schedule.remaining_secs = 0
  pause_schedule.paused = true
  assert_eq(start_agent_count(tick_and_fire(paused, input_idle=true)), 0)
}

///|
test "a fired loop run steers like any other run" {
  let state = armed_state("30s do x")
  guard state.schedule is Some(schedule) else { fail("expected a schedule") }
  schedule.remaining_secs = 0
  let fired = tick_and_fire(state, input_idle=true)
  assert_eq(start_agent_count(fired), 1)
  // The fired run is a normal engine turn: a typed prompt steers it rather
  // than being rejected — the ownership discipline is shared, not special.
  let steered = update(state, UiInput(Steer(Prompt("also check the docs"))))
  assert_true(
    [ for cmd in steered if cmd is SteerAgent(_) => cmd ].length() == 1,
  )
}

///|
test "loop command grammar: rejections name the problem" {
  guard parse_loop_command("") is Err(usage) else { fail("expected usage") }
  assert_true(usage.contains("usage:"))
  guard parse_loop_command("5m") is Err(no_prompt) else {
    fail("expected prompt-required")
  }
  assert_true(no_prompt.contains("prompt is required"))
  guard parse_loop_command("9s do x") is Err(too_short) else {
    fail("expected minimum-interval rejection")
  }
  assert_true(too_short.contains("at least 10s"))
  guard parse_loop_command("soon do x") is Err(bad_interval) else {
    fail("expected invalid-interval rejection")
  }
  assert_true(bad_interval.contains("invalid interval 'soon'"))
  guard parse_loop_command("--max nope 5m do x") is Err(bad_count) else {
    fail("expected bad --max rejection")
  }
  assert_true(bad_count.contains("--max"))
  guard parse_loop_command("--max 0 5m do x") is Err(zero_count) else {
    fail("expected zero --max rejection")
  }
  assert_true(zero_count.contains("--max"))
}

///|
test "loop status segment mirrors schedule state" {
  // No loop: the segment is empty and leaves no dangling separator.
  assert_eq(loop_segment_text(None), "")
  // Counting: a compact countdown.
  let schedule : Schedule = {
    prompt: "do x",
    interval_secs: 300,
    max_fires: 20,
    remaining_secs: 277,
    fires: 0,
    paused: false,
    fired_run_id: None,
  }
  assert_eq(loop_segment_text(Some(schedule)), "⟳ 4m 37s")
  schedule.remaining_secs = 45
  assert_eq(loop_segment_text(Some(schedule)), "⟳ 45s")
  schedule.remaining_secs = 3725
  assert_eq(loop_segment_text(Some(schedule)), "⟳ 1h 02m 05s")
  // Due but deferred, its own fire in flight, and paused.
  schedule.remaining_secs = 0
  assert_eq(loop_segment_text(Some(schedule)), "⟳ due")
  schedule.fired_run_id = Some(7)
  assert_eq(loop_segment_text(Some(schedule)), "⟳ running")
  schedule.fired_run_id = None
  schedule.paused = true
  assert_eq(loop_segment_text(Some(schedule)), "⟳ paused")
}

///|
test "loop segment precedes the clippable variable-length fields" {
  // The status line clips at terminal width from the right; an armed loop's
  // countdown must sit ahead of a long cwd so it cannot be pushed off-screen.
  let state = armed_state("5m do x")
  let segments = status_segments(state)
  guard segments.search_by(segment => segment.text.has_prefix("⟳"))
    is Some(loop_index) else {
    fail("expected the loop segment")
  }
  guard segments.search_by(segment => segment.text == state.config.cwd)
    is Some(cwd_index) else {
    fail("expected the cwd segment")
  }
  assert_true(loop_index < cwd_index)
}

///|
test "a due loop never fires into a teardown batch" {
  let state = armed_state("30s do x")
  guard state.schedule is Some(schedule) else { fail("expected a schedule") }
  schedule.remaining_secs = 0
  // The drained batch carries a KillEngine (second Ctrl-C) alongside the dying
  // run's terminal: run is idle again, but firing now would prompt a process
  // the same batch kills.
  let killing : Array[Cmd] = [KillEngine]
  scheduler_maybe_fire(state, input_idle=true, killing)
  assert_eq(start_agent_count(killing), 0)
  let cancelling : Array[Cmd] = [CancelAgent]
  scheduler_maybe_fire(state, input_idle=true, cancelling)
  assert_eq(start_agent_count(cancelling), 0)
  let quitting : Array[Cmd] = [Quit]
  scheduler_maybe_fire(state, input_idle=true, quitting)
  assert_eq(start_agent_count(quitting), 0)
  // The fire stayed due: a clean batch dispatches it.
  let clean : Array[Cmd] = []
  scheduler_maybe_fire(state, input_idle=true, clean)
  assert_eq(start_agent_count(clean), 1)
}

///|
test "loop status reports a deferred fire as due" {
  let schedule : Schedule = {
    prompt: "do x",
    interval_secs: 30,
    max_fires: 20,
    remaining_secs: 30,
    fires: 0,
    paused: false,
    fired_run_id: None,
  }
  assert_eq(loop_status_position(schedule), "next in 30s")
  schedule.remaining_secs = 0
  assert_eq(loop_status_position(schedule), "due, waiting for an idle moment")
  schedule.fired_run_id = Some(3)
  assert_eq(loop_status_position(schedule), "running now")
  schedule.fired_run_id = None
  schedule.paused = true
  assert_eq(loop_status_position(schedule), "paused")
}

///|
test "a due loop defers behind a prompt steer racing the turn's terminal" {
  let state = armed_state("30s do x")
  guard state.schedule is Some(schedule) else { fail("expected a schedule") }
  schedule.remaining_secs = 0
  // The drained batch carries the user's prompt steer (emitted while the turn
  // still ran) with the terminal event behind it having already cleared
  // pending_steers: the steer is about to bounce off the closed turn, so the
  // fire must wait rather than jump ahead of the user's unsettled text.
  let steering : Array[Cmd] = [SteerAgent(Prompt("user text"))]
  scheduler_maybe_fire(state, input_idle=true, steering)
  assert_eq(start_agent_count(steering), 0)
  // A command-context steer keeps the designed ordering: fire after it.
  let command_context : Array[Cmd] = [SteerAgent(Command("ls output"))]
  scheduler_maybe_fire(state, input_idle=true, command_context)
  assert_eq(start_agent_count(command_context), 1)
}
