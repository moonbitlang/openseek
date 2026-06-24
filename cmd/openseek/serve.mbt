///|
/// One decoded command from the serve-mode controller (e.g. the TUI) on
/// stdin.
priv enum ServeCommand {
  Prompt(String)
  Steer(@agent_runtime.SteerInput)
  Compact
  Cancel
}

///|
/// A queued serve-mode operation that must wait for active work to finish.
priv enum PendingWork {
  PendingPrompt(String)
  PendingCompact
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
  TurnDone
  CompactDone(@agent_session.Session)
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
      match decode_steer_input(json) {
        Ok(input) => Ok(Steer(input))
        Err(message) => Err(message)
      }
    { "command": "prompt", .. } => Err("expected a string \"text\" field")
    { "command": "compact", .. } => Ok(Compact)
    { "command": "cancel", .. } => Ok(Cancel)
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
}

///|
fn remove_next_pending_prompt(pending : Array[PendingWork]) -> Unit {
  for index, work in pending {
    if work is PendingPrompt(_) {
      ignore(pending.remove(index))
      return
    }
  }
}

///|
fn has_pending_prompt(pending : Array[PendingWork]) -> Bool {
  for work in pending {
    if work is PendingPrompt(_) {
      return true
    }
  }
  false
}

///|
test "pending prompt helpers ignore queued compactions" {
  let pending : Array[PendingWork] = []
  assert_false(has_pending_prompt(pending))
  pending.push(PendingCompact)
  assert_false(has_pending_prompt(pending))
  pending.push(PendingPrompt("next"))
  assert_true(has_pending_prompt(pending))
  remove_next_pending_prompt(pending)
  assert_false(has_pending_prompt(pending))
  assert_eq(pending.length(), 1)
  assert_true(pending[0] is PendingCompact)
}

///|
/// Run the engine as a long-lived session server: read JSONL commands from
/// stdin, run turns sequentially against one shared session, and write the
/// usual JSONL event stream to stdout. This is the engine half of the
/// persistent-engine design — one process per conversation instead of one
/// per prompt.
///
/// The runtime and the tool registry are built once and shared by every
/// turn, so stateful tools survive turn boundaries (a `moon_check` watcher
/// started in turn 1 keeps reporting in turn 5). `steer` rides the
/// runtime's lossless steering queue into the running (or already
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
  let api_key = api_key(matches)
  let api_url = api_url(matches)
  let model = @deepseek.Model::parse(value(matches, "model"))
  let max_steps = max_steps(matches)
  let thinking = @deepseek.ThinkingMode::parse(value(matches, "thinking"))
  let (store, initial_session) = match session_id(matches) {
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
    // Built once: stateful tool records live in this registry, and
    // rebuilding it per turn would orphan running watchers (see
    // @agent.build_tools).
    let tools = @agent.build_tools(runtime, scope)
    // All scheduling flows through one ordered queue with one consumer:
    // wire commands from the reader, plus the internal turn-completion and
    // shutdown markers. A second scheduler (e.g. acting on commands inside
    // the reader) would race the consumer's view of the active turn — a
    // controller writing `prompt\nsteer\n` in one buffer must have its
    // steer land in that prompt's turn, exactly as the wire order says.
    let steps : @async.Queue[ServeStep] = Queue(kind=Unbounded)
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

    async fn append_command_context(text : String) -> Unit {
      session = if store is Some(store) {
        store.append(session, User(UserMessage(text))) catch {
          error if @async.is_being_cancelled() ||
            @async.is_cancellation_error(error) => raise error
          error => {
            @xlog.error() <?
              {
                "event": "session_error",
                "error": "failed to append command context: \{error}",
              }
            return
          }
        }
      } else {
        session.append(User(UserMessage(text)))
      }
      @xlog.info() <?
        { "event": "steer_applied", "kind": "command", "content": text }
    }

    // Steers still queued when work ends: prompt steering must not leak into a
    // later turn, but command context is durable local output, so persist it at
    // the session's current boundary. Called whenever the loop returns to idle
    // (turn or compaction done), so a `!` delivered mid-work is never left
    // orphaned in the steer queue to be lost or applied to an unrelated prompt.
    async fn drain_command_context() -> Unit {
      for input in runtime.drain_steers() {
        match input {
          Prompt(text) =>
            @xlog.warn() <? { "event": "steer_dropped", "content": text }
          Command(text) => append_command_context(text)
        }
      }
    }

    fn start_turn(task_text : String) -> @async.Task[Unit] {
      group.spawn() <| () => {
        let _ = @agent.run_turn_in_scope(
          runtime,
          scope,
          api_key,
          model,
          session,
          task_text,
          append_item=(current, item) => {
            let next = match store {
              Some(store) => store.append(current, item)
              None => current.append(item)
            }
            session = next
            next
          },
          max_steps~,
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
            ignore(steps.try_put(TurnDone) catch { _ => false })
            return
          }
        }
        ignore(steps.try_put(TurnDone) catch { _ => false })
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

    fn start_next_pending() -> Unit {
      pending_loop~: for ;; {
        if active_work is Some(_) || pending.length() == 0 {
          break pending_loop~
        }
        match pending.remove(0) {
          PendingPrompt(text) => {
            active_work = Some(ActiveTurn(start_turn(text)))
            break pending_loop~
          }
          PendingCompact => {
            active_work = Some(ActiveCompact(start_compaction(session)))
            break pending_loop~
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
                Some(ActiveTurn(_)) => @agent.steer(runtime, text)
                Some(ActiveCompact(_)) | None =>
                  if has_pending_prompt(pending) {
                    @agent.steer(runtime, text)
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
              if active_work is Some(_) || has_pending_prompt(pending) {
                runtime.queue_steer(Command(text))
              } else {
                append_command_context(text)
              }
          }
        Wire(Cancel) =>
          match active_work {
            Some(ActiveTurn(task)) => task.cancel()
            Some(ActiveCompact(task)) => task.cancel()
            None =>
              // No active work: in wire order the cancel targets the next
              // submitted prompt, so withdraw it before it starts.
              if pending.length() > 0 {
                remove_next_pending_prompt(pending)
              }
          }
        Wire(Compact) =>
          if active_work is Some(_) {
            pending.push(PendingCompact)
          } else {
            active_work = Some(ActiveCompact(start_compaction(session)))
          }
        TurnDone => {
          drain_command_context()
          active_work = None
          start_next_pending()
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
