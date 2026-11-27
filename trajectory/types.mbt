///|
/// What one span on the timeline represents.
///
/// The vocabulary follows the run itself: a `Run` holds every `Turn`, a turn
/// holds the model calls, tool executions and waits that moved it forward, and
/// the cross-cutting work (a `.mbtx` script, one of its nested PTC calls, a
/// background job, a `job_wait` block) nests one level deeper so the timeline
/// never collapses it into a single opaque block.
#derive(Eq)
pub(all) enum SpanKind {
  /// The whole traced task: one root session plus every session it spawned.
  Run
  /// One turn of one session, from the input that opened it to its terminal.
  Turn
  /// One model request/response.
  LlmCall
  /// One ordinary tool execution.
  ToolExec
  /// A `.mbtx` program run through the `mbtx` tool.
  WorkflowScript
  /// One host-tool call recorded inside a `.mbtx` program's PTC trace.
  PtcToolCall
  /// A background job's own running interval.
  BackgroundJob
  /// One `job_wait` call, i.e. the main loop blocking on background jobs.
  JobWait
  /// A zero-width marker: a compaction summary, a steer, a runtime notice.
  Milestone
}

///|
/// How a span ended, or `Running` while it is still open.
#derive(Eq)
pub(all) enum SpanStatus {
  Running
  Succeeded
  /// The work reported an error: a failed tool, a failed turn.
  Failed
  /// The work was asked to stop.
  Aborted
  /// Someone outside the run cancelled it, or a crash left it dangling.
  Interrupted
  /// The turn reached its context ceiling and yielded its next turn.
  Yielded
}

///|
/// Where a milestone came from. Kept apart from `label` so the frontend can
/// pick an icon without matching display text.
#derive(Eq)
pub(all) enum MilestoneTag {
  Compaction
  Steer
  RuntimeNotice
  ContextYield
  TurnStart
}

///|
/// One interval on the waterfall.
///
/// `started_at_ms` and `ended_at_ms` are wall-clock unix milliseconds taken
/// from the durable session log (`SessionEvent::unix_ms`), so spans from
/// different sessions compare directly. `ended_at_ms` is `None` for work that
/// had not finished when the log was read: the viewer extends those to its own
/// clock instead of guessing an end.
///
/// `parent_id` is the span this one hangs under. `depth` is the nesting level
/// it renders at (`Run` 0, its turns 1, their steps 2, and so on). `title` is
/// the label of the lane the span belongs to — the session's own first line,
/// or `main` / `sub-run N` when the file carries no prompt.
#derive(Eq)
pub(all) struct TrajectorySpan {
  id : String
  parent_id : String?
  session_id : String
  title : String
  depth : Int32
  kind : SpanKind
  status : SpanStatus
  label : String
  started_at_ms : Int64
  ended_at_ms : Int64?
  /// The background job this span started or waited on, when it has one. The
  /// viewer offers it as the handle into the job's `.out` log.
  job_id : String?
  /// All background jobs this span started or waited on (for example a
  /// `job_wait` waiting on several jobs at once).
  job_ids : Array[String]
  /// The durable event this span was read from, so a viewer can open that
  /// exact event in the session's own log. Absent only on the synthetic run
  /// span, which no single event wrote.
  sequence : Int32?
  /// Milestone flavour; `None` on every non-milestone span.
  tag : MilestoneTag?
  metadata : Map[String, Json]
}

///|
/// One session taking part in the run: the root, or a child one.
#derive(Eq)
pub(all) struct TrajectorySession {
  session_id : String
  parent_session_id : String?
  /// The lane label: the session's first prompt line, or a default by depth.
  title : String
  depth : Int32
  started_at_ms : Int64
  ended_at_ms : Int64?
}

///|
/// Run-wide totals, so the viewer can print a summary line without walking
/// every span.
///
/// `wall_ms` is the traced window; `llm_ms`, `tool_ms`, `wait_ms` and
/// `job_ms` are sums over spans of that kind. They overlap in real time (a
/// child agent's work runs inside the parent's tool span), so they are summed
/// per lane rather than claimed to add up to the wall clock.
#derive(Eq)
pub(all) struct TrajectoryStats {
  wall_ms : Int64
  llm_ms : Int64
  tool_ms : Int64
  wait_ms : Int64
  job_ms : Int64
  prompt_tokens : Int64
  completion_tokens : Int64
  /// The longest single step of the run, and the chain it hangs from.
  ///
  /// Deliberately not claimed to be a scheduling critical path: a
  /// dependency-weighted path needs a causal graph the log does not carry,
  /// and summing nested envelopes would count one wall-clock stretch twice.
  /// What it reports is the one step that took the most time, so "where did
  /// this run spend its time" has an answer a reader can go and look at. A
  /// session or turn span is its children's subtotal, never the answer, and
  /// `critical_path` is that step's ancestry, ending at the step itself.
  critical_path_ms : Int64
  critical_path : Array[String]
  span_count : Int32
  turn_count : Int32
  session_count : Int32
}

///|
/// The whole traced run, ready to render.
///
/// `spans` is in rendering order: every span is preceded by its ancestors and
/// followed by its descendants, oldest first among siblings.
#derive(Eq)
pub(all) struct Trajectory {
  root_session_id : String
  /// Earliest span start; the left edge of the timeline.
  t0_ms : Int64
  /// Latest event or span end; the right edge for finished work.
  t_end_ms : Int64
  /// True while some span is still `Running`, i.e. the run may still grow.
  live : Bool
  sessions : Array[TrajectorySession]
  spans : Array[TrajectorySpan]
  stats : TrajectoryStats
}

///|
/// Lightweight durable job timing and outcome from `jobs/<generation>/*.json`.
///
/// When supplied alongside `.jsonl` logs, `BackgroundJob` spans use the
/// recorded start, finish, and terminal status rather than waiting for a
/// later `job_wait` observation (or staying `Running` forever when unwaited).
#derive(Eq)
pub(all) struct JobMetadata {
  session_id : String
  job_id : String
  started_at_ms : Int64
  finished_at_ms : Int64?
  status : SpanStatus
}

///|
/// One session's durable file, as the reader hands it over.
///
/// `text` is the session file verbatim: one header line plus the append-only
/// event lines. `title` is the user-facing name when the store has one, used
/// as the session's lane label.
pub(all) struct SessionLog {
  id : String
  text : String
  title : String?
}

///|
/// Stable JSON tag for a span kind, used on the wire and by the viewer.
pub fn SpanKind::tag(self : SpanKind) -> String {
  match self {
    Run => "run"
    Turn => "turn"
    LlmCall => "llm"
    ToolExec => "tool"
    WorkflowScript => "workflow"
    PtcToolCall => "ptc"
    BackgroundJob => "job"
    JobWait => "wait"
    Milestone => "milestone"
  }
}

///|
/// Stable JSON tag for a span status, used on the wire and by the viewer.
pub fn SpanStatus::tag(self : SpanStatus) -> String {
  match self {
    Running => "running"
    Succeeded => "succeeded"
    Failed => "failed"
    Aborted => "aborted"
    Interrupted => "interrupted"
    Yielded => "yielded"
  }
}

///|
/// Stable JSON tag for a milestone flavour.
pub fn MilestoneTag::tag(self : MilestoneTag) -> String {
  match self {
    Compaction => "compaction"
    Steer => "steer"
    RuntimeNotice => "runtime_notice"
    ContextYield => "context_yield"
    TurnStart => "turn_start"
  }
}

///|
/// Duration of a span read against a clock, for a span that is still running.
/// A span that started after `now_ms` (clock skew between the writer and the
/// reader) reports `0`, never a negative width.
pub fn TrajectorySpan::duration_ms(
  self : TrajectorySpan,
  now_ms : Int64,
) -> Int64 {
  let end = match self.ended_at_ms {
    Some(end) => end
    None => now_ms
  }
  if end < self.started_at_ms {
    0L
  } else {
    end - self.started_at_ms
  }
}
