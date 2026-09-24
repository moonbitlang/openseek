///|
/// A normalized engine event. The bridge's `openseek.event` payload is
/// tagged by a `String`; this enum is the form `update()` matches on, so
/// each case carries only the fields that event actually uses and the match
/// is exhaustive.
pub(all) enum EngineEvent {
  // The 1-based step counter. Optional only because the run stage that
  // carries it (`AtStep`) is: every engine that emits `agent_step` has
  // numbered it (1f761102, the commit that introduced both).
  AgentStep(Int?)
  // The provider request for the current step failed and is being retried.
  // The view discards the failed attempt's transient streams and shows the
  // retry while the engine waits out its backoff.
  StreamRetry(attempt~ : Int, max_attempts~ : Int, reason~ : String)
  AssistantDelta(String)
  ReasoningDelta(String)
  ReasoningMessage(String)
  AssistantMessage(String)
  BackgroundNotice(String)
  Usage(prompt_tokens~ : Int, completion_tokens~ : Int)
  ToolResult(
    tool_name~ : String,
    is_error~ : Bool,
    content~ : String,
    brief~ : String?
  )
  ToolCallDecodeError(tool_name~ : String, reason~ : String)
  // A sub-run's lifecycle brackets. Between them the conversation shows a
  // live lane instead of a notice: a sub-run can run for forty-five minutes,
  // and a line that never changes is indistinguishable from a hang. The
  // finish reports what it cost — the only place those numbers appear.
  SubrunOpened(id~ : String, kind~ : String, label~ : String)
  SubrunClosed(id~ : String, status~ : String, steps~ : Int, tokens~ : Int)
  // A workflow's lifecycle brackets. A workflow is a run inside an `mbtx`
  // snippet that delegates to child agents of its own; the engine has to
  // announce it because the workflow library is generic and the parent sees
  // only one opaque tool call, however many children it starts.
  //
  // `journal` and `events` are files the host tails: the ledger of resolved
  // calls, and the sidecar that reports a launch when it starts. The ordinal
  // range says which `<parent>-sr-N` transcripts belong to this run.
  WorkflowOpened(
    id~ : String,
    journal~ : String,
    events~ : String,
    first_child~ : Int,
    child_count~ : Int
  )
  WorkflowClosed(id~ : String)
  AgentFinished(String)
  // The current turn stopped at the model's context ceiling after attempting
  // an automatic checkpoint. It is run-terminal, but not task success.
  ContextYield(String)
  AgentAborted(String)
  MaxStepsExhausted
  AgentSetupFailed(String)
  // Steering input settled by the engine: applied at a step boundary, or
  // dropped because it raced the turn's end. Current hosts echo the globally
  // unique local submission id; `None` is a legacy lifecycle-only receipt and
  // must never claim a local ledger entry by matching text.
  SteerApplied(content~ : @protocol.Content, submission_id~ : String?)
  SteerDropped(content~ : @protocol.Content, submission_id~ : String?)
  // An automatic checkpoint completed inside the open turn. Unlike the
  // manual lifecycle below, this does not put the conversation into an idle
  // compaction phase.
  AutoCompactionFinished(String)
  // Conversation compaction lifecycle: the engine started summarizing the
  // history, finished (carrying the checkpoint summary text), or failed
  // (carrying the reason). Requested while the engine is idle, so these arrive
  // outside any open turn.
  CompactionStarted
  CompactionFinished(String)
  CompactionFailed(String)
  // A tool is blocked asking for permission to run outside its sandbox. The
  // turn does not advance until `agent.approval` carries an answer back, so
  // this is the one engine event whose presentation has to be answerable
  // rather than merely readable.
  ApprovalRequested(
    id~ : String,
    tool_name~ : String,
    detail~ : String,
    body~ : String?
  )
  // The question settled: by this client's answer, by another client's, or by
  // the engine's own deadline. The prompt is retired either way, so the view
  // never has to decide whose answer it was.
  ApprovalResolved(id~ : String)
  // The engine could not append an item to the durable session. Idle-time
  // appends have no other failure channel: unlike a turn, nothing terminal
  // follows them, and the host does not normalize this event. Whatever was
  // waiting on that append — a goal command most of all — would otherwise
  // wait on a commit that is never coming, with no word of why.
  SessionAppendFailed(String)
}

///|
/// Project the shared typed engine event into the subset rendered by the
/// transcript. Unknown wire events were rejected before this function; `None`
/// means a known event that intentionally has no desktop presentation.
pub fn decode_engine_event(event : @protocol.Event) -> EngineEvent? {
  match event {
    JobChanged(..) | JobsSnapshot(..) | JobStopResult(..) => None
    AgentStep(step~) => Some(AgentStep(Some(step)))
    StreamRetry(attempt~, max_attempts~, reason~) =>
      Some(StreamRetry(attempt~, max_attempts~, reason~))
    AssistantDelta(content~) => Some(AssistantDelta(content))
    ReasoningDelta(content~) => Some(ReasoningDelta(content))
    ReasoningMessage(content~) => Some(ReasoningMessage(content))
    AssistantMessage(content~) => Some(AssistantMessage(content))
    // A background-job completion notice (or an engine idle-time diagnostic),
    // emitted while the engine is idle. Transport for the conversation's
    // idle-event routing; the durable notice card is its one presentation.
    BackgroundNotice(content~) => Some(BackgroundNotice(content))
    Usage(usage~) =>
      Some(
        Usage(
          prompt_tokens=usage.prompt_tokens,
          completion_tokens=usage.completion_tokens,
        ),
      )
    ToolResult(tool_name~, is_error~, content~, brief~, ..) =>
      Some(ToolResult(tool_name~, is_error~, content~, brief~))
    ToolCallDecodeError(tool_name~, error~, ..) =>
      Some(ToolCallDecodeError(tool_name~, reason=error))
    AgentFinished(answer~) => Some(AgentFinished(answer))
    ContextYield(answer~, ..) => Some(ContextYield(answer))
    AgentAborted(reason~) => Some(AgentAborted(reason))
    MaxStepsExhausted => Some(MaxStepsExhausted)
    AgentSetupFailed(error~) => Some(AgentSetupFailed(error))
    SteerApplied(content~, submission_id~, ..) =>
      Some(SteerApplied(content~, submission_id~))
    SteerDropped(content~, submission_id~) =>
      Some(SteerDropped(content~, submission_id~))
    AutoCompactionFinished(summary~, ..) =>
      Some(AutoCompactionFinished(summary))
    CompactionStarted(..) => Some(CompactionStarted)
    CompactionFinished(summary~, ..) => Some(CompactionFinished(summary))
    CompactionFailed(error~) => Some(CompactionFailed(error))
    // The engine's own report that a durable append did not happen. The host
    // has no use for it and drops it, so unless the view reads it off the raw
    // stream nobody hears about it at all.
    SessionError(error~) => Some(SessionAppendFailed(error))
    ApprovalRequested(id~, tool_name~, detail~, body~) =>
      Some(ApprovalRequested(id~, tool_name~, detail~, body~))
    // The outcome word is dropped: this view shows one prompt at a time and
    // retires it on settlement, so WHY it settled changes nothing it renders.
    // What ran, or did not, arrives as the tool's own result.
    ApprovalResolved(id~, ..) => Some(ApprovalResolved(id~))
    // A sub-run's lifecycle brackets. The id pairs the two, and pairs both
    // with the host's `subrun.progress` pushes in between; the finish is
    // where its cost is reported, since nothing durable records it.
    SubrunStarted(id~, kind~, label~) => Some(SubrunOpened(id~, kind~, label~))
    SubrunFinished(id~, status~, steps~, prompt_tokens~, completion_tokens~) =>
      Some(
        SubrunClosed(
          id~,
          status~,
          steps~,
          tokens=prompt_tokens + completion_tokens,
        ),
      )
    // A workflow's brackets, carried through unchanged: the host needs the
    // paths to tail and the ordinal range to know whose children these are.
    WorkflowStarted(id~, journal~, events~, first_child~, child_count~) =>
      Some(WorkflowOpened(id~, journal~, events~, first_child~, child_count~))
    WorkflowFinished(id~) => Some(WorkflowClosed(id~))
    // Not shown, and now each one a recorded decision rather than a line the
    // view drops unnoticed. `plan_reminder` and the goal reminders/checks are
    // model-directed text, not news for the user (the TUI drops them too);
    // `goal_updated` and the block/unblock events duplicate the durable
    // `[goal]` marker commits this client already renders and reduces off the
    // `session.event` stream (see `goal.mbt`), so the stream copies stay
    // wire-transport; the auto-continue budget is a headless-run concern the
    // desktop does not drive yet;
    // `turn_failed` and `command_error` reach the view as the host's normalized
    // error, not as stream events; `auto_compaction_started/failed` are internal
    // to an open turn, unlike the finish this view previews;
    // `session_started`/`workspace_created`/`fleet_started` describe a headless
    // run's setup; the MCP events are engine-side registry diagnostics.
    GoalUpdated(..)
    | GoalBlocked(..)
    | GoalUnblocked
    | GoalCheck(..)
    | GoalReminder(..)
    | GoalContinue(..)
    | GoalBudgetExhausted(..)
    | PlanReminder(..)
    | TurnFailed(..)
    | CommandError(..)
    | AutoCompactionStarted(..)
    | AutoCompactionFailed(..)
    | SessionStarted(..)
    | WorkspaceCreated(..)
    | FleetStarted(..)
    | McpConfigIgnored(..)
    | McpConfigUnreadable(..)
    | McpConfigInvalid(..)
    | McpToolsRegistered(..)
    | McpToolDuplicate(..)
    | McpToolRenamed(..)
    | McpToolsCapped(..)
    | McpServerSkippedOverCap(..)
    | McpConnectFailed(..)
    | McpListToolsFailed(..)
    | McpListToolsTimeout(..)
    | McpNoTools(..) => None
  }
}
