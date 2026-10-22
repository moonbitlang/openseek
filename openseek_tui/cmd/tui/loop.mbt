///|
async fn read_ui_events(ui : @ui.Ui, messages : @async.Queue[Msg]) -> Unit {
  for ;; {
    let event = ui.read_event()
    messages.put(UiInput(event))
    // A delivered submission is now visible to the message loop's drain, so
    // its slice of the UI's mid-flight window can close. Exactly the
    // submission events pair with `pending_submissions` increments (both
    // submit helpers emit precisely one of these three); other events must
    // not decrement, or a rapid second Enter still sitting in the UI's
    // internal event queue would be masked and a due /loop could overtake it.
    if event is (Steer(_) | Queue(_) | SlashCommand(_)) {
      ui.submission_delivered()
    }
    if event is Quit {
      break
    }
  }
}

///|
async fn tick_ui(messages : @async.Queue[Msg]) -> Unit {
  for ;; {
    @async.sleep(1000)
    messages.put(Tick)
  }
}

///|
/// Cap on the engine stderr we retain to surface in a no-terminal-event error.
/// We still read past it so the child can never block writing to a full stderr
/// pipe (which would deadlock the `proc.wait()` below), but only this many bytes
/// are held in memory and rendered; the overflow is counted and dropped.
const StderrCaptureLimitBytes : Int32 = 8192

///|
/// Per-read size while draining stderr past the cap. The retained bytes are
/// bounded by the remaining budget so the buffer never overshoots; once full we
/// keep reading in blocks this size only to drain the pipe, discarding them.
const StderrDrainChunkBytes : Int32 = 4096

///|
/// Drain an engine's stderr `reader` to EOF, retaining at most
/// `StderrCaptureLimitBytes`. Reading continues past the cap (so the child does
/// not block on a full pipe), but once the buffer is full further chunks are
/// discarded and a truncation marker is appended. Bytes are decoded lossily —
/// stderr is best-effort diagnostics, so a split multi-byte sequence at a chunk
/// boundary becomes a replacement char rather than failing the whole decode.
///
/// A read error ends the drain but is folded into the returned text (after
/// whatever was captured before it) rather than discarded, so a failure to read
/// the engine's diagnostics is visible instead of looking like empty stderr.
/// Cancellation is re-raised so a Ctrl-C still tears the task group down.
async fn drain_stderr_capped(reader : @process.ReadFromProcess) -> String {
  let buffer = Buffer()
  let mut truncated = false
  let mut read_error : String? = None
  for ;; {
    // While there is budget, bound the read by it so a single large `read_some`
    // can never overshoot the cap; once full, read fixed blocks purely to drain.
    let remaining = StderrCaptureLimitBytes - buffer.length()
    let max_len = if remaining > 0 { remaining } else { StderrDrainChunkBytes }
    let chunk = reader.read_some(max_len~) catch {
      // Stop on a genuine read error, but keep the prefix already captured and
      // record the failure so it is surfaced below. `None` ends the loop the
      // same way EOF does.
      error => {
        read_error = Some("\{error}")
        None
      }
    }
    match chunk {
      None => break
      // Under budget the chunk is `<= remaining`, so it fits exactly; once the
      // buffer is full any further bytes are dropped and flag truncation.
      Some(chunk) =>
        if remaining > 0 {
          buffer.write_bytes(chunk)
        } else {
          truncated = true
        }
    }
  }
  let text = StringBuilder()
  text <+ "\{@utf8.decode_lossy(buffer.to_bytes())}"
  if truncated {
    text <+ "\n… (stderr truncated at \{StderrCaptureLimitBytes} bytes)"
  }
  if read_error is Some(message) {
    text <+ "\n… (stderr read failed: \{message})"
  }
  text.to_string()
}

///|
/// The transcript item for steering input that never reached a turn —
/// whether the client dropped it (no live engine) or the engine rejected it
/// (the steer raced the terminal event through the pipes). Either way the
/// text must not vanish silently.
fn steer_dropped_item(text : String) -> @ui.TranscriptItem {
  Error(
    "Input was not delivered (the task ended as you sent it) — submit it again: \{text}",
  )
}

///|
/// One pending steer was settled (applied or dropped): stop acknowledging
/// it on the activity line. Settlement is matched by text, not position —
/// an untagged drop from a finished turn can trail into the next turn's
/// lifetime, and it must never consume an acknowledgment belonging to a
/// fresh steer it has nothing to do with. No match (the old turn's list
/// was already swept) is a no-op.
fn confirm_pending_steer(state : State, text : String) -> Unit {
  if state.pending_steers.search(text) is Some(index) {
    state.pending_steers.remove(index) |> ignore
  }
}

///|
fn is_terminal_event(event : @event.AgentEvent) -> Bool {
  match event {
    AgentFinished(_)
    | AgentAborted(_)
    | MaxStepsExhausted
    | AgentError(_)
    | CompactionFinished(_)
    | ContextYield(_) => true
    _ => false
  }
}

///|
/// The `AgentError` for an engine that closed its stdout without a terminal
/// event: the exit `code` plus the captured stderr `diagnostics` (already
/// trimmed) as detail, or no detail when there were none.
fn engine_exit_without_result(
  code : Int32,
  diagnostics : StringView,
) -> @event.AgentEvent {
  let detail = if diagnostics.is_empty() { "" } else { ":\n\{diagnostics}" }
  AgentError("engine exited (code \{code}) without a result\{detail}")
}

///|
fn engine_extra_env(config : AppConfig) -> Map[String, String] {
  let env = {
    "OPENSEEK_API_URL": config.api_url.unwrap_or(""),
    "OPENSEEK_MODEL": config.model.to_string(),
    "OPENSEEK_THINKING": config.thinking.to_string(),
  }
  // Absent means context-bounded turns: the variable must be OMITTED, not
  // set to "" — the engine treats an empty value as a parse error.
  if config.max_steps is Some(max_steps) {
    env["OPENSEEK_MAX_STEPS"] = max_steps.to_string()
  }
  // Explicit flags override any inherited value; unset ones leave it alone.
  if config.retry_attempts is Some(attempts) {
    env["OPENSEEK_RETRY_ATTEMPTS"] = attempts.to_string()
  }
  if config.retry_backoff_ms is Some(backoff_ms) {
    env["OPENSEEK_RETRY_BACKOFF_MS"] = backoff_ms.to_string()
  }
  let api_key_env = match config.model {
    Kimi(_) => "KIMI"
    Glm(_) => "GLM"
    Deepseek(_) => "DEEPSEEK"
  }
  env[api_key_env] = config.api_key
  env
}

///|
fn engine_env(
  config : AppConfig,
  inherited : Map[String, String],
) -> Map[String, String] {
  let env = inherited.copy()
  env.merge_in_place(engine_extra_env(config))
  env
}

///|
/// Run a `!` shell command locally and post its result to the message loop.
///
/// Unlike a prompt, a shell command is the TUI's own responsibility: it runs it
/// through the agent's shell execution (`@command_context.collect_shell_output`, which
/// picks `sh`/`pwsh` per platform and captures merged output but skips the
/// agent-only command policy), then posts the raw result back to the message
/// loop, which renders it and sends it into the conversation (see
/// `CommandResult` in `update`). A Ctrl-C cancels the child and reports that
/// instead; nothing is sent for a cancelled command. `id` is the command's
/// (`ShellCommand::id`), and names it in whichever report this makes.
async fn run_shell_command(
  command : String,
  messages : @async.Queue[Msg],
  id~ : Int32,
  cwd? : String,
) -> Unit {
  let outcome : Result[@command_context.ShellOutput, Error]? = @async.handle_cancellation(() => {
      try @command_context.collect_shell_output(command, cwd?) catch {
        error => Err(error)
      } noraise {
        output => Ok(output)
      }
    },
  )
  guard outcome is Some(result) else {
    // Cancelled (cancellation bypasses `catch`): report it, so the command
    // line survives as a "(cancelled)" card.
    messages.try_put(CommandCancelled(command~, id~)) |> ignore
    return
  }
  messages.put(CommandResult(command~, id~, result))
}

///|
// The live streaming line is only a transient status preview: it keeps the
// *tail* of the stream (the newest text) so the line visibly moves while the
// model types. The final assistant text is committed later by
// `assistant_message`, so the buffer only needs to cover the widest plausible
// terminal row; the bound keeps per-delta work constant during long
// code-generation streams.
const StreamingPreviewMaxColumns : Int32 = 240

///|
/// Keep the last `max_cols` display columns of `text`, marking an elided front
/// with a leading `…`. The inverse of `DisplayText::truncate`, which keeps the
/// front — a streaming preview must keep the end, where the new text arrives.
fn tail_columns(text : String, max_cols : Int32) -> String {
  let display = @displaytext.DisplayText(text)
  if display.width() <= max_cols {
    return text
  }
  // Reserve one column for the `…` marker; `at_or_after` lands past a wide
  // char straddling the cut, so the kept tail never exceeds the budget.
  let keep_from = display.textual_position_at_or_after(
    @displaytext.DisplayPosition::new(column=display.width() - max_cols + 1),
  )
  "…\{display.view(keep_from, display.end())}"
}

///|
/// Collapse whitespace runs (newline, CR, tab, space) to a single space so a
/// streamed fragment stays renderable on the one-row activity line — streamed
/// code is mostly newlines and indentation, which would otherwise hit the
/// renderer as control characters.
fn collapse_preview_whitespace(text : String) -> String {
  let out = StringBuilder()
  for ch in text; last_was_space = false {
    if ch is (' ' | '\t' | '\n' | '\r') {
      if !last_was_space {
        out.write_char(' ')
      }
      continue true
    } else {
      out.write_char(ch)
      continue false
    }
  }
  out.to_string()
}

///|
fn append_streaming_preview(current : String?, delta : String) -> String {
  let combined = match current {
    Some(text) => "\{text}\{delta}"
    None => delta
  }
  // Re-collapsing the bounded buffer keeps a whitespace run that spans two
  // deltas collapsed too; the buffer is at most a few hundred chars, so the
  // rescan is constant work per delta.
  tail_columns(
    collapse_preview_whitespace(combined),
    StreamingPreviewMaxColumns,
  )
}

///|
/// Apply one agent progress event to `state`, queueing any transcript updates in
/// `cmds`. Terminal events call `finish_run`, leaving the agent idle so the
/// queue drain at the end of `update` can start the next input.
fn handle_agent_event(
  state : State,
  event : @event.AgentEvent,
  cmds : Array[Cmd],
) -> Unit {
  match event {
    AgentStep => {
      state.step_response = None
      state.streaming_preview = None
    }
    // The retried request streams from scratch: drop what the abandoned
    // attempt previewed, so its deltas are not joined onto it.
    StreamRetry => state.streaming_preview = None
    ReasoningDelta(text) =>
      if text != "" && !(state.streaming_preview is Some(Response(_))) {
        let current = match state.streaming_preview {
          Some(Reasoning(current)) => Some(current)
          _ => None
        }
        state.streaming_preview = Some(
          Reasoning(append_streaming_preview(current, text)),
        )
      }
    AssistantDelta(text) =>
      if text != "" {
        let current = match state.streaming_preview {
          Some(Response(current)) => Some(current)
          _ => None
        }
        state.streaming_preview = Some(
          Response(append_streaming_preview(current, text)),
        )
      }
    // The turn's full reasoning, emitted once streaming ends and before the
    // assistant message commits — so the transcript reads thought → answer.
    ReasoningMessage(text) => {
      if state.streaming_preview is Some(Reasoning(_)) {
        state.streaming_preview = None
      }
      if !text.is_blank() {
        cmds.push(AppendItem(reasoning_item(text)))
      }
    }
    // Prompt steering took effect at the engine's step boundary: echo the input
    // into the transcript at its true conversational position, the way the
    // model actually saw it.
    //
    // A `!` command's output is steered the same way but was already shown, as
    // its result card, when the command finished: for it this event is only a
    // delivery acknowledgment, recognized by the tag it was sent with.
    SteerApplied(Prompt(text, submission_id~)) =>
      if state.settle_output(submission_id) is None {
        confirm_pending_steer(state, text)
        cmds.push(AppendItem(Input(Prompt(text))))
      }
    // A notice (e.g. a background job finishing) originates in the engine, not
    // from a pending local steer, so just render it in the transcript — except
    // goal markers, whose steer path is transport: the user-facing
    // confirmation is the goal_updated event that follows the durable append.
    // Idle background notices arrive untagged (as EngineBackgroundNotice),
    // making the tagged BackgroundNotice path unreachable — but render it
    // the same way for completeness.
    SteerApplied(Notice(text)) | BackgroundNotice(text) =>
      if @agent_session.goal_marker(text) is None &&
        @agent_session.parse_goal_baseline(text) is None {
        cmds.push(AppendItem(Input(Notice(text))))
      }
    // Normally unreachable from the wire: the engine client routes
    // steer_dropped events to the untagged message (they always trail the
    // racing turn's terminal, so a run-tagged copy would be stale-filtered).
    // Kept as defense in depth for any future in-run emitter.
    SteerDropped(text, submission_id~) => {
      confirm_pending_steer(state, text)
      steer_dropped(state, text, submission_id, cmds)
    }
    AssistantMessage(text) => {
      state.step_response = Some(text)
      state.streaming_preview = None
      if !text.is_blank() {
        cmds.push(AppendItem(Response(text)))
      }
    }
    SessionError(error) => cmds.push(AppendItem(Error(error)))
    Usage(usage) => state.usage = Some(usage)
    ToolResult(result) => cmds.push(AppendItem(tool_item(result)))
    // Sub-run lifecycle brackets, shown as transcript notices so the child's
    // interleaved tool calls read as belonging to the sub-run. Non-terminal:
    // the outer run stays busy throughout.
    SubrunStarted(kind~, label~) =>
      cmds.push(AppendItem(Input(Notice("\{kind} subrun started: \{label}"))))
    // Counts that are not the child's own account are not shown as if they
    // were: unknown spend is not zero spend.
    SubrunFinished(status~, steps~, unaccounted~) => {
      let spend = match unaccounted {
        Some(_) => "usage unknown"
        None => "\{steps} step(s)"
      }
      cmds.push(
        AppendItem(Input(Notice("subrun finished: \{status} (\{spend})"))),
      )
    }
    AgentFinished(answer) => {
      let already_appended = state.step_response is Some(response) &&
        response == answer
      // `AgentFinished` follows `AssistantMessage` for normal chat responses,
      // but tool-controlled finish results may arrive without one.
      if !already_appended && !answer.is_blank() {
        cmds.push(AppendItem(Response(answer)))
      }
      scheduler_on_run_end(state, LoopRunFinished, cmds)
      state.finish_run()
    }
    AgentAborted(reason) => {
      cmds.push(AppendItem(Error("aborted: \{reason}")))
      scheduler_on_run_end(state, LoopRunFailed("was aborted"), cmds)
      state.finish_run()
    }
    MaxStepsExhausted => {
      cmds.push(AppendItem(Error("max steps exhausted")))
      scheduler_on_run_end(state, LoopRunFailed("hit max steps"), cmds)
      state.finish_run()
    }
    AgentError(message) => {
      cmds.push(AppendItem(Error(message)))
      scheduler_on_run_end(state, LoopRunFailed("errored"), cmds)
      state.finish_run()
    }
    // A rejected control command keeps the engine serving and carries no
    // identity for which command produced it: the engine client stamps it with
    // the mutable `latest_run`, so a delayed rejection of an earlier command
    // can arrive once a later run — including a `/compact` run — is already in
    // flight. With no way to know whether the rejection belongs to the active
    // run, never end a run on it; only surface it, and let the run finish on its own terminal event. The
    // supported serve engine answers `/compact` with `compaction_finished`/
    // `compaction_failed`, so the only command this leaves unacknowledged is one
    // sent to an engine that does not implement it — which the user can cancel.
    CommandRejected(message) =>
      cmds.push(AppendItem(Error("engine rejected command: \{message}")))
    // Compaction landed: the engine summarized the conversation into the durable
    // session. The transcript on screen is unchanged — it is the display, not
    // the model's context — so confirm with a notice that previews the summary
    // now standing in for the prior turns, and close the run.
    CompactionFinished(summary) => {
      cmds.push(AppendItem(compaction_item(summary)))
      state.finish_run()
    }
    // Routed untagged by the engine client — goal updates as
    // `EngineGoalUpdated`, so idle confirmations survive the stale-run guard,
    // and the auto-continue lifecycle as background notices — so they never
    // arrive run-tagged.
    GoalUpdated(_) | GoalContinue(_) | GoalBudgetExhausted => ()
    // Terminal for the run but not task success: surface the continuation
    // guidance the yield answer carries. For a scheduled /loop run the next
    // fire IS the continuation, so a ceiling yield settles the schedule as
    // a completed fire rather than wedging it (codex review).
    ContextYield(answer) => {
      scheduler_on_run_end(state, LoopRunFinished, cmds)
      cmds.push(AppendItem(Response(answer)))
      cmds.push(
        AppendItem(
          Notice(
            ToolCall(
              @doc.Text::plain(
                "context ceiling reached — send a prompt to continue in a new turn",
              ),
            ),
          ),
        ),
      )
      state.finish_run()
    }
  }
}

///|
fn command_notice(title : String) -> @ui.TranscriptItem {
  Notice(ToolCall(@doc.Text::plain(title)))
}

///|
fn handle_compact_command(
  state : State,
  arguments : String,
  cmds : Array[Cmd],
) -> Unit {
  if !arguments.is_blank() {
    cmds.push(AppendItem(Error("/compact does not accept arguments")))
    return
  }
  if !(state.run is Idle) {
    cmds.push(
      AppendItem(
        Error("Context can only be compacted when no task is running."),
      ),
    )
    return
  }
  if state.queued.length() > 0 {
    cmds.push(
      AppendItem(
        Error("Context cannot be compacted with queued input pending."),
      ),
    )
    return
  }
  // Hold the loop busy for the duration: compaction is a model call that can run
  // for many seconds, and a slash command never echoes itself into the
  // transcript, so the notice is the only sign work has begun until it lands.
  cmds.push(AppendItem(command_notice("compacting context…")))
  let run_id = state.start_run(@env.now().reinterpret_as_int64())
  // Mark the run non-steerable: a prompt typed while this is in flight must be
  // queued, not steered into a compaction the engine will refuse it from.
  state.run_is_compaction = true
  cmds.push(CompactSession(run_id~))
}

///|
fn handle_slash_command(
  state : State,
  name : String,
  arguments : String,
  cmds : Array[Cmd],
) -> Unit {
  match name.to_lower() {
    "exit" =>
      if arguments.is_blank() {
        cmds.push(Quit)
      } else {
        cmds.push(AppendItem(Error("/exit does not accept arguments")))
      }
    "compact" => handle_compact_command(state, arguments, cmds)
    "loop" => handle_loop_command(state, arguments, cmds)
    "goal" => handle_goal_command(state, arguments, cmds)
    "inspect" =>
      if arguments.is_blank() {
        cmds.push(AppendItem(Input(Notice("starting the session viewer…"))))
        cmds.push(OpenViewer)
      } else {
        cmds.push(AppendItem(Error("/inspect does not accept arguments")))
      }
    other => cmds.push(AppendItem(Error("Unknown slash command: /\{other}")))
  }
}

///|
/// Start running the `!` command `command` beside the conversation.
///
/// There is no input echo: the result card already shows `$ command` and is
/// the only form persisted, so an echo would double the command line live and
/// diverge from a resumed session, which only re-renders the card.
fn launch_command(
  state : State,
  command : String,
  holds_queue~ : Bool,
  cmds : Array[Cmd],
) -> Unit {
  let id = state.start_command(
    command,
    @env.now().reinterpret_as_int64(),
    holds_queue~,
  )
  cmds.push(RunCommand(id~, command))
}

///|
/// Start the turn that answers the typed prompt `text`.
fn start_prompt(state : State, text : String, cmds : Array[Cmd]) -> Unit {
  let run_id = state.start_run(@env.now().reinterpret_as_int64())
  cmds.push(AppendItem(Input(Prompt(text))))
  cmds.push(StartAgent(run_id~, text))
}

///|
/// Send the output of the finished `!` command `shell` into the conversation,
/// the way a typed message goes: steered into a turn that is running, and
/// otherwise as the prompt of a turn of its own, which the idle check at the
/// end of `update` starts — at once when the conversation is idle, after the
/// compaction or interrupt that is in the way when it is not.
///
/// A steer is tagged and remembered until the engine answers for it: the
/// receipt says whether the output reached the turn, and until it does the
/// output keeps the command's hold on the input queue.
fn send_output(
  state : State,
  shell : ShellCommand,
  envelope : String,
  cmds : Array[Cmd],
) -> Unit {
  if state.run is Running(_) && !state.run_is_compaction {
    let submission_id = "shell-\{shell.id}"
    state.steered_outputs.push({
      submission_id,
      command: shell.command,
      envelope,
      holds_queue: shell.holds_queue,
      interrupted: false,
    })
    cmds.push(SteerOutput(submission_id~, envelope))
  } else {
    state.held_outputs.push({ command: shell.command, envelope, })
  }
}

///|
/// Ctrl-C: give up every `!` output that has not reached the agent. The user
/// asked for everything to stop, and an output that started a turn afterwards
/// would undo that.
///
/// One that is waiting to start a turn is dropped here and now. One that was
/// steered is only marked: its receipt is still to come, and may yet say it
/// reached the turn after all (see `steer_dropped`).
fn abandon_outputs(state : State, cmds : Array[Cmd]) -> Unit {
  for output in state.steered_outputs {
    output.interrupted = true
  }
  for output in state.held_outputs {
    cmds.push(
      AppendItem(output_not_sent_item(output.command, InterruptedFirst)),
    )
  }
  state.held_outputs.clear()
}

///|
/// Why a `!` command's output was given up before it reached the agent.
priv enum NotSent {
  InterruptedFirst
  EngineExitedFirst
}

///|
/// The notice that the output of `command` never reached the agent and will
/// not be sent again. Its card stays on screen either way; this is what says
/// the agent did not read it.
fn output_not_sent_item(command : String, why : NotSent) -> @ui.TranscriptItem {
  let reason = match why {
    InterruptedFirst => "the task was interrupted first"
    EngineExitedFirst => "the engine exited first"
  }
  Input(Notice("The output of `\{command}` was not sent: \{reason}."))
}

///|
/// A steer never reached a turn. Typed text would otherwise vanish silently,
/// so the user is told to submit it again. A `!` command's output — a steer
/// whose tag is one this client is waiting on — is not theirs to retype: it
/// waits for the conversation to be idle and starts a turn then, unless
/// Ctrl-C came while it was out (see `abandon_outputs`). It is held rather
/// than steered again because whatever refused this steer may refuse the
/// next.
fn steer_dropped(
  state : State,
  text : String,
  submission_id : String?,
  cmds : Array[Cmd],
) -> Unit {
  guard state.settle_output(submission_id) is Some(output) else {
    cmds.push(AppendItem(steer_dropped_item(text)))
    return
  }
  if output.interrupted {
    cmds.push(
      AppendItem(output_not_sent_item(output.command, InterruptedFirst)),
    )
  } else {
    state.held_outputs.push({
      command: output.command,
      envelope: output.envelope,
    })
  }
}

///|
fn update(state : State, message : Msg) -> Array[Cmd] {
  let cmds : Array[Cmd] = []
  // Drop task-originated messages that do not belong to the run currently in
  // flight. When a task emits a natural terminal event and is then cancelled in
  // the same window, both messages queue; the first finishes the run and drains
  // the next queued input, and without this guard the second, stale terminal
  // would `finish_run` (and possibly start another task) on top of that new run.
  if message.run_id() is Some(id) && !state.owns_run(id) {
    return cmds
  }
  match message {
    UiInput(event) =>
      match event {
        SlashCommand(name~, arguments~) =>
          handle_slash_command(state, name, arguments, cmds)
        // Enter on a `!` command runs it now, whatever the conversation is
        // doing: it runs beside the conversation, not in its run slot.
        Steer(Command(command)) =>
          launch_command(state, command, holds_queue=false, cmds)
        // A notice is engine-internal, never user-submitted.
        Steer(Notice(_)) => ()
        // Enter while idle starts the turn; Enter while a turn runs steers it
        // — the text is folded into that turn at its next step boundary.
        // Neither waits behind the input queue: Enter means now, Tab means
        // after what is queued.
        Steer(Prompt(text)) =>
          if state.run is Idle {
            start_prompt(state, text, cmds)
          } else if state.run is Interrupting(_) {
            // The turn is being cancelled: a steer sent now could outlive
            // the dying turn in the engine's queue and contaminate a later
            // prompt. Refuse rather than race.
            cmds.push(
              AppendItem(
                Error(
                  "The task is being interrupted and cannot be steered. Press Tab to queue this input.",
                ),
              ),
            )
          } else if state.run_is_compaction {
            // Compaction is a non-steerable model call; the serve engine drops
            // steers during it. Reject locally so the prompt is not lost — the
            // user can queue it to run once compaction lands.
            cmds.push(
              AppendItem(
                Error(
                  "Context is being compacted and cannot be steered. Press Tab to queue this input.",
                ),
              ),
            )
          } else if !text.is_blank() {
            // A blank steer would be filtered engine-side without any
            // settling event, leaving a phantom acknowledgment; there is
            // nothing to say to the model anyway, so it is dropped here.
            //
            // Acknowledge immediately: the transcript echo only comes at the
            // step boundary, but the user pressed Enter *now*.
            state.pending_steers.push(text)
            cmds.push(SteerAgent(text))
          }
        Queue(input) => state.queued.push(input)
        // Ctrl+C stops whatever is running — the turn and every `!` command
        // alike — and gives up every `!` output that has not reached the
        // agent. When nothing is running it quits the TUI (the common "press
        // Ctrl+C to get out" expectation), rather than printing a dead-end
        // "nothing to interrupt" notice. A second Ctrl+C while a turn is
        // already being interrupted escalates from the polite cancel command
        // to killing the engine process; a `!` command has nothing harder
        // than another cancel.
        Interrupt => {
          let stopped_commands = !state.commands.is_empty()
          for shell in state.commands {
            shell.interrupted = true
            cmds.push(CancelCommand(id=shell.id))
          }
          abandon_outputs(state, cmds)
          match state.run {
            Idle => if !stopped_commands { cmds.push(Quit) }
            Running(started_ms) => {
              state.run = Interrupting(started_ms)
              cmds.push(CancelAgent)
            }
            Interrupting(_) => cmds.push(KillEngine)
          }
        }
        Quit => cmds.push(Quit)
      }
    AgentProgress(event, ..) => handle_agent_event(state, event, cmds)
    AgentCancelled(..) => {
      cmds.push(AppendItem(Error("interrupted")))
      scheduler_on_run_end(state, LoopRunFailed("was interrupted"), cmds)
      state.finish_run()
    }
    CommandCancelled(command~, id~) =>
      if state.finish_command(id) is Some(_) {
        cmds.push(AppendItem(command_cancelled_item(command)))
      }
    AgentFailed(error, ..) => {
      cmds.push(AppendItem(Error("agent failed: \{error}")))
      scheduler_on_run_end(state, LoopRunFailed("failed"), cmds)
      state.finish_run()
    }
    CommandResult(command~, id~, result) =>
      if state.finish_command(id) is Some(shell) {
        // The card lands here, at shell-completion time. For a command that
        // ran alongside a live turn that is deliberately *not* the position
        // the engine persists the corresponding user message — it appends that
        // at the turn's next step boundary, so assistant/tool events already
        // in flight can sit after `$ cmd` live but before it on resume. This
        // is intentional: the live transcript is a real-time log (entries
        // appear when they happen), while the durable session reflects
        // model-visible conversational order. Deferring the card to the
        // boundary would leave the user staring at silence for the rest of a
        // long tool call after their command already finished, which the
        // immediate card exists to avoid.
        cmds.push(AppendItem(command_item(command, result)))
        // The output is sent the way a typed message is, and the agent
        // answers it. The card above is that message's only echo, live and on
        // resume alike.
        //
        // Not when there is nothing to answer: the command could not be run,
        // or Ctrl-C reached it as it finished. Its card is then all there is —
        // the conversation never hears of it.
        if result is Ok(_) && !shell.interrupted {
          send_output(
            state,
            shell,
            @command_context.encode(command, result),
            cmds,
          )
        }
      }
    // The steer never reached a turn. Run state is untouched — the run's own
    // death report (or terminal event) settles it.
    SteerDropped(text, submission_id~) => {
      confirm_pending_steer(state, text)
      steer_dropped(state, text, submission_id, cmds)
    }
    // Settles no typed steer's acknowledgment by construction: the rejecting turn's terminal already
    // swept its acknowledgments, and a text match here could only steal a
    // fresh identical-text steer's entry from the next turn.
    EngineSteerDropped(text, submission_id~) =>
      steer_dropped(state, text, submission_id, cmds)
    EngineSessionError(error) => cmds.push(AppendItem(Error(error)))
    // Goal markers are filtered for the same reason as on the steer path:
    // their notice leg is transport, and goal_updated carries the
    // confirmation (defense in depth against engine version skew).
    EngineBackgroundNotice(text) =>
      if @agent_session.goal_marker(text) is None &&
        @agent_session.parse_goal_baseline(text) is None {
        cmds.push(AppendItem(Input(Notice(text))))
      }
    // The engine's durable-append confirmation is the only writer of the
    // mirrored goal state.
    EngineGoalUpdated(goal) => apply_goal_update(state, goal, cmds)
    // No receipt can come from an engine that is gone. The output it was
    // sent is given up, so it cannot hold the queue forever, and the user is
    // told the agent never read it.
    EngineSteerLost(submission_id~) =>
      if state.settle_output(Some(submission_id)) is Some(output) {
        cmds.push(
          AppendItem(output_not_sent_item(output.command, EngineExitedFirst)),
        )
      }
    EngineExited => ()
    // The link gets a line of its own so that, on a wide enough terminal, it
    // stays one unbroken, clickable run of text.
    ViewerOpened(Ok(url)) =>
      cmds.push(AppendItem(Input(Notice("watch this session live:\n\{url}"))))
    ViewerOpened(Err(error)) =>
      cmds.push(
        AppendItem(Error("could not start the session viewer: \{error}")),
      )
    BrowserOpened(outcome) =>
      cmds.push(AppendItem(Input(Notice(browser_notice(outcome)))))
    // Tick is a 1s heartbeat: it keeps the message loop turning so the trailing
    // refresh_ui re-runs (the elapsed-time activity line keeps advancing during
    // quiet stretches) and steps the `/loop` countdown. Bookkeeping only — a
    // due schedule is dispatched at the post-update choke point.
    Tick => scheduler_tick(state)
  }
  // One turn runs at a time: whenever the conversation is idle and something
  // is waiting, start the next turn. A `!` command's output that could not be
  // sent when it was ready goes first — it is older than anything still
  // queued — and has no input echo, its card being on screen already.
  //
  // Then the input queue, unless a command taken from it is still running or
  // its steered output is still unanswered for: the queue waits for that
  // command's output to reach a turn (see `ShellCommand`). A queued
  // prompt starts its turn; a queued `!` command starts running, and leaves
  // the conversation idle. Only submissions and events that end a run or a
  // command can reach "idle with something waiting", so this never fires
  // spuriously.
  if state.run is Idle {
    if state.held_outputs.length() > 0 {
      let output = state.held_outputs.remove(0)
      let run_id = state.start_run(@env.now().reinterpret_as_int64())
      cmds.push(StartAgent(run_id~, output.envelope))
    } else if state.queued.length() > 0 &&
      !state.commands.any(shell => shell.holds_queue) &&
      !state.steered_outputs.any(output => output.holds_queue) {
      match state.queued.remove(0) {
        Prompt(text) => start_prompt(state, text, cmds)
        Command(command) =>
          launch_command(state, command, holds_queue=true, cmds)
        // A notice is engine-internal, never a user-submitted queued input.
        Notice(_) => ()
      }
    }
  }
  cmds
}

///|
async fn[G] run_message_loop(
  state : State,
  ui : @ui.Ui,
  group : @async.TaskGroup[G],
  messages : @async.Queue[Msg],
) -> Unit {
  // The persistent serve-mode engine connection: one process serves every
  // prompt of this TUI session. Prompts, steers, and cancels are commands on
  // its stdin; a `!` shell command is a local task, kept in `command_tasks`
  // under its id so an interrupt can cancel it directly.
  let engine = EngineClient(state.config, messages)
  let command_tasks : Map[Int32, @async.Task[Unit]] = Map([])
  outer~: for ;; {
    // Apply every message already enqueued before deciding anything further:
    // `read_event` resets the composer before its UiInput reaches this queue,
    // so a due `/loop` fire deciding on composer emptiness alone could
    // overtake a just-pressed Enter still in flight (or a `/loop pause` racing
    // the very fire it meant to prevent). Updates are synchronous — nothing
    // new can arrive mid-drain — so after the drain the queue is provably
    // empty and the composer check cannot contradict pending input.
    let cmds : Array[Cmd] = []
    for message = messages.get() {
      cmds.append(update(state, message))
      match messages.try_get() {
        Some(next) => continue next
        None => break
      }
    }
    // The `/loop` dispatch choke point: runs once per drained batch, after
    // lifecycle changes are applied and queued input has drained, with the one
    // gate `update` cannot see — whether the user has draft text in the
    // composer. A due fire appends its StartAgent here.
    scheduler_maybe_fire(state, input_idle=ui.input_idle(), cmds)
    for cmd in cmds {
      match cmd {
        AppendItem(item) => ui.append_item(item)
        StartAgent(run_id~, task) => engine.prompt(group, run_id, task)
        RunCommand(id~, command) =>
          command_tasks[id] = group.spawn(no_wait=true) <| () => {
            run_shell_command(command, messages, id~, cwd=state.config.cwd)
          }
        // Absent once the command has reported: a repeated Ctrl-C then has
        // nothing left to cancel.
        CancelCommand(id~) =>
          if command_tasks.get(id) is Some(task) {
            task.cancel()
          }
        SteerAgent(text) => engine.steer(text)
        SteerOutput(submission_id~, envelope) =>
          engine.steer(envelope, submission_id~)
        UpdateGoal(goal) => engine.goal(group, goal)
        OpenViewer => {
          let session_root = state.config.session_root
          let session = state.config.session_id.value()
          group.spawn_bg(no_wait=true) <| () => {
            let result = try open_viewer(session_root, session) catch {
              error => Err("\{error}")
            } noraise {
              url => Ok(url)
            }
            messages.put(ViewerOpened(result))
            // The link is in the transcript first, so it is there to use
            // whatever happens to the browser.
            if result is Ok(url) {
              messages.put(BrowserOpened(@open_in_browser.open(url)))
            }
          }
        }
        CompactSession(run_id~) => engine.compact(group, run_id)
        CancelAgent => engine.cancel_turn()
        KillEngine => engine.kill()
        Quit => {
          // Close the engine's stdin (the serve protocol's shutdown signal) and
          // give it a bounded moment to finish writing what it was already
          // sent to the store and exit.
          engine.shutdown()
          // If the engine failed to persist something (or could not be
          // written to), it emitted a `session_error` the reader turned into
          // an `EngineSessionError`; one may be sitting in the queue as we
          // break, so drain and surface it. Everything else queued is dropped
          // on purpose: a `!` that only finished after we began quitting never
          // had its card rendered (shell output is carded on completion, not
          // streamed), so dropping it is consistent with resume and a
          // deliberate quit has no next turn that needs the output.
          while messages.try_get() is Some(pending) {
            if pending is EngineSessionError(error) {
              ui.append_item(Error(error))
            }
          }
          break outer~
        }
      }
    }
    // A command that has reported is no longer tracked by `state`; drop its
    // task handle with it.
    for id in command_tasks.keys().to_array() {
      if !state.commands.any(shell => shell.id == id) {
        command_tasks.remove(id)
      }
    }
    refresh_ui(ui, state)
  }
}

///|
fn drain_test_state() -> State {
  State({
    api_key: "k",
    api_url: Some("https://proxy.example/v1/chat/completions"),
    model: Deepseek(V4Pro),
    cwd: ".",
    max_steps: Some(10),
    retry_attempts: None,
    retry_backoff_ms: None,
    thinking: Max,
    session_id: SessionId("test"),
    session_root: ".openseek",
    engine: "openseek",
    engine_args_prefix: [],
  })
}

///|
fn start_agent_count(cmds : Array[Cmd]) -> Int32 {
  cmds.count_if(cmd => cmd is StartAgent(_, ..))
}

///|
fn error_item_count(cmds : Array[Cmd]) -> Int32 {
  cmds.count_if(cmd => cmd is AppendItem(Error(_)))
}

///|
fn run_command_count(cmds : Array[Cmd]) -> Int32 {
  cmds.count_if(cmd => cmd is RunCommand(_, ..))
}

///|
/// The envelope a `!` command that printed `output` and exited 0 is sent as.
fn test_envelope(command : String, output : String) -> String {
  @command_context.encode(command, Ok(test_output(output)))
}

///|
fn test_output(text : String) -> @command_context.ShellOutput {
  { exit_code: Some(0), text, output_limit_reached: false, }
}

///|
/// Submit `!command` with Enter and return the id it runs under.
fn enter_command(state : State, command : String) -> Int32 raise {
  guard update(state, UiInput(Steer(Command(command)))) is [RunCommand(id~, _)] else {
    fail("expected the command to start running")
  }
  id
}

///|
fn compact_session_count(cmds : Array[Cmd]) -> Int32 {
  cmds.count_if(cmd => cmd is CompactSession(_))
}

///|
test "engine configuration puts supported placement in argv" {
  let config = drain_test_state().config
  let env = engine_extra_env(config)
  assert_true(env.get("DEEPSEEK") == Some(config.api_key))
  assert_true(env.get("OPENSEEK_THINKING") == Some("max"))
  assert_true(
    env.get("OPENSEEK_API_URL") ==
    Some("https://proxy.example/v1/chat/completions"),
  )
  let kimi_env = engine_extra_env({ ..config, model: Kimi(K27CodeHighSpeed), })
  assert_true(kimi_env.get("KIMI") == Some(config.api_key))
  assert_true(kimi_env.get("DEEPSEEK") is None)
  let glm_env = engine_extra_env({ ..config, model: Glm(G53), })
  assert_true(glm_env.get("GLM") == Some(config.api_key))
  assert_true(glm_env.get("DEEPSEEK") is None)
  // Retry overrides reach the engine only when set.
  assert_true(env.get("OPENSEEK_RETRY_ATTEMPTS") is None)
  let retry_env = engine_extra_env({
    ..config,
    retry_attempts: Some(1),
    retry_backoff_ms: Some(250),
  })
  assert_true(retry_env.get("OPENSEEK_RETRY_ATTEMPTS") == Some("1"))
  assert_true(retry_env.get("OPENSEEK_RETRY_BACKOFF_MS") == Some("250"))
  @debug.assert_eq(config.engine_serve_args(), [
    "serve", "--session=test", "--session-root=.openseek", "--dir=.",
  ])
  @debug.assert_eq(
    { ..config, engine_args_prefix: ["@engine.rsp"], }.engine_serve_args(),
    [
      "@engine.rsp", "serve", "--session=test", "--session-root=.openseek", "--dir=.",
    ],
  )
  @debug.assert_eq(
    {
      ..config,
      cwd: "--workspace",
      session_id: SessionId("--resume"),
      session_root: "--store",
    }.engine_serve_args(),
    [
      "serve", "--session=--resume", "--session-root=--store", "--dir=--workspace",
    ],
  )
}

///|
test "agent engine env preserves unrelated inherited values" {
  let inherited = {
    "CUSTOM_PARENT_SETTING": "keep",
    "OPENSEEK_API_URL": "https://parent.example/chat/completions",
    "PATH": "/bin",
  }
  let env = engine_env(drain_test_state().config, inherited)
  assert_true(env.get("PATH") == Some("/bin"))
  assert_true(env.get("CUSTOM_PARENT_SETTING") == Some("keep"))
  assert_true(
    env.get("OPENSEEK_API_URL") ==
    Some("https://proxy.example/v1/chat/completions"),
  )
  assert_true(inherited.get("PATH") == Some("/bin"))
}

///|
test "agent engine env clears inherited api url without override" {
  let config = { ..drain_test_state().config, api_url: None, }
  let env = engine_env(config, {
    "OPENSEEK_API_URL": "https://parent.example/chat/completions",
  })
  assert_true(env.get("OPENSEEK_API_URL") == Some(""))
}

///|
test "exit slash command quits" {
  let state = drain_test_state()
  let cmds = update(state, UiInput(SlashCommand(name="exit", arguments="")))
  assert_eq(quit_count(cmds), 1)

  let rejected = update(
    state,
    UiInput(SlashCommand(name="exit", arguments="now")),
  )
  assert_eq(quit_count(rejected), 0)
  assert_eq(error_item_count(rejected), 1)
}

///|
test "compact slash command starts a compaction run when idle" {
  let state = drain_test_state()
  let cmds = update(state, UiInput(SlashCommand(name="compact", arguments="")))
  assert_eq(compact_session_count(cmds), 1)
  assert_eq(error_item_count(cmds), 0)
  // The run is held busy so a concurrent prompt cannot interleave with the
  // engine's compaction, and so the activity line shows work in progress.
  assert_false(state.run is Idle)
  // The start notice precedes the command, so the compaction is the tail.
  guard cmds is [_, CompactSession(run_id~)] else {
    fail("expected a compaction command")
  }
  assert_true(state.owns_run(run_id))

  // A second compact while the first is still running is refused, not queued.
  let busy = update(state, UiInput(SlashCommand(name="compact", arguments="")))
  assert_eq(compact_session_count(busy), 0)
  assert_eq(error_item_count(busy), 1)

  // The engine's terminal event closes the run and previews the new context.
  let done = update(
    state,
    AgentProgress(run_id~, CompactionFinished("- goal: ship /compact")),
  )
  assert_eq(compact_session_count(done), 0)
  guard done is [AppendItem(Notice(_))] else {
    fail("expected a compaction preview notice")
  }
  assert_true(state.run is Idle)
}

///|
test "a prompt during compaction is rejected locally, not steered" {
  let state = drain_test_state()
  let started = update(
    state,
    UiInput(SlashCommand(name="compact", arguments="")),
  )
  guard started is [_, CompactSession(_)] else {
    fail("expected compaction to start")
  }
  assert_true(state.run_is_compaction)

  // Enter with a prompt must not steer (the engine drops steers during
  // compaction); it is rejected locally so the text is not lost.
  let steered = update(state, UiInput(Steer(Prompt("hello"))))
  assert_eq(error_item_count(steered), 1)
  assert_true(steered.all(cmd => !(cmd is SteerAgent(_))))
  assert_eq(state.pending_steers.length(), 0)

  // Tab queues it instead, to run once compaction lands.
  let _ = update(state, UiInput(Queue(Prompt("hello"))))
  assert_eq(state.queued.length(), 1)

  // When compaction finishes the queued prompt drains and starts.
  let done = update(
    state,
    AgentProgress(run_id=state.run_id, CompactionFinished("summary")),
  )
  assert_false(state.run_is_compaction)
  assert_eq(start_agent_count(done), 1)
}

///|
test "a rejected command surfaces an error without ending the run in flight" {
  // A command_error carries no identity for which command was rejected (it is
  // stamped with the mutable latest_run), so a delayed rejection of an earlier
  // command must never end the run currently in flight — only surface it.
  // During a /compact run: the rejection does not end it; the real terminal
  // event still does.
  let compacting = drain_test_state()
  let started = update(
    compacting,
    UiInput(SlashCommand(name="compact", arguments="")),
  )
  guard started is [_, CompactSession(run_id~)] else {
    fail("expected compaction to start")
  }
  let rejected = update(
    compacting,
    AgentProgress(run_id~, CommandRejected("unknown command: steer")),
  )
  assert_eq(error_item_count(rejected), 1)
  assert_false(compacting.run is Idle)
  let _ = update(
    compacting,
    AgentProgress(run_id~, CompactionFinished("summary")),
  )
  assert_true(compacting.run is Idle)

  // During an ordinary prompt turn, a rejected command (e.g. the context sent
  // after a `!` shell command) must not terminate the turn it has nothing to do
  // with — surface it, but keep the run active so its real output still lands.
  let prompting = drain_test_state()
  let _ = update(prompting, UiInput(Steer(Prompt("work"))))
  guard prompting.run is Running(_) else { fail("expected a running prompt") }
  let run_id = prompting.run_id
  let noise = update(
    prompting,
    AgentProgress(run_id~, CommandRejected("unknown command: steer")),
  )
  assert_eq(error_item_count(noise), 1)
  assert_true(prompting.run is Running(_))
}

///|
test "compact slash command rejects arguments and pending work" {
  let with_args = drain_test_state()
  let rejected = update(
    with_args,
    UiInput(SlashCommand(name="compact", arguments="now")),
  )
  assert_eq(error_item_count(rejected), 1)
  assert_eq(compact_session_count(rejected), 0)
  assert_true(with_args.run is Idle)

  let queued_state = drain_test_state()
  queued_state.queued.push(Prompt("later"))
  let queued_cmds : Array[Cmd] = []
  handle_compact_command(queued_state, "", queued_cmds)
  assert_eq(error_item_count(queued_cmds), 1)
  assert_eq(compact_session_count(queued_cmds), 0)
}

///|
test "unknown slash command reports an error" {
  let state = drain_test_state()
  let cmds = update(state, UiInput(SlashCommand(name="unknown", arguments="")))
  assert_eq(error_item_count(cmds), 1)
  assert_true(state.run is Idle)
}

///|
test "a submitted shell command runs locally, beside the conversation" {
  let state = drain_test_state()
  // A `!` command is a local RunCommand, never the agent engine's, and it does
  // not take the run slot: the conversation stays idle while it runs.
  let cmds = update(state, UiInput(Steer(Command("ls"))))
  assert_eq(run_command_count(cmds), 1)
  assert_eq(start_agent_count(cmds), 0)
  assert_true(state.run is Idle)
  assert_eq(state.commands.length(), 1)
}

///|
test "queued input drains exactly when the agent is idle" {
  let state = drain_test_state()

  // Submit while idle: starts immediately, nothing left queued.
  let cmds = update(state, UiInput(Steer(Prompt("a"))))
  assert_true(state.run is Running(_))
  assert_eq(state.queued.length(), 0)
  assert_eq(start_agent_count(cmds), 1)

  // Submit while running: queues, no new agent started.
  let cmds = update(state, UiInput(Queue(Prompt("b"))))
  assert_true(state.run is Running(_))
  assert_eq(state.queued.length(), 1)
  assert_eq(start_agent_count(cmds), 0)

  // A non-terminal progress event must not drain the queue.
  let cmds = update(
    state,
    AgentProgress(run_id=state.run_id, AssistantMessage("thinking")),
  )
  assert_true(state.run is Running(_))
  assert_eq(state.queued.length(), 1)
  assert_eq(start_agent_count(cmds), 0)

  // Agent finishes with one queued: drains "b" and starts it.
  let cmds = update(
    state,
    AgentProgress(run_id=state.run_id, AgentFinished("done-a")),
  )
  assert_true(state.run is Running(_))
  assert_eq(state.queued.length(), 0)
  assert_eq(start_agent_count(cmds), 1)

  // Agent finishes with empty queue: stays idle, nothing started.
  let cmds = update(
    state,
    AgentProgress(run_id=state.run_id, AgentFinished("done-b")),
  )
  assert_true(state.run is Idle)
  assert_eq(state.queued.length(), 0)
  assert_eq(start_agent_count(cmds), 0)
}

///|
test "a stale terminal event from a superseded run is ignored" {
  let state = drain_test_state()

  // Run A starts, and a second input B is queued behind it.
  let _ = update(state, UiInput(Steer(Prompt("a"))))
  let run_a = state.run_id
  let _ = update(state, UiInput(Queue(Prompt("b"))))

  // A finishes: the queue drains and B starts as a new run with a fresh id.
  let _ = update(state, AgentProgress(run_id=run_a, AgentFinished("done-a")))
  assert_true(state.run is Running(_))
  let run_b = state.run_id
  assert_true(run_b != run_a)

  // A late terminal from the already-superseded run A (e.g. an `AgentCancelled`
  // that races a natural finish) must be dropped: it neither finishes B nor
  // drains the queue again.
  let cmds = update(state, AgentCancelled(run_id=run_a))
  assert_eq(cmds.length(), 0)
  assert_true(state.run is Running(_))
  assert_eq(state.run_id, run_b)
}

///|
fn quit_count(cmds : Array[Cmd]) -> Int32 {
  cmds.count_if(cmd => cmd is Quit)
}

///|
test "Ctrl+C quits when idle and interrupts when a task is running" {
  let state = drain_test_state()

  // Idle: an interrupt quits the TUI rather than reporting a dead end.
  let cmds = update(state, UiInput(Interrupt))
  assert_eq(quit_count(cmds), 1)
  assert_eq(error_item_count(cmds), 0)
  assert_true(state.run is Idle)

  // Running: the same interrupt cancels the task instead of quitting.
  let _ = update(state, UiInput(Steer(Prompt("a"))))
  assert_true(state.run is Running(_))
  let cmds = update(state, UiInput(Interrupt))
  assert_eq(quit_count(cmds), 0)
  assert_true(cmds.any(cmd => cmd is CancelAgent))
  assert_true(state.run is Interrupting(_))

  // A second interrupt escalates from the polite cancel command to killing
  // the engine process.
  let cmds = update(state, UiInput(Interrupt))
  assert_true(cmds.any(cmd => cmd is KillEngine))
  assert_eq(quit_count(cmds), 0)

  // Steering a turn that is being cancelled is refused: the text could
  // outlive the dying turn in the engine's queue and contaminate a later
  // prompt.
  let cmds = update(state, UiInput(Steer(Prompt("late idea"))))
  assert_eq(error_item_count(cmds), 1)
  assert_true(cmds.all(cmd => !(cmd is SteerAgent(_))))
}

///|
test "a tick while idle never starts an agent" {
  let state = drain_test_state()
  let cmds = update(state, Tick)
  assert_true(state.run is Idle)
  assert_eq(start_agent_count(cmds), 0)
}

///|
test "steering a running agent sends a steer command" {
  let state = drain_test_state()

  // Idle Steer submits and starts a task.
  let _ = update(state, UiInput(Steer(Prompt("a"))))
  assert_true(state.run is Running(_))
  assert_eq(state.queued.length(), 0)

  // Steer while running: a steer command for the engine — no queueing, no
  // new run, no error. The transcript echo comes later, from the engine's
  // steer_applied event at the boundary where the model actually saw it.
  let cmds = update(state, UiInput(Steer(Prompt("b"))))
  assert_eq(state.queued.length(), 0)
  assert_eq(start_agent_count(cmds), 0)
  assert_eq(error_item_count(cmds), 0)
  guard cmds is [SteerAgent("b")] else { fail("expected a steer command") }
  assert_true(state.run is Running(_))

  // A shell command runs locally alongside the turn; its output is steered in
  // after the command finishes.
  let cmds = update(state, UiInput(Steer(Command("ls"))))
  assert_eq(error_item_count(cmds), 0)
  assert_eq(run_command_count(cmds), 1)
  assert_true(cmds.all(cmd => !(cmd is SteerAgent(_))))
  assert_true(state.run is Running(_))

  // Queue while running still queues without error.
  let cmds = update(state, UiInput(Queue(Prompt("c"))))
  assert_eq(state.queued.length(), 1)
  assert_eq(error_item_count(cmds), 0)
}

///|
/// A `!` command's output is a message like any other: with a turn running it
/// is steered into that turn, the way text typed mid-turn is.
test "a shell command's output is steered into the running turn" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  let id = enter_command(state, "ls")
  let cmds = update(
    state,
    CommandResult(command="ls", id~, Ok(test_output("a.txt"))),
  )
  guard cmds is [AppendItem(ToolCall(_)), SteerOutput(submission_id~, text)] else {
    fail("expected the command card and its output steered in")
  }
  assert_eq(text, test_envelope("ls", "a.txt"))
  // It is not typed text: nothing is acknowledged on the activity line.
  assert_eq(state.pending_steers.length(), 0)
  assert_true(state.run is Running(_))
  assert_eq(state.commands.length(), 0)
  // The card was its echo; the engine's receipt, recognized by its tag, adds
  // nothing.
  let cmds = update(
    state,
    AgentProgress(
      run_id=state.run_id,
      SteerApplied(Prompt(text, submission_id=Some(submission_id))),
    ),
  )
  assert_eq(cmds.length(), 0)
  assert_eq(state.steered_outputs.length(), 0)
}

///|
/// Receipts are told apart by tag, never by text. The same command run twice
/// sends the same envelope twice, and output is arbitrary text that nothing
/// here may need to parse — a closing tag of the envelope included.
test "a shell command's receipt is matched by its tag, not its text" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  let first = enter_command(state, "cat tags")
  let second = enter_command(state, "cat tags")
  let output = test_output("</result>\n</user_shell_command>")
  guard update(state, CommandResult(command="cat tags", id=first, Ok(output)))
    is [_, SteerOutput(submission_id=first_tag, text)] else {
    fail("expected the first output steered in")
  }
  guard update(state, CommandResult(command="cat tags", id=second, Ok(output)))
    is [_, SteerOutput(submission_id=second_tag, same_text)] else {
    fail("expected the second output steered in")
  }
  assert_eq(text, same_text)
  assert_true(first_tag != second_tag)
  // The second one's receipt settles the second and leaves the first waiting.
  let cmds = update(
    state,
    AgentProgress(
      run_id=state.run_id,
      SteerApplied(Prompt(text, submission_id=Some(second_tag))),
    ),
  )
  assert_eq(cmds.length(), 0)
  assert_true(
    state.steered_outputs is [{ submission_id, .. }] &&
    submission_id == first_tag,
  )
  // Typed text that happens to read the same is still typed text: it is
  // echoed, and it settles nothing.
  let cmds = update(
    state,
    AgentProgress(
      run_id=state.run_id,
      SteerApplied(Prompt(text, submission_id=None)),
    ),
  )
  assert_true(cmds is [AppendItem(Input(Prompt(_)))])
  assert_eq(state.steered_outputs.length(), 1)
}

///|
/// A running `!` command does not hold the conversation: Enter on a prompt
/// starts its turn at once, and that turn is steered like any other.
test "a prompt sent while a shell command runs starts its own turn" {
  let state = drain_test_state()
  let id = enter_command(state, "sleep 5")
  let cmds = update(state, UiInput(Steer(Prompt("meanwhile"))))
  guard cmds is [AppendItem(Input(Prompt("meanwhile"))), StartAgent(text, ..)] else {
    fail("expected the prompt's turn")
  }
  assert_eq(text, "meanwhile")
  assert_true(state.run is Running(_))
  assert_true(state.commands.any(shell => shell.id == id))
  let cmds = update(state, UiInput(Steer(Prompt("change of plan"))))
  assert_true(cmds is [SteerAgent("change of plan")])
}

///|
/// Ctrl-C stops whatever is running. A `!` command has no engine behind it,
/// so a second Ctrl-C cancels it again rather than killing anything, and the
/// TUI only quits once nothing is left to stop.
test "Ctrl+C stops running shell commands instead of quitting" {
  let state = drain_test_state()
  let first = enter_command(state, "sleep 100")
  let second = enter_command(state, "sleep 200")
  let cmds = update(state, UiInput(Interrupt))
  assert_true(
    cmds is [CancelCommand(id=a), CancelCommand(id=b)] &&
    a == first &&
    b == second,
  )
  assert_true(state.run is Idle)
  // Until the tasks report, the commands are still there to stop.
  let cmds = update(state, UiInput(Interrupt))
  assert_eq(quit_count(cmds), 0)
  assert_true(cmds.all(cmd => cmd is CancelCommand(..)))
  let _ = update(state, CommandCancelled(command="sleep 100", id=first))
  let _ = update(state, CommandCancelled(command="sleep 200", id=second))
  assert_eq(quit_count(update(state, UiInput(Interrupt))), 1)
}

///|
test "Ctrl+C stops the turn and the shell commands running beside it" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  let id = enter_command(state, "sleep 100")
  let cmds = update(state, UiInput(Interrupt))
  assert_true(cmds is [CancelCommand(id=stopped), CancelAgent] && stopped == id)
  assert_true(state.run is Interrupting(_))
  // The second one escalates on the turn; the command just gets cancelled
  // again.
  let cmds = update(state, UiInput(Interrupt))
  assert_true(cmds is [CancelCommand(..), KillEngine])
}

///|
test "a cancelled shell command survives as a card, not a lost line" {
  let state = drain_test_state()
  let id = enter_command(state, "sleep 100")
  let _ = update(state, UiInput(Interrupt))

  // The cancelled task reports back with no result. The command line must still
  // appear — as a "(cancelled)" card, since it has no input echo — and nothing
  // is sent into the conversation.
  let cmds = update(state, CommandCancelled(command="sleep 100", id~))
  guard cmds is [AppendItem(ToolCall(_))] else {
    fail("expected exactly one cancelled command card, not a lost line")
  }
  assert_true(state.run is Idle)
  assert_eq(state.commands.length(), 0)
  // A second report for the same command is nobody's.
  assert_eq(
    update(state, CommandCancelled(command="sleep 100", id~)).length(),
    0,
  )
}

///|
/// There is nothing for the agent to answer in a command that never ran: its
/// card is all there is, and the conversation never hears of it.
test "a shell command that could not run leaves only its card" {
  let state = drain_test_state()
  let id = enter_command(state, "ls")
  let cmds = update(
    state,
    CommandResult(command="ls", id~, Err(Failure::Failure("boom"))),
  )
  // A spawn failure still renders a command card (not a bare error), so the
  // `$ ls` line survives without an input echo.
  guard cmds is [AppendItem(ToolCall(_))] else {
    fail("expected only the command card")
  }
  assert_true(state.run is Idle)
  assert_eq(state.held_outputs.length(), 0)

  let cmds = update(state, UiInput(Steer(Prompt("what changed?"))))
  guard cmds
    is [AppendItem(Input(Prompt("what changed?"))), StartAgent(text, ..)] else {
    fail("expected prompt transcript item and agent start")
  }
  assert_eq(text, "what changed?")
}

///|
/// A `!` command's output is a message like any other: when nothing else is
/// going on, the agent answers it.
async test "a finished shell command starts the turn that answers it" {
  let state = drain_test_state()
  let id = enter_command(state, "echo hello")
  let messages = @async.Queue(kind=Unbounded)
  run_shell_command("echo hello", messages, id~)
  let cmds = update(state, messages.get())
  // The card is the message's only echo: the prompt itself is not shown.
  guard cmds is [AppendItem(ToolCall(_)), StartAgent(text, ..)] else {
    fail("expected a command card and the turn on its output")
  }
  assert_true(text.contains("<command>\necho hello\n</command>"))
  assert_true(text.contains("hello"))
  assert_true(state.run is Running(_))
  assert_eq(state.commands.length(), 0)
  // It is an engine turn: steering reaches it.
  let cmds = update(state, UiInput(Steer(Prompt("and then?"))))
  assert_true(cmds is [SteerAgent("and then?")])
}

///|
/// Tab means "after this". A `!` command taken from the queue holds the queue
/// until its output has been answered, so the prompt queued behind it is asked
/// of an agent that has read that output.
test "a queued shell command holds the queue until its output is answered" {
  let state = drain_test_state()
  guard update(state, UiInput(Queue(Command("make")))) is [RunCommand(id~, _)] else {
    fail("expected the queued command to start running")
  }
  assert_true(state.run is Idle)
  let cmds = update(state, UiInput(Queue(Prompt("did it pass?"))))
  assert_eq(cmds.length(), 0)
  assert_eq(state.queued.length(), 1)
  // Its output starts a turn; the queued prompt waits for that turn too.
  let cmds = update(
    state,
    CommandResult(command="make", id~, Ok(test_output("ok"))),
  )
  guard cmds is [AppendItem(ToolCall(_)), StartAgent(run_id~, text)] else {
    fail("expected the command card and the turn on its output")
  }
  assert_eq(text, test_envelope("make", "ok"))
  assert_eq(state.queued.length(), 1)
  let cmds = update(state, AgentProgress(run_id~, AgentFinished("built")))
  guard cmds
    is [
      AppendItem(Response("built")),
      AppendItem(Input(Prompt("did it pass?"))),
      StartAgent(text, ..),
    ] else {
    fail("expected the queued prompt's turn")
  }
  assert_eq(text, "did it pass?")
}

///|
/// Only a command the queue itself started holds it: one run with Enter is
/// beside the conversation, and what is queued goes ahead.
test "a shell command run with Enter does not hold the queue" {
  let state = drain_test_state()
  let _ = enter_command(state, "sleep 100")
  let cmds = update(state, UiInput(Queue(Prompt("meanwhile"))))
  assert_eq(start_agent_count(cmds), 1)
  assert_eq(state.queued.length(), 0)
}

///|
/// Ctrl-C says the user does not want this to go on. A command that finishes
/// in the same moment still shows its output, but answers to nobody.
async test "a shell command that finishes while being interrupted starts no turn" {
  let state = drain_test_state()
  let id = enter_command(state, "echo hello")
  let _ = update(state, UiInput(Interrupt))
  let messages = @async.Queue(kind=Unbounded)
  run_shell_command("echo hello", messages, id~)
  let cmds = update(state, messages.get())
  guard cmds is [AppendItem(ToolCall(_))] else {
    fail("expected only the command card")
  }
  assert_true(state.run is Idle)
  assert_eq(state.held_outputs.length(), 0)
}

///|
/// A steer can miss its turn: the turn ends as the output arrives. Typed text
/// is handed back to be submitted again; a command's output is not the user's
/// to retype, so it starts the turn that answers it instead.
test "a shell command's output that misses its turn starts one of its own" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  let id = enter_command(state, "ls")
  guard update(
      state,
      CommandResult(command="ls", id~, Ok(test_output("a.txt"))),
    )
    is [_, SteerOutput(submission_id~, envelope)] else {
    fail("expected the output steered in")
  }
  let _ = update(
    state,
    AgentProgress(run_id=state.run_id, AgentFinished("done")),
  )
  assert_true(state.run is Idle)
  let dropped = EngineSteerDropped(envelope, submission_id=Some(submission_id))
  let cmds = update(state, dropped)
  guard cmds is [StartAgent(text, ..)] else {
    fail("expected the turn on the dropped output, and no resubmit notice")
  }
  assert_eq(text, envelope)
  // A receipt answers for its output once. A second one is nobody's, and
  // reads as a steer this client did not send as an output.
  assert_eq(error_item_count(update(state, dropped)), 1)
}

///|
/// The drop can also arrive once the next turn is under way. The output then
/// waits for that turn rather than being steered again: whatever refused it
/// once may again.
test "a shell command's output dropped into the next turn waits for it" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  let id = enter_command(state, "ls")
  guard update(
      state,
      CommandResult(command="ls", id~, Ok(test_output("a.txt"))),
    )
    is [_, SteerOutput(submission_id~, envelope)] else {
    fail("expected the output steered in")
  }
  let _ = update(
    state,
    AgentProgress(run_id=state.run_id, AgentFinished("done")),
  )
  let _ = update(state, UiInput(Steer(Prompt("next"))))
  let cmds = update(
    state,
    EngineSteerDropped(envelope, submission_id=Some(submission_id)),
  )
  assert_eq(cmds.length(), 0)
  let cmds = update(
    state,
    AgentProgress(run_id=state.run_id, AgentFinished("ok")),
  )
  guard cmds is [AppendItem(Response("ok")), StartAgent(text, ..)] else {
    fail("expected the turn on the held output")
  }
  assert_eq(text, envelope)
}

///|
/// A command taken from the queue holds the queue until its output has
/// reached a turn — not merely until it has been steered. Steered into a turn
/// the user started meanwhile, the output can still miss it, and the drop only
/// arrives after that turn's end: the prompt queued behind the command must
/// not slip in between.
test "a queued shell command holds the queue until its steered output settles" {
  let state = drain_test_state()
  guard update(state, UiInput(Queue(Command("make")))) is [RunCommand(id~, _)] else {
    fail("expected the queued command to start running")
  }
  let _ = update(state, UiInput(Queue(Prompt("did it pass?"))))
  let _ = update(state, UiInput(Steer(Prompt("meanwhile"))))
  let turn = state.run_id
  guard update(state, CommandResult(command="make", id~, Ok(test_output("ok"))))
    is [_, SteerOutput(submission_id~, envelope)] else {
    fail("expected the output steered into the turn in progress")
  }
  // The turn ends before the steer lands. The queued prompt stays put.
  let cmds = update(state, AgentProgress(run_id=turn, AgentFinished("done")))
  assert_eq(start_agent_count(cmds), 0)
  assert_eq(state.queued.length(), 1)
  // The drop brings the output back; it goes first, and the prompt follows it.
  let cmds = update(
    state,
    EngineSteerDropped(envelope, submission_id=Some(submission_id)),
  )
  guard cmds is [StartAgent(run_id~, text)] else {
    fail("expected the turn on the output")
  }
  assert_eq(text, envelope)
  let cmds = update(state, AgentProgress(run_id~, AgentFinished("built")))
  assert_true(
    cmds is [_, AppendItem(Input(Prompt("did it pass?"))), StartAgent(_, ..)],
  )
}

///|
/// An engine that is gone sends no receipt. The output it was sent is given
/// up — said, not silent — and stops holding the queue.
test "a steered output is given up when the engine it was sent to exits" {
  let state = drain_test_state()
  guard update(state, UiInput(Queue(Command("make")))) is [RunCommand(id~, _)] else {
    fail("expected the queued command to start running")
  }
  let _ = update(state, UiInput(Queue(Prompt("did it pass?"))))
  let _ = update(state, UiInput(Steer(Prompt("meanwhile"))))
  let turn = state.run_id
  guard update(state, CommandResult(command="make", id~, Ok(test_output("ok"))))
    is [_, SteerOutput(submission_id~, _)] else {
    fail("expected the output steered into the turn in progress")
  }
  let _ = update(state, AgentProgress(run_id=turn, AgentError("engine exited")))
  assert_eq(state.queued.length(), 1)
  let cmds = update(state, EngineSteerLost(submission_id~))
  guard cmds
    is [
      AppendItem(Input(Notice(notice))),
      AppendItem(Input(Prompt("did it pass?"))),
      StartAgent(_, ..),
    ] else {
    fail("expected the notice, then the queue to go on")
  }
  assert_true(notice.contains("`make`"))
  assert_eq(state.steered_outputs.length(), 0)
  // The loss is reported once per steer; a repeat answers for nothing.
  assert_eq(update(state, EngineSteerLost(submission_id~)).length(), 0)
}

///|
/// An engine's exit, by itself, says nothing about a steered output: only the
/// process it was written to can lose it. One the loop recorded in the same
/// batch as the exit has not been sent yet — its steer then finds no engine,
/// comes back as a local drop, and is sent again like any other. Giving it up
/// at the exit would leave that drop with nothing to match, and report the
/// envelope as typed text.
test "an engine exit alone does not give up an output not yet sent to it" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  let turn = state.run_id
  let id = enter_command(state, "ls")
  guard update(
      state,
      CommandResult(command="ls", id~, Ok(test_output("a.txt"))),
    )
    is [_, SteerOutput(submission_id~, envelope)] else {
    fail("expected the output steered in")
  }
  assert_eq(update(state, EngineExited).length(), 0)
  assert_eq(state.steered_outputs.length(), 1)
  let _ = update(state, AgentProgress(run_id=turn, AgentError("engine exited")))
  let cmds = update(
    state,
    SteerDropped(envelope, submission_id=Some(submission_id)),
  )
  guard cmds is [StartAgent(text, ..)] else {
    fail("expected the turn on the output, and no resubmit error")
  }
  assert_eq(text, envelope)
}

///|
/// Not after Ctrl-C: the turn the output missed is one the user stopped, and
/// starting another on their behalf would undo that.
test "a shell command's output dropped by an interrupted turn is not sent again" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  let id = enter_command(state, "ls")
  guard update(
      state,
      CommandResult(command="ls", id~, Ok(test_output("a.txt"))),
    )
    is [_, SteerOutput(submission_id~, envelope)] else {
    fail("expected the output steered in")
  }
  let _ = update(state, UiInput(Interrupt))
  let _ = update(
    state,
    AgentProgress(run_id=state.run_id, AgentAborted("interrupted")),
  )
  assert_true(state.run is Idle)
  let cmds = update(
    state,
    EngineSteerDropped(envelope, submission_id=Some(submission_id)),
  )
  guard cmds is [AppendItem(Input(Notice(notice)))] else {
    fail("expected a notice and no turn")
  }
  assert_true(notice.contains("`ls`"))
  assert_true(state.run is Idle)
  assert_eq(state.held_outputs.length(), 0)
}

///|
/// The mark is the output's own. A prompt queued behind the interrupted turn
/// starts as soon as that turn ends, before the drop arrives; the output must
/// still be recognized as one the user stopped, and not get a turn after it.
test "an interrupted output stays given up when a queued prompt runs next" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  let turn = state.run_id
  let id = enter_command(state, "ls")
  guard update(
      state,
      CommandResult(command="ls", id~, Ok(test_output("a.txt"))),
    )
    is [_, SteerOutput(submission_id~, envelope)] else {
    fail("expected the output steered in")
  }
  let _ = update(state, UiInput(Queue(Prompt("next"))))
  let _ = update(state, UiInput(Interrupt))
  let cmds = update(
    state,
    AgentProgress(run_id=turn, AgentAborted("interrupted")),
  )
  assert_eq(start_agent_count(cmds), 1)
  let next = state.run_id
  let cmds = update(
    state,
    EngineSteerDropped(envelope, submission_id=Some(submission_id)),
  )
  guard cmds is [AppendItem(Input(Notice(_)))] else {
    fail("expected only the not-sent notice")
  }
  assert_eq(state.held_outputs.length(), 0)
  // Nothing of it is left to start once the queued prompt's turn ends.
  let cmds = update(state, AgentProgress(run_id=next, AgentFinished("ok")))
  assert_eq(start_agent_count(cmds), 0)
  assert_true(state.run is Idle)
}

///|
/// Ctrl-C only marks a steered output: its receipt is still to come, and an
/// applied one means the output did reach the turn. That is settled quietly.
test "an output that reached its turn before Ctrl-C is not reported lost" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  let id = enter_command(state, "ls")
  guard update(
      state,
      CommandResult(command="ls", id~, Ok(test_output("a.txt"))),
    )
    is [_, SteerOutput(submission_id~, envelope)] else {
    fail("expected the output steered in")
  }
  let _ = update(state, UiInput(Interrupt))
  let cmds = update(
    state,
    AgentProgress(
      run_id=state.run_id,
      SteerApplied(Prompt(envelope, submission_id=Some(submission_id))),
    ),
  )
  assert_eq(cmds.length(), 0)
  assert_eq(state.steered_outputs.length(), 0)
}

///|
/// An output waiting out a compaction has not reached the agent either. Ctrl-C
/// on the compaction gives it up there and then, rather than leaving it to
/// start a turn the moment the compaction is out of the way.
test "Ctrl+C on a compaction gives up the output waiting behind it" {
  let state = drain_test_state()
  let _ = update(state, UiInput(SlashCommand(name="compact", arguments="")))
  let compaction = state.run_id
  let id = enter_command(state, "ls")
  let _ = update(
    state,
    CommandResult(command="ls", id~, Ok(test_output("a.txt"))),
  )
  assert_eq(state.held_outputs.length(), 1)
  let cmds = update(state, UiInput(Interrupt))
  guard cmds is [AppendItem(Input(Notice(notice))), CancelAgent] else {
    fail("expected the not-sent notice and the cancel")
  }
  assert_true(notice.contains("`ls`"))
  assert_eq(state.held_outputs.length(), 0)
  let cmds = update(state, AgentCancelled(run_id=compaction))
  assert_eq(start_agent_count(cmds), 0)
  assert_true(state.run is Idle)
  // A command run after the Ctrl-C is new business: its output is sent.
  let id = enter_command(state, "pwd")
  let cmds = update(
    state,
    CommandResult(command="pwd", id~, Ok(test_output("/tmp"))),
  )
  assert_eq(start_agent_count(cmds), 1)
}

///|
/// A compaction cannot be steered, so an output that is ready during one waits
/// for it and then starts its turn.
test "a shell command's output waits out a compaction" {
  let state = drain_test_state()
  let _ = update(state, UiInput(SlashCommand(name="compact", arguments="")))
  let id = enter_command(state, "ls")
  let cmds = update(
    state,
    CommandResult(command="ls", id~, Ok(test_output("a.txt"))),
  )
  guard cmds is [AppendItem(ToolCall(_))] else {
    fail("expected only the command card while compacting")
  }
  let cmds = update(
    state,
    AgentProgress(run_id=state.run_id, CompactionFinished("summary")),
  )
  guard cmds is [AppendItem(_), StartAgent(text, ..)] else {
    fail("expected the compaction notice, then the turn on the output")
  }
  assert_eq(text, test_envelope("ls", "a.txt"))
}

///|
test "a sent steer is acknowledged until the engine settles it" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  assert_eq(state.pending_steers.length(), 0)

  // Enter mid-run: acknowledged immediately, before any engine round trip —
  // this is the only feedback between the keypress and the transcript echo.
  let _ = update(state, UiInput(Steer(Prompt("make it rhyme"))))
  assert_eq(state.pending_steers.length(), 1)
  guard pending_steer_segment(state.pending_steers) is [_, _] else {
    fail("expected an activity-line acknowledgment")
  }

  // The engine confirms: acknowledgment clears, transcript echo appends.
  let _ = update(
    state,
    AgentProgress(
      run_id=state.run_id,
      SteerApplied(Prompt("make it rhyme", submission_id=None)),
    ),
  )
  assert_eq(state.pending_steers.length(), 0)
  assert_eq(pending_steer_segment(state.pending_steers).length(), 0)

  // A dropped steer also clears the acknowledgment (and shows its notice).
  let _ = update(state, UiInput(Steer(Prompt("too late"))))
  assert_eq(state.pending_steers.length(), 1)
  let _ = update(state, SteerDropped("too late", submission_id=None))
  assert_eq(state.pending_steers.length(), 0)

  // A turn ending sweeps anything still unconfirmed.
  let _ = update(state, UiInput(Steer(Prompt("orphaned"))))
  assert_eq(state.pending_steers.length(), 1)
  let _ = update(
    state,
    AgentProgress(run_id=state.run_id, AgentFinished("done")),
  )
  assert_eq(state.pending_steers.length(), 0)
}

///|
test "a trailing drop from a dead turn never steals a fresh acknowledgment" {
  let state = drain_test_state()
  // Turn A is steered, then ends (sweeping its pending entry).
  let _ = update(state, UiInput(Steer(Prompt("task a"))))
  let _ = update(state, UiInput(Steer(Prompt("old steer"))))
  let _ = update(
    state,
    AgentProgress(run_id=state.run_id, AgentFinished("done-a")),
  )
  assert_eq(state.pending_steers.length(), 0)
  // Turn B starts and is steered before A's untagged drop arrives.
  let _ = update(state, UiInput(Steer(Prompt("task b"))))
  let _ = update(state, UiInput(Steer(Prompt("fresh steer"))))
  assert_eq(state.pending_steers.length(), 1)
  // The old turn's wire drop settles nothing of B's — even with identical
  // text, a wire drop's own entries are swept before it is processed.
  let _ = update(state, EngineSteerDropped("old steer", submission_id=None))
  assert_eq(state.pending_steers.length(), 1)
  let _ = update(state, EngineSteerDropped("fresh steer", submission_id=None))
  assert_eq(state.pending_steers.length(), 1)
  assert_eq(state.pending_steers[0], "fresh steer")
}

///|
test "blank steers are neither sent nor acknowledged" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("task"))))
  let cmds = update(state, UiInput(Steer(Prompt("   "))))
  // The engine would filter it without any settling event, so the TUI must
  // not create an acknowledgment that can never clear.
  assert_eq(state.pending_steers.length(), 0)
  assert_true(cmds.all(cmd => !(cmd is SteerAgent(_))))
}

///|
test "a steer_applied event echoes the input into the transcript" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  let cmds = update(
    state,
    AgentProgress(
      run_id=state.run_id,
      SteerApplied(Prompt("make it rhyme", submission_id=None)),
    ),
  )
  guard cmds is [AppendItem(Input(Prompt(text)))] else {
    fail("expected the steered input echoed as a transcript item")
  }
  assert_eq(text, "make it rhyme")
  // The run keeps going: a steer is not a terminal event.
  assert_true(state.run is Running(_))
}

///|
test "a finished subrun shows its steps, or unknown usage when unaccounted" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  let items : Array[@ui.TranscriptItem] = []
  append_items(
    state,
    {
      "event": "subrun_finished",
      "id": "sr-1",
      "status": "captured",
      "steps": 12,
      "prompt_tokens": 34000,
      "completion_tokens": 5600,
    },
    items,
  )
  append_items(
    state,
    {
      "event": "subrun_finished",
      "id": "sr-2",
      "status": "cancelled",
      "steps": 0,
      "prompt_tokens": 0,
      "completion_tokens": 0,
      "unaccounted": "the sub-run was cancelled before its result was read",
    },
    items,
  )
  guard items is [Input(Notice(accounted)), Input(Notice(unknown))] else {
    fail("expected two subrun notices")
  }
  assert_eq(accounted, "subrun finished: captured (12 step(s))")
  // Unknown spend is not zero spend: no "0 step(s)".
  assert_eq(unknown, "subrun finished: cancelled (usage unknown)")
  // Neither ends the outer run.
  assert_true(state.run is Running(_))
}

///|
test "compact_lines strips CRLF so tool output has no stray carriage returns" {
  inspect(compact_lines("a\r\nb\r\nc", 6).join("|"), content="a|b|c")
  // Truncation still works and the kept lines carry no `\r`.
  inspect(
    compact_lines("a\r\nb\r\nc\r\nd\r\ne", 3).join("|"),
    content="a|... +3 lines|e",
  )
}

///|
/// Decode one engine event and run it through `update`, appending any resulting
/// transcript items to `items`. Accumulating into a caller-owned array lets a
/// test replay a whole session and snapshot the rendered transcript at the end.
fn append_items(
  state : State,
  value : Json,
  items : Array[@ui.TranscriptItem],
) -> Unit {
  guard @event.decode_event(value) is Some(event) else { return }
  for cmd in update(state, AgentProgress(run_id=state.run_id, event)) {
    if cmd is AppendItem(item) {
      items.push(item)
    }
  }
}

///|
/// Cancellation bypasses `catch` under async 0.22, so these two check that a
/// Ctrl-C is still reported: the handlers moved to `handle_cancellation`.
async test "a cancelled shell command reports its cancellation" {
  let messages : @async.Queue[Msg] = Queue(kind=Unbounded)
  @async.with_task_group(group => {
    let task = group.spawn(() => run_shell_command("sleep 10", messages, id=7))
    @async.sleep(200)
    task.cancel()
  })
  guard messages.try_get() is Some(CommandCancelled(command~, id=7)) else {
    fail("expected CommandCancelled")
  }
  assert_eq(command, "sleep 10")
}

///|
async test "a shell command runs locally and posts its output" {
  let messages = @async.Queue(kind=Unbounded)
  // `echo` is the same on POSIX `sh` and Windows `pwsh`, so the platform shell
  // `@command_context.collect_shell_output` picks runs this on either.
  run_shell_command("echo hello", messages, id=1)
  // The only message is the local command result: a completed tool item titled
  // with the command, its stdout as a dimmed detail line. Nothing is sent to the
  // engine.
  let item = match messages.get() {
    CommandResult(command~, result, ..) => {
      assert_eq(command, "echo hello")
      command_item(command, result)
    }
    _ => fail("expected a CommandResult")
  }
  debug_inspect(
    item,
    content=(
      #|ToolCall(
      #|  {
      #|    title: {
      #|      spans: [
      #|        {
      #|          display: {
      #|            text: "$ echo hello",
      #|            units: [
      #|              {
      #|                text: <StringView: "$">,
      #|                width: 1,
      #|                textual_end: TextualPosition(1),
      #|                display_end: DisplayPosition(1),
      #|              },
      #|              {
      #|                text: <StringView: " ">,
      #|                width: 1,
      #|                textual_end: TextualPosition(2),
      #|                display_end: DisplayPosition(2),
      #|              },
      #|              {
      #|                text: <StringView: "e">,
      #|                width: 1,
      #|                textual_end: TextualPosition(3),
      #|                display_end: DisplayPosition(3),
      #|              },
      #|              {
      #|                text: <StringView: "c">,
      #|                width: 1,
      #|                textual_end: TextualPosition(4),
      #|                display_end: DisplayPosition(4),
      #|              },
      #|              {
      #|                text: <StringView: "h">,
      #|                width: 1,
      #|                textual_end: TextualPosition(5),
      #|                display_end: DisplayPosition(5),
      #|              },
      #|              {
      #|                text: <StringView: "o">,
      #|                width: 1,
      #|                textual_end: TextualPosition(6),
      #|                display_end: DisplayPosition(6),
      #|              },
      #|              {
      #|                text: <StringView: " ">,
      #|                width: 1,
      #|                textual_end: TextualPosition(7),
      #|                display_end: DisplayPosition(7),
      #|              },
      #|              {
      #|                text: <StringView: "h">,
      #|                width: 1,
      #|                textual_end: TextualPosition(8),
      #|                display_end: DisplayPosition(8),
      #|              },
      #|              {
      #|                text: <StringView: "e">,
      #|                width: 1,
      #|                textual_end: TextualPosition(9),
      #|                display_end: DisplayPosition(9),
      #|              },
      #|              {
      #|                text: <StringView: "l">,
      #|                width: 1,
      #|                textual_end: TextualPosition(10),
      #|                display_end: DisplayPosition(10),
      #|              },
      #|              {
      #|                text: <StringView: "l">,
      #|                width: 1,
      #|                textual_end: TextualPosition(11),
      #|                display_end: DisplayPosition(11),
      #|              },
      #|              {
      #|                text: <StringView: "o">,
      #|                width: 1,
      #|                textual_end: TextualPosition(12),
      #|                display_end: DisplayPosition(12),
      #|              },
      #|            ],
      #|            width: 12,
      #|            cjk: false,
      #|          },
      #|          style: { foreground: Default, background: Default, underline: false },
      #|        },
      #|      ],
      #|    },
      #|    status: Some(Completed),
      #|    details: [
      #|      {
      #|        spans: [
      #|          {
      #|            display: {
      #|              text: "hello",
      #|              units: [
      #|                {
      #|                  text: <StringView: "h">,
      #|                  width: 1,
      #|                  textual_end: TextualPosition(1),
      #|                  display_end: DisplayPosition(1),
      #|                },
      #|                {
      #|                  text: <StringView: "e">,
      #|                  width: 1,
      #|                  textual_end: TextualPosition(2),
      #|                  display_end: DisplayPosition(2),
      #|                },
      #|                {
      #|                  text: <StringView: "l">,
      #|                  width: 1,
      #|                  textual_end: TextualPosition(3),
      #|                  display_end: DisplayPosition(3),
      #|                },
      #|                {
      #|                  text: <StringView: "l">,
      #|                  width: 1,
      #|                  textual_end: TextualPosition(4),
      #|                  display_end: DisplayPosition(4),
      #|                },
      #|                {
      #|                  text: <StringView: "o">,
      #|                  width: 1,
      #|                  textual_end: TextualPosition(5),
      #|                  display_end: DisplayPosition(5),
      #|                },
      #|              ],
      #|              width: 5,
      #|              cjk: false,
      #|            },
      #|            style: {
      #|              foreground: Basic(BrightBlack),
      #|              background: Default,
      #|              underline: false,
      #|            },
      #|          },
      #|        ],
      #|      },
      #|    ],
      #|  },
      #|)
    ),
  )
}

///|
test "a stream retry drops the abandoned attempt's preview" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  let items : Array[@ui.TranscriptItem] = []
  append_items(
    state,
    { "event": "assistant_delta", "content": "half an ans" },
    items,
  )
  append_items(
    state,
    {
      "event": "stream_retry",
      "attempt": 1,
      "max_attempts": 3,
      "reason": "connection reset",
    },
    items,
  )
  assert_true(state.streaming_preview is None)
  append_items(state, { "event": "assistant_delta", "content": "Hello" }, items)
  assert_true(state.streaming_preview is Some(Response("Hello")))
  assert_eq(items.length(), 0)
}

///|
test "assistant_delta accumulates live text and commits only the final message" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  let items : Array[@ui.TranscriptItem] = []
  append_items(state, { "event": "assistant_delta", "content": "Hel" }, items)
  append_items(state, { "event": "assistant_delta", "content": "lo" }, items)
  assert_eq(items.length(), 0)
  assert_true(state.streaming_preview is Some(Response("Hello")))
  assert_true(state.step_response is None)
  append_items(
    state,
    { "event": "assistant_message", "content": "Hello" },
    items,
  )
  assert_true(state.streaming_preview is None)
  assert_true(state.step_response is Some("Hello"))
  append_items(state, { "event": "agent_finished", "answer": "Hello" }, items)
  debug_inspect(items, content="[Response(\"Hello\")]")
}

///|
test "assistant_message clears live streaming text while tools continue" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  let items : Array[@ui.TranscriptItem] = []
  append_items(
    state,
    { "event": "assistant_delta", "content": "Need tool" },
    items,
  )
  assert_true(state.streaming_preview is Some(Response("Need tool")))
  append_items(
    state,
    { "event": "assistant_message", "content": "Need tool" },
    items,
  )
  assert_true(state.run is Running(_))
  assert_true(state.streaming_preview is None)
  assert_true(state.step_response is Some("Need tool"))
  assert_eq(items.length(), 1)
}

///|
test "assistant_delta live preview keeps the newest tail within the cap" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  let items : Array[@ui.TranscriptItem] = []
  append_items(
    state,
    {
      "event": "assistant_delta",
      "content": String::make(StreamingPreviewMaxColumns * 4, 'x'),
    },
    items,
  )
  guard state.streaming_preview is Some(Response(first)) else {
    fail("expected streaming preview")
  }
  assert_true(
    @displaytext.DisplayText(first).width() <= StreamingPreviewMaxColumns,
  )
  assert_true(first.has_prefix("…"))
  // The preview is a tail window: new deltas keep showing up at its end
  // (instead of freezing once the cap is reached, as a head truncation would).
  append_items(state, { "event": "assistant_delta", "content": "more" }, items)
  guard state.streaming_preview is Some(Response(second)) else {
    fail("expected streaming preview")
  }
  assert_true(second.has_suffix("more"))
  assert_true(
    @displaytext.DisplayText(second).width() <= StreamingPreviewMaxColumns,
  )
  assert_eq(items.length(), 0)
}

///|
test "streamed newlines collapse so the preview stays one line" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  let items : Array[@ui.TranscriptItem] = []
  append_items(
    state,
    { "event": "assistant_delta", "content": "fn main {\n" },
    items,
  )
  append_items(
    state,
    { "event": "assistant_delta", "content": "  println(1)\n}" },
    items,
  )
  // The run of newline + indentation spanning the two deltas collapses to a
  // single space; the preview holds no control characters.
  assert_true(
    state.streaming_preview is Some(Response("fn main { println(1) }")),
  )
}

///|
test "reasoning streams live, then commits one thought item" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  let items : Array[@ui.TranscriptItem] = []
  append_items(
    state,
    { "event": "reasoning_delta", "content": "Let me" },
    items,
  )
  append_items(
    state,
    { "event": "reasoning_delta", "content": " think" },
    items,
  )
  assert_true(state.streaming_preview is Some(Reasoning("Let me think")))
  assert_eq(items.length(), 0)
  // The turn's reasoning lands as one `✻` thought item.
  append_items(
    state,
    {
      "event": "reasoning_message",
      "content": "Let me think about names.\nThe user said Hongbo.",
    },
    items,
  )
  assert_true(state.streaming_preview is None)
  guard items is [Thought(_)] else { fail("expected a single Thought item") }
  // Blank reasoning never appends an empty aside.
  append_items(
    state,
    { "event": "reasoning_delta", "content": "unused" },
    items,
  )
  append_items(state, { "event": "reasoning_message", "content": "  " }, items)
  assert_true(state.streaming_preview is None)
  assert_eq(items.length(), 1)
}

///|
test "late reasoning cannot replace a live response preview" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  let items : Array[@ui.TranscriptItem] = []
  append_items(
    state,
    { "event": "reasoning_delta", "content": "thinking" },
    items,
  )
  append_items(
    state,
    { "event": "assistant_delta", "content": "answer" },
    items,
  )
  append_items(state, { "event": "reasoning_delta", "content": " late" }, items)
  assert_true(state.streaming_preview is Some(Response("answer")))
  assert_eq(items.length(), 0)
}

///|
test "replaying a recorded engine session renders the transcript" {
  let state = drain_test_state()
  // Submit a task so the agent is running before progress arrives.
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  assert_true(state.run is Running(_))

  // A realistic one-step session: think, report usage, run a tool, finish.
  let items : Array[@ui.TranscriptItem] = []
  append_items(state, { "event": "agent_step", "step": 1 }, items)
  append_items(
    state,
    { "event": "assistant_message", "content": "Let me check the project." },
    items,
  )
  append_items(
    state,
    {
      "event": "usage",
      "usage": {
        "prompt_tokens": 100,
        "completion_tokens": 20,
        "total_tokens": 120,
        "prompt_cache_hit_tokens": 0,
        "prompt_cache_miss_tokens": 100,
      },
    },
    items,
  )
  append_items(
    state,
    {
      "event": "tool_result",
      "tool_call_id": "c1",
      "tool_name": "bash",
      "is_error": false,
      "content": "ok",
    },
    items,
  )
  append_items(
    state,
    { "event": "agent_finished", "answer": "all done" },
    items,
  )

  // The rendered transcript: the assistant message, the tool result, and the
  // final answer. `agent_step` and `usage` update state without emitting items.
  debug_inspect(
    items,
    content=(
      #|[
      #|  Response("Let me check the project."),
      #|  ToolCall(
      #|    {
      #|      title: {
      #|        spans: [
      #|          {
      #|            display: {
      #|              text: "Tool bash",
      #|              units: [
      #|                {
      #|                  text: <StringView: "T">,
      #|                  width: 1,
      #|                  textual_end: TextualPosition(1),
      #|                  display_end: DisplayPosition(1),
      #|                },
      #|                {
      #|                  text: <StringView: "o">,
      #|                  width: 1,
      #|                  textual_end: TextualPosition(2),
      #|                  display_end: DisplayPosition(2),
      #|                },
      #|                {
      #|                  text: <StringView: "o">,
      #|                  width: 1,
      #|                  textual_end: TextualPosition(3),
      #|                  display_end: DisplayPosition(3),
      #|                },
      #|                {
      #|                  text: <StringView: "l">,
      #|                  width: 1,
      #|                  textual_end: TextualPosition(4),
      #|                  display_end: DisplayPosition(4),
      #|                },
      #|                {
      #|                  text: <StringView: " ">,
      #|                  width: 1,
      #|                  textual_end: TextualPosition(5),
      #|                  display_end: DisplayPosition(5),
      #|                },
      #|                {
      #|                  text: <StringView: "b">,
      #|                  width: 1,
      #|                  textual_end: TextualPosition(6),
      #|                  display_end: DisplayPosition(6),
      #|                },
      #|                {
      #|                  text: <StringView: "a">,
      #|                  width: 1,
      #|                  textual_end: TextualPosition(7),
      #|                  display_end: DisplayPosition(7),
      #|                },
      #|                {
      #|                  text: <StringView: "s">,
      #|                  width: 1,
      #|                  textual_end: TextualPosition(8),
      #|                  display_end: DisplayPosition(8),
      #|                },
      #|                {
      #|                  text: <StringView: "h">,
      #|                  width: 1,
      #|                  textual_end: TextualPosition(9),
      #|                  display_end: DisplayPosition(9),
      #|                },
      #|              ],
      #|              width: 9,
      #|              cjk: false,
      #|            },
      #|            style: { foreground: Default, background: Default, underline: false },
      #|          },
      #|        ],
      #|      },
      #|      status: Some(Completed),
      #|      details: [
      #|        {
      #|          spans: [
      #|            {
      #|              display: {
      #|                text: "ok",
      #|                units: [
      #|                  {
      #|                    text: <StringView: "o">,
      #|                    width: 1,
      #|                    textual_end: TextualPosition(1),
      #|                    display_end: DisplayPosition(1),
      #|                  },
      #|                  {
      #|                    text: <StringView: "k">,
      #|                    width: 1,
      #|                    textual_end: TextualPosition(2),
      #|                    display_end: DisplayPosition(2),
      #|                  },
      #|                ],
      #|                width: 2,
      #|                cjk: false,
      #|              },
      #|              style: {
      #|                foreground: Basic(BrightBlack),
      #|                background: Default,
      #|                underline: false,
      #|              },
      #|            },
      #|          ],
      #|        },
      #|      ],
      #|    },
      #|  ),
      #|  Response("all done"),
      #|]
    ),
  )
  match state.usage {
    Some(usage) => assert_eq(usage.total_tokens, 120)
    None => fail("usage not recorded")
  }
  // The terminal event left the agent idle.
  assert_true(state.run is Idle)
}
