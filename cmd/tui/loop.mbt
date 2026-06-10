///|
async fn read_ui_events(ui : @ui.Ui, messages : @async.Queue[Msg]) -> Unit {
  for ;; {
    let event = ui.read_event()
    messages.put(UiInput(event))
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
  let text = StringBuilder::new()
  text.write_string(@utf8.decode_lossy(buffer.to_bytes()))
  if truncated {
    text.write_string(
      "\n… (stderr truncated at \{StderrCaptureLimitBytes} bytes)",
    )
  }
  if read_error is Some(message) {
    text.write_string("\n… (stderr read failed: \{message})")
  }
  text.to_string()
}

///|
fn is_terminal_event(event : @event.AgentEvent) -> Bool {
  match event {
    AgentFinished(_) | AgentAborted(_) | MaxStepsExhausted | AgentError(_) =>
      true
    _ => false
  }
}

///|
fn engine_args(task : String) -> Array[String] {
  ["--", task]
}

///|
fn engine_extra_env(config : AppConfig) -> Map[String, String] {
  {
    "DEEPSEEK": config.api_key,
    "DEEPSEEK_MODEL": config.model.to_string(),
    "OPENSEEK_MAX_STEPS": config.max_steps.to_string(),
    "OPENSEEK_SESSION": config.session_id.value(),
    "OPENSEEK_SESSION_ROOT": config.session_root,
  }
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
/// The engine is a separate process (`config.engine`, default `openseek`): it
/// runs the task and writes one JSON event per line to stdout. `@jsonl.each`
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
      // The TUI accepts hyphen-valued tasks (`allow_hyphen_values`), so a task
      // can start with `-`/`--` (e.g. the literal text `--help`). Forward it
      // after a `--` delimiter so the engine's argparse treats it as the task
      // positional rather than parsing it as one of its own options (which would
      // exit/print help and never emit a terminal JSONL event). Session settings
      // go through a fully materialized environment so custom replay engines do
      // not need to accept OpenSeek-specific flags, and inherited session vars
      // cannot shadow explicit TUI config.
      engine_args(task),
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
      let detail = if diagnostics.is_empty() { "" } else { ":\n\{diagnostics}" }
      messages.put(
        AgentProgress(
          run_id~,
          AgentError("engine exited (code \{code}) without a result\{detail}"),
        ),
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
/// agent-only command policy), renders the output into the transcript, and never
/// forwards it to the agent engine or any model. A Ctrl-C cancels the child and
/// reports the interruption like an aborted task.
async fn run_shell_command(
  run_id : Int,
  command : String,
  messages : @async.Queue[Msg],
) -> Unit {
  let item : @ui.TranscriptItem = command_item(
    command,
    @shell.collect_shell_output(command),
  ) catch {
    error if @async.is_being_cancelled() || @async.is_cancellation_error(error) => {
      messages.put(AgentCancelled(run_id~))
      return
    }
    error => Error("command failed: \{error}")
  }
  messages.put(CommandResult(run_id~, item))
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
  "…" + display.view(keep_from, display.end()).to_owned()
}

///|
/// Collapse whitespace runs (newline, CR, tab, space) to a single space so a
/// streamed fragment stays renderable on the one-row activity line — streamed
/// code is mostly newlines and indentation, which would otherwise hit the
/// renderer as control characters.
fn collapse_preview_whitespace(text : String) -> String {
  let out = StringBuilder::new()
  let mut last_was_space = false
  for ch in text {
    if ch is (' ' | '\t' | '\n' | '\r') {
      if !last_was_space {
        out.write_char(' ')
      }
      last_was_space = true
    } else {
      out.write_char(ch)
      last_was_space = false
    }
  }
  out.to_string()
}

///|
fn append_streaming_preview(current : String?, delta : String) -> String {
  let combined = match current {
    Some(text) => text + delta
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
    AssistantMessage(text) => {
      state.step_response = Some(text)
      state.streaming_response = None
      state.streaming_reasoning = None
      if !text.trim().is_empty() {
        cmds.push(AppendItem(Response(text)))
      }
    }
    // Out-of-band runtime diagnostics (e.g. `moon check --watch`) the engine fed
    // back to the model. The model reacts to them, so surface them to the user
    // too rather than dropping them: lift the watcher status into the status bar
    // and append the stripped diagnostics as a `↻` tool-style notice.
    RuntimeUpdate(text) => {
      let update = parse_runtime_update(text)
      state.watcher_status = update.status
      if update.status != "" || update.diagnostics.length() > 0 {
        cmds.push(AppendItem(runtime_item(update)))
      }
    }
    Usage(usage) => state.usage = Some(usage)
    ToolResult(result) => cmds.push(AppendItem(tool_item(result)))
    AgentFinished(answer) => {
      let already_appended = if state.step_response is Some(response) {
        response == answer
      } else {
        false
      }
      // `AgentFinished` follows `AssistantMessage` for normal chat responses,
      // but tool-controlled finish results may arrive without one.
      if !already_appended && !answer.trim().is_empty() {
        cmds.push(AppendItem(Response(answer)))
      }
      state.finish_run()
    }
    AgentAborted(reason) => {
      cmds.push(AppendItem(Error("aborted: " + reason)))
      state.finish_run()
    }
    MaxStepsExhausted => {
      cmds.push(AppendItem(Error("max steps exhausted")))
      state.finish_run()
    }
    AgentError(message) => {
      cmds.push(AppendItem(Error(message)))
      state.finish_run()
    }
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
        // Steering (redirecting a task mid-run) is not implementable with the
        // current agent API. Steer only submits when idle; while a task runs it
        // reports an error instead of silently queuing. Queue always queues.
        Steer(input) =>
          if state.run is Idle {
            state.queued.push(input)
          } else {
            cmds.push(
              AppendItem(
                Error(
                  "Steering is not supported while a task is running. Press Tab to queue this input.",
                ),
              ),
            )
          }
        Queue(input) => state.queued.push(input)
        // Ctrl+C interrupts the running task; when nothing is running it quits
        // the TUI (the common "press Ctrl+C to get out" expectation), rather than
        // printing a dead-end "nothing to interrupt" notice.
        Interrupt =>
          match state.run {
            Idle => cmds.push(Quit)
            Running(started_ms) => {
              state.run = Interrupting(started_ms)
              cmds.push(CancelAgent)
            }
            Interrupting(_) => cmds.push(CancelAgent)
          }
        Quit => cmds.push(Quit)
      }
    AgentProgress(event, ..) => handle_agent_event(state, event, cmds)
    AgentCancelled(..) => {
      cmds.push(AppendItem(Error("interrupted")))
      state.finish_run()
    }
    AgentFailed(error, ..) => {
      cmds.push(AppendItem(Error("agent failed: \{error}")))
      state.finish_run()
    }
    CommandResult(item, ..) => {
      cmds.push(AppendItem(item))
      state.finish_run()
    }
    // No state change: Tick is a 1s heartbeat that just keeps the message loop
    // turning so the trailing refresh_ui re-runs and the elapsed-time activity
    // line ("Working (12s)") keeps advancing during quiet stretches.
    Tick => ()
  }
  // One input runs at a time: whenever the TUI is idle and inputs are waiting,
  // start the next one. A prompt is dispatched to the agent engine; a `!` shell
  // command is run locally instead. Only submissions and run-ending events can
  // reach "idle with a non-empty queue", so this never fires spuriously.
  if state.run is Idle && state.queued.length() > 0 {
    let input = state.queued.remove(0)
    cmds.push(AppendItem(Input(input)))
    let run_id = state.start_run(@async.now())
    match input {
      Prompt(text) => cmds.push(StartAgent(run_id~, text))
      Command(command) => cmds.push(RunCommand(run_id~, command))
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
  // The task handle for the run currently in flight, used to cancel it on
  // interrupt. It is set when a run is dispatched and cleared once `state` goes
  // back to `Idle` below, so it always tracks the active run and a stale event
  // (dropped by `update`, leaving `state.run` untouched) can never null it out.
  let mut running_task : @async.Task[Unit]? = None
  outer~: for ;; {
    let message = messages.get()
    for cmd in update(state, message) {
      match cmd {
        AppendItem(item) => ui.append_item(item)
        StartAgent(run_id~, task) =>
          running_task = Some(
            group.spawn(no_wait=true) <| () => {
              run_agent_task(state.config, run_id, task, messages)
            },
          )
        RunCommand(run_id~, command) =>
          running_task = Some(
            group.spawn(no_wait=true) <| () => {
              run_shell_command(run_id, command, messages)
            },
          )
        CancelAgent => if running_task is Some(task) { task.cancel() }
        Quit => break outer~
      }
    }
    // A terminal event for the active run leaves `state` idle (unless the queue
    // drain in `update` immediately started the next run, which re-sets the
    // handle above); drop the stale handle so an interrupt cannot cancel a task
    // that has already finished.
    if state.run is Idle {
      running_task = None
    }
    refresh_ui(ui, state)
  }
}
