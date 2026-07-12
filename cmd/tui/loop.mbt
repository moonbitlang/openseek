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
const StderrCaptureLimitBytes : Int = 8192

///|
/// Per-read size while draining stderr past the cap. The retained bytes are
/// bounded by the remaining budget so the buffer never overshoots; once full we
/// keep reading in blocks this size only to drain the pipe, discarding them.
const StderrDrainChunkBytes : Int = 4096

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
      error if @async.is_being_cancelled() ||
        @async.is_cancellation_error(error) => raise error
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
  code : Int,
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
    "OPENSEEK_SESSION": config.session_id.value(),
    "OPENSEEK_SESSION_ROOT": config.session_root,
    "OPENSEEK_DIR": config.cwd,
  }
  // Absent means context-bounded turns: the variable must be OMITTED, not
  // set to "" — the engine treats an empty value as a parse error.
  if config.max_steps is Some(max_steps) {
    env["OPENSEEK_MAX_STEPS"] = max_steps.to_string()
  }
  let api_key_env = match config.model {
    Kimi(_) => "KIMI"
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
  // The merge overwrites every OpenSeek setting — including the always-present
  // session id — so inherited session vars can never shadow this TUI's config.
  let env = inherited.copy()
  env.merge_in_place(engine_extra_env(config))
  env
}

///|
/// Spawn the agent engine for one input and stream its JSONL stdout into the
/// message loop.
///
/// The engine is a separate process (`config.engine`, default `openseek` or
/// `tcc @<generated-response-file>` under Moon's debug native runner): it runs
/// the task and writes one JSON event per line to stdout. `@jsonl.each`
/// reads those lines, skips blanks, and parses each as JSON; we map the value to
/// an `AgentEvent` and forward it as `AgentProgress`. If the engine closes its
/// stream without a terminal event (it crashed, or exited before answering), we
/// synthesize an `AgentError` so the loop never hangs waiting for a result that
/// will not come.
async fn run_agent_task(
  config : AppConfig,
  run_id : Int,
  task : String,
  messages : @async.Queue[Msg],
) -> Unit {
  @async.with_task_group(group => {
    let (reader, child_stdout) = @process.read_from_process()
    let (stderr_reader, child_stderr) = @process.read_from_process()
    let child_env = engine_env(config, @env.get_env_vars())
    let proc = @process.spawn(
      group,
      config.engine,
      // The queued task is already prompt text here; `run` is the engine's
      // headless one-shot subcommand. Forward the task after a `--` delimiter
      // so the engine's argparse treats any leading `-`/`--` as the task
      // positional rather than parsing it as one of its own options (which
      // would exit/print help and never emit a terminal JSONL event). Session
      // settings go through a fully materialized environment so custom replay
      // engines do not need to accept OpenSeek-specific flags, and inherited
      // session vars cannot shadow explicit TUI config.
      config.engine_args(["run", "--", task]),
      inherit_env=false,
      extra_env=child_env,
      stdout=child_stdout,
      stderr=child_stderr,
    )
    // Drain the engine's stderr concurrently with stdout. Capturing it (rather
    // than letting it inherit the terminal) keeps diagnostics from corrupting
    // the screen `@ui.with_ui` is drawing, and lets us surface them if the
    // engine dies without a terminal event. The drain is bounded: a misbehaving
    // engine (crash loop, verbose build log) could write unbounded stderr, so we
    // keep only a capped prefix in memory while still reading to EOF.
    // `drain_stderr_capped` folds any read error into its returned text and only
    // raises on cancellation, which should tear the whole group down — so there
    // is nothing to swallow here.
    let stderr_task = group.spawn(no_wait=true) <| () => {
      drain_stderr_capped(stderr_reader)
    }
    let mut saw_terminal = false
    // A malformed (non-JSON) line raises out of `each`. The only such output is
    // a runtime crash dump, so rather than surface a parse error we stop reading
    // and let the exit code below explain the failure. Cancellation is re-raised
    // to the outer handler so a Ctrl-C still reports `AgentCancelled`.
    // `each`'s callback is synchronous, so enqueue with `try_put` (the queue
    // is unbounded, so it never rejects) rather than the async `put`.
    @jsonl.each(reader, json => {
      if @event.decode_event(json) is Some(event) {
        if is_terminal_event(event) {
          saw_terminal = true
        }
        messages.try_put(AgentProgress(run_id~, event)) |> ignore
      }
    }) catch {
      error if @async.is_being_cancelled() ||
        @async.is_cancellation_error(error) => raise error
      // Protocol violation: stop reading and kill the child instead of waiting
      // for it. If the engine keeps writing past the bad line, nobody is
      // draining its stdout, so a plain `proc.wait()` could deadlock on a full
      // pipe. `cancel()` sends SIGTERM (then SIGKILL) so `wait()` returns.
      _ => proc.cancel()
    }
    // We are done reading; close the read end so the child sees EOF/EPIPE
    // rather than blocking on a pipe we no longer drain.
    reader.close()
    let code = proc.wait()
    if !saw_terminal {
      // The engine produced no terminal event. Its stderr is the only clue to
      // why (a crash, a network/API error), so fold it into the reported error.
      let diagnostics = stderr_task.wait().trim()
      messages.put(
        AgentProgress(run_id~, engine_exit_without_result(code, diagnostics)),
      )
    }
  }) catch {
    error if @async.is_being_cancelled() || @async.is_cancellation_error(error) =>
      messages.put(AgentCancelled(run_id~))
    error => messages.put(AgentFailed(run_id~, error))
  }
}

///|
/// Run a `!` shell command locally and post its result to the message loop.
///
/// Unlike a prompt, a shell command is the TUI's own responsibility: it runs it
/// through the agent's shell execution (`@shell.collect_shell_output`, which
/// picks `sh`/`pwsh` per platform and captures merged output but skips the
/// agent-only command policy), then posts the raw result back to the message
/// loop for transcript rendering and shell-style text handoff. A Ctrl-C cancels
/// the child and reports the interruption like an aborted task.
async fn run_shell_command(
  command : String,
  messages : @async.Queue[Msg],
  run_id? : Int,
) -> Unit {
  let result : Result[@shell.ShellOutput, Error] = try
    @shell.collect_shell_output(command)
  catch {
    error if @async.is_being_cancelled() || @async.is_cancellation_error(error) => {
      // A foreground command owns the run slot: report its cancellation so the
      // command line survives as a "(cancelled)" card. A background command
      // (no run id) leaves no trace — it never owned the slot and its agent
      // turn reports its own interruption.
      if run_id is Some(id) {
        messages.put(CommandCancelled(command~, run_id=id))
      }
      return
    }
    error => Err(error)
  } noraise {
    output => Ok(output)
  }
  messages.put(CommandResult(command~, run_id~, result))
}

///|
// The live streaming line is only a transient status preview: it keeps the
// *tail* of the stream (the newest text) so the line visibly moves while the
// model types. The final assistant text is committed later by
// `assistant_message`, so the buffer only needs to cover the widest plausible
// terminal row; the bound keeps per-delta work constant during long
// code-generation streams.
const StreamingPreviewMaxColumns : Int = 240

///|
/// Keep the last `max_cols` display columns of `text`, marking an elided front
/// with a leading `…`. The inverse of `DisplayText::truncate`, which keeps the
/// front — a streaming preview must keep the end, where the new text arrives.
fn tail_columns(text : String, max_cols : Int) -> String {
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
      state.streaming_response = None
      state.streaming_reasoning = None
    }
    AssistantDelta(text) =>
      if text != "" {
        state.streaming_response = Some(
          append_streaming_preview(state.streaming_response, text),
        )
        // Content starting means the thinking phase is over; the content
        // preview replaces the reasoning one.
        state.streaming_reasoning = None
      }
    ReasoningDelta(text) =>
      if text != "" {
        state.streaming_reasoning = Some(
          append_streaming_preview(state.streaming_reasoning, text),
        )
      }
    // The turn's full reasoning, emitted once streaming ends and before the
    // assistant message commits — so the transcript reads thought → answer.
    ReasoningMessage(text) => {
      state.streaming_reasoning = None
      if !text.trim().is_empty() {
        cmds.push(AppendItem(reasoning_item(text)))
      }
    }
    // Prompt steering took effect at the engine's step boundary: echo the input
    // into the transcript at its true conversational position, the way the
    // model actually saw it.
    SteerApplied(Prompt(text)) => {
      confirm_pending_steer(state, text)
      cmds.push(AppendItem(Input(Prompt(text))))
    }
    // Command context is already rendered as a local shell result; its applied
    // event is only a delivery acknowledgment.
    SteerApplied(Command(_)) => ()
    // A notice (e.g. a background job finishing) originates in the engine, not
    // from a pending local steer, so just render it in the transcript — except
    // goal markers, whose steer path is transport: the user-facing
    // confirmation is the goal_updated event that follows the durable append.
    // Idle background notices arrive untagged (as EngineBackgroundNotice),
    // making the tagged BackgroundNotice path unreachable — but render it
    // the same way for completeness.
    SteerApplied(Notice(text)) | BackgroundNotice(text) =>
      if @agent_session.goal_marker(text) is None {
        cmds.push(AppendItem(Input(Notice(text))))
      }
    // Normally unreachable from the wire: the engine client routes
    // steer_dropped events to the untagged message (they always trail the
    // racing turn's terminal, so a run-tagged copy would be stale-filtered).
    // Kept as defense in depth for any future in-run emitter.
    SteerDropped(text) => {
      confirm_pending_steer(state, text)
      cmds.push(AppendItem(steer_dropped_item(text)))
    }
    AssistantMessage(text) => {
      state.step_response = Some(text)
      state.streaming_response = None
      state.streaming_reasoning = None
      if !text.trim().is_empty() {
        cmds.push(AppendItem(Response(text)))
      }
    }
    SessionError(error) => cmds.push(AppendItem(Error(error)))
    Usage(usage) => state.usage = Some(usage)
    ToolResult(result) => cmds.push(AppendItem(tool_item(result)))
    AgentFinished(answer) => {
      let already_appended = state.step_response is Some(response) &&
        response == answer
      // `AgentFinished` follows `AssistantMessage` for normal chat responses,
      // but tool-controlled finish results may arrive without one.
      if !already_appended && !answer.trim().is_empty() {
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
    // (e.g. the context delivered after a `!` shell command) can arrive once a
    // later run — including a `/compact` run — is already in flight. With no way
    // to know whether the rejection belongs to the active run, never end a run on
    // it; only surface it, and let the run finish on its own terminal event. The
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
    // The serve client posts goal updates untagged (EngineGoalUpdated) so
    // idle confirmations survive the stale-run guard — but ONESHOT mode
    // forwards engine events run-tagged, so this path is live there: the
    // mirror must follow (a goal(met) mid-run would otherwise leave /goal
    // reporting a cleared goal until restart).
    GoalUpdated(goal) => apply_goal_update(state, goal, cmds)
    // Likewise routed untagged by the client (as background notices).
    GoalContinue(_) | GoalBudgetExhausted => ()
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
  if !arguments.trim().is_empty() {
    cmds.push(AppendItem(Error("/compact does not accept arguments")))
    return
  }
  // Compaction is a command on the persistent serve engine; a oneshot engine is
  // spawned per prompt and has no session to summarize between turns.
  if state.config.engine_mode is OneShot {
    cmds.push(
      AppendItem(Error("Compaction is not supported by a oneshot engine.")),
    )
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
      if arguments.trim().is_empty() {
        cmds.push(Quit)
      } else {
        cmds.push(AppendItem(Error("/exit does not accept arguments")))
      }
    "compact" => handle_compact_command(state, arguments, cmds)
    "loop" => handle_loop_command(state, arguments, cmds)
    "goal" => handle_goal_command(state, arguments, cmds)
    other => cmds.push(AppendItem(Error("Unknown slash command: /\{other}")))
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
        // Enter while idle submits; Enter while a task runs steers it — prompt
        // text is folded into the running turn at its next step boundary, and
        // `!` commands run locally before their output is steered.
        Steer(input) =>
          if state.run is Idle {
            state.queued.push(input)
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
          } else if state.run_is_command {
            // The active run is a local shell command: there is no engine
            // turn to steer, and steering the idle engine would start a
            // phantom turn behind the command's back.
            cmds.push(
              AppendItem(
                Error(
                  "A local shell command is running and cannot be steered. Press Tab to queue this input.",
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
          } else if state.config.engine_mode is OneShot {
            // One-shot engines have no command channel into a running
            // process — the original pre-serve limitation.
            cmds.push(
              AppendItem(
                Error(
                  "Steering is not supported by a oneshot engine. Press Tab to queue this input.",
                ),
              ),
            )
          } else {
            match input {
              Prompt(text) =>
                // A blank steer would be filtered engine-side without any
                // settling event, leaving a phantom acknowledgment; there is
                // nothing to say to the model anyway, so drop it here.
                if !text.trim().is_empty() {
                  // Acknowledge immediately: the transcript echo only comes
                  // at the step boundary, but the user pressed Enter *now*.
                  state.pending_steers.push(text)
                  cmds.push(SteerAgent(Prompt(text)))
                }
              // No input echo for a `!` command: the result card already shows
              // `$ command`, and that card is the only form persisted, so an
              // echo here would double the command line live and diverge from a
              // resumed session, which only re-renders the card.
              Command(command) => {
                // Its eventual completion hands command context to the engine;
                // a scheduled `/loop` fire must not slip in between (the
                // context would land in the scheduled turn instead of this
                // conversation), so track it as busy until the result arrives.
                state.background_commands += 1
                cmds.push(RunCommand(run_id=None, command))
              }
              // A notice is engine-internal, never user-submitted steering.
              Notice(_) => ()
            }
          }
        Queue(input) => state.queued.push(input)
        // Ctrl+C interrupts the running task; when nothing is running it quits
        // the TUI (the common "press Ctrl+C to get out" expectation), rather than
        // printing a dead-end "nothing to interrupt" notice. A second Ctrl+C
        // while already interrupting escalates from the polite cancel command
        // to killing the engine process.
        Interrupt =>
          match state.run {
            Idle => cmds.push(Quit)
            Running(started_ms) => {
              state.run = Interrupting(started_ms)
              cmds.push(CancelAgent)
            }
            Interrupting(_) =>
              // Escalation only makes sense for an engine turn; a stuck
              // local shell command has nothing harder than another cancel,
              // and killing the engine would punish an innocent bystander.
              if state.run_is_command {
                cmds.push(CancelAgent)
              } else {
                cmds.push(KillEngine)
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
    CommandCancelled(command~, ..) => {
      cmds.push(AppendItem(command_cancelled_item(command)))
      state.finish_run()
    }
    AgentFailed(error, ..) => {
      cmds.push(AppendItem(Error("agent failed: \{error}")))
      scheduler_on_run_end(state, LoopRunFailed("failed"), cmds)
      state.finish_run()
    }
    CommandResult(command~, run_id~, result) => {
      let text = @command_context.encode(command, result)
      // The card lands here, at shell-completion time. For a background command
      // (run alongside a live turn) that is deliberately *not* the position the
      // engine persists the corresponding user message — it appends that at the
      // turn's next step boundary, so assistant/tool events already in flight
      // can sit after `$ cmd` live but before it on resume. This is intentional:
      // the live transcript is a real-time log (entries appear when they
      // happen), while the durable session reflects model-visible conversational
      // order. Deferring the card to the boundary would leave the user staring
      // at silence for the rest of a long tool call after their command already
      // finished, which the immediate card exists to avoid.
      cmds.push(AppendItem(command_item(command, result)))
      // Only a foreground command (launched while idle) owns the run slot; a
      // background command running alongside a live agent turn must leave it be
      // — it only releases its hold on the `/loop` fire gate.
      if run_id is Some(_) {
        state.finish_run()
      } else {
        state.background_commands = (state.background_commands - 1).max(0)
      }
      // Serve appends the `!` output as durable user-shell context at its
      // current session boundary. OneShot has no live engine session to append
      // to, and its command-context path is retired ahead of removing OneShot
      // entirely: the command still runs and renders locally, it is just not
      // handed to the model.
      if state.config.engine_mode is Serve {
        cmds.push(SteerAgent(Command(text)))
      }
    }
    // The steer never reached a turn; the text would otherwise vanish
    // silently. Run state is untouched — the run's own death report (or
    // terminal event) settles it.
    SteerDropped(text) => {
      confirm_pending_steer(state, text)
      cmds.push(AppendItem(steer_dropped_item(text)))
    }
    // Settles nothing by construction: the rejecting turn's terminal already
    // swept its acknowledgments, and a text match here could only steal a
    // fresh identical-text steer's entry from the next turn.
    EngineSteerDropped(text) => cmds.push(AppendItem(steer_dropped_item(text)))
    EngineSessionError(error) => cmds.push(AppendItem(Error(error)))
    // Goal markers are filtered for the same reason as on the steer path:
    // their notice leg is transport, and goal_updated carries the
    // confirmation (defense in depth against engine version skew).
    EngineBackgroundNotice(text) =>
      if @agent_session.goal_marker(text) is None {
        cmds.push(AppendItem(Input(Notice(text))))
      }
    // The engine's durable-append confirmation is the only writer of the
    // mirrored goal state.
    EngineGoalUpdated(goal) => apply_goal_update(state, goal, cmds)
    EngineExited => ()
    // Tick is a 1s heartbeat: it keeps the message loop turning so the trailing
    // refresh_ui re-runs (the elapsed-time activity line keeps advancing during
    // quiet stretches) and steps the `/loop` countdown. Bookkeeping only — a
    // due schedule is dispatched at the post-update choke point.
    Tick => scheduler_tick(state)
  }
  // One input runs at a time: whenever the TUI is idle and inputs are waiting,
  // start the next one. A prompt is dispatched to the agent engine; a `!` shell
  // command is run locally instead. Only submissions and run-ending events can
  // reach "idle with a non-empty queue", so this never fires spuriously.
  if state.run is Idle && state.queued.length() > 0 {
    let input = state.queued.remove(0)
    let run_id = state.start_run(@env.now().reinterpret_as_int64())
    match input {
      Prompt(text) => {
        cmds.push(AppendItem(Input(Prompt(text))))
        cmds.push(StartAgent(run_id~, text))
      }
      // No input echo for a `!` command: the result card (command_item) already
      // shows `$ command` and is the only form persisted to the session, so
      // echoing here too would show the command twice live and diverge from
      // resume, which only re-renders that card.
      Command(command) => {
        state.run_is_command = true
        cmds.push(RunCommand(run_id=Some(run_id), command))
      }
      // A notice is engine-internal, never a user-submitted queued input.
      Notice(_) => ()
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
  // its stdin; a `!` shell command remains a local task, tracked by
  // `running_task` so an interrupt can cancel it directly.
  let engine = EngineClient(state.config, messages)
  let mut running_task : @async.Task[Unit]? = None
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
    // composer. A due fire appends its StartAgent here, after any
    // command-context steer the updates produced.
    scheduler_maybe_fire(state, input_idle=ui.input_idle(), cmds)
    for cmd in cmds {
      match cmd {
        AppendItem(item) => ui.append_item(item)
        StartAgent(run_id~, task) =>
          match state.config.engine_mode {
            Serve => {
              // An engine turn has no local task. A queued prompt can start
              // in the same update that finished a `!` command (state never
              // passes through Idle, so the cleanup below never runs); clear
              // the stale handle here or the next Ctrl-C would cancel a dead
              // command task instead of the engine turn.
              running_task = None
              engine.prompt(group, run_id, task)
            }
            // The escape hatch for engines that only speak the original
            // protocol: one process per prompt, cancelled like a local task.
            OneShot =>
              running_task = Some(
                group.spawn(no_wait=true) <| () => {
                  run_agent_task(state.config, run_id, task, messages)
                },
              )
          }
        // A foreground command (run_id present) owns the cancellable run slot:
        // spawn it and stash the task so Cancel/Kill can reach it. A background
        // command (run_id absent) runs alongside a live agent turn and must stay
        // fire-and-forget, never displacing the turn as the cancel target.
        RunCommand(run_id~, command) =>
          if run_id is Some(_) {
            running_task = Some(
              group.spawn(no_wait=true) <| () => {
                run_shell_command(command, messages, run_id?)
              },
            )
          } else {
            group.spawn_bg(no_wait=true) <| () => {
              run_shell_command(command, messages, run_id?)
            }
          }
        SteerAgent(input) => engine.steer(group, input)
        UpdateGoal(goal) => engine.goal(group, goal)
        // Compaction is an engine operation with no local task. Clear any stale
        // command handle (as a queued prompt would) so a Ctrl-C cancels this
        // compaction turn rather than a finished command task.
        CompactSession(run_id~) => {
          running_task = None
          engine.compact(group, run_id)
        }
        CancelAgent =>
          match running_task {
            // A local shell command (or a one-shot engine run) in flight:
            // cancel its task directly.
            Some(task) => task.cancel()
            None => engine.cancel_turn()
          }
        KillEngine =>
          match running_task {
            // One-shot runs and local commands have no separate process to
            // escalate to beyond cancelling the task again.
            Some(task) => task.cancel()
            None => engine.kill()
          }
        Quit => {
          // Close the engine's stdin (the serve protocol's shutdown signal) and
          // give it a bounded moment to drain any already-delivered command
          // context to the store and exit, so quitting right after a `!` does
          // not lose output the user already saw carded.
          engine.shutdown()
          // If the engine actually failed to persist a delivered `!` context (or
          // could not be written to), it emitted a `session_error` the reader
          // turned into an `EngineSessionError`; one may be sitting in the queue
          // as we break, so drain and surface it. Everything else queued is
          // dropped on purpose: a `!` that only finished after we began quitting
          // never had its card rendered (shell output is carded on completion,
          // not streamed), so dropping it is consistent with resume and a
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
    // A terminal event for the active run leaves `state` idle (unless the
    // queue drain in `update` immediately started the next run); drop the
    // stale local task handle so an interrupt cannot cancel a command that
    // already finished.
    if state.run is Idle {
      running_task = None
    }
    refresh_ui(ui, state)
  }
}

///|
fn drain_test_state() -> State {
  State::new({
    api_key: "k",
    api_url: Some("https://proxy.example/v1/chat/completions"),
    model: Deepseek(V4Pro),
    cwd: ".",
    max_steps: Some(10),
    thinking: Max,
    session_id: SessionId("test"),
    session_root: ".openseek",
    engine: "openseek",
    engine_args_prefix: [],
    engine_mode: Serve,
  })
}

///|
fn drain_oneshot_test_state() -> State {
  State::new({
    ..drain_test_state().config,
    engine: "./replayer",
    engine_args_prefix: [],
    engine_mode: OneShot,
  })
}

///|
fn start_agent_count(cmds : Array[Cmd]) -> Int {
  cmds.count_if(cmd => cmd is StartAgent(_, ..))
}

///|
fn error_item_count(cmds : Array[Cmd]) -> Int {
  cmds.count_if(cmd => cmd is AppendItem(Error(_)))
}

///|
/// Foreground `!` commands: those that own a run slot (run_id present).
fn run_command_count(cmds : Array[Cmd]) -> Int {
  cmds.count_if(cmd => cmd is RunCommand(run_id=Some(_), _))
}

///|
/// Background `!` commands launched alongside a live turn (run_id absent).
fn run_background_command_count(cmds : Array[Cmd]) -> Int {
  cmds.count_if(cmd => cmd is RunCommand(run_id=None, _))
}

///|
fn compact_session_count(cmds : Array[Cmd]) -> Int {
  cmds.count_if(cmd => cmd is CompactSession(_))
}

///|
test "engine configuration travels through the environment" {
  let config = drain_test_state().config
  let env = engine_extra_env(config)
  guard env.get("OPENSEEK_SESSION") is Some(session_id) else {
    fail("missing session id env")
  }
  guard env.get("OPENSEEK_SESSION_ROOT") is Some(session_root) else {
    fail("missing session root env")
  }
  guard env.get("OPENSEEK_DIR") is Some(dir) else {
    fail("missing workspace dir env")
  }
  assert_eq(session_id, "test")
  assert_eq(session_root, ".openseek")
  assert_eq(dir, ".")
  assert_true(env.get("DEEPSEEK") == Some(config.api_key))
  assert_true(env.get("OPENSEEK_THINKING") == Some("max"))
  assert_true(
    env.get("OPENSEEK_API_URL") ==
    Some("https://proxy.example/v1/chat/completions"),
  )
  let kimi_env = engine_extra_env({ ..config, model: Kimi(K27CodeHighSpeed) })
  assert_true(kimi_env.get("KIMI") == Some(config.api_key))
  assert_true(kimi_env.get("DEEPSEEK") is None)
}

///|
test "agent engine env overrides inherited session config" {
  let inherited = {
    "OPENSEEK_SESSION": "parent",
    "OPENSEEK_SESSION_ROOT": "/tmp/parent",
    "OPENSEEK_DIR": "/tmp/parent-workspace",
    "OPENSEEK_API_URL": "https://parent.example/chat/completions",
    "PATH": "/bin",
  }
  let env = engine_env(drain_test_state().config, inherited)
  assert_true(env.get("PATH") == Some("/bin"))
  assert_true(env.get("OPENSEEK_SESSION") == Some("test"))
  assert_true(env.get("OPENSEEK_SESSION_ROOT") == Some(".openseek"))
  assert_true(env.get("OPENSEEK_DIR") == Some("."))
  assert_true(
    env.get("OPENSEEK_API_URL") ==
    Some("https://proxy.example/v1/chat/completions"),
  )
  assert_true(inherited.get("OPENSEEK_SESSION") == Some("parent"))
}

///|
test "agent engine env clears inherited api url without override" {
  let config = { ..drain_test_state().config, api_url: None }
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
test "compact slash command is unavailable on a oneshot engine" {
  let state = State::new({ ..drain_test_state().config, engine_mode: OneShot })
  let cmds = update(state, UiInput(SlashCommand(name="compact", arguments="")))
  assert_eq(error_item_count(cmds), 1)
  assert_eq(compact_session_count(cmds), 0)
  assert_true(state.run is Idle)
}

///|
test "unknown slash command reports an error" {
  let state = drain_test_state()
  let cmds = update(state, UiInput(SlashCommand(name="unknown", arguments="")))
  assert_eq(error_item_count(cmds), 1)
  assert_true(state.run is Idle)
}

///|
test "a submitted shell command runs locally, not via the agent" {
  let state = drain_test_state()
  // A `!` command submitted while idle drains to a local RunCommand, never to
  // the agent engine.
  let cmds = update(state, UiInput(Steer(Command("ls"))))
  assert_true(state.run is Running(_))
  assert_eq(run_command_count(cmds), 1)
  assert_eq(start_agent_count(cmds), 0)
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
fn quit_count(cmds : Array[Cmd]) -> Int {
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
  guard cmds is [SteerAgent(Prompt(text))] else {
    fail("expected a steer command")
  }
  assert_eq(text, "b")
  assert_true(state.run is Running(_))

  // A shell command runs locally in the background; its output is sent as
  // command context after the command finishes.
  let cmds = update(state, UiInput(Steer(Command("ls"))))
  assert_eq(error_item_count(cmds), 0)
  assert_eq(run_background_command_count(cmds), 1)
  assert_eq(run_command_count(cmds), 0)
  assert_true(cmds.all(cmd => !(cmd is SteerAgent(_))))
  assert_true(state.run is Running(_))

  // Queue while running still queues without error.
  let cmds = update(state, UiInput(Queue(Prompt("c"))))
  assert_eq(state.queued.length(), 1)
  assert_eq(error_item_count(cmds), 0)
}

///|
test "a background shell command result sends command context" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  assert_true(state.run is Running(_))

  let cmds = update(
    state,
    CommandResult(command="ls", run_id=None, Err(Failure::Failure("boom"))),
  )
  guard cmds is [AppendItem(_), SteerAgent(Command(text))] else {
    fail("expected command transcript item and command steer")
  }
  assert_true(text.contains("<user_shell_command>"))
  assert_true(text.contains("<command>\nls\n</command>"))
  assert_true(text.contains("error running shell:"))
  assert_eq(state.pending_steers.length(), 0)
  assert_true(state.run is Running(_))
}

///|
test "oneshot engines reject steering" {
  let state = drain_oneshot_test_state()
  let _ = update(state, UiInput(Steer(Prompt("a"))))
  assert_true(state.run is Running(_))
  // No command channel into a one-shot process: steering errors instead of
  // emitting a steer command.
  let cmds = update(state, UiInput(Steer(Prompt("b"))))
  assert_eq(error_item_count(cmds), 1)
  assert_true(cmds.all(cmd => !(cmd is SteerAgent(_))))
  let _ = update(
    state,
    AgentProgress(run_id=state.run_id, AgentFinished("done")),
  )
}

///|
test "a running shell command is never steered and never kills the engine" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Command("sleep 5"))))
  assert_true(state.run is Running(_))
  assert_true(state.run_is_command)

  // Steering a local command run errors instead of poking the idle engine.
  let cmds = update(state, UiInput(Steer(Prompt("change of plan"))))
  assert_eq(error_item_count(cmds), 1)
  assert_true(cmds.all(cmd => !(cmd is SteerAgent(_))))

  // Interrupt escalation stays on the local task: a second Ctrl-C cancels
  // again rather than killing the bystander engine process.
  let _ = update(state, UiInput(Interrupt))
  assert_true(state.run is Interrupting(_))
  let cmds = update(state, UiInput(Interrupt))
  assert_true(cmds.any(cmd => cmd is CancelAgent))
  assert_true(cmds.all(cmd => !(cmd is KillEngine)))

  // Finishing the command clears the flag.
  let _ = update(
    state,
    CommandResult(
      run_id=Some(state.run_id),
      command="sleep 5",
      Err(Failure::Failure("interrupted")),
    ),
  )
  assert_false(state.run_is_command)
}

///|
test "a cancelled foreground shell command survives as a card, not a lost line" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Command("sleep 100"))))
  let command_run = state.run_id
  assert_true(state.run_is_command)

  // Ctrl-C moves the command into Interrupting and cancels its local task.
  let _ = update(state, UiInput(Interrupt))
  assert_true(state.run is Interrupting(_))

  // The cancelled task reports back with no result. The command line must still
  // appear — as a "(cancelled)" card, since the live input echo was dropped —
  // and the run settles without handing anything to the engine.
  let cmds = update(
    state,
    CommandCancelled(command="sleep 100", run_id=command_run),
  )
  guard cmds is [AppendItem(ToolCall(_))] else {
    fail("expected exactly one cancelled command card, not a lost line")
  }
  assert_true(cmds.all(cmd => !(cmd is SteerAgent(_))))
  assert_true(state.run is Idle)
  assert_false(state.run_is_command)
}

///|
test "a completed shell command is persisted as an idle user message" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Command("ls"))))
  let command_run = state.run_id
  let cmds = update(
    state,
    CommandResult(
      run_id=Some(command_run),
      command="ls",
      Err(Failure::Failure("boom")),
    ),
  )
  // A spawn failure still renders a command card (not a bare error), so the
  // `$ ls` line survives now that the live input echo is gone — matching the
  // `$ ls (failed)` card resume reconstructs from the persisted context.
  guard cmds is [AppendItem(ToolCall(_)), SteerAgent(Command(text))] else {
    fail("expected a command card and command steer")
  }
  assert_true(text.contains("<user_shell_command>"))
  assert_true(text.contains("<command>\nls\n</command>"))
  assert_true(text.contains("error running shell:"))
  assert_true(state.run is Idle)
  assert_true(cmds.all(cmd => !(cmd is StartAgent(_, ..))))
  assert_false(state.run_is_command)

  let cmds = update(state, UiInput(Steer(Prompt("what changed?"))))
  guard cmds
    is [AppendItem(Input(Prompt("what changed?"))), StartAgent(run_id~, text)] else {
    fail("expected prompt transcript item and agent start")
  }
  assert_true(run_id != command_run)
  assert_eq(text, "what changed?")
  assert_true(state.run is Running(_))
  assert_false(state.run_is_command)
}

///|
test "a command context delivery failure reports without prompt fallback" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Command("ls"))))
  let command_run = state.run_id
  let cmds = update(
    state,
    CommandResult(
      run_id=Some(command_run),
      command="ls",
      Err(Failure::Failure("boom")),
    ),
  )
  guard cmds is [AppendItem(_), SteerAgent(Command(_))] else {
    fail("expected command steer")
  }
  let cmds = update(state, EngineSessionError("store unavailable"))
  assert_eq(error_item_count(cmds), 1)

  let cmds = update(state, UiInput(Steer(Prompt("what changed?"))))
  guard cmds
    is [AppendItem(Input(Prompt("what changed?"))), StartAgent(run_id=_, text)] else {
    fail("expected prompt transcript item and agent start")
  }
  assert_eq(text, "what changed?")
}

///|
test "oneshot shell commands run locally but hand nothing to the model" {
  let state = drain_oneshot_test_state()
  let _ = update(state, UiInput(Steer(Command("ls"))))
  let command_run = state.run_id
  // The command runs and renders, but OneShot delivers no context: no steer is
  // emitted and the output is not folded into any later prompt.
  let cmds = update(
    state,
    CommandResult(
      run_id=Some(command_run),
      command="ls",
      Err(Failure::Failure("boom")),
    ),
  )
  guard cmds is [AppendItem(_)] else {
    fail("expected only the command transcript item")
  }
  assert_true(cmds.all(cmd => !(cmd is SteerAgent(_))))
  assert_true(state.run is Idle)

  let cmds = update(state, UiInput(Steer(Prompt("summarize"))))
  guard cmds
    is [AppendItem(Input(Prompt("summarize"))), StartAgent(run_id=_, text)] else {
    fail("expected prompt transcript item and agent start")
  }
  assert_eq(text, "summarize")
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
    AgentProgress(run_id=state.run_id, SteerApplied(Prompt("make it rhyme"))),
  )
  assert_eq(state.pending_steers.length(), 0)
  assert_eq(pending_steer_segment(state.pending_steers).length(), 0)

  // A dropped steer also clears the acknowledgment (and shows its notice).
  let _ = update(state, UiInput(Steer(Prompt("too late"))))
  assert_eq(state.pending_steers.length(), 1)
  let _ = update(state, SteerDropped("too late"))
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
  let _ = update(state, EngineSteerDropped("old steer"))
  assert_eq(state.pending_steers.length(), 1)
  let _ = update(state, EngineSteerDropped("fresh steer"))
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
    AgentProgress(run_id=state.run_id, SteerApplied(Prompt("make it rhyme"))),
  )
  guard cmds is [AppendItem(Input(Prompt(text)))] else {
    fail("expected the steered input echoed as a transcript item")
  }
  assert_eq(text, "make it rhyme")
  // The run keeps going: a steer is not a terminal event.
  assert_true(state.run is Running(_))
}

///|
test "a command steer_applied event is only a delivery acknowledgment" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  let cmds = update(
    state,
    AgentProgress(
      run_id=state.run_id,
      SteerApplied(Command("<user_shell_command>")),
    ),
  )
  assert_eq(cmds.length(), 0)
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
async test "a shell command runs locally and posts its output" {
  let messages = @async.Queue(kind=Unbounded)
  // `echo` is the same on POSIX `sh` and Windows `pwsh`, so the platform shell
  // `@shell.collect_shell_output` picks runs this on either.
  run_shell_command("echo hello", messages, run_id=1)
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
test "assistant_delta accumulates live text and commits only the final message" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  let items : Array[@ui.TranscriptItem] = []
  append_items(state, { "event": "assistant_delta", "content": "Hel" }, items)
  append_items(state, { "event": "assistant_delta", "content": "lo" }, items)
  assert_eq(items.length(), 0)
  assert_true(state.streaming_response is Some("Hello"))
  assert_true(state.step_response is None)
  append_items(
    state,
    { "event": "assistant_message", "content": "Hello" },
    items,
  )
  assert_true(state.streaming_response is None)
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
  assert_true(state.streaming_response is Some("Need tool"))
  append_items(
    state,
    { "event": "assistant_message", "content": "Need tool" },
    items,
  )
  assert_true(state.run is Running(_))
  assert_true(state.streaming_response is None)
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
  guard state.streaming_response is Some(first) else {
    fail("expected streaming preview")
  }
  assert_true(
    @displaytext.DisplayText(first).width() <= StreamingPreviewMaxColumns,
  )
  assert_true(first.has_prefix("…"))
  // The preview is a tail window: new deltas keep showing up at its end
  // (instead of freezing once the cap is reached, as a head truncation would).
  append_items(state, { "event": "assistant_delta", "content": "more" }, items)
  guard state.streaming_response is Some(second) else {
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
  assert_true(state.streaming_response is Some("fn main { println(1) }"))
}

///|
test "reasoning_message commits a thought item and clears the preview" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  let items : Array[@ui.TranscriptItem] = []
  append_items(
    state,
    { "event": "reasoning_delta", "content": "Let me think" },
    items,
  )
  assert_true(state.streaming_reasoning is Some("Let me think"))
  // The full reasoning lands as one `✻` thought item, and the live preview
  // is finished with.
  append_items(
    state,
    {
      "event": "reasoning_message",
      "content": "Let me think about names.\nThe user said Hongbo.",
    },
    items,
  )
  assert_true(state.streaming_reasoning is None)
  guard items is [Thought(_)] else { fail("expected a single Thought item") }
  // Blank reasoning never appends an empty aside.
  append_items(state, { "event": "reasoning_message", "content": "  " }, items)
  assert_eq(items.length(), 1)
}

///|
test "reasoning_delta drives the thinking preview until content arrives" {
  let state = drain_test_state()
  let _ = update(state, UiInput(Steer(Prompt("do it"))))
  let items : Array[@ui.TranscriptItem] = []
  append_items(
    state,
    { "event": "reasoning_delta", "content": "Let me think" },
    items,
  )
  assert_true(state.streaming_reasoning is Some("Let me think"))
  assert_true(state.streaming_response is None)
  assert_eq(items.length(), 0)
  // The first content delta ends the thinking phase: the content preview
  // replaces the reasoning one.
  append_items(
    state,
    { "event": "assistant_delta", "content": "Answer" },
    items,
  )
  assert_true(state.streaming_reasoning is None)
  assert_true(state.streaming_response is Some("Answer"))
  // The committed message clears both previews.
  append_items(
    state,
    { "event": "assistant_message", "content": "Answer" },
    items,
  )
  assert_true(state.streaming_response is None)
  assert_true(state.streaming_reasoning is None)
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
