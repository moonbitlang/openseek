///|
/// One event on the engine's stdout JSONL stream — the wire contract between
/// `openseek run`/`openseek serve` and every client that reads them (the TUI,
/// the desktop host, and any script consuming `run`'s stdout).
///
/// The stream doubles as the process log: `emit` routes through `@xlog`, whose
/// handler serializes an `Entry` per line as
/// `{"timestamp":…,"level":…,"source":…,<fields>}` — structured fields are
/// hoisted to the top level, so an event's own fields sit alongside the
/// envelope rather than nested under it.
///
/// Every variant owns its log level, so a call site cannot report the same
/// event at two severities. `emit` is the only writer; `parse` is its inverse.
pub(all) enum Event {
  // ── agent loop ─────────────────────────────────────────────────────────
  AgentSetupFailed(error~ : String)
  AgentStep(step~ : Int)
  AgentAborted(reason~ : String)
  AgentFinished(answer~ : String)
  MaxStepsExhausted
  TurnFailed(error~ : String)
  AssistantDelta(content~ : String)
  AssistantMessage(content~ : String)
  ReasoningMessage(content~ : String)
  Usage(usage~ : Usage)
  /// `brief` is always written, `null` when the tool reported none: an absent
  /// key and a null one are indistinguishable to every decoder, so the shape
  /// stays uniform across the three call sites that emit a tool result.
  ToolResult(
    tool_call_id~ : String,
    tool_name~ : String,
    is_error~ : Bool,
    content~ : String,
    brief~ : String?
  )
  ToolCallDecodeError(
    tool_call_id~ : String,
    tool_name~ : String,
    error~ : String
  )

  // ── steering ───────────────────────────────────────────────────────────
  SteerApplied(kind~ : String, content~ : String)
  SteerDropped(content~ : String)
  BackgroundNotice(content~ : String)

  // ── goal ───────────────────────────────────────────────────────────────
  GoalUpdated(goal~ : String?)
  GoalBlocked(reason~ : String)
  GoalUnblocked
  GoalCheck(content~ : String)
  GoalReminder(content~ : String)
  GoalContinue(remaining~ : Int)
  GoalBudgetExhausted(turns~ : Int)

  // ── plan ───────────────────────────────────────────────────────────────
  PlanReminder(content~ : String)

  // ── compaction ─────────────────────────────────────────────────────────
  CompactionStarted(from_sequence~ : Int, to_sequence~ : Int)
  CompactionFinished(
    from_sequence~ : Int,
    to_sequence~ : Int,
    summary~ : String
  )
  /// Reported at `Error` even when the cause was cancellation: no decoder
  /// reads the envelope's level, so one severity per event costs nothing and
  /// keeps the level a property of the event rather than of the call site.
  CompactionFailed(error~ : String)
  AutoCompactionStarted(from_sequence~ : Int, to_sequence~ : Int)
  AutoCompactionFinished(
    from_sequence~ : Int,
    to_sequence~ : Int,
    summary~ : String
  )
  AutoCompactionFailed(error~ : String)
  ContextYield(to_sequence~ : Int, answer~ : String)

  // ── subrun ─────────────────────────────────────────────────────────────
  /// A nested sub-run (a review, an explore) began inside this run. `id` is
  /// unique within the stream so overlapping sub-runs pair each start with
  /// its finish; `kind` names the surface ("review", "explore"); `label` is
  /// a short, DISPLAY-BOUNDED string (typically a truncated, sanitized
  /// query) — never unbounded raw input.
  SubrunStarted(id~ : String, kind~ : String, label~ : String)
  /// The paired completion. The emitter's contract (the sub-run runner —
  /// wire-first: this variant ships ahead of it): emit on success, failure,
  /// AND cancellation, and BEFORE the parent turn's own terminal event (the
  /// TUI's stale-run guard drops run-tagged events after a terminal), so a
  /// reader never shows a sub-run as running forever. `status` is the
  /// sub-run terminal in snake_case ("captured", "no_report", "max_steps",
  /// "context_yield", "timed_out", "failed", "cancelled"); `steps` and the
  /// token counts are the child's actual spend, for cost attribution.
  SubrunFinished(
    id~ : String,
    status~ : String,
    steps~ : Int,
    prompt_tokens~ : Int,
    completion_tokens~ : Int
  )

  // ── session / workspace ────────────────────────────────────────────────
  /// `workspace_root` is optional because it postdates the event: engines
  /// between d11e04c2 (which added `session_started`) and d5d0b208 (which
  /// added `--dir`) emit only `session` and `session_root`. No client reads it.
  SessionStarted(
    session~ : String,
    session_root~ : String,
    workspace_root~ : String?
  )
  SessionError(error~ : String)
  WorkspaceCreated(dir~ : String)
  CommandError(error~ : String)
  FleetStarted(runs~ : Int, task~ : String)

  // ── mcp ────────────────────────────────────────────────────────────────
  McpConfigIgnored(reason~ : String)
  McpConfigUnreadable(path~ : String, error~ : String)
  McpConfigInvalid(path~ : String, error~ : String)
  McpToolsRegistered(servers~ : Int, tools~ : Int, names~ : Array[String])
  McpToolDuplicate(server~ : String, tool~ : String)
  McpToolRenamed(from~ : String, to~ : String)
  McpToolsCapped(server~ : String, kept~ : Int)
  McpServerSkippedOverCap(server~ : String)
  /// `error` is always written, `null` when the connection produced no error
  /// value (the server simply yielded nothing) — same uniformity rule as
  /// `ToolResult::brief`.
  McpConnectFailed(server~ : String, error~ : String?)
  McpListToolsFailed(server~ : String, error~ : String)
  McpListToolsTimeout(server~ : String)
  McpNoTools(server~ : String)
} derive(Eq, Debug)

///|
pub extend Event with Debug::{to_repr}

///|
pub extend Event with Eq::{equal, not_equal}
