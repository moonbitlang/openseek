///|
/// Default step bound: effectively unbounded (Int max). Turns are bounded
/// by the context window instead — a response at the ceiling yields the
/// turn with a checkpoint summary — so a step count only binds when a
/// caller passes one explicitly.
pub let unbounded_max_steps : Int = 2147483647

///|
/// Model requests since the last plan activity — a successful `plan` call or
/// an injected reminder, whichever is more recent — before the loop injects a
/// plan staleness reminder. Fifty is roughly one reminder per MILESTONE of
/// work: the original ten mirrored Claude Code's 10-turn todo cadence, but an
/// openseek request is far smaller than a CC turn, and live long-horizon runs
/// showed the mismatch (40 nags against 14 actual plan calls in a 478-request
/// build — every nag replayed in context forever; issue #422). Re-nagging is
/// variant-dependent: with a recorded checklist the reminder re-surfaces real
/// state and may repeat, while the no-plan nudge fires at most once per turn —
/// a model that ignored "consider recording a plan" once gains nothing from
/// hearing it again.
pub let plan_reminder_after_steps : Int = 50

///|
/// The staleness reminder injected when the `plan` tool has gone unused for
/// `plan_reminder_after_steps` model requests. With a known current plan the
/// reminder re-surfaces it — the last plan call may sit dozens of steps back
/// in context — and otherwise it nudges once toward recording a plan, while
/// staying explicit that trivial work should ignore it.
fn plan_reminder_text(checklist : String?) -> String {
  match checklist {
    Some(lines) =>
      (
        $|\{@agent_session.PlanReminderPrefix}
        $|The plan tool has not been called in a while. If progress was made,
        $|update step statuses; if the plan no longer matches the work,
        $|replace it or clear it with steps: []. Current plan:
        $|\{lines}
      )
    None =>
      (
        $|\{@agent_session.PlanReminderPrefix}
        $|The plan tool has not been used in this turn. If this task takes
        $|several distinct steps, record a plan with the plan tool and keep
        $|step statuses current. If not, ignore this reminder.
      )
  }
}

///|
/// Plan staleness tracking for one turn. When the plan tool is registered,
/// `silent_steps` advances once per model request and resets on either kind
/// of plan activity — a successful `plan` call (which also refreshes
/// `checklist`) or an injected reminder — so the reminder fires only after
/// enough silence since both. The no-plan nudge additionally fires at most
/// once per turn (`nagged_without_plan`): repeats are reserved for the
/// checklist variant, which re-surfaces real recorded state instead of
/// repeating advice the model already declined once. Turn-local by design —
/// a fresh user turn resets the cadence. `checklist` carries the last
/// successfully recorded plan for the reminder to re-surface.
priv struct PlanCadence {
  registered : Bool
  mut silent_steps : Int
  mut checklist : String?
  mut nagged_without_plan : Bool
}

///|
fn PlanCadence::PlanCadence(registered~ : Bool) -> PlanCadence {
  { registered, silent_steps: 0, checklist: None, nagged_without_plan: false }
}

///|
fn PlanCadence::should_remind(self : Self) -> Bool {
  self.registered &&
  self.silent_steps >= plan_reminder_after_steps &&
  (self.checklist is Some(_) || !self.nagged_without_plan)
}

///|
fn PlanCadence::reminder_text(self : Self) -> String {
  plan_reminder_text(self.checklist)
}

///|
fn PlanCadence::record_reminder(self : Self) -> Unit {
  self.silent_steps = 0
  // The once-per-turn cap applies only to the no-plan nudge; a turn that
  // later records a plan re-nags through the checklist variant regardless.
  if self.checklist is None {
    self.nagged_without_plan = true
  }
}

///|
fn PlanCadence::record_model_request(self : Self) -> Unit {
  if self.registered {
    self.silent_steps += 1
  }
}

///|
fn PlanCadence::record_plan_success(
  self : Self,
  tool_call : @agent_tool.AgentToolCall,
  output : @agent_tool.ToolOutput,
) -> Unit {
  if self.registered && tool_call.name == "plan" && !output.is_error {
    self.silent_steps = 0
    self.checklist = @plan.reminder_checklist(tool_call.arguments)
  }
}

///|
/// Run a one-shot OpenSeek task and discard the returned session.
///
/// This is the highest-level convenience entry point. It creates a fresh
/// in-memory session with id `"one-shot"`, appends `task` as the first user
/// event, runs the agent loop, logs progress through the configured process
/// logger, and returns `Unit`. It does not persist the session and does not
/// expose the final `Session` value to the caller.
///
/// `system_prompt_text` is required. Prompt selection is intentionally owned by
/// the application layer, not by `agent`; this package does not depend on the
/// `prompt` package. `thinking` defaults to `Max`. `workspace_root` defaults to
/// `"."` and is passed into the per-turn `AgentRuntime`; local file and shell
/// tools resolve relative paths against that root. `api_url` is forwarded to
/// the DeepSeek client and is mainly useful for tests or compatible endpoints.
///
/// Use `run_turn_with_append` when every committed event must be persisted as
/// the turn progresses, or `run_turn_in_scope` when runtime/tool state must span
/// turns.
pub async fn run(
  api_key~ : String,
  model~ : @deepseek.Model,
  task~ : String,
  system_prompt_text~ : String,
  max_steps? : Int = unbounded_max_steps,
  thinking? : @deepseek.ThinkingMode = Max,
  api_url? : String,
  workspace_root? : String = ".",
) -> Unit {
  let session = @agent_session.Session(
    SessionId("one-shot"),
    system_prompt=system_prompt_text,
  )
  ignore(
    run_turn_with_append(
      api_key~,
      model~,
      session~,
      task~,
      append_item=(session, item) => session.append(item),
      max_steps~,
      thinking~,
      api_url?,
      workspace_root~,
    ),
  )
}

///|
/// Runs one user turn and calls `append_item` for every session event as soon as
/// it is committed. This lets a filesystem-backed caller preserve progress even
/// if the engine process exits later in the turn.
///
/// This is the persistence hook for one-shot and CLI session recording. The
/// callback receives the current session snapshot and the next `SessionItem`;
/// it must return the new session snapshot after appending that item. The agent
/// uses the returned value as the current session for all later work, so the
/// callback is the single source of truth for sequencing.
///
/// `append_item` is called for the initial user task, every assistant/tool/
/// runtime/steer event that is committed, and the terminal event. If the
/// callback raises, the turn attempts to append a failure terminal describing
/// that append failure and then re-raises the original error. This means a
/// durable store can preserve the partial turn up to the failure point.
///
/// This owns a fresh runtime, task group, and tool registry for the duration of
/// one turn. Use `run_turn_in_scope` when the caller needs to preserve runtime
/// state or tool state across turns.
pub async fn run_turn_with_append(
  api_key~ : String,
  model~ : @deepseek.Model,
  session~ : @agent_session.Session,
  task~ : String,
  append_item~ : async (@agent_session.Session, @agent_session.SessionItem) -> @agent_session.Session,
  max_steps? : Int = unbounded_max_steps,
  thinking? : @deepseek.ThinkingMode = Max,
  api_url? : String,
  workspace_root? : String = ".",
) -> @agent_session.Session {
  @async.with_task_group() <| group => {
    run_turn_in_scope(
      runtime=AgentRuntime(workspace_root~),
      scope=AgentTaskScope(group),
      api_key~,
      model~,
      session~,
      task~,
      append_item~,
      max_steps~,
      thinking~,
      api_url?,
    )
  }
}

///|
async test "run_turn_with_append closes failed persisted turns" {
  let initial = @agent_session.Session(SessionId("s1"), system_prompt="system")
  let mut calls = 0
  let mut persisted = initial
  let _ = run_turn_with_append(
    api_key="unused",
    model=Deepseek(V4Pro),
    session=initial,
    task="hello",
    append_item=(session, item) => {
      calls = calls + 1
      if calls == 2 {
        fail("persist terminal failed")
      }
      let next = session.append(item)
      persisted = next
      next
    },
    max_steps=0,
  ) catch {
    error => {
      assert_true("\{error}".contains("persist terminal failed"))
      assert_eq(calls, 3)
      let events = persisted.events()
      assert_eq(events.length(), 2)
      assert_true(events[0].item() is User(_))
      guard events[1].item() is Terminal(Failed(message)) else {
        fail("expected failed terminal")
      }
      assert_true(message.contains("persist terminal failed"))
      return
    }
  }
  fail("expected failed append to be re-raised")
}

///|
/// Runs one user turn inside a caller-owned runtime and task scope.
///
/// This is the building block for callers that keep an engine alive across
/// turns (serve mode): the shared `runtime` carries steering input across the
/// turn boundary, and a `tools` registry can be built once with `build_tools`
/// and reused across turns. When `tools` is
/// omitted a fresh registry is built for this turn only. `scope` bounds
/// background work the turn's tools spawn, so it must outlive every turn that
/// may have spawned some. One-shot callers should prefer `run` or
/// `run_turn_with_append`, which own everything for the duration of a single
/// turn.
///
/// The loop appends `task` as a user message before the first model request.
/// At each step boundary it first drains and applies pending non-blank steers.
/// When the registry includes the `plan` tool and
/// `plan_reminder_after_steps` model requests pass without a successful
/// `plan` call, the loop also injects a durable plan staleness reminder that
/// re-surfaces the recorded plan (rate-limited by the same threshold). It
/// sends the current DeepSeek chat projection with the active tool schemas,
/// records assistant responses, executes tool calls in order, and records
/// tool results. When a response reports token usage at or past 80% of the
/// model's context window, the loop appends a checkpoint summary before
/// continuing — prior turns first so the active task stays verbatim, then at
/// most one full-range checkpoint per turn — and rebuilds its request buffer
/// from the compacted projection (`auto_compaction_*` events; fail-open on
/// summary errors). The turn ends when the model answers with no tool calls, the
/// `finish` tool returns `Control(Finish)`, a tool returns `Control(Abort)`,
/// `max_steps` is exhausted, the task is cancelled, or an unexpected error
/// escapes.
/// A model final answer is stored as `Terminal(Finished(...))`; session replay
/// projects that terminal back into an assistant message for later turns.
/// Long-lived callers must carry the returned or append-updated `Session`
/// across turns, not any loop-local request buffer. Each new turn constructs a
/// fresh `AgentLoop` whose model context starts from `Session::chat_messages`,
/// so TUI/serve-style callers preserve final answers through the session.
///
/// A steer that arrives while the model's apparent final answer or a `finish`
/// tool call is in flight keeps the turn alive. The would-be final answer is
/// stored as an ordinary assistant message, or the finish batch is closed with
/// tool-result messages, then the steer is appended and the loop continues.
///
/// `tools` should normally be a registry built once with `build_tools(runtime,
/// scope)` for a long-lived engine. If `tools` is omitted, this function builds
/// a fresh registry for this call only. `api_url` is forwarded to the DeepSeek
/// client. The caller owns the lifetime of `runtime`, `scope`, and any shared
/// `tools` registry passed here.
pub async fn[X] run_turn_in_scope(
  runtime~ : @agent_runtime.AgentRuntime,
  scope~ : @agent_runtime.AgentTaskScope[X],
  api_key~ : String,
  model~ : @deepseek.Model,
  session~ : @agent_session.Session,
  task~ : String,
  append_item~ : async (@agent_session.Session, @agent_session.SessionItem) -> @agent_session.Session,
  max_steps? : Int = unbounded_max_steps,
  thinking? : @deepseek.ThinkingMode = Max,
  api_url? : String,
  tools? : @agent_tool.Tools,
) -> @agent_session.Session {
  let client = @client.Client(api_key~, model~, thinking~, api_url?)
  let summary_client = @client.Client(api_key~, model~, api_url?, thinking=No)
  let session = session |> append_item(User(UserMessage(task)))
  let tools = try {
    match tools {
      Some(tools) => tools
      None => build_tools(runtime, scope)
    }
  } catch {
    error => {
      @xlog.error() <? { "event": "agent_setup_failed", "error": "\{error}" }
      return session
        |> append_item(Terminal(Failed("agent setup failed: \{error}")))
    }
  }
  AgentLoop(runtime~, client~, summary_client~, tools~, append_item~, session~).run(
    session, max_steps,
  )
}

///|
/// Queued steering input worth applying: drained losslessly, blanks dropped.
fn @agent_runtime.AgentRuntime::pending_steers(
  runtime : Self,
) -> Array[@agent_runtime.SteerInput] {
  [
    for input in runtime.drain_steers() if input
    is (Prompt(text) | Command(text) | Notice(text)) &&
    !text.trim().is_empty() => input
  ]
}

///|
fn print_usage(usage : @deepseek.Usage) -> Unit {
  @xlog.info() <? { "event": "usage", "usage": usage }
}
