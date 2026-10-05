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
/// cost the child actually spent — read from the child's own result file
/// (`usage`, `steps`), so it is exact for the requests the child made.
struct SubrunResult[T] {
  value : T?
  terminal : SubrunTerminal
  steps_used : Int
  prompt_tokens : Int
  completion_tokens : Int
  cost_usd : Double?
  unaccounted : String?
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
/// The child's own money figure for the run: the `usage.cost_usd` its result
/// file reported. `None` means unknown, never free: an engine
/// that prices nothing leaves it absent.
pub fn[T] SubrunResult::cost_usd(self : SubrunResult[T]) -> Double? {
  self.cost_usd
}

///|
/// Why the counts may fall short of what the child spent: it left no usable
/// result, so they are only what was observed. `None` when they are the
/// child's own account.
pub fn[T] SubrunResult::unaccounted(self : SubrunResult[T]) -> String? {
  self.unaccounted
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
/// With a `ChildSession` this RAISES, before anything is spawned or
/// announced, when the child's ordinal cannot be recorded: a durable child
/// is never launched on an id the ledger does not hold.
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
  // A durable child's ordinal comes from the session's ledger, recorded
  // before the child exists. A child with no session of its own leaves
  // nothing an ordinal could collide on, and counts in memory.
  let ordinal = match child_session {
    Some(spec) => spec.allocate(count=1, owner="engine")
    None => {
      ephemeral_ids.val += 1
      ephemeral_ids.val
    }
  }
  let id = "sr-\{ordinal}"
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
    unaccounted : String?,
  ) -> Unit {
    emit_event(
      SubrunFinished(
        id~,
        status~,
        steps~,
        prompt_tokens~,
        completion_tokens~,
        unaccounted~,
      ),
    )
  }
  // The spawn/drain/deadline machinery is the SHARED contract
  // implementation in `moonbitlang/workflow/spawn` — one definition for the
  // engine and for every foreign adapter. Cancellation re-raises out of
  // it after teardown; the errdefer closes the finish bracket first. A
  // result-file child reports its costs only in its result, so a cancelled
  // one's are unknown.
  errdefer finished(
    "cancelled",
    0,
    0,
    0,
    Some("the sub-run was cancelled before its result was read"),
  )
  let contract = @spawn.contract_run(
    command~,
    args~,
    input~,
    kind~,
    id~,
    wall_deadline_ms~,
    cwd?,
    extra_env?,
  )
  // Re-typing the raw report happens HERE, at the layer that knows the
  // schema: a finished run whose report the caller rejects is a Failed
  // sub-run, never rendered.
  let (value, terminal) = match contract.outcome {
    Finished(value~, ..) =>
      match parse_report(value) {
        Ok(value) => (Some(value), Captured)
        Err(problem) =>
          ((None : T?), Failed("subrun report rejected: \{problem}"))
      }
    DidNotFinish(failure~, ..) =>
      (
        None,
        match failure {
          NoReport => NoReport
          MaxSteps => MaxSteps
          ContextYield => ContextYield
          TimedOut => TimedOut
          // A contract run never skips: skipping is a replay decision.
          Skipped => Failed("skipped")
          Failed(reason) => Failed(reason)
        },
      )
  }
  // Every contract run accounts for its attempt, launched or not.
  let attempt = contract.outcome.attempt()
  let steps_used = attempt.map(a => a.steps_used).unwrap_or(0)
  let prompt_tokens = attempt.map(a => a.prompt_tokens).unwrap_or(0)
  let completion_tokens = attempt.map(a => a.completion_tokens).unwrap_or(0)
  let unaccounted = attempt.bind(a => a.unaccounted)
  finished(
    status_of(terminal),
    steps_used,
    prompt_tokens,
    completion_tokens,
    unaccounted,
  )
  {
    value,
    terminal,
    steps_used,
    prompt_tokens,
    completion_tokens,
    cost_usd: attempt.bind(a => a.cost_usd),
    unaccounted,
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
/// It also names the session's ledger: the one allocator of child ordinals
/// for this parent, shared by `run_subrun` and by every workflow snippet's
/// reserved block. An ordinal is recorded durably before it is handed out,
/// so a restarted engine cannot reuse one an earlier process gave away —
/// including a block a snippet was given and has not used yet.
///
/// The ledger is opened, and this process becomes the session's one owner
/// of it, at the FIRST allocation — not when this value is built. A session
/// that never delegates gets no ledger and no lock file, and a session
/// directory is not created ahead of the session's own first record. So the
/// rule is one ALLOCATOR per session, not one engine: several engines may
/// run turns of a session, and whichever allocates first holds the ledger
/// until it closes.
struct ChildSession {
  root : String
  parent : String
  ledger_path : String
  ledger_dirs : Array[String]?
  first_free : async () -> Int
  /// Serializes opening, every allocation, and closing: ownership is never
  /// released under an allocation that has not finished.
  gate : @async.Mutex
  mut ledger : @ledger.Ledger?
  mut closed : Bool
}

///|
/// The children of session `parent` under `root`, numbered from the ledger
/// at `ledger`.
///
/// `first_free` answers, when asked, the lowest child ordinal the session
/// store shows to be unused: one past the highest child session that
/// exists. It is asked each time the ledger is opened, not once up front —
/// a child that is not in the ledger (one from before the ledger existed)
/// may appear between building this value and the first allocation. The
/// ledger starts from whichever of that and its own records is further on.
///
/// `ledger_dirs` is the chain of directories the ledger's existence depends
/// on, innermost first, made durable with its first record; left out, only
/// the ledger's own directory is.
pub fn ChildSession::ChildSession(
  root~ : String,
  parent~ : String,
  ledger~ : String,
  ledger_dirs? : Array[String],
  first_free? : async () -> Int = () => 1,
) -> ChildSession {
  {
    root,
    parent,
    ledger_path: ledger,
    ledger_dirs,
    first_free,
    gate: Mutex(),
    ledger: None,
    closed: false,
  }
}

///|
/// Allocate `count` consecutive child ordinals and return the first, taking
/// ownership of the session's ledger if this is the first allocation.
///
/// Raises, returning no allocation, when another process already holds this
/// session's ledger — one allocator at a time, so that two cannot hand out
/// the same ordinal — when the record cannot be written, or once this value
/// has been closed. An opening that fails is tried afresh by the next
/// allocation.
async fn ChildSession::allocate(
  self : ChildSession,
  count~ : Int,
  owner~ : String,
) -> Int {
  self.gate.acquire()
  defer self.gate.release()
  guard !self.closed else {
    fail("this session's subagents are closed: its engine is stopping")
  }
  let ledger = match self.ledger {
    Some(ledger) => ledger
    None => {
      let floor = (self.first_free)()
      guard @ledger.Ledger::open(
          self.ledger_path,
          floor~,
          dirs?=self.ledger_dirs,
        )
        is Some(ledger) else {
        fail(
          "another openseek process is already running this session's subagents",
        )
      }
      self.ledger = Some(ledger)
      ledger
    }
  }
  ledger.allocate(count~, owner~)
}

///|
/// Stop allocating for this session and give up its ledger, once any
/// allocation in flight has finished. An allocation that arrives later is
/// refused — it does not quietly take the ledger back. Exiting releases the
/// ledger too; this is for an engine that stops serving a session and keeps
/// living, and it belongs AFTER the tasks that may allocate have ended.
pub async fn ChildSession::close(self : ChildSession) -> Unit {
  self.gate.acquire()
  defer self.gate.release()
  self.closed = true
  if self.ledger is Some(ledger) {
    ledger.close()
    self.ledger = None
  }
}

///|
/// Ordinals for children that have no session of their own (`--no-session`):
/// unique within this engine's event stream, which is all the pairing of a
/// started bracket with its finished one needs.
let ephemeral_ids : Ref[Int] = { val: 0, }

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
