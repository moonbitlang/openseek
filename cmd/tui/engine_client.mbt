///|
/// A live serve-mode engine process: the stdin command channel and the
/// process handle for escalation.
priv struct EngineProcess {
  writer : @process.WriteToProcess
  proc : @process.Process
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
  mut latest_run : Int
  // Whether a prompt has been sent whose terminal event has not come back.
  // Owned here rather than inferred from the stream so an engine that dies
  // before emitting anything still gets its run reported as failed.
  mut run_open : Bool
}

///|
fn EngineClient::EngineClient(
  config : AppConfig,
  messages : @async.Queue[Msg],
) -> EngineClient {
  { config, messages, live: None, latest_run: 0, run_open: false }
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
  self.live = Some({ writer, proc })
  group.spawn_bg(no_wait=true) <| () => {
    let stderr_task = group.spawn(no_wait=true) <| () => {
      drain_stderr_capped(stderr_reader)
    }
    @jsonl.each(reader, json => {
      if @event.decode_event(json) is Some(event) {
        if is_terminal_event(event) {
          self.run_open = false
        }
        self.messages.try_put(AgentProgress(run_id=self.latest_run, event))
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
    self.live = None
    let code = proc.wait()
    // EOF with a run still open means the engine died mid-turn: close that
    // run with its only available diagnostics. A terminal event followed by
    // a clean exit (TUI shutdown, graceful EOF) reports nothing.
    if self.run_open {
      let diagnostics = stderr_task.wait().trim()
      let detail = if diagnostics.is_empty() { "" } else { ":\n\{diagnostics}" }
      self.run_open = false
      self.messages.put(
        AgentProgress(
          run_id=self.latest_run,
          AgentError("engine exited (code \{code}) without a result\{detail}"),
        ),
      )
    }
  }
}

///|
/// Write one JSONL command line to the engine, starting it first when
/// needed. A write failure means the engine just died: the client is marked
/// dead for respawn and the error is reported against `run_id`.
async fn[G] EngineClient::send(
  self : EngineClient,
  group : @async.TaskGroup[G],
  run_id : Int,
  command : Json,
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
  self.latest_run = run_id
  self.run_open = true
  self.send(group, run_id, { "command": "prompt", "text": text })
}

///|
async fn[G] EngineClient::steer(
  self : EngineClient,
  group : @async.TaskGroup[G],
  text : String,
) -> Unit {
  self.send(group, self.latest_run, { "command": "steer", "text": text })
}

///|
async fn[G] EngineClient::cancel_turn(
  self : EngineClient,
  group : @async.TaskGroup[G],
) -> Unit {
  self.send(group, self.latest_run, { "command": "cancel" })
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
