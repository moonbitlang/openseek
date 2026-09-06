///|
priv struct AgentLoop {
  runtime : @agent_runtime.AgentRuntime
  client : @client.Client
  /// Client for auto-compaction checkpoint summaries: thinking=No where the
  /// model honors the control — a handoff summary needs no reasoning budget.
  summary_client : @client.Client
  tools : @agent_tool.Tools
  append_item : async (@agent_session.Session, @agent_session.SessionItem) -> @agent_session.Session
  /// Turn-local DeepSeek request buffer. `AgentLoop` is private and per-run; a
  /// later user turn gets a fresh loop seeded from `Session::chat_messages`, not
  /// this array. Updates are append-first: whenever the loop adds a message here
  /// for a newly appended session item, the durable append has already
  /// succeeded.
  messages : Array[@deepseek.ChatMessage]
  plan_cadence : PlanCadence
  goal_cadence : GoalCadence
  /// The advisory goal-met gate: given the met goal's text and its
  /// captured baseline, produce the notice to append (or None for
  /// nothing). Review-neutral by type — the CLI layer supplies a callback
  /// that runs the reviewer child; the loop only schedules and injects.
  on_goal_met : (async (String, @agent_session.GoalBaseline?) -> String?)?
  /// Latest session returned by a successful append. The run-level error
  /// handler uses it to persist a terminal failure/interruption even when the
  /// local loop state is behind the last durable session.
  mut last_session : @agent_session.Session
}

///|
fn AgentLoop::AgentLoop(
  runtime~ : @agent_runtime.AgentRuntime,
  client~ : @client.Client,
  summary_client~ : @client.Client,
  tools~ : @agent_tool.Tools,
  append_item~ : async (@agent_session.Session, @agent_session.SessionItem) -> @agent_session.Session,
  session~ : @agent_session.Session,
  on_goal_met? : async (String, @agent_session.GoalBaseline?) -> String?,
) -> AgentLoop {
  {
    runtime,
    client,
    summary_client,
    tools,
    append_item,
    on_goal_met,
    messages: session.chat_messages(),
    plan_cadence: PlanCadence(registered=tools.find("plan") is Some(_)),
    goal_cadence: GoalCadence(
      session,
      // Control-gated like the finish salvage: a custom non-control tool
      // that happens to be named "goal" keeps its own schema and executor —
      // the loop protocol only claims the name when the registered
      // definition declares itself a control tool (the built-in does).
      tool_registered=tools.find("goal") is Some(definition) &&
        definition.is_control(),
    ),
    last_session: session,
  }
}

///|
priv enum FinishOutcome {
  /// The terminal is appended; the turn is over.
  Sealed(@agent_session.Session)
  /// User input arrived during the compact-on-finish checkpoint: the
  /// answer stayed an ordinary assistant message, the steers are applied,
  /// and the turn continues from the compacted projection.
  ContinueTurn(@agent_session.Session)
}

///|
priv enum AgentStepOutcome {
  StepContinue(@agent_session.Session)
  StepDone(@agent_session.Session)
  /// The running batch budget stopped execution: the remainder is already
  /// skip-closed and the turn must yield at the ceiling checkpoint.
  StepYield(@agent_session.Session)
}

///|
priv enum ToolCallOutcome {
  /// The tool returned a normal result; continue executing the remaining calls
  /// in the current assistant tool-call batch.
  ContinueToolBatch(@agent_session.Session)
  /// Stop the current tool batch and let the agent make another model request
  /// with the updated session, without appending a terminal item.
  ContinueAgentLoop(@agent_session.Session)
  /// Stop the current tool batch and finish the agent turn with a terminal
  /// session item already appended.
  FinishAgentLoop(@agent_session.Session)
}

///|
/// A finish attempt's verdict, seen from inside a tool batch: a sealed turn
/// stops the loop, a compact-on-finish continuation goes back to the model.
fn ToolCallOutcome::of_finish(outcome : FinishOutcome) -> ToolCallOutcome {
  match outcome {
    Sealed(session) => FinishAgentLoop(session)
    ContinueTurn(session) => ContinueAgentLoop(session)
  }
}

///|
/// Result note for tool calls discarded because the turn is ending at the
/// context ceiling.
let ceiling_skip_note : String = "skipped: the turn is yielding at the context ceiling; re-issue after the checkpoint if still needed"

///|
/// Turn skeleton — one provider round per step; every exit lands in exactly
/// one labeled terminal:
///
///   for step < max_steps:
///     prepare_step ── chat(step)
///     ├─ no tool calls
///     │   ├─ no steers ── goal unchecked? ─ goal-check round ─ (seal │ continue)
///     │   │               else finish_turn ─────────────────── (seal │ continue)
///     │   └─ steers ── record answer as a plain assistant message
///     │                ├─ soft ceiling ── yield (checkpoint; steers survive)
///     │                └─ apply steers ── continue
///     ├─ hard ceiling ── record assistant ── salvage a finish?
///     │   ├─ salvaged ── (done │ continue │ yield)
///     │   └─ close the batch with skip notes ── yield
///     └─ tool batch ── handle_tool_calls ── (continue │ done │ budget yield)
///   nobreak ── Terminal(Failed("max steps exhausted"))
///   catch   ── Terminal(Interrupted │ Failed) ── re-raise
///
/// "seal │ continue": finishing consults the checkpoint policy — a turn that
/// completes at the ceiling checkpoints first, and a steer landing during that
/// checkpoint converts the finish into a continuation.
async fn AgentLoop::run(
  self : Self,
  session : @agent_session.Session,
  max_steps : Int,
) -> @agent_session.Session {
  self.last_session = session
  try {
    for step in 0..<max_steps; session = session {
      let session = self.prepare_step(session)
      let response = self.chat(step)
      // Usage only exists per response, so ceiling pressure is detected at
      // each exit point below by consulting this response's usage — no
      // pressure state exists anywhere, not even across lines: a pressured
      // step always ends the turn within its own iteration. Two tiers: at
      // the SOFT ceiling the turn ends gracefully at this step's boundary
      // (batches still execute, aggregate-budgeted); at the HARD ceiling —
      // or when a soft batch cannot be proven to fit — no batch starts.
      // Abort and error exits stay exempt by policy: failure paths never
      // wait on a checkpoint request.
      if response.tool_calls.is_empty() {
        let steer_inputs = self.runtime.pending_steers()
        if steer_inputs.is_empty() {
          if step + 1 < max_steps &&
            self.goal_cadence.due_finish_check() is Some(_) {
            // The model considers itself done, but the standing goal is
            // unconfirmed: keep the would-be answer as an ordinary assistant
            // message and ask once whether the goal is met. The model may
            // finish again immediately, so the turn is never held hostage.
            // At the ceiling the history is checkpointed first, so the
            // check round cannot overflow the pressured context.
            match
              self.continue_into_goal_check(
                session,
                response.usage,
                spent_result_chars=0,
                kept_answer=response.content,
                keep_only_when_compacted=false,
                reasoning_content?=response.optional_reasoning_content(),
              ) {
              Sealed(next) => return next
              ContinueTurn(next) => continue next
            }
          }
          // Every provider response is durable as an Assistant event. The
          // terminal seals the turn but does not double as model-step evidence.
          match
            self.finish_turn(
              session,
              response.content,
              usage=response.usage,
              reasoning_content?=response.optional_reasoning_content(),
            ) {
            Sealed(next) => return next
            ContinueTurn(next) => continue next
          }
        }
        // The model considers itself done, but user-visible input arrived while the
        // final call was in flight: user input wins over model-initiated completion.
        // The would-be answer stays as an ordinary assistant message and the turn
        // continues with the new input folded in.
        let session = self.record_assistant(session, response)
        if self.at_soft_context_ceiling(response.usage) {
          // Yield now rather than answering the steer in a starved context;
          // the steers survive the checkpoint verbatim.
          return self.yield_at_context_ceiling(session, steer_inputs)
        }
        let session = self.apply_steer_inputs(session, steer_inputs)
        continue session
      } else if self.at_hard_context_ceiling(response.usage) {
        // Past the hard ceiling the batch never executes: its results
        // could fill the remaining headroom, overflowing the checkpoint
        // request itself. Close every call with a skip note — API-valid, a
        // few bytes — and yield; the checkpoint summary carries the state
        // and the model re-issues the calls next turn if needed.
        let session = self.record_assistant(
          session,
          response,
          tool_calls=response.tool_calls,
        )
        match
          self.salvage_control_calls_at_ceiling(
            session,
            response,
            last_step=step + 1 >= max_steps,
          ) {
          Some(StepDone(next)) => return next
          // A steer arrived during the salvaged finish's checkpoint: the
          // turn continues from the compacted projection.
          Some(StepContinue(next)) => continue next
          Some(StepYield(next)) =>
            return self.yield_at_context_ceiling(
              next,
              self.runtime.pending_steers(),
            )
          None => ()
        }
        let session = self.close_skipped_tool_calls(
          session,
          response.tool_calls,
          note=ceiling_skip_note,
        )
        return self.yield_at_context_ceiling(
          session,
          self.runtime.pending_steers(),
        )
      } else {
        match
          self.handle_tool_calls(
            session,
            response,
            last_step=step + 1 >= max_steps,
          ) {
          // Plain continuation — including after a checkpoint whose late
          // steer converted a finish into a continue: the soft decision
          // lives in handle_tool_calls, which knows the batch's real
          // growth and must not re-fire on stale pre-checkpoint usage.
          StepContinue(next) => continue next
          StepDone(next) => return next
          // The running budget stopped the batch mid-way — at ANY usage
          // level, including below the soft ceiling: a below-threshold
          // response with several large results could otherwise push the
          // next request past the window before any ceiling check runs.
          StepYield(next) =>
            return self.yield_at_context_ceiling(
              next,
              self.runtime.pending_steers(),
            )
        }
      }
    } nobreak {
      // A goal met in the last step's batch still needs its durable clear.
      let session = self.flush_goal_tombstone(session)
      let session = self.append(
        session,
        Terminal(Failed("max steps exhausted")),
      )
      @emit.emit(MaxStepsExhausted)
      session
    }
  } catch {
    error => self.seal_unwinding_turn(error)
  }
}

///|
/// Record the terminal a dying turn implies, then let the error keep
/// propagating — this never returns normally. Every append here is best
/// effort: the store may already be gone, and the caller's error outranks
/// anything that fails on the way out.
async fn[T] AgentLoop::seal_unwinding_turn(self : Self, error : Error) -> T {
  let terminal : @agent_session.SessionItem = if @async.is_being_cancelled() ||
    @async.is_cancellation_error(error) {
    Terminal(Interrupted("cancelled"))
  } else {
    Terminal(Failed("agent failed: \{error}"))
  }
  // Best-effort: a goal met in the dying batch keeps its durable clear
  // when the store still accepts appends.
  let session = self.flush_goal_tombstone(self.last_session) catch {
    _ => self.last_session
  }
  ignore(self.append(session, terminal) catch { _ => session })
  raise error
}

///|
async fn AgentLoop::append(
  self : Self,
  session : @agent_session.Session,
  item : @agent_session.SessionItem,
) -> @agent_session.Session {
  let next = (self.append_item)(session, item)
  self.last_session = next
  next
}

///|
/// Durably append a runtime notice and mirror it into the in-flight chat
/// buffer — the notice becomes model-visible only after the durable append
/// succeeds, so a failed append never leaves the buffer ahead of the log.
async fn AgentLoop::append_runtime_notice(
  self : Self,
  session : @agent_session.Session,
  content : String,
) -> @agent_session.Session {
  let next = self.append(session, Runtime(RuntimeNotice(content)))
  self.messages.push(ChatMessage(User, content~))
  next
}

///|
/// Durably append the response's assistant message and mirror it into the
/// in-flight chat buffer — the two must stay in lockstep (see `messages`).
async fn AgentLoop::record_assistant(
  self : Self,
  session : @agent_session.Session,
  response : @deepseek.ChatResponse,
  tool_calls? : Array[@deepseek.ToolCall],
) -> @agent_session.Session {
  let reasoning_content = response.optional_reasoning_content()
  let session = self.append(
    session,
    Assistant(
      AssistantMessage(response.content, tool_calls?, reasoning_content?),
    ),
  )
  self.messages.push(
    ChatMessage(
      Assistant,
      content=response.content,
      tool_calls?,
      reasoning_content?,
    ),
  )
  session
}

///|
fn AgentLoop::push_finished_message(self : Self, answer : String) -> Unit {
  if !answer.is_blank() {
    self.messages.push(ChatMessage(Assistant, content=answer))
  }
}

///|
/// Fold steering input into the conversation: each becomes a durable session
/// item and a model-visible chat message. Prompt/command steering persists as a
/// user message; a background notice persists as a `RuntimeNotice` (so on resume
/// it renders as a system notice, not user input). All emit `steer_applied`; the
/// `kind` field distinguishes them.
async fn AgentLoop::apply_steer_inputs(
  self : Self,
  session : @agent_session.Session,
  inputs : ArrayView[@agent_runtime.SteerInput],
) -> @agent_session.Session {
  for input in inputs; current = session {
    let (kind, text, item) : (String, String, @agent_session.SessionItem) = match
      input {
      Prompt(text) => ("prompt", text, User(UserMessage(text)))
      Command(text) => ("command", text, User(UserMessage(text)))
      Notice(text) => ("notice", text, Runtime(RuntimeNotice(text)))
    }
    let next = self.append(current, item)
    // A goal-baseline notice is transport for the durable pairing record:
    // it must land in the session (adjacent to its marker) but carries
    // nothing for the model — a commit sha as user input is pure noise —
    // and nothing for controllers, who would only have to filter it back
    // out of every echo path.
    if input is Notice(text) &&
      @agent_session.parse_goal_baseline(text) is Some(_) {
      continue next
    }
    self.messages.push(ChatMessage(User, content=text))
    @emit.emit(SteerApplied(kind~, content=text))
    if input is Notice(text) {
      self.goal_cadence.observe_notice(text)
    }
    continue next
  } nobreak {
    current
  }
}

///|
async fn AgentLoop::prepare_step(
  self : Self,
  session : @agent_session.Session,
) -> @agent_session.Session {
  // A goal(met) recorded in the previous batch lands its durable tombstone
  // here, at a batch-safe boundary.
  let session = self.flush_goal_tombstone(session)
  // Steering first: user-visible mid-turn input should be applied before plan
  // reminders or the next model request.
  let session = self.apply_steer_inputs(session, self.runtime.pending_steers())
  // A goal met without a finish attempt still gets its owed review before
  // the next model request (the finish seams handle the met-then-finish
  // shapes; this covers met-then-keep-working). AFTER the steers: a queued
  // replacement goal observed just above clears the pending review, so a
  // superseded audit is cancelled before it ever launches.
  let mut session = self.run_pending_review(session)
  if self.goal_cadence.due_reminder() is Some(goal) {
    let reminder = goal_reminder_text(
      goal,
      tool_registered=self.goal_cadence.tool_registered,
    )
    session = self.append_runtime_notice(session, reminder)
    @emit.emit(GoalReminder(content=reminder))
    self.goal_cadence.record_reminder()
  }
  if self.plan_cadence.should_remind() {
    let reminder = self.plan_cadence.reminder_text()
    session = self.append_runtime_notice(session, reminder)
    @emit.emit(PlanReminder(content=reminder))
    self.plan_cadence.record_reminder()
  }
  self.plan_cadence.record_model_request()
  session
}

///|
async fn AgentLoop::chat(self : Self, step : Int) -> @deepseek.ChatResponse {
  @emit.emit(AgentStep(step=step + 1))
  let response = self.client.chat(
    self.messages,
    tools=self.tools.function_tools(),
    stream=StreamHandler(
      on_content_delta=delta => {
        if delta != "" {
          @emit.emit(AssistantDelta(content=delta))
        }
      },
      on_reasoning_delta=delta => {
        if delta != "" {
          @emit.emit(ReasoningDelta(content=delta))
        }
      },
    ),
  )
  response.log_and_reasoning_content()
}

///|
fn @deepseek.ChatResponse::log_and_reasoning_content(
  response : Self,
) -> @deepseek.ChatResponse {
  // Reasoning first, so a consumer appending events in order shows the
  // thinking above the answer it led to.
  if response.reasoning_content != "" {
    @emit.emit(ReasoningMessage(content=response.reasoning_content))
  }
  if response.content != "" {
    @emit.emit(AssistantMessage(content=response.content))
  }
  @emit.emit(Usage(usage=wire_usage(response.usage)))
  response
}

///|
async fn AgentLoop::handle_tool_calls(
  self : Self,
  session : @agent_session.Session,
  response : @deepseek.ChatResponse,
  last_step~ : Bool,
) -> AgentStepOutcome {
  let session = self.record_assistant(
    session,
    response,
    tool_calls=response.tool_calls,
  )
  let prefetched = self.prefetch_concurrent_results(response)
  let mut spent_result_chars : Int64 = 0
  for call_index, native_call in response.tool_calls; session = session {
    // Running batch budget: stop BEFORE a call whose worst case could push
    // the projection past what the checkpoint request needs. Uses actual
    // recorded sizes for everything already executed, so it only ever
    // pessimizes one call ahead — no pre-execution estimate over the whole
    // batch, no false positives at low usage.
    if !self.next_call_fits(response.usage, spent_result_chars) {
      // A control call in the unexecuted remainder is a completion in
      // progress, not more output — on small-window models the budget can
      // trip well below the hard ceiling, and skip-closing a finish (or a
      // goal verdict) would turn an already-completed task into a context
      // yield. The executed prefix's growth rides along so a salvaged
      // completion still checkpoints.
      match
        self.salvage_control_calls_at_ceiling(
          session,
          response,
          from=call_index,
          spent_result_chars~,
          last_step~,
        ) {
        Some(outcome) => return outcome
        None => ()
      }
      let session = self.close_skipped_tool_calls(
        session,
        response.tool_calls[call_index:],
        note=ceiling_skip_note,
      )
      return StepYield(session)
    }
    let tool_call = @agent_tool.AgentToolCall(native_call) catch {
      error => {
        let content = "error: \{error}"
        let session = self.record_tool_result(
          session,
          tool_call_id=native_call.id,
          tool_name=native_call.name,
          content~,
          is_error=true,
        )
        @emit.emit(
          ToolCallDecodeError(
            tool_call_id=native_call.id,
            tool_name=native_call.name,
            error="\{error}",
          ),
        )
        continue session
      }
    }
    match
      self.execute_tool_call(
        session,
        response,
        call_index,
        native_call,
        tool_call,
        spent_result_chars~,
        last_step~,
        prefetched?=prefetched.get(call_index),
      ) {
      ContinueToolBatch(next) => {
        // Account the result actually recorded for this call (the loop
        // clamp bounds it at max_tool_result_chars).
        spent_result_chars += recorded_result_chars(next)
        continue next
      }
      ContinueAgentLoop(next) => return StepContinue(next)
      FinishAgentLoop(next) => return StepDone(next)
    }
  } nobreak {
    // The batch ran to completion. The soft decision includes the batch's
    // own growth: a below-threshold response whose results carried the
    // context into the soft band still ends here, gracefully, instead of
    // sending one more oversized request to find out.
    if self.at_soft_context_ceiling(
        response.usage,
        extra_result_chars=spent_result_chars,
      ) {
      StepYield(session)
    } else {
      StepContinue(session)
    }
  }
}

///|
/// Execute maximal runs of ADJACENT concurrent-safe tool calls up front,
/// concurrently, returning their actions keyed by batch index. The
/// sequential batch loop then consumes the cached actions in call order,
/// so recording, budget accounting, ceiling handling, and result ordering
/// are byte-identical to sequential execution — only the waiting overlaps.
///
/// A group prefetches only when a call sequential execution might skip
/// cannot be in it: the ENTIRE batch prefix through the group's last call
/// must fit the running batch budget worst-case (no child for a call the
/// ceiling would skip-close), and NOTHING after a control-registered call
/// in the batch prefetches at all — a sealing finish/abort ends the batch
/// early, and sequential execution would never have launched the calls
/// behind it. Goal calls (loop-intercepted), control tools, undecodable
/// calls, and unknown tools never prefetch — the loop's own paths handle
/// them. Only cancellation escapes a prefetch; tool failures fold into
/// the action `execute_tool_call` already returns.
///
/// The durable session is byte-identical to sequential execution; the
/// LIVE event stream is not — a prefetched group's child brackets emit
/// while earlier batch calls are still recording. Readers pair by id.
async fn AgentLoop::prefetch_concurrent_results(
  self : Self,
  response : @deepseek.ChatResponse,
) -> Map[Int, @agent_tool.ToolAction] {
  let results : Map[Int, @agent_tool.ToolAction] = Map([])
  let groups : Array[Array[(Int, @agent_tool.AgentToolCall)]] = []
  let current : Array[(Int, @agent_tool.AgentToolCall)] = []
  fn flush() -> Unit {
    if current.length() >= 2 {
      groups.push(current.copy())
    }
    current.clear()
  }

  for index, native in response.tool_calls {
    let tool = self.tools.find(native.name)
    // Nothing prefetches from behind a batch-sealing call; the group
    // already accumulated BEFORE it executes either way, so it stays.
    if tool is Some(tool) && tool.is_control() {
      flush()
      break
    }
    let safe = tool is Some(tool) &&
      tool.is_concurrent_safe() &&
      !tool.is_control() &&
      !(native.name == "goal" && self.goal_cadence.tool_registered)
    guard safe else {
      flush()
      continue
    }
    let call = @agent_tool.AgentToolCall(native) catch {
      error if @async.is_being_cancelled() ||
        @async.is_cancellation_error(error) => raise error
      _ => {
        flush()
        continue
      }
    }
    current.push((index, call))
  }
  flush()
  for group in groups {
    guard group.last() is Some((last_index, _)) else { continue }
    // Worst case for every call before and inside the group: each records
    // a full clamped result. Conservative — refusing a prefetch only means
    // the calls run sequentially, exactly as before.
    let worst_prior = last_index.to_int64() * max_tool_result_chars.to_int64()
    guard self.next_call_fits(response.usage, worst_prior) else { continue }
    @async.with_task_group() <| scope => {
      for entry in group {
        let (index, call) = entry
        scope.spawn_bg(() => {
          results.set(index, @agent_tool.execute_tool_call(call, self.tools))
        })
      }
    }
  }
  results
}

///|
async fn AgentLoop::execute_tool_call(
  self : Self,
  session : @agent_session.Session,
  response : @deepseek.ChatResponse,
  call_index : Int,
  native_call : @deepseek.ToolCall,
  tool_call : @agent_tool.AgentToolCall,
  spent_result_chars~ : Int64,
  last_step~ : Bool,
  prefetched? : @agent_tool.ToolAction,
) -> ToolCallOutcome {
  // The goal status tool is loop-intercepted: only the loop knows whether a
  // goal currently stands, and the durable clear must be sequenced by the
  // loop, so the registry entry never executes here. Gated on registration:
  // a hallucinated `goal` call against a registry that never advertised the
  // tool must get the normal unknown-tool error, not clear a standing goal.
  if tool_call.name == "goal" && self.goal_cadence.tool_registered {
    return self.handle_goal_tool_call(session, native_call, tool_call)
  }
  let result = match prefetched {
    // Already executed concurrently with its batch siblings; recording and
    // accounting proceed exactly as for a fresh execution.
    Some(action) => action
    None => @agent_tool.execute_tool_call(tool_call, self.tools)
  }
  match result {
    Control(Finish(answer)) => {
      let session = self.record_tool_result(
        session,
        tool_call_id=native_call.id,
        tool_name=tool_call.name,
        content="finished: \{answer}",
      )
      // Close the batch's unexecuted remainder, whatever comes next: every
      // call in the assistant's batch needs a result message — in CALL
      // order, matching the assistant's tool_calls echo sequence — so the
      // durable log and any checkpoint request generated from it stay
      // API-valid without projection repair text leaking into summaries.
      // Step attribution comes from the Assistant event recorded before this
      // batch, so it does not depend on which result appears last.
      let remaining_tool_calls = response.tool_calls[call_index + 1:]
      let session = self.close_skipped_tool_calls(
        session,
        remaining_tool_calls,
        note="skipped: an earlier finish tool call ended the batch before this call ran",
      )
      let steer_inputs = self.runtime.pending_steers()
      if steer_inputs.is_empty() {
        // An unchecked standing goal converts the completion into a check
        // round BEFORE steer/ceiling routing: the batch remainder is
        // already closed above, so the check is the only insertion. At the
        // ceiling the history is checkpointed first (see the helper).
        // On the final bounded step there is no request budget left for a
        // check round: injecting one would exit into "max steps exhausted"
        // and turn a successful bounded turn into a failure. Finish.
        if !last_step &&
          (
            self.goal_cadence.due_finish_check() is Some(_) ||
            self.goal_cadence.due_review()
          ) {
          return ToolCallOutcome::of_finish(
            self.continue_into_goal_check(
              session,
              response.usage,
              spent_result_chars~,
              kept_answer=answer,
              keep_only_when_compacted=true,
            ),
          )
        }
        return ToolCallOutcome::of_finish(
          self.finish_turn(
            session,
            answer,
            usage=response.usage,
            spent_result_chars~,
            answer_already_durable=true,
          ),
        )
      }
      // User input wins over the finish tool as well — but never answered in
      // a starved context: at the ceiling the turn yields and the steers
      // survive the checkpoint verbatim.
      if self.at_soft_context_ceiling(
          response.usage,
          extra_result_chars=spent_result_chars,
        ) {
        return FinishAgentLoop(
          self.yield_at_context_ceiling(session, steer_inputs),
        )
      }
      let session = self.apply_steer_inputs(session, steer_inputs)
      ContinueAgentLoop(session)
    }
    Control(Abort(reason)) => {
      let session = self.append(
        session,
        Tool(
          ToolResult(
            tool_call_id=native_call.id,
            tool_name=tool_call.name,
            content="aborted: \{reason}",
            is_error=true,
          ),
        ),
      )
      // The abort closes the batch; a goal met earlier in it still needs
      // its durable clear before the terminal.
      let session = self.flush_goal_tombstone(session)
      let session = self.append(session, Terminal(Aborted(reason)))
      @emit.emit(AgentAborted(reason~))
      return FinishAgentLoop(session)
    }
    Respond(output) => {
      // Clamp once, here, so the durable item, the in-flight model message
      // (via record_tool_result), and the live JSONL/TUI event all carry
      // the SAME bounded content — a log that disagrees with what the
      // model saw defeats the cap for live consumers.
      let content = clamp_tool_result_content(output.content)
      let session = self.record_tool_result(
        session,
        tool_call_id=native_call.id,
        tool_name=tool_call.name,
        content~,
        is_error=output.is_error,
        brief?=output.brief,
      )
      self.plan_cadence.record_plan_success(tool_call, output)
      log_tool_result(
        native_call,
        tool_call,
        is_error=output.is_error,
        content~,
        brief=output.brief,
      )
      ContinueToolBatch(session)
    }
  }
}

///|
/// Append synthetic error results for tool calls left unexecuted after a finish
/// tool loses to newly arrived user input or to a goal check.
///
/// Every call in the assistant's batch needs a result message, so the finish
/// call's result and skipped notes for the unexecuted remainder are pushed
/// before the new input.
async fn AgentLoop::close_skipped_tool_calls(
  self : Self,
  session : @agent_session.Session,
  remaining_tool_calls : ArrayView[@deepseek.ToolCall],
  note~ : String,
) -> @agent_session.Session {
  for skipped in remaining_tool_calls; session = session {
    let session = self.record_tool_result(
      session,
      tool_call_id=skipped.id,
      tool_name=skipped.name,
      content=note,
      is_error=true,
    )
    @emit.emit(
      ToolResult(
        tool_call_id=skipped.id,
        tool_name=skipped.name,
        is_error=true,
        content=note,
        brief=None,
      ),
    )
    continue session
  } nobreak {
    session
  }
}

///|
/// At the context ceiling, a batch carrying control-registered calls is a
/// completion in progress, not more work — honor those calls instead of
/// discarding them. A control tool's action is loop flow bounded to a few
/// bytes by contract (see `AgentToolDefinition::control`), so executing it
/// cannot grow the checkpoint request the way ordinary tool output would.
/// Non-control calls are skip-closed: their results cannot change an
/// already-decided completion, and executing them would grow the
/// checkpoint request. The built-in `finish` seals the turn through its
/// Control(Finish) path, which also closes the remainder and checkpoints;
/// `goal(met)` records its durable verdict rather than being skip-closed
/// into a resurrected goal; a custom completion tool declaring control
/// (e.g. a review engine's submit tool) seals the same way finish does. A
/// non-control tool — including one shadowing a control name like
/// `finish` — is skip-closed like any other call here.
///
/// Returns None when the batch carries no control-registered call —
/// nothing was appended and the caller proceeds with the plain yield.
/// Otherwise the outcome distinguishes a sealed turn (StepDone: finished
/// or yielded) from a continuation (StepContinue: a steer arriving during
/// a salvaged completion's checkpoint converted it into ContinueTurn —
/// treating that as a failed salvage would close already-closed calls
/// again and fold the steer into a second summary). When the executed
/// controls all return ordinary results (e.g. a goal verdict with no
/// finish, or a completion override answering with Respond), every call
/// ends up closed and the turn yields at the ceiling with those durable
/// results kept.
///
/// `from` is where the unexecuted remainder starts: 0 when the whole batch
/// is being skipped (hard ceiling), or the tripping call's index when the
/// running budget stopped execution mid-batch — calls before it already
/// executed and have results (their growth arrives as
/// `spent_result_chars`, so a salvaged completion still checkpoints).
/// Control calls are exempt from the PRE-execution fit check (their
/// results are bounded by contract), but a non-sealing control's recorded
/// result still accumulates into the running total, so a later sealing
/// control sizes its checkpoint against what was actually appended.
async fn AgentLoop::salvage_control_calls_at_ceiling(
  self : Self,
  session : @agent_session.Session,
  response : @deepseek.ChatResponse,
  from? : Int = 0,
  spent_result_chars? : Int64 = 0,
  last_step~ : Bool,
) -> AgentStepOutcome? {
  // The registry must declare a call's tool a CONTROL tool: that is how
  // the loop knows — without executing — that honoring the call appends a
  // few bytes, not tool output.
  guard response.tool_calls[from:].any(call => {
    self.tools.find(call.name) is Some(definition) && definition.is_control()
  }) else {
    return None
  }
  let session = for index = from, session = session, spent = spent_result_chars {
    if index >= response.tool_calls.length() {
      break session
    }
    let call = response.tool_calls[index]
    let is_control_call = self.tools.find(call.name) is Some(definition) &&
      definition.is_control()
    if is_control_call {
      let decoded : @agent_tool.AgentToolCall? = Some(AgentToolCall(call)) catch {
        _ => None
      }
      match decoded {
        Some(tool_call) =>
          match
            self.execute_tool_call(
              session,
              response,
              index,
              call,
              tool_call,
              spent_result_chars=spent,
              last_step~,
            ) {
            // A non-sealing control appended an ordinary result (a goal
            // verdict echo, a rejected submit): its growth must ride along
            // like an executed prefix's, or a LATER sealing control would
            // size its compact-on-finish decision against stale usage
            // while the reserved checkpoint headroom is already spent.
            ContinueToolBatch(next) =>
              continue index + 1, next, spent + recorded_result_chars(next)
            // The control already closed the batch remainder and prepared a
            // continuation (e.g. a control finish converted into a goal
            // check): re-scanning the same calls would duplicate results
            // and bypass the injected check.
            ContinueAgentLoop(next) => return Some(StepContinue(next))
            // A control that SEALED the turn (finish, a custom completion,
            // or an abort) owns the terminal: executing anything after it
            // would append past a terminal and override the intended
            // outcome.
            FinishAgentLoop(next) => return Some(StepDone(next))
          }
        // An undecodable control call cannot be honored; close it like a
        // skipped call so the batch stays API-valid.
        None => ()
      }
    }
    continue index + 1,
      self.close_skipped_tool_calls(
        session,
        response.tool_calls[index:index + 1],
        note=ceiling_skip_note,
      ),
      spent
  }
  // Controls ran but none sealed or continued the turn: every call is
  // closed (executed or skip-noted), so yield at the ceiling with the
  // recorded results carried into the checkpoint.
  Some(
    StepDone(
      self.yield_at_context_ceiling(session, self.runtime.pending_steers()),
    ),
  )
}

///|
/// Ceiling for one recorded tool result, in UTF-16 units. It MUST sit
/// above every in-tree tool's self-cap PLUS its metadata footer (shell
/// inline output caps at 12K; read caps its body budget at 50K and then
/// appends a `<system>…</system>` footer), so in-tree results always pass
/// through untouched — a loop-level cut would strip exactly the
/// truncation/line/exit metadata the model needs to know a result is
/// incomplete. The clamp therefore only ever fires on custom tool
/// registrations, which is what gives the soft-tier batch budget a real
/// per-call bound.
let max_tool_result_chars : Int = 60_000

///|
let tool_result_truncation_marker : String = "\n[truncated: result exceeded the 60000-char cap]"

///|
/// Chars recorded by the tool result the last append added, or 0 when the
/// last event is not one — the batch budget's accounting unit.
fn recorded_result_chars(session : @agent_session.Session) -> Int64 {
  if session.events().peek() is Some(event) && event.item() is Tool(result) {
    result.content().length().to_int64()
  } else {
    0
  }
}

///|
/// Clamp an oversized tool result to `max_tool_result_chars`, never
/// splitting a surrogate pair.
fn clamp_tool_result_content(content : String) -> String {
  if content.length() <= max_tool_result_chars {
    return content
  }
  // The marker fits INSIDE the cap: the recorded result must never exceed
  // the per-call figure soft_batch_fits budgets with.
  let marker = tool_result_truncation_marker
  let body_budget = max_tool_result_chars - marker.length()
  "\{content.clamped_view(end=body_budget)}\{marker}"
}

///|
test "tool result clamp snaps a UTF-16 cut before a surrogate pair" {
  let marker = tool_result_truncation_marker
  let prefix = String::make(max_tool_result_chars - marker.length() - 1, 'x')
  let tail = String::make(marker.length() + 1, 'y')
  let clamped = clamp_tool_result_content("\{prefix}😀\{tail}")
  assert_true(clamped.has_suffix(marker))
  assert_false(clamped.contains("😀"))
  assert_true(clamped.length() <= max_tool_result_chars)
}

///|
/// Record one tool result: append it durably and mirror it into the in-flight
/// chat messages. The two must stay in lockstep — every tool call in an
/// assistant batch needs a matching result message for the conversation to
/// stay API-valid.
async fn AgentLoop::record_tool_result(
  self : Self,
  session : @agent_session.Session,
  tool_call_id~ : String,
  tool_name~ : String,
  content~ : String,
  is_error? : Bool = false,
  brief? : String,
) -> @agent_session.Session {
  let content = clamp_tool_result_content(content)
  let session = self.append(
    session,
    Tool(ToolResult(tool_call_id~, tool_name~, content~, is_error~, brief?)),
  )
  self.messages.push(ChatMessage(Tool(tool_call_id), content~))
  session
}

///|
/// Convert a completion attempt into a goal-check round. At the soft
/// ceiling the history is checkpointed FIRST, so the check round runs from
/// a compacted context — continuing with the uncheckpointed pressured
/// history plus the check notice could overflow the next request. A failed
/// checkpoint yields fail-open instead: the goal survives in the raw log
/// and the next turn's start re-surfaces it. `kept_answer` (with its
/// reasoning) becomes an ordinary assistant message — appended after any
/// summary, so it stays verbatim — BOTH arms pass it: without it a ceiling
/// checkpoint covers the finish result and the check round would see only
/// the lossy summary instead of the verbatim answer non-ceiling checks
/// get. Only the no-tool arm passes reasoning: the finish tool's answer is
/// synthetic (its reasoning lives on the batch's covered assistant
/// message; re-attaching it would duplicate what Kimi preserves there).
/// Run the owed goal-met review, if any, and append its notice. A no-op
/// without a pending review or a callback. Failure folding: external
/// cancellation re-raises; any other reviewer failure becomes an
/// `[review] unavailable` notice — the gate is advisory and must never
/// break the turn.
async fn AgentLoop::run_pending_review(
  self : Self,
  session : @agent_session.Session,
) -> @agent_session.Session {
  guard self.goal_cadence.pending_review is Some((goal, baseline)) else {
    return session
  }
  self.goal_cadence.pending_review = None
  guard self.on_goal_met is Some(callback) else { return session }
  // The audit is bound to the MET CLAIM, not to whichever goal currently
  // stands: a replacement queued while the reviewer runs is applied at the
  // next boundary, AFTER this notice — chronologically truthful ordering.
  // (Pre-launch economy is separate: a replacement observed before this
  // point already cleared the pending slot and no audit was spawned.)
  let notice = callback(goal, baseline) catch {
    error if @async.is_being_cancelled() || @async.is_cancellation_error(error) =>
      raise error
    error =>
      Some(
        "[review] unavailable: \{@agent_tool.brief_line("\{error}", limit=200)}",
      )
  }
  match notice {
    Some(text) => self.append_runtime_notice(session, text)
    None => session
  }
}

///|
async fn AgentLoop::continue_into_goal_check(
  self : Self,
  session : @agent_session.Session,
  usage : @deepseek.Usage,
  spent_result_chars~ : Int64,
  kept_answer~ : String,
  keep_only_when_compacted~ : Bool,
  reasoning_content? : String,
) -> FinishOutcome {
  // Flush the deferred goal tombstone FIRST: the review-gate disjunct
  // makes this flow reachable with a pending tombstone (same-batch
  // goal(met)+finish), and the fail-open arm below seals via
  // finish_context_yield — sealing without the flush would resurrect a
  // met goal for auto-continue, and the flush-first order also keeps
  // [goal cleared] ahead of the [review] notice in the durable log. A
  // no-op on every pre-gate entry.
  let session = self.flush_goal_tombstone(session)
  let at_ceiling = self.at_soft_context_ceiling(
    usage,
    extra_result_chars=spent_result_chars,
  )
  let (session, compacted) = if at_ceiling {
    self.checkpoint_at_ceiling(session, [])
  } else {
    (session, false)
  }
  if at_ceiling && !compacted {
    let to_sequence = session.last_sequence()
    // A no-tool answer exists nowhere else: persist it before sealing, or
    // the completion attempt is lost with the failed checkpoint. The
    // finish-tool variant is already durable as the batch's tool result.
    let session = if keep_only_when_compacted {
      session
    } else {
      self.append(
        session,
        Assistant(AssistantMessage(kept_answer, reasoning_content?)),
      )
    }
    // Same lossless-steering rule as the yield path: input queued during
    // the failed checkpoint request persists (uncovered) instead of being
    // boundary-dropped at TurnDone.
    let session = self.apply_steer_inputs(
      session,
      self.runtime.pending_steers(),
    )
    // The owed audit still runs on this fail-open seal: its durable digest
    // is what the next (auto-continued) turn inherits.
    let session = self.run_pending_review(session)
    return Sealed(
      self.finish_context_yield(session, to_sequence, compacted=false),
    )
  }
  // The finish-tool arm's answer is already durable as the batch's tool
  // result, so it is re-kept only when a checkpoint just covered it; the
  // no-tool arm's answer exists nowhere else and is always kept.
  let session = if !keep_only_when_compacted || at_ceiling {
    let session = self.append(
      session,
      Assistant(
        AssistantMessage(
          kept_answer,
          reasoning_content?,
          is_replay=keep_only_when_compacted,
        ),
      ),
    )
    self.messages.push(
      ChatMessage(Assistant, content=kept_answer, reasoning_content?),
    )
    session
  } else {
    session
  }
  // Steers queued during the checkpoint await land NOW, before the check:
  // otherwise the next prepare_step would append them after it, the model
  // would answer the newer instruction, and — finish_checked being spent —
  // finish without ever addressing the standing-goal check.
  let session = self.apply_steer_inputs(session, self.runtime.pending_steers())
  // Those steers may themselves have SET or CLEARED the goal: check the
  // cadence's CURRENT goal, never the text captured before the checkpoint —
  // a goal set during the await deserves its own check, and a cleared one
  // needs none (finish_checked stays unspent).
  let session = match self.goal_cadence.due_finish_check() {
    Some(current) => self.inject_goal_check(session, current)
    None => session
  }
  // The owed goal-met review lands here too: same batch-safe boundary,
  // same continuation — the model sees the audit before it may finish
  // again.
  let session = self.run_pending_review(session)
  if at_ceiling {
    // Re-seed the in-flight buffer from the compacted projection: the
    // whole point of the checkpoint is that the check round is small.
    self.messages.clear()
    self.messages.append(session.chat_messages())
  }
  ContinueTurn(session)
}

///|
/// Answer a finish attempt with the once-per-turn goal check: a durable
/// runtime notice plus the mirrored model message, so the next request asks
/// the model to confirm the standing goal before the turn may end.
async fn AgentLoop::inject_goal_check(
  self : Self,
  session : @agent_session.Session,
  goal : String,
) -> @agent_session.Session {
  let check = goal_check_text(
    goal,
    tool_registered=self.goal_cadence.tool_registered,
  )
  let session = self.append_runtime_notice(session, check)
  @emit.emit(GoalCheck(content=check))
  self.goal_cadence.record_finish_check()
  // The check must stay the newest instruction: a plan reminder landing at
  // the same cadence boundary would bury it — the model would answer the
  // plan nag, and finish_checked is already spent, bypassing the gate.
  self.plan_cadence.record_reminder()
  session
}

///|
/// Durably record the turn's final answer and mirror it for the still-live
/// loop state.
///
/// Compact-on-finish: a turn that completes at the context ceiling still
/// leaves a checkpoint, so the next turn seeds from the compacted
/// projection instead of landing its first request on a pressured one. The
/// answer is not yet durable when the summary generates, so it cannot fold
/// into the checkpoint text — it projects verbatim after the summary, and
/// the turn stays a normal success (`agent_finished`, real answer) on both
/// the wire and the durable log. Fail-open: a failed checkpoint finishes
/// uncompacted.
///
/// EXCEPT when user input queued during the checkpoint request: then the
/// steer-beats-finish rule applies once more and the turn CONTINUES from
/// the compacted projection (`ContinueTurn`) — the answer becomes ordinary
/// history and the model addresses the steer with fresh headroom.
async fn AgentLoop::finish_turn(
  self : Self,
  session : @agent_session.Session,
  answer : String,
  usage~ : @deepseek.Usage,
  spent_result_chars? : Int64 = 0,
  reasoning_content? : String,
  answer_already_durable? : Bool = false,
) -> FinishOutcome {
  // A met claim reaching a seal that skipped the review continuation (the
  // last bounded step) still gets its audit: the model cannot react this
  // turn, but the durable digest is exactly what the user — or the next
  // auto-continued turn — needs to judge the claim. No-op when nothing is
  // owed.
  let session = self.run_pending_review(session)
  // A goal met in the turn's final batch still needs its durable clear
  // before the terminal seals the turn — and before any compact-on-finish
  // checkpoint, so the tombstone is covered like the rest of the history.
  let session = self.flush_goal_tombstone(session)
  let session = if self.at_soft_context_ceiling(
      usage,
      extra_result_chars=spent_result_chars,
    ) {
    let (session, compacted) = self.checkpoint_at_ceiling(session, [])
    // The checkpoint request takes seconds; user input may have queued
    // while it was in flight. Appending it before the terminal would make
    // the decided answer read as its reply, and leaving it queued gets it
    // boundary-dropped at TurnDone — so the steer-beats-finish rule
    // applies once more: the answer stays an ordinary assistant message
    // and the turn continues, from the compacted projection.
    let steers = self.runtime.pending_steers()
    if !steers.is_empty() {
      let to_sequence = session.last_sequence()
      // Keep the response's reasoning on the converted message: Kimi
      // requires preserved reasoning_content on historical assistant
      // messages, and this answer is history now.
      let session = self.append(
        session,
        Assistant(
          AssistantMessage(
            answer,
            reasoning_content?,
            is_replay=answer_already_durable,
          ),
        ),
      )
      let session = self.apply_steer_inputs(session, steers)
      if !compacted {
        // The checkpoint FAILED: continuing would build the next request
        // from the same pressured, uncheckpointed history plus two more
        // messages — the exact overflow the guard exists to prevent.
        // Yield fail-open instead: the answer and steers are durable
        // (uncovered, heading the next turn) and the next turn's pressure
        // retries the checkpoint.
        return Sealed(
          self.finish_context_yield(session, to_sequence, compacted=false),
        )
      }
      // Re-seed the in-flight buffer from the projection: the whole point
      // of the checkpoint is that the continuation request is small, and
      // the buffer must never disagree with Session::chat_messages.
      self.messages.clear()
      self.messages.append(session.chat_messages())
      return ContinueTurn(session)
    }
    session
  } else {
    session
  }
  // A no-tool provider response is not otherwise durable. Record it once as
  // Assistant before the terminal; a completion tool already has the response's
  // Assistant/tool-call event, so its answer needs only the terminal seal.
  let session = if !answer_already_durable {
    self.append(
      session,
      Assistant(AssistantMessage(answer, reasoning_content?)),
    )
  } else {
    session
  }
  let session = self.append(session, Terminal(Finished(answer)))
  self.push_finished_message(answer)
  @emit.emit(AgentFinished(answer~))
  Sealed(session)
}

///|
fn log_tool_result(
  native_call : @deepseek.ToolCall,
  tool_call : @agent_tool.AgentToolCall,
  is_error~ : Bool,
  content~ : String,
  brief~ : String?,
) -> Unit {
  @emit.emit(
    ToolResult(
      tool_call_id=native_call.id,
      tool_name=tool_call.name,
      is_error~,
      content~,
      brief~,
    ),
  )
}

///|
/// The provider's token counts as the protocol carries them.
///
/// `@protocol.Usage` is structurally identical, and deliberately separate: the
/// event stream's shape must not be whatever the vendor's response struct
/// happens to be this week, and `protocol` is a leaf module that cannot depend
/// on the provider layer. This is the only place the two meet.
fn wire_usage(usage : @deepseek.Usage) -> @protocol.Usage {
  {
    prompt_tokens: usage.prompt_tokens,
    completion_tokens: usage.completion_tokens,
    total_tokens: usage.total_tokens,
    prompt_cache_hit_tokens: usage.prompt_cache_hit_tokens,
    prompt_cache_miss_tokens: usage.prompt_cache_miss_tokens,
  }
}

///|
fn @deepseek.ChatResponse::optional_reasoning_content(
  response : Self,
) -> String? {
  match response.reasoning_content {
    "" => None
    content => Some(content)
  }
}
