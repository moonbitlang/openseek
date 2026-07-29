///|
/// A live serve-mode engine process: the stdin command channel and the
/// process handle for escalation.
priv struct EngineProcess {
  writer : @process.WriteToProcess
  proc : @process.Process
  // Run bookkeeping is owned by the process whose stream produced it: a
  // reader at EOF must report the run that was open on *its* engine, never
  // one a respawned successor has since started.
  mut latest_run : Int
  mut run_open : Bool
  // The stdout reader task for this engine, so a graceful shutdown can wait for
  // the engine to drain its stdin and exit before teardown kills it.
  mut reader : @async.Task[Unit]?
  // Goal set/clear lines written to THIS engine but not yet answered by a
  // matching durable goal_updated (Some(text)=set, None=clear; unrelated
  // updates must not consume an ack). Owned by the process like run
  // bookkeeping: a replaced engine's EOF must not clear — or falsely warn
  // about — a successor's outstanding ack.
  pending_goal_acks : Array[String?]
}

///|
/// The TUI's connection to one long-lived `serve` engine process — the
/// client half of the persistent-engine design.
///
/// One engine serves every prompt of a TUI session: prompts, steers, and
/// cancels are written as JSONL commands to its stdin, and its stdout event
/// stream feeds the message loop continuously. Turns are strictly
/// sequential on the wire, so decoded events are stamped with the run id of
/// the most recently submitted input — by the time a new prompt is written,
/// the previous turn's terminal event has already been emitted ahead of it
/// in the stream.
///
/// The engine is spawned on first use and respawned on the next prompt
/// after it dies: the durable session is the source of truth, so a fresh
/// process resumes the same conversation. Death with a run in flight is
/// reported into the message loop as that run's failure, with the captured
/// stderr prefix as the diagnostic.
priv struct EngineClient {
  config : AppConfig
  messages : @async.Queue[Msg]
  mut live : EngineProcess?
}

///|
fn EngineClient::EngineClient(
  config : AppConfig,
  messages : @async.Queue[Msg],
) -> EngineClient {
  { config, messages, live: None }
}

///|
/// Spawn the serve-mode engine and its stream readers inside `group`.
///
/// The stdout reader runs for the engine's lifetime, decoding events and
/// stamping them with the current run id; the stderr drain keeps the capped
/// diagnostics prefix. When stdout ends the engine is gone: the client is
/// marked dead (so the next prompt respawns) and, if a run was in flight,
/// its failure is reported with the exit code and stderr.
async fn[G] EngineClient::start(
  self : EngineClient,
  group : @async.TaskGroup[G],
) -> Unit {
  let (child_stdin, writer) = @process.write_to_process()
  let (reader, child_stdout) = @process.read_from_process()
  let (stderr_reader, child_stderr) = @process.read_from_process()
  let child_env = engine_env(self.config, @env.get_env_vars())
  let proc = @process.spawn(
    group,
    self.config.engine,
    self.config.engine_args(["serve"]),
    inherit_env=false,
    extra_env=child_env,
    stdin=child_stdin,
    stdout=child_stdout,
    stderr=child_stderr,
    no_wait=true,
  )
  let engine : EngineProcess = {
    writer,
    proc,
    latest_run: 0,
    run_open: false,
    reader: None,
    pending_goal_acks: [],
  }
  self.live = Some(engine)
  let reader_task = group.spawn(no_wait=true) <| () => {
    let stderr_task = group.spawn(no_wait=true) <| () => {
      drain_stderr_capped(stderr_reader)
    }
    @jsonl.each(reader, json => {
      if @event.decode_event(json) is Some(event) {
        match event {
          // A wire-level drop races the turn's terminal event by
          // construction (the engine only rejects steers once idle), so a
          // run-tagged message would arrive after finish_run and be eaten
          // by the stale-run guard. Post it untagged so the resubmit notice
          // always reaches the user.
          SteerDropped(text) =>
            self.messages.try_put(EngineSteerDropped(text)) |> ignore
          // A rejection can answer an idle command (e.g. /goal sent to an
          // engine that does not implement it), where no run owns it and a
          // tagged message would be eaten by the stale-run guard. Rejections
          // are never run-terminal, so untagged is safe in-run too.
          CommandRejected(message) => {
            // A rejection cannot be correlated to a specific pending goal
            // ack; settle them all — the rejection itself is surfaced, and
            // stale entries would otherwise mis-warn at EOF or consume a
            // later matching ack.
            engine.pending_goal_acks.clear()
            self.messages.try_put(
              EngineBackgroundNotice("engine rejected command: \{message}"),
            )
            |> ignore
          }
          // A background job finished between turns: the engine already emitted
          // this untagged, so post it untagged too — a run-tagged message would
          // be swept by the stale-run guard once the turn closed.
          BackgroundNotice(text) =>
            self.messages.try_put(EngineBackgroundNotice(text)) |> ignore
          // A durable goal update. Posted untagged: an idle set/clear (or one
          // landing after its turn closed) must survive the stale-run guard.
          GoalUpdated(goal) => {
            if engine.pending_goal_acks.search(goal) is Some(index) {
              engine.pending_goal_acks.remove(index) |> ignore
            }
            self.messages.try_put(EngineGoalUpdated(goal)) |> ignore
          }
          // Auto-continue lifecycle from a headless-armed goal: surfaced as
          // plain notices — the TUI never arms auto itself, and engine-
          // initiated turns are invisible to run tracking by design.
          GoalContinue(remaining) => {
            let budget = if remaining < 0 {
              "unlimited auto turns"
            } else {
              "\{remaining} auto turns left"
            }
            self.messages.try_put(
              EngineBackgroundNotice("goal: engine continuing (\{budget})"),
            )
            |> ignore
          }
          GoalBudgetExhausted =>
            self.messages.try_put(
              EngineBackgroundNotice(
                "goal: auto-continue budget exhausted; goal still standing",
              ),
            )
            |> ignore
          // A command context's delivery ack. The output is already rendered as
          // a local card and the engine appended it synchronously, so there is
          // nothing to do — in particular, do not echo it like a prompt steer.
          SteerApplied(Command(_)) => ()
          // The engine reports this when a command-context append failed; surface
          // it so the lost output is not silent.
          AgentError(_) as failure => {
            // A failed turn can swallow a goal notice drained into it (its
            // store append died with the turn): settle pending acks so a
            // retry is not mis-correlated and EOF does not mis-warn.
            engine.pending_goal_acks.clear()
            self.messages.try_put(
              AgentProgress(run_id=engine.latest_run, failure),
            )
            |> ignore
          }
          SessionError(error) => {
            // Persistence failed: any pending goal ack may never be
            // answered — settle rather than mis-warn or mis-consume later.
            engine.pending_goal_acks.clear()
            self.messages.try_put(EngineSessionError(error)) |> ignore
          }
          _ => {
            if is_terminal_event(event) {
              engine.run_open = false
            }
            self.messages.try_put(
              AgentProgress(run_id=engine.latest_run, event),
            )
            |> ignore
          }
        }
      }
    }) catch {
      error if @async.is_being_cancelled() ||
        @async.is_cancellation_error(error) => raise error
      // Protocol violation (a non-JSON line is a crash dump): stop reading
      // and kill the engine so `wait` below returns and reports it.
      _ => proc.cancel()
    }
    reader.close()
    // A respawn may already have replaced this engine (e.g. after a failed
    // write); only clear the slot if it is still ours.
    if self.live is Some(current) && physical_equal(current, engine) {
      self.live = None
    }
    let code = proc.wait()
    // EOF with a run still open means this engine died mid-turn: close that
    // run with its only available diagnostics. A terminal event followed by
    // a clean exit (TUI shutdown, graceful EOF) reports nothing — and a
    // successor's runs are out of reach by construction, since this reader
    // only ever sees its own process's bookkeeping.
    if engine.run_open {
      let diagnostics = stderr_task.wait().trim()
      engine.run_open = false
      self.messages.put(
        AgentProgress(
          run_id=engine.latest_run,
          engine_exit_without_result(code, diagnostics),
        ),
      )
    }
    // An idle goal update the engine never confirmed died with it: say so —
    // silence here reads as success.
    if engine.pending_goal_acks.length() > 0 {
      engine.pending_goal_acks.clear()
      // EngineSessionError, not a background notice: the quit path's
      // post-shutdown drain renders only errors, and quit-before-confirm
      // is exactly the case this warning exists for.
      self.messages.try_put(
        EngineSessionError(
          "goal update may not have been recorded: the engine exited before confirming it — check /goal and resend if needed",
        ),
      )
      |> ignore
    }
    // The watchers this engine owned died with it: let the loop observe the
    // engine boundary, whatever the exit reason.
    self.messages.put(EngineExited)
  }
  engine.reader = Some(reader_task)
}

///|
/// Write one JSONL command line to the live engine. Never spawns one:
/// `prompt` owns engine startup, while mid-turn controls must not — a steer
/// reaching a freshly spawned idle engine would become a phantom prompt. A
/// write failure means the engine just died: the client is marked dead for
/// respawn and the error is reported against `run_id`.
async fn EngineClient::send(
  self : EngineClient,
  run_id : Int,
  command : Json,
) -> Unit {
  guard self.live is Some(live) else {
    self.messages.put(
      AgentFailed(run_id~, Failure::Failure("engine is not running")),
    )
    return
  }
  live.writer.write("\{command.stringify()}\n") catch {
    error if @async.is_being_cancelled() || @async.is_cancellation_error(error) =>
      raise error
    error => {
      self.live = None
      self.messages.put(AgentFailed(run_id~, error))
    }
  }
}

///|
/// Open `run_id` on the live engine and write its opening `command` — the
/// shared tail of `prompt` and `compact`. Stamps the run bookkeeping the
/// stdout reader relies on to attribute events and an EOF-without-terminal
/// failure to the right run.
async fn EngineClient::open_run(
  self : EngineClient,
  run_id : Int,
  command : Json,
) -> Unit {
  guard self.live is Some(live) else {
    self.messages.put(
      AgentFailed(run_id~, Failure::Failure("engine is not running")),
    )
    return
  }
  live.latest_run = run_id
  live.run_open = true
  self.send(run_id, command)
}

///|
async fn[G] EngineClient::prompt(
  self : EngineClient,
  group : @async.TaskGroup[G],
  run_id : Int,
  text : String,
) -> Unit {
  if self.live is None {
    self.start(group) catch {
      error if @async.is_being_cancelled() ||
        @async.is_cancellation_error(error) => raise error
      error => {
        self.messages.put(AgentFailed(run_id~, error))
        return
      }
    }
  }
  self.open_run(run_id, (Prompt(text~) : @protocol.Command).to_json())
}

///|
/// Ensure the long-lived engine is running for an explicit user operation
/// on the durable session (command context, goal update), starting it if
/// idle. Returns the live process, or None after posting an
/// EngineSessionError naming `what`.
async fn[G] EngineClient::live_for(
  self : EngineClient,
  group : @async.TaskGroup[G],
  what : String,
) -> EngineProcess? {
  if self.live is None {
    self.start(group) catch {
      error if @async.is_being_cancelled() ||
        @async.is_cancellation_error(error) => raise error
      error => {
        self.messages.put(
          EngineSessionError("failed to start engine for \{what}: \{error}"),
        )
        return None
      }
    }
  }
  match self.live {
    Some(live) => Some(live)
    None => {
      self.messages.put(
        EngineSessionError("failed to send \{what}: engine is not running"),
      )
      None
    }
  }
}

///|
/// Send typed model-visible input to the serve engine. Prompt steering is only
/// deliverable to an open run; command context may start the long-lived engine
/// so an idle session can append it without opening a model turn.
async fn[G] EngineClient::steer(
  self : EngineClient,
  group : @async.TaskGroup[G],
  input : @agent_runtime.SteerInput,
) -> Unit {
  match input {
    // A `Notice` is engine-internal (a tool pushing a completion notice); it is
    // not something the TUI sends, but route it like a prompt for completeness.
    Prompt(text) | Notice(text) =>
      match self.live {
        Some(live) if live.run_open =>
          self.send(
            live.latest_run,
            (Steer(kind=Prompt, text~) : @protocol.Command).to_json(),
          )
        _ => self.messages.put(SteerDropped(text))
      }
    Command(text) => {
      guard self.live_for(group, "command context") is Some(live) else {
        return
      }
      let command : Json = (Steer(kind=Command, text~) : @protocol.Command).to_json()
      // Delivery here is fire-and-forget by design. The serve protocol's
      // contract is that every accepted command context is answered with
      // exactly one terminal ack — `steer_applied` (persisted) or
      // `session_error` (append failed) — and both are surfaced (the latter as
      // an error). We deliberately do NOT track an outstanding-ack counter to
      // cover the one out-of-contract gap: an engine that accepts this line and
      // then exits emitting neither ack (a crash mid-handler, or a custom engine
      // that ignores the contract). That case leaves the `!` card on screen but
      // its output absent from the resumed session, with no error.
      //
      // This is an intentional trade-off, not an oversight. The idle append is a
      // single synchronous store write immediately followed by its ack in the
      // same handler, so the accept-but-never-ack window is vanishingly small
      // for the real engine. A previous version tracked the pending write and
      // reported it at EOF, but that bought this rare true-positive at the cost
      // of a symmetric *false* positive — an engine dying just after the append
      // succeeded but before the ack was observed would wrongly warn "output not
      // saved" when it was — plus the bookkeeping to keep the count exact across
      // batched steers and append failures. The blast radius of the gap is
      // cosmetic and recoverable: the command is simply missing on resume as if
      // never run (the user saw it live and can re-run it); nothing is corrupted.
      live.writer.write("\{command.stringify()}\n") catch {
        error if @async.is_being_cancelled() ||
          @async.is_cancellation_error(error) => raise error
        error => {
          self.live = None
          self.messages.put(
            EngineSessionError("failed to send command context: \{error}"),
          )
        }
      }
    }
  }
}

///|
/// Send a standing-goal update to the serve engine: `Some(text)` sets or
/// replaces the goal, `None` clears it. Like command context, this is an
/// explicit user operation on the durable session, so it may start the
/// long-lived engine to record the goal without opening a model turn. The
/// engine answers every persisted update with `goal_updated`, which is the
/// only signal that mutates the TUI's mirrored goal state.
async fn[G] EngineClient::goal(
  self : EngineClient,
  group : @async.TaskGroup[G],
  goal : String?,
) -> Unit {
  guard self.live_for(group, "goal update") is Some(live) else { return }
  let command : Json = match goal {
    // The TUI only ever sets a manual goal; `auto` is the serve protocol's
    // affordance for a headless controller.
    Some(text) => (GoalSet(text~, auto=false) : @protocol.Command).to_json()
    None => (GoalClear : @protocol.Command).to_json()
  }
  // Registered BEFORE the write: a fast engine can append the marker and
  // emit goal_updated while the write call is still yielding, and the
  // reader must find the expected ack already present. Rolled back if the
  // write itself fails.
  live.pending_goal_acks.push(goal)
  live.writer.write("\{command.stringify()}\n") catch {
    error if @async.is_being_cancelled() || @async.is_cancellation_error(error) =>
      raise error
    error => {
      if live.pending_goal_acks.search(goal) is Some(index) {
        live.pending_goal_acks.remove(index) |> ignore
      }
      self.live = None
      self.messages.put(
        EngineSessionError("failed to send goal update: \{error}"),
      )
    }
  }
}

///|
/// Ask the engine to compact the conversation. Like `prompt`, this is an
/// explicit user operation on the durable session, so it may spawn the engine
/// (a fresh process resumes the same session and compacts it) and it opens a
/// run whose terminal event — `compaction_finished` or a failure — closes it.
async fn[G] EngineClient::compact(
  self : EngineClient,
  group : @async.TaskGroup[G],
  run_id : Int,
) -> Unit {
  if self.live is None {
    self.start(group) catch {
      error => {
        self.messages.put(AgentFailed(run_id~, error))
        return
      }
    }
  }
  self.open_run(run_id, (Compact : @protocol.Command).to_json())
}

///|
/// Cancel the running turn. With no live engine or open run this is a
/// silent no-op — the turn the user wanted dead is already gone.
async fn EngineClient::cancel_turn(self : EngineClient) -> Unit {
  if self.live is Some(live) && live.run_open {
    self.send(live.latest_run, (Cancel : @protocol.Command).to_json())
  }
}

///|
/// Hard escalation: kill the engine process outright. The stdout reader
/// observes the EOF and reports the in-flight run's failure; the next
/// prompt respawns a fresh engine on the same durable session.
fn EngineClient::kill(self : EngineClient) -> Unit {
  if self.live is Some(live) {
    live.proc.cancel()
  }
}

///|
/// Grace period for the serve engine to drain a freshly delivered command
/// context to the store and exit after its stdin is closed, before a hard
/// teardown. Bounded so a stuck or mid-turn engine cannot hang TUI exit.
const EngineDrainGraceMs : Int = 2000

///|
/// Graceful shutdown for TUI exit: closing the engine's stdin is the serve
/// protocol's EOF signal, letting it finish draining and exit 0. We then wait
/// (bounded) for the stdout reader to observe that exit, so an engine spawned
/// just to append a `!` command's output gets to persist it before teardown —
/// quitting right after a `!` must not lose that context. If the engine does
/// not exit in time (e.g. a turn is still in flight), kill it so exit never
/// hangs; the task-group teardown reaps whatever remains.
async fn EngineClient::shutdown(self : EngineClient) -> Unit {
  guard self.live is Some(live) else { return }
  live.writer.close()
  guard live.reader is Some(reader) else { return }
  if @async.with_timeout_opt(EngineDrainGraceMs, () => reader.wait()) is None {
    // The protocol-clean exit stalled (e.g. a turn still in flight). Escalate
    // through the process library's own cancellation: the engine was spawned
    // with the default `graceful_cancel(timeout=5000)`, so `cancel()` sends
    // SIGTERM and, if still alive after the grace, SIGKILL — termination is
    // guaranteed. Wait for the reader to finish observing that exit before
    // teardown proceeds; that wait is bounded by the escalation.
    live.proc.cancel()
    reader.wait()
  }
}
