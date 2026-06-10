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
}

///|
/// The TUI's connection to one long-lived `--serve` engine process — the
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
    ["--serve"],
    inherit_env=false,
    extra_env=child_env,
    stdin=child_stdin,
    stdout=child_stdout,
    stderr=child_stderr,
    no_wait=true,
  )
  let engine : EngineProcess = { writer, proc, latest_run: 0, run_open: false }
  self.live = Some(engine)
  group.spawn_bg(no_wait=true) <| () => {
    let stderr_task = group.spawn(no_wait=true) <| () => {
      drain_stderr_capped(stderr_reader)
    }
    @jsonl.each(reader, json => {
      if @event.decode_event(json) is Some(event) {
        if is_terminal_event(event) {
          engine.run_open = false
        }
        self.messages.try_put(AgentProgress(run_id=engine.latest_run, event))
        |> ignore
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
      let detail = if diagnostics.is_empty() { "" } else { ":\n\{diagnostics}" }
      engine.run_open = false
      self.messages.put(
        AgentProgress(
          run_id=engine.latest_run,
          AgentError("engine exited (code \{code}) without a result\{detail}"),
        ),
      )
    }
    // The watchers this engine owned died with it: let the loop reset
    // engine-scoped status, whatever the exit reason.
    self.messages.put(EngineExited)
  }
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
  live.writer.write(command.stringify() + "\n") catch {
    error => {
      self.live = None
      self.messages.put(AgentFailed(run_id~, error))
    }
  }
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
      error => {
        self.messages.put(AgentFailed(run_id~, error))
        return
      }
    }
  }
  guard self.live is Some(live) else {
    self.messages.put(
      AgentFailed(run_id~, Failure::Failure("engine is not running")),
    )
    return
  }
  live.latest_run = run_id
  live.run_open = true
  self.send(run_id, { "command": "prompt", "text": text })
}

///|
/// Steer the running turn, or report the input as undeliverable when there
/// is no live engine with an open run (e.g. the engine died an instant
/// before the user pressed Enter). Steering must never spawn an engine: an
/// idle serve process treats steer as a prompt, which would mutate the
/// session behind the TUI's back under a run id nobody owns.
async fn EngineClient::steer(self : EngineClient, text : String) -> Unit {
  match self.live {
    Some(live) if live.run_open =>
      self.send(live.latest_run, { "command": "steer", "text": text })
    _ => self.messages.put(SteerDropped(text))
  }
}

///|
/// Cancel the running turn. With no live engine or open run this is a
/// silent no-op — the turn the user wanted dead is already gone.
async fn EngineClient::cancel_turn(self : EngineClient) -> Unit {
  if self.live is Some(live) && live.run_open {
    self.send(live.latest_run, { "command": "cancel" })
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
/// Graceful shutdown for TUI exit: closing the engine's stdin is the serve
/// protocol's EOF signal, letting it finish draining and exit 0. Any
/// straggler is reaped by task-group teardown.
fn EngineClient::shutdown(self : EngineClient) -> Unit {
  if self.live is Some(live) {
    live.writer.close()
  }
}
