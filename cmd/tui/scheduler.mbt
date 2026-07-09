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
    guard ch >= '0' && ch <= '9' else { return None }
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
  let (digits, unit) = if text.strip_suffix("s") is Some(digits) {
    (digits, 1)
  } else if text.strip_suffix("m") is Some(digits) {
    (digits, 60)
  } else if text.strip_suffix("h") is Some(digits) {
    (digits, 3600)
  } else {
    (text, 1)
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
