///|
/// One event on the engine's stdout JSONL stream — the wire contract between
/// `openseek run`/`openseek serve` and every client that reads them (the TUI,
/// the desktop host, and any script consuming `run`'s stdout).
///
/// The stream is a protocol, not a log. `emit` (in `openseek_protocol/emit`)
/// writes each event's line — exactly its flat `to_json` fields — straight to
/// stdout through its own writer, never through a logger — the CLI links none
/// — so a client reading stdout sees only events.
///
/// There is no severity on the line: a client that wants one derives it from
/// the variant it decoded. `emit` is the only writer; `parse` is its inverse.
pub(all) enum Event {
  // ── agent loop ─────────────────────────────────────────────────────────
  AgentSetupFailed(error~ : String)
  AgentStep(step~ : Int)
  AgentAborted(reason~ : String)
  AgentFinished(answer~ : String)
  MaxStepsExhausted
  TurnFailed(error~ : String)
  AssistantDelta(content~ : String)
  /// One transient provider reasoning fragment. Consumers may render or ignore
  /// these high-volume progress events; completed reasoning still emits once
  /// as `ReasoningMessage` and is stored with its assistant response.
  ReasoningDelta(content~ : String)
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

  // ── approval ───────────────────────────────────────────────────────────
  /// A tool is asking the controller for permission and is BLOCKED until an
  /// `approval` command carrying this `id` comes back. The one event on this
  /// stream that is a question rather than a report, and the only one a
  /// controller MUST answer: there is no deadline behind it, so a controller
  /// that reads events and never writes one leaves the turn stopped until
  /// somebody cancels it.
  ///
  /// `id` is minted by the engine and is unique within one engine process.
  /// `body` is what would actually RUN, verbatim — the `mbtx` program —
  /// while `detail` describes only what would be granted. A controller that
  /// renders one without the other is asking someone to approve a permission
  /// without showing them what it is for.
  ApprovalRequested(
    id~ : String,
    tool_name~ : String,
    detail~ : String,
    body~ : String?
  )
  /// How a previously requested approval settled — including when it settled
  /// without the controller's answer — the turn was interrupted, or a second
  /// controller answered first. Purely informational: a controller uses it to
  /// retire the prompt it is showing.
  ///
  /// `outcome` is `"allowed_once"`, `"rejected"`, or `"cancelled"`. The
  /// runtime's fourth outcome, `unavailable`, never appears here: it is what an
  /// engine with no controller answers, and such an engine emits no request in
  /// the first place.
  ApprovalResolved(id~ : String, outcome~ : String)

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
  /// Also reported when the cause was cancellation; how loudly to show it is
  /// the client's call, made from the variant.
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

  // ── workflow ───────────────────────────────────────────────────────────
  /// A `mbtx` snippet started a workflow: a run that delegates to child
  /// agents of its own, through `moonbitlang/workflow`.
  ///
  /// The engine emits this because nothing else can. The workflow library is
  /// generic — it never learns openseek exists — so a run inside a snippet
  /// would otherwise be invisible: the parent sees one opaque `mbtx` tool
  /// call, however many children it starts. What mbtx knows, and says here,
  /// is where it told the run to write and which child ordinals it reserved
  /// for it. Discovery is therefore not discovery; a reader is told where to
  /// look, exactly as `SubrunStarted` tells it a sub-run began.
  ///
  /// `journal` is an append-only JSONL ledger of RESOLVED calls (phase,
  /// timings, spend); `events` is the sidecar that reports a launch when it
  /// STARTS, which the journal cannot — an entry carries an outcome, so it
  /// lands only at completion. Both are absolute paths a reader tails.
  ///
  /// `first_child`/`child_count` bound the reserved ordinals: the child
  /// sessions of this run are exactly `<parent>-sr-N` for N in
  /// `[first_child, first_child + child_count)`, which is how a reader knows
  /// which transcripts belong to it.
  WorkflowStarted(
    id~ : String,
    journal~ : String,
    events~ : String,
    first_child~ : Int,
    child_count~ : Int
  )
  /// The paired completion, emitted on every exit of the snippet that owns
  /// the run — success, failure, and cancellation — so a reader never shows
  /// a workflow as running forever.
  WorkflowFinished(id~ : String)

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
