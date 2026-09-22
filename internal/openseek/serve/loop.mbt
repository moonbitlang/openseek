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
///
/// `approval` is the one command that answers the engine rather than
/// instructing it, and the one whose absence stalls a turn: under
/// `--approval ask` a tool that asks to run outside its sandbox blocks until
/// the decision arrives, with no deadline behind it. A controller that cannot
/// answer must not ask to be asked — the flag defaults to `never`, and under
/// it the argument that asks is not offered to the model at all.
/// Session-server skeleton — one steps queue, three producers, one pump;
/// `active_work` is the only mode state (turn │ compact │ idle):
///
///   producers: stdin reader ──────────── Wire(command)
///              turn/compact completions ─ TurnDone(finished~) │ CompactDone
///              background-job exits ───── BackgroundNotice
///   pump: for ;; match step
///     ├─ Wire(Prompt)          ── active? queue pending : start turn
///     ├─ Wire(Steer(Prompt))   ── turn running │ prompt queued? queue steer : reject
///     ├─ Wire(Steer(Command│Notice)) ── queue losslessly; idle ⇒ drain to log
///     ├─ Wire(Cancel)          ── cancel active work; disarm auto-continue
///     ├─ Wire(Compact)         ── idle? start compact : queue
///     ├─ Wire(Goal)            ── durable marker; auto=true arms auto-continue
///     ├─ Wire(Approval)        ── release a tool blocked INSIDE the active turn
///     ├─ BackgroundNotice      ── idle? drain queued context to the log
///     ├─ TurnDone              ── drain context ── start next pending work
///     │                           └─ armed goal(auto) unmet ⇒ auto-continue
///     ├─ CompactDone           ── adopt compacted session ── start next pending
///     └─ Shutdown              ── exit serve~
async fn run_serve(
  matches : @argparse.Matches,
  workspace_root~ : String,
) -> Unit {
  let (model, thinking, api_url) = @options.agent_settings(matches)
  guard model.api_key(matches.values) is Some(api_key) else {
    fail("an API key is required for \{model}: pass --api-key")
  }
  let (retry_attempts, retry_backoff_ms) = @options.retry_overrides(matches)
  let max_steps = @options.max_steps(matches)
  let review_deadline_ms = @options.review_deadline_ms(matches)
  let session_id = match matches {
    {
      values: {
        "session"? : Some([session, ..])
        | (Some([]) | None with session = ""),
        ..
      },
      ..
    } =>
      match session.trim() {
        "" => None
        session => Some(@agent_session.SessionId("\{session}"))
      }
  }
  let (store, initial_session) = match session_id {
    Some(id) => {
      let store = @store.SessionStore(
        @setup.session_root(matches, workspace_root~),
      )
      (
        Some(store),
        @setup.load_or_new_session(store, id, matches, model, workspace_root~),
      )
    }
    // No durable session requested: the conversation still spans every
    // prompt of this process's lifetime, it just leaves nothing behind.
    None =>
      (
        None,
        Session(
          SessionId("serve"),
          system_prompt=@setup.configured_system_prompt(
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
  // The desk outlives every turn: a question is asked by a tool inside one
  // turn's task and answered by the loop below, which is the process's single
  // command consumer. Both close over this one value.
  let approval_desk = @execution.ApprovalDesk::ApprovalDesk(
    now_ms=@env.now().reinterpret_as_int64(),
  )
  let approval = @execution.approval_channel(
    @execution.approval_policy(matches, interactive=true),
    approval_desk,
  )
  @async.with_task_group(group => {
    let runtime = @agent_runtime.AgentRuntime(workspace_root~, approval?)
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
    let exe = @setup.self_executable()
    // A durable serve session makes its children durable siblings
    // (`<id>-sr-N` in the same root); --no-session keeps them in-memory.
    // The ordinal floor keeps a resumed session from reusing a child id an
    // earlier engine process persisted.
    let child_session = match store {
      Some(store) => {
        let parent = initial_session.id().value()
        Some(
          @agent_subrun.ChildSession(
            root=store.root(),
            parent~,
            first_free=@setup.first_free_child_ordinal(store, parent),
          ),
        )
      }
      None => None
    }
    // The same coordinates, in the shape an mbtx snippet needs: a workflow it
    // runs delegates to children that must be named from the SAME ordinal
    // counter `run_subrun` uses, or a snippet's child and a `review` child
    // collide on one transcript file.
    let mbtx_subrun = child_session.map(spec => {
      let (exe, launch_prefix) = @setup.workflow_launch(exe)
      spec.injection(
        exe~,
        launch_prefix~,
        workspace_root~,
        model="\{model}",
        api_url?,
        // Read at reservation time from the loop-updated session, never a
        // snapshot: a review requested mid-turn audits the LIVE goal.
        criteria=() => @execution.audit_criteria(session),
      )
    })
    let extra_tools = @execution.build_extra_tools(
      scope,
      model~,
      api_key~,
      workspace_root~,
      mcp_config_path?=@options.mcp_config_path(matches),
      deepseek_api_key?=@options.deepseek_api_key(matches),
      api_url?,
    )
    // The advisory goal-met gate (--review-gate): built once, shared by
    // every turn; engine-initiated, so it runs on its own allowance.
    let on_goal_met = if @options.review_gate_enabled(matches) {
      Some(
        @execution.build_goal_met_gate(
          self_exe=exe,
          model~,
          api_url~,
          workspace_root~,
          review_deadline_ms?,
          child_session?,
        ),
      )
    } else {
      None
    }
    let job_log_dir = match store {
      Some(store) => Some(store.job_logs_dir(initial_session.id()))
      None => None
    }
    let tools = @agent.build_tools(
      runtime,
      scope,
      job_log_dir?,
      on_background_wake=() => {
        ignore(steps.try_put(BackgroundNotice) catch { _ => false })
      },
      extra_tools~,
      mbtx_subrun?,
    )
    group.spawn_bg(no_wait=true) <| () => {
      @jsonl.each(@stdio.stdin, json => {
        match decode_serve_command(json) {
          Ok(command) => steps.try_put(Wire(command)) |> ignore
          Err(message) => @emit.emit(CommandError(error=message))
        }
      }) catch {
        @async.TaskCancelled as error => raise error
        // A malformed (non-JSON) line is a controller bug: report it and
        // stop reading commands, which shuts the server down gracefully.
        error => @emit.emit(CommandError(error="command stream: \{error}"))
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
      @compact.compact_session(
        store?,
        current,
        api_key~,
        model~,
        api_url?,
        retry_attempts?,
        retry_backoff_ms?,
      ) catch {
        @async.TaskCancelled as error => raise error
        error => {
          @emit.emit(CompactionFailed(error="\{error}"))
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
          @async.TaskCancelled as error => raise error
          error => {
            @emit.emit(SessionError(error="failed to append \{what}: \{error}"))
            return false
          }
        }
      } else {
        session.append(item)
      }
      true
    }

    async fn append_command_context(
      text : String,
      kind : String,
      submission_id : String?,
    ) -> Unit {
      if append_idle_item(
          User(UserMessage(text, submission_id?)),
          "command context",
        ) {
        @emit.emit(SteerApplied(kind~, content=text, submission_id~))
      }
    }

    // Report a durably appended goal marker to the controller. Called only
    // after the append succeeded — never at queue time, when the marker could
    // still be lost with a dying turn — so the TUI can only learn a goal that
    // was actually persisted.
    fn report_goal_update(content : String) -> Unit {
      match @agent_session.goal_marker(content) {
        Some(GoalSet(text)) => @emit.emit(GoalUpdated(goal=Some(text)))
        Some(GoalCleared) => @emit.emit(GoalUpdated(goal=None))
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
    // Persist the captured baseline notice, if any, IMMEDIATELY before its
    // goal marker: Session::current_goal_baseline pairs strictly by
    // adjacency, and this loop is the single appender on the idle/drain
    // paths. A failed baseline append is absorbed — the goal still sets;
    // only the future review gate loses its anchor.
    async fn append_goal_baseline(baseline : String?) -> Unit {
      if baseline is Some(notice) {
        append_idle_item(Runtime(RuntimeNotice(notice)), "goal baseline")
        |> ignore
      }
    }

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
        @emit.emit(BackgroundNotice(content=text))
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
        Prompt(text, submission_id~) =>
          @emit.emit(SteerDropped(content=text, submission_id~))
        Command(text, submission_id~) =>
          append_command_context(text, "command", submission_id)
        Notice(text) =>
          if @agent_session.parse_goal_baseline(text) is Some(_) {
            // The steer-path baseline landing at idle (its turn ended
            // first): persist it exactly where it sits in the drain order —
            // its goal marker is the very next input — without dressing it
            // as a background notice.
            append_idle_item(Runtime(RuntimeNotice(text)), "goal baseline")
            |> ignore
          } else {
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
        .search_by(input => input is Prompt(_, ..))
        .unwrap_or(inputs.length())
      for input in inputs[boundary:] {
        runtime.queue_steer(input)
      }
      [..inputs[:boundary]]
    }

    fn start_turn(
      task_text : String,
      submission_id : String?,
    ) -> @async.Task[Unit] {
      group.spawn() <| () => {
        errdefer {
          @emit.emit(AgentAborted(reason="interrupted"))
          ignore(steps.try_put(TurnDone(finished=false)) catch { _ => false })
        }
        let _ = @agent.run_turn_in_scope(
          runtime~,
          scope~,
          api_key~,
          model~,
          session~,
          task=task_text,
          submission_id?,
          on_goal_met?,
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
          retry_attempts?,
          retry_backoff_ms?,
          tools~,
        ) catch {
          error => {
            // The turn died but the session server must not: a cancelled
            // turn already appended its Interrupted terminal inside the
            // loop, and any other failure is reported as a terminal wire
            // event so the controller can close the run.
            if error is @async.TaskCancelled {
              @emit.emit(AgentAborted(reason="interrupted"))
            } else {
              @emit.emit(TurnFailed(error="\{error}"))
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
        errdefer {
          @emit.emit(CompactionFailed(error="cancelled"))
          ignore(steps.try_put(CompactDone(current)) catch { _ => false })
        }
        let next = compact_and_report(current) catch {
          @async.TaskCancelled => {
            @emit.emit(CompactionFailed(error="cancelled"))
            current
          }
          error => {
            @emit.emit(CompactionFailed(error="\{error}"))
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
          PendingPrompt(text, submission_id~) =>
            active_work = Some(ActiveTurn(start_turn(text, submission_id)))
          PendingCompact =>
            active_work = Some(ActiveCompact(start_compaction(session)))
          // Instant work: append the goal at its ordered position and keep
          // draining the queue. A command context produced BEFORE the goal
          // was queued lands first — the goal may depend on that output,
          // and durable order must match arrival order.
          // Fenced context: apply at its ordered position and keep draining.
          PendingContext(input) => apply_idle_context_input(input)
          PendingGoal(marker, context, is_auto, serial, baseline) => {
            for input in context {
              apply_idle_context_input(input)
            }
            append_goal_baseline(baseline)
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
        @async.TaskCancelled as error => raise error
        _ => break serve~
      }
      match step {
        Wire(Prompt(text, submission_id~)) =>
          match active_work {
            // One turn at a time: extra prompts wait their wire-order turn.
            Some(_) => pending.push(PendingPrompt(text, submission_id~))
            None =>
              active_work = Some(ActiveTurn(start_turn(text, submission_id)))
          }
        Wire(Steer(input)) =>
          match input {
            Prompt(text, submission_id~) =>
              match active_work {
                // A turn is running, or a prompt is queued ahead of this steer:
                // the lossless steering queue delivers it at that turn's next
                // step boundary (or its first, if it has not started yet).
                Some(ActiveTurn(_)) =>
                  runtime.queue_steer(Prompt(text, submission_id~))
                Some(ActiveCompact(_)) | None =>
                  if has_pending_prompt(pending) {
                    runtime.queue_steer(Prompt(text, submission_id~))
                  } else {
                    // An idle (or merely compacting) engine never converts
                    // prompt steering into a prompt: the only way it arrives
                    // here is racing a turn's terminal event through the pipes.
                    // Reject it so the controller can ask for a resubmit.
                    @emit.emit(SteerDropped(content=text, submission_id~))
                  }
              }
            Command(text, submission_id~) =>
              // Defer to the steering queue whenever any work is active (a turn
              // or a compaction) or a prompt is queued, so the context is
              // appended at the next turn's drain — never written straight into
              // a session a running compaction is about to replace. Only a fully
              // idle engine appends it immediately.
              if has_pending_goal(pending) {
                // Fenced behind the queued goal: wire order must stay
                // goal-then-context for context sent after the goal.
                pending.push(PendingContext(Command(text, submission_id~)))
              } else if active_work is Some(_) || has_pending_prompt(pending) {
                runtime.queue_steer(Command(text, submission_id~))
              } else {
                append_command_context(text, "command", submission_id)
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
        Wire(JobsSnapshot(request_id~)) => {
          let jobs = match tools.background_job_runtime() {
            Some(runtime) => runtime.records()
            None => []
          }
          @emit.emit(JobsSnapshot(request_id~, jobs~))
        }
        Wire(JobStop(request_id~, generation~, job_id~)) => {
          let _ = group.spawn(no_wait=true) <| () => {
            let outcome : @protocol.JobStopOutcome = match
              tools.background_job_runtime() {
              None => NotFound
              Some(jobs) =>
                if jobs.generation() != generation {
                  WrongRuntime
                } else if jobs.snapshot(job_id) is None {
                  NotFound
                } else if jobs
                  .records()
                  .any(job => job.id == job_id && job.state.is_terminal()) {
                  AlreadyTerminal
                } else {
                  ignore(jobs.stop(job_id))
                  Stopped
                }
            }
            @emit.emit(
              JobStopResult(request_id~, generation~, job_id~, outcome~),
            )
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
            Some(ActiveTurn(task)) | Some(ActiveCompact(task)) => task.cancel()
            None =>
              // No active work: in wire order the cancel targets the next
              // submitted prompt, so withdraw it before it starts.
              remove_next_pending_prompt(pending)
          }
        }
        // Never queued behind active work, and never queued at all: the tool
        // it answers is ALREADY running, inside the active turn, blocked on
        // this reply. Deferring it the way a prompt is deferred would wait for
        // the very turn the answer is needed to finish.
        Wire(Approval(id~, allow~)) => approval_desk.settle(id, allow)
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
          // Captured at COMMAND RECEIPT (bounded; see baseline.mbt) so every
          // path records the worktree as it stood when the user set the
          // goal, not when the marker eventually lands. For a QUEUED goal
          // behind a long turn this anchor may predate that turn's commits
          // — a known divergence: the gate treats the baseline as advisory
          // context for a current-worktree audit, never exact attribution.
          let baseline : String? = match action {
            SetGoal(_, ..) => Some(@setup.capture_goal_baseline(workspace_root))
            ClearGoal => None
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
              PendingGoal(
                marker, context, is_auto, goal_command_serial, baseline,
              ),
            )
          } else if active_work is Some(ActiveTurn(_)) {
            // A live turn: the lossless steer queue makes the marker
            // model-visible at the next step boundary (reporting after the
            // durable append); if the turn ends first, the TurnDone drain
            // persists it before any queued prompt starts, so the next turn
            // still sees it.
            // Two consecutive synchronous queue_steer calls: nothing can
            // interleave between them, so the loop applies (or the idle
            // drain persists) baseline and marker adjacently.
            if baseline is Some(notice) {
              runtime.queue_steer(Notice(notice))
            }
            runtime.queue_steer(Notice(marker), wake=true)
          } else {
            append_goal_baseline(baseline)
            if append_goal_marker(marker) {
              maybe_promote_goal_auto(false)
            }
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
            @emit.emit(GoalContinue(remaining=goal_turns_remaining))
            active_work = Some(ActiveTurn(start_turn(GoalContinuePrompt, None)))
          } else if armed &&
            finished &&
            !shutting_down &&
            active_work is None &&
            pending.length() == 0 &&
            goal_turns_remaining == 0 {
            // The loop ran its full budget without the goal being met:
            // disarm and tell the controller, once.
            goal_auto_target = None
            @emit.emit(GoalBudgetExhausted(turns=GoalAutoContinueMaxTurns))
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
          // The reader that would have answered them is what just died, so
          // every standing question is now unanswerable. Active work is
          // allowed to finish on EOF rather than being cancelled, which only
          // terminates if each wait inside it can still end — and an
          // approval's is the one with no clock behind it.
          approval_desk.withdraw_all()
          if active_work is None && pending.length() == 0 {
            break serve~
          }
        }
      }
    }
  })
}
