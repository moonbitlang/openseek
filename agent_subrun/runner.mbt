///|
/// How a sub-run ended. External cancellation of the CALLER is deliberately
/// not a terminal: it re-raises out of `run_subrun` (tearing the child down
/// on the way) so structured concurrency sees it, per the engine-wide rule
/// that cancellation is never folded into an ordinary failure.
pub enum SubrunTerminal {
  /// The child submitted a valid report before exiting.
  Captured
  /// The child exited cleanly without ever submitting a report.
  NoReport
  /// The child exhausted its step budget without a report.
  MaxSteps
  /// The child yielded at its context ceiling without a report.
  ContextYield
  /// The runner's wall deadline expired: stdin was closed (graceful cancel)
  /// and the child was terminated after the grace period. A report that
  /// arrived before the cut still reports `Captured`.
  TimedOut
  /// The child failed: spawn failure, a turn/setup failure it reported, a
  /// garbled report, or an exit with none of the above observed.
  Failed(String)
} derive(Debug, Eq)

///|
/// The outcome of one sub-run: the parsed report when there is one, plus the
/// cost the child actually spent — observed from the child's own event
/// stream (`usage` summed, `agent_step` maxed), so it is exact for the
/// requests the child made.
struct SubrunResult[T] {
  value : T?
  terminal : SubrunTerminal
  steps_used : Int
  prompt_tokens : Int
  completion_tokens : Int
  cost_usd : Double?
  subrun_id : String
} derive(Debug)

///|
/// The parsed report, when the child submitted one.
pub fn[T] SubrunResult::value(self : SubrunResult[T]) -> T? {
  self.value
}

///|
/// How the sub-run ended.
pub fn[T] SubrunResult::terminal(self : SubrunResult[T]) -> SubrunTerminal {
  self.terminal
}

///|
/// Model requests the child actually made.
pub fn[T] SubrunResult::steps_used(self : SubrunResult[T]) -> Int {
  self.steps_used
}

///|
/// The child's own money figure for the run, summed from the `usage.cost_usd`
/// its event stream reported. `None` means unknown, never free: an engine
/// that prices nothing leaves it absent.
pub fn[T] SubrunResult::cost_usd(self : SubrunResult[T]) -> Double? {
  self.cost_usd
}

///|
/// The runner-assigned sub-run id ("sr-N"): the same id the
/// SubrunStarted/SubrunFinished brackets carried, and — when the child was
/// launched with a `ChildSession` — the suffix of the child's durable
/// session id.
pub fn[T] SubrunResult::subrun_id(self : SubrunResult[T]) -> String {
  self.subrun_id
}

///|
/// Run one sub-run in a DEDICATED CHILD PROCESS and report what happened and
/// what it cost.
///
/// `command`/`args` name the child — in production the parent's own
/// executable running a preset in managed mode, `["run", "--input-format",
/// "json", "--cancel-on-stdin-eof", "--kind", <kind>, "--result-file",
/// "{result_file}", ...]` (same binary, so the report's derived JSON codecs
/// cannot drift), in tests any script that speaks transport 2 of the
/// workflow child contract. The runner writes the request as one JSON line on
/// the child's stdin and HOLDS THE PIPE OPEN: closing it is the
/// graceful-cancel signal. The child's result file decides the outcome and
/// its cost; its stdout is for humans and is not read. `parse_report` turns
/// the result's output into the typed value (rejects become `Failed`). A
/// child with no `ChildSession` is launched with `--no-session`, so it keeps
/// its transcript in memory rather than starting a session of its own.
///
/// Deadline: after `wall_deadline_ms` the runner closes stdin and gives the
/// child `cancel_grace_ms` to flush and exit — a report that lands during
/// the grace still counts — then terminates it. External cancellation of
/// the caller re-raises after teardown; it is never folded into a terminal.
///
/// Lifecycle brackets: the runner emits `SubrunStarted{id, kind, label}`
/// before anything else and a PAIRED `SubrunFinished{id, status, costs}` on
/// every exit — success, failure, and cancellation (emitted before the
/// re-raise) — so a reader never shows a sub-run as running forever. Both
/// land during the parent's tool call, well before the parent turn's own
/// terminal event, which the TUI's stale-run guard requires. `label` is
/// display-bounded here defensively; `emit_event` is a test seam that
/// defaults to the process log.
pub async fn[T] run_subrun(
  command~ : String,
  args~ : Array[String],
  input~ : Json,
  parse_report~ : (Json) -> Result[T, String],
  wall_deadline_ms~ : Int,
  kind~ : String,
  label~ : String,
  cwd? : String,
  child_session? : ChildSession,
  extra_env? : Map[String, String],
  emit_event? : (@protocol.Event) -> Unit = event => @emit.emit(event),
) -> SubrunResult[T] {
  // Bump the process counter past any child ordinal an earlier engine
  // process already persisted for this parent — monotonic, so it can only
  // skip ids, never reuse one. Without a child session, a floor of 1 is a
  // no-op.
  let first_free = match child_session {
    Some(spec) => spec.first_free
    None => 1
  }
  let id = "sr-\{reserve_subrun_ordinals(1, first_free~)}"
  // The child persists its own transcript under `<parent>-<id>` when the
  // parent is durable: the id exists only after allocation, so the session
  // argv is the runner's to append, not the caller's.
  let args = match child_session {
    Some(spec) =>
      [..args, "--session", "\{spec.parent}-\{id}", "--session-root", spec.root]
    None => [..args, "--no-session"]
  }
  emit_event(
    SubrunStarted(id~, kind~, label=@agent_tool.brief_line(label, limit=72)),
  )
  fn finished(
    status : String,
    steps : Int,
    prompt_tokens : Int,
    completion_tokens : Int,
  ) -> Unit {
    emit_event(
      SubrunFinished(id~, status~, steps~, prompt_tokens~, completion_tokens~),
    )
  }
  // The spawn/drain/deadline machinery is the SHARED contract
  // implementation in `moonbitlang/workflow/spawn` — one definition for the
  // engine and for every foreign adapter. Cancellation re-raises out of
  // it after teardown; the errdefer closes the finish bracket first. A
  // result-file child reports its costs only in its result, so a cancelled
  // one closes with none.
  errdefer finished("cancelled", 0, 0, 0)
  let contract = @spawn.contract_run(
    command~,
    args~,
    input~,
    kind~,
    id~,
    wall_deadline_ms~,
    cwd?,
    extra_env?,
    transport=ResultFile,
  )
  // Re-typing the raw report happens HERE, at the layer that knows the
  // schema: a Captured contract terminal whose report the caller rejects
  // is a Failed sub-run, never rendered.
  let (value, terminal) = match contract.terminal {
    Captured =>
      match contract.report {
        Some(report) =>
          match parse_report(report) {
            Ok(value) => (Some(value), Captured)
            Err(problem) =>
              ((None : T?), Failed("subrun report rejected: \{problem}"))
          }
        None => (None, Failed("captured terminal without a report"))
      }
    NoReport => (None, NoReport)
    MaxSteps => (None, MaxSteps)
    ContextYield => (None, ContextYield)
    TimedOut => (None, TimedOut)
    Failed(reason) => (None, Failed(reason))
  }
  finished(
    status_of(terminal),
    contract.steps_used,
    contract.prompt_tokens,
    contract.completion_tokens,
  )
  {
    value,
    terminal,
    steps_used: contract.steps_used,
    prompt_tokens: contract.prompt_tokens,
    completion_tokens: contract.completion_tokens,
    cost_usd: contract.cost_usd,
    subrun_id: id,
  }
}

///|
/// Where a child persists its own transcript: the parent's session root
/// plus the parent's session id. The runner derives the child's session id
/// as `<parent>-<subrun id>` — a sibling of the parent's session in the
/// same root, so session tooling (the viewer, `openseek sessions`)
/// discovers child transcripts with no extra plumbing.
///
/// `first_free` is the lowest child ordinal no earlier engine process has
/// persisted for this parent (the CLI scans the store at startup). The
/// sub-run counter is per-process, so without this floor a RESUMED durable
/// session would reuse `sr-1` — and the fresh child session would die on
/// its first append against the old child's file (stale-snapshot check).
struct ChildSession {
  root : String
  parent : String
  first_free : Int
}

///|
/// See `ChildSession`.
pub fn ChildSession::ChildSession(
  root~ : String,
  parent~ : String,
  first_free? : Int = 1,
) -> ChildSession {
  { root, parent, first_free, }
}

///|
/// Per-process monotonic sub-run ids: unique within one engine's stream,
/// which is all the pairing contract needs.
let subrun_ids : Ref[Int] = { val: 0, }

///|
/// Reserve `count` consecutive child ordinals from THIS process's counter and
/// return the first.
///
/// Child sessions are named `<parent>-sr-N`, and `run_subrun` is no longer the
/// only thing that mints one: an mbtx snippet running a workflow allocates its
/// own children. Both must draw from the same counter, or a snippet's `sr-1`
/// and a `review` call's `sr-1` name the same file and the second child dies
/// on its first append against the first's snapshot.
///
/// `first_free` is the same floor `ChildSession` carries — the lowest ordinal
/// no earlier engine process persisted for this parent — applied here so a
/// block reserved right after a resume cannot reuse a persisted id either.
/// Monotonic: this can skip ordinals, never reuse one.
fn reserve_subrun_ordinals(count : Int, first_free~ : Int) -> Int {
  if subrun_ids.val < first_free - 1 {
    subrun_ids.val = first_free - 1
  }
  let base = subrun_ids.val + 1
  subrun_ids.val += if count > 0 { count } else { 1 }
  base
}

///|
/// The wire status vocabulary for a terminal (the "cancelled" status has no
/// terminal — cancellation re-raises — and is emitted by its errdefer).
fn status_of(terminal : SubrunTerminal) -> String {
  match terminal {
    Captured => "captured"
    NoReport => "no_report"
    MaxSteps => "max_steps"
    ContextYield => "context_yield"
    TimedOut => "timed_out"
    Failed(_) => "failed"
  }
}

///|
#doc(hidden)
#deprecated
pub extend SubrunResult with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend SubrunTerminal with Debug::{to_repr}

///|
#doc(hidden)
#deprecated
pub extend SubrunTerminal with Eq::{equal, not_equal}
