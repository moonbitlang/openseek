// Live view of a workflow a snippet is running, read from the two files the
// engine told this host about.
//
// A workflow written in an `mbtx` snippet runs inside a sandbox the host does
// not manage, and delegates to child engines the host never launched. All the
// host is TOLD is the `workflow_started` bracket — which names a journal, a
// sidecar, and the child ordinals the run may use — and, eventually,
// `workflow_finished`. In between, nothing about the run reaches this process
// as an event: the library that runs it is generic and never learns openseek
// exists (`moonbitlang/workflow`), and the snippet's own output is captured by
// the tool call that owns it.
//
// What the run DOES leave where the host can reach it is those two files, in
// the session store:
//
// - the SIDECAR (`events.jsonl`) reports a child the moment it is launched and
//   again when it ends, each line carrying the child's session id — the
//   earliest a reader can learn a subagent exists;
// - the JOURNAL (`journal.jsonl`) is the library's ledger of RESOLVED calls:
//   phase, timings, spend, and the child's session id as `attempt_id`. An
//   entry carries an outcome, so it lands only at completion; a reader with
//   only the journal learns of a child no earlier than its finish.
//
// This tail follows both, remembering a byte offset per file and reading only
// what was appended since, and hands each line to the caller as a typed
// callback. It decides nothing about the run's lifetime: the caller starts it
// at `workflow_started` and cancels it at `workflow_finished`.
//
// Deliberately simpler than `subrun/probe.mbt`. Both files are append-only by
// contract and never rewritten in place, so there is no torn-tail repair to
// detect and no watermark to keep — a truncation (size below the offset) is
// treated as a fresh file and re-read from the head.

///|
/// How long a tail is kept alive after the run's finish bracket. The snippet
/// writes its last sidecar lines and journal entries just before it exits,
/// and the bracket can arrive up to a whole interval before the next poll —
/// cancelling on the bracket would lose exactly those lines, leaving a child
/// that finished showing as running. Two intervals guarantee one full poll
/// over the final state of both files.
pub let drain_grace_ms : Int = 2 * WorkflowTailIntervalMs

///|
/// Whether `ordinal` is one the run was announced with. The host synthesizes
/// a sub-run bracket for every child the sidecar names, and the sidecar is
/// written by the snippet — a buggy or hostile one could name an ordinary
/// `explore` child's id and collide with a real lane. The announced block is
/// the host's own knowledge; a child outside it is not this run's.
pub fn in_block(ordinal : Int, first_child~ : Int, child_count~ : Int) -> Bool {
  ordinal >= first_child && ordinal < first_child + child_count
}

///|
/// How often the tail re-checks its files. Nothing kicks it: a snippet's
/// appends do not reach this process as events, so this interval IS the
/// update rate. The same cadence as the sub-run probe, for the same reason.
const WorkflowTailIntervalMs = 1500

///|
/// The most one poll reads from one file. A burst of completions yields its
/// tail on the next pass instead of one large allocation; a line arriving a
/// poll late costs nothing a ledger cares about.
let workflow_tail_max_chunk : Int64 = 128 * 1024

///|
/// One file's tail: where the last poll stopped, and the partial line it
/// stopped inside. Bytes, not text, so a chunk boundary inside a multi-byte
/// character cannot corrupt the line it belongs to.
priv struct FileTail {
  path : String
  mut offset : Int64
  mut carry : Bytes
}

///|
/// Read whatever was appended since the last poll and return the complete
/// lines it contains, decoded. Every failure is silent and non-fatal: the file
/// may not exist yet (the snippet has not launched a child), may be mid-write,
/// or may be gone (a run directory reclaimed after the bracket). A line is
/// worth exactly as much as the next successful poll.
async fn FileTail::poll(self : FileTail) -> Array[String] {
  let file = @fs.open(self.path, mode=ReadOnly) catch { _ => return [] }
  defer file.close()
  let size = file.size() catch { _ => return [] }
  if size < self.offset {
    // Shorter than what was read: not the file that was read. Both files are
    // append-only, so this is a replacement, and the head is the only honest
    // place to resume from.
    self.offset = 0
    self.carry = b""
  }
  if size <= self.offset {
    return []
  }
  let want = size - self.offset
  let take = if want > workflow_tail_max_chunk {
    workflow_tail_max_chunk
  } else {
    want
  }
  let chunk = file.read_exactly_at(take.to_int(), position=self.offset) catch {
    _ => return []
  }
  self.offset += take
  let pending = self.carry + chunk
  let lines : Array[String] = []
  let mut line_start = 0
  for index in 0..<pending.length() {
    if pending[index] != b'\n' {
      continue
    }
    let text = @utf8.decode_lossy(pending[line_start:index].to_owned())
      .trim(chars="\r\n \t")
      .to_owned()
    if !text.is_empty() {
      lines.push(text)
    }
    line_start = index + 1
  }
  self.carry = pending[line_start:].to_owned()
  lines
}

///|
/// A child the sidecar reported launched.
pub(all) struct ChildStarted {
  /// The child's session id, `<parent>-sr-N` — the same string its own record
  /// is named by and the journal's `attempt_id` will carry.
  child : String
  kind : String
  label : String
} derive(Eq, Debug)

///|
pub extend ChildStarted with Eq::{equal, not_equal}

///|
pub extend ChildStarted with Debug::{to_repr}

///|
/// A child the sidecar reported ended.
pub(all) struct ChildFinished {
  child : String
  /// The contract's own vocabulary: `captured`, `no_report`, `max_steps`,
  /// `context_yield`, `timed_out`, `skipped`, `failed`.
  status : String
  steps : Int
  /// Prompt and completion tokens together; the sidecar does not split them.
  tokens : Int
} derive(Eq, Debug)

///|
pub extend ChildFinished with Eq::{equal, not_equal}

///|
pub extend ChildFinished with Debug::{to_repr}

///|
/// One sidecar line, or `None` for a line this build does not read.
fn parse_sidecar(text : String) -> Result[ChildStarted, ChildFinished]? {
  let json = @json.parse(text) catch { _ => return None }
  match json {
    {
      "event": "agent_started",
      "child": String(child),
      "kind": String(kind),
      "label": String(label),
      ..
    } => Some(Ok({ child, kind, label, }))
    {
      "event": "agent_finished",
      "child": String(child),
      "status": String(status),
      "steps": Number(steps, ..),
      "tokens": Number(tokens, ..),
      ..
    } =>
      Some(
        Err({ child, status, steps: steps.to_int(), tokens: tokens.to_int(), }),
      )
    _ => None
  }
}

///|
/// One journal line as the ledger row a reader wants, or `None` for a line
/// this build does not read.
///
/// The journal is `moonbitlang/workflow`'s own format: `{"v":1,"e":ENTRY}`
/// where ENTRY carries the call (kind, label), the outcome as a tagged array
/// — `["Finished", {value, attempt}]` or `["DidNotFinish", {failure,
/// attempt}]` — and the attribution the host renders: phase and the two
/// timestamps. Only the fields named here are read; anything else on the
/// line is ignored, so an added field upstream changes nothing.
fn parse_journal(
  text : String,
  workflow~ : String,
  session~ : String,
) -> @protocol.WorkflowEntryPayload? {
  let json = @json.parse(text) catch { _ => return None }
  guard json is { "v": Number(1, ..), "e": Object(entry), .. } else {
    return None
  }
  guard entry.get("call") is Some(Object(call)) &&
    call.get("kind") is Some(String(kind)) &&
    call.get("label") is Some(String(label)) else {
    return None
  }
  guard entry.get("outcome") is Some(Array([String(tag), Object(body)])) else {
    return None
  }
  let attempt = match body.get("attempt") {
    Some(Object(attempt)) => Some(attempt)
    _ => None
  }
  guard attempt is Some(attempt) &&
    attempt.get("attempt_id") is Some(String(child)) else {
    // A call that never launched (a refused or skipped one) has no child and
    // nothing for a per-subagent view to point at; the sidecar did not report
    // it either.
    return None
  }
  let status = match tag {
    "Finished" => "captured"
    _ =>
      match body.get("failure") {
        Some(Array([String(name), ..])) => failure_status(name)
        Some(String(name)) => failure_status(name)
        _ => "failed"
      }
  }
  let int_at = fn(fields : Map[String, Json], name : String) -> Int {
    match fields.get(name) {
      Some(Number(n, ..)) => n.to_int()
      _ => 0
    }
  }
  // Milliseconds since the epoch, as the plain JSON numbers the journal
  // writes them as. `Double` carries them exactly and crosses the wire as a
  // number; core's `Int64` codec would want a string.
  let time_at = fn(fields : Map[String, Json], name : String) -> Double? {
    match fields.get(name) {
      Some(Number(n, ..)) => Some(n)
      _ => None
    }
  }
  Some({
    workflow,
    session,
    child,
    kind,
    label,
    phase: match entry.get("phase") {
      Some(String(phase)) => Some(phase)
      _ => None
    },
    status,
    steps: int_at(attempt, "steps_used"),
    prompt_tokens: int_at(attempt, "prompt_tokens"),
    completion_tokens: int_at(attempt, "completion_tokens"),
    cost_usd: match attempt.get("cost_usd") {
      Some(Number(cost, ..)) => Some(cost)
      _ => None
    },
    started_at: time_at(entry, "started_at"),
    finished_at: time_at(entry, "finished_at"),
  })
}

///|
/// The contract's snake_case status for a library failure name — the same
/// vocabulary the `subrun_finished` bracket uses, so a reader learns one.
fn failure_status(name : String) -> String {
  match name {
    "TimedOut" => "timed_out"
    "NoReport" => "no_report"
    "MaxSteps" => "max_steps"
    "ContextYield" => "context_yield"
    "Skipped" => "skipped"
    _ => "failed"
  }
}

///|
/// Tail one workflow's sidecar and journal until the task is cancelled,
/// reporting each line through the matching callback.
///
/// The caller owns the lifetime: it starts this at the `workflow_started`
/// bracket and cancels it at `workflow_finished`. Nothing here decides when a
/// run is over — the brackets already say so, and a tail that guessed from
/// the files could only guess late. The sidecar is polled before the journal
/// on every pass, so a child's `started` line is always seen before the entry
/// that resolves it.
pub async fn follow_run(
  workflow~ : String,
  session~ : String,
  journal~ : String,
  events~ : String,
  on_child_started~ : async (ChildStarted) -> Unit,
  on_child_finished~ : async (ChildFinished) -> Unit,
  on_entry~ : async (@protocol.WorkflowEntryPayload) -> Unit,
) -> Unit {
  let sidecar : FileTail = { path: events, offset: 0, carry: b"", }
  let ledger : FileTail = { path: journal, offset: 0, carry: b"", }
  for ;; {
    @async.sleep(WorkflowTailIntervalMs)
    for line in sidecar.poll() {
      match parse_sidecar(line) {
        Some(Ok(started)) => on_child_started(started)
        Some(Err(finished)) => on_child_finished(finished)
        None => ()
      }
    }
    for line in ledger.poll() {
      if parse_journal(line, workflow~, session~) is Some(entry) {
        on_entry(entry)
      }
    }
  }
}

///|
/// A label fit for a lane. The sidecar's label is whatever the snippet's
/// author passed to `wf.agent(label=...)` — model-written and unbounded —
/// while a bracket's label is display-bounded by contract, so the same bound
/// `run_subrun` applies (72 characters) is applied here before one is
/// synthesized.
pub fn display_label(label : String) -> String {
  let flat = label.replace_all(old="\n", new=" ").trim(chars=" \t").to_owned()
  if flat.length() <= 72 {
    flat
  } else {
    flat.view(end_offset=71).to_owned() + "…"
  }
}
