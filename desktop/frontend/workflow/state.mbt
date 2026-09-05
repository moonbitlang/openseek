// A workflow a snippet is running, as this client can see it: the run the
// engine announced, and one row per subagent, assembled from three sources
// that tick at different moments.
//
// The engine's `workflow_started` bracket says a run exists and which child
// ordinals it may use. The sub-run brackets the host synthesizes from the
// run's sidecar say a child STARTED (with its kind and label) and ENDED (with
// its status and spend). The `workflow.entry` push, read from the run's
// journal, says how a call RESOLVED — phase, timings, cost — and it lands
// only at completion. A row is therefore born from a bracket and refined by
// an entry; either can arrive without the other (a snippet that died leaves
// started rows with no entry; a client that connected late may see entries
// for rows it never saw start), so every update is keyed by the child's
// session id and tolerates missing halves.
//
// Nothing here is durable. The journal and the transcripts in the session
// store are the record; this is what the client knows right now, and it is
// dropped with the conversation it belongs to.

///|
/// One resolved call, as the host read it from the journal. Mirrors the
/// `workflow.entry` payload field for field; the bridge converts.
pub(all) struct Entry {
  workflow : String
  session : String
  child : String
  kind : String
  label : String
  phase : String?
  status : String
  steps : Int
  prompt_tokens : Int
  completion_tokens : Int
  cost_usd : Double?
  /// Milliseconds since the epoch.
  started_at : Double?
  finished_at : Double?
} derive(Eq, @debug.Debug)

///|
pub extend Entry with Eq::{equal, not_equal}

///|
pub extend Entry with @debug.Debug::{to_repr}

///|
/// One subagent of a run. `status` is `None` while the child is running.
pub(all) struct Row {
  /// The child's session id, `<parent>-sr-N`: what the sidebar folds under
  /// the parent and what a click opens.
  child : String
  ordinal : Int
  kind : String
  label : String
  phase : String?
  status : String?
  steps : Int
  tokens : Int
  cost_usd : Double?
  /// Milliseconds since the epoch.
  started_at : Double?
  finished_at : Double?
} derive(Eq, @debug.Debug)

///|
pub extend Row with Eq::{equal, not_equal}

///|
pub extend Row with @debug.Debug::{to_repr}

///|
/// One run. `closed` flips at `workflow_finished`; rows are kept, because a
/// finished run is exactly what a reader wants to look back over.
pub(all) struct Run {
  id : String
  session : String
  first_child : Int
  child_count : Int
  closed : Bool
  rows : Array[Row]
} derive(Eq, @debug.Debug)

///|
pub extend Run with Eq::{equal, not_equal}

///|
pub extend Run with @debug.Debug::{to_repr}

///|
/// The ordinal in a sub-run id (`sr-7` → 7), or `None` for any other shape.
fn ordinal_of(id : String) -> Int? {
  guard id.has_prefix("sr-") else { return None }
  let digits = id.view(start_offset=3)
  // Bounded as `@protocol.split_child_session_id` bounds it: nine digits,
  // so a pathological id cannot overflow, and beyond that it is simply not
  // a sub-run id.
  guard !digits.is_empty() &&
    digits.length() <= 9 &&
    digits.iter().all(c => c.is_ascii_digit()) else {
    return None
  }
  let ordinal = for c in digits; ordinal = 0 {
    continue ordinal * 10 + (c.to_int() - '0'.to_int())
  } nobreak {
    ordinal
  }
  Some(ordinal)
}

///|
/// Whether `ordinal` is one this run reserved.
///
/// Attribution by RANGE is the one place a reader keys on ordinals rather
/// than an explicit id, and it is sound only because of two invariants the
/// engine holds: blocks are allocated parent-side from one counter (so two
/// runs never overlap) and the host refuses sidecar children outside the
/// announced block (so nothing outside a run ever wears its ordinals). The
/// synthesized bracket carries `sr-N` and no run id; carrying one would let
/// this be explicit, and is the natural next protocol change.
fn Run::owns(self : Run, ordinal : Int) -> Bool {
  ordinal >= self.first_child && ordinal < self.first_child + self.child_count
}

///|
/// The engine announced a run. A repeated id (a reconnect replaying the
/// bracket) refreshes the announcement without dropping the rows already
/// known.
pub fn opened(
  runs : Array[Run],
  id~ : String,
  session~ : String,
  first_child~ : Int,
  child_count~ : Int,
) -> Array[Run] {
  match runs.search_by(run => run.id == id) {
    Some(index) => {
      let updated = runs.copy()
      updated[index] = {
        ..runs[index],
        first_child,
        child_count,
        closed: false,
      }
      updated
    }
    None =>
      [
        ..runs,
        { id, session, first_child, child_count, closed: false, rows: [], },
      ]
  }
}

///|
/// The engine closed a run. Rows stay; only the state flips, so a run that
/// ended abnormally still shows every child it started.
pub fn closed(runs : Array[Run], id~ : String) -> Array[Run] {
  runs.map(run => if run.id == id { { ..run, closed: true, } } else { run })
}

///|
/// A sub-run started. When its ordinal belongs to a run this client knows,
/// it is that run's child and gets a row; otherwise it is an ordinary
/// `explore`/`review` sub-run and none of this package's business.
pub fn child_opened(
  runs : Array[Run],
  id~ : String,
  kind~ : String,
  label~ : String,
) -> Array[Run] {
  guard ordinal_of(id) is Some(ordinal) else { return runs }
  runs.map(run => {
    guard run.owns(ordinal) else { return run }
    let child = "\{run.session}-\{id}"
    match run.rows.search_by(row => row.child == child) {
      // Seen already (an entry outran the bracket, or a replay): keep what
      // is known, just make sure it reads as running again if it was not.
      Some(index) => {
        let rows = run.rows.copy()
        rows[index] = { ..rows[index], kind, label, }
        { ..run, rows, }
      }
      None =>
        {
          ..run,
          rows: [
            ..run.rows,
            {
              child,
              ordinal,
              kind,
              label,
              phase: None,
              status: None,
              steps: 0,
              tokens: 0,
              cost_usd: None,
              started_at: None,
              finished_at: None,
            },
          ],
        }
    }
  })
}

///|
/// A sub-run ended. The bracket carries the terminal and the spend; the
/// journal's entry, when it lands, adds phase, timings and cost.
pub fn child_closed(
  runs : Array[Run],
  id~ : String,
  status~ : String,
  steps~ : Int,
  tokens~ : Int,
) -> Array[Run] {
  guard ordinal_of(id) is Some(ordinal) else { return runs }
  runs.map(run => {
    guard run.owns(ordinal) else { return run }
    let child = "\{run.session}-\{id}"
    match run.rows.search_by(row => row.child == child) {
      Some(index) => {
        let rows = run.rows.copy()
        rows[index] = { ..rows[index], status: Some(status), steps, tokens, }
        { ..run, rows, }
      }
      // A finish for a child whose start this client never saw: still a
      // fact about the run. Recorded with what the bracket says.
      None =>
        {
          ..run,
          rows: [
            ..run.rows,
            {
              child,
              ordinal,
              kind: "",
              label: "",
              phase: None,
              status: Some(status),
              steps,
              tokens,
              cost_usd: None,
              started_at: None,
              finished_at: None,
            },
          ],
        }
    }
  })
}

///|
/// A call resolved in the journal. Keyed by the child's session id: refines
/// the row a bracket created, or creates one when the brackets were missed.
/// The bracket's status and the entry's agree by construction (both come
/// from the same contract terminal), so the entry's may overwrite.
pub fn entry(runs : Array[Run], entry : Entry) -> Array[Run] {
  runs.map(run => {
    guard run.id == entry.workflow && run.session == entry.session else {
      return run
    }
    let refined = fn(row : Row) -> Row {
      {
        ..row,
        kind: if row.kind.is_empty() {
          entry.kind
        } else {
          row.kind
        },
        label: if row.label.is_empty() {
          entry.label
        } else {
          row.label
        },
        phase: entry.phase,
        status: Some(entry.status),
        steps: entry.steps,
        tokens: entry.prompt_tokens + entry.completion_tokens,
        cost_usd: entry.cost_usd,
        started_at: entry.started_at,
        finished_at: entry.finished_at,
      }
    }
    match run.rows.search_by(row => row.child == entry.child) {
      Some(index) => {
        let rows = run.rows.copy()
        rows[index] = refined(rows[index])
        { ..run, rows, }
      }
      None => {
        let ordinal = match entry.child.rev_find("-sr-") {
          Some(at) =>
            ordinal_of(entry.child.view(start_offset=at + 1).to_owned()).unwrap_or(
              0,
            )
          None => 0
        }
        {
          ..run,
          rows: [
            ..run.rows,
            refined({
              child: entry.child,
              ordinal,
              kind: "",
              label: "",
              phase: None,
              status: None,
              steps: 0,
              tokens: 0,
              cost_usd: None,
              started_at: None,
              finished_at: None,
            }),
          ],
        }
      }
    }
  })
}

///|
/// The rows of a run, oldest child first — the order they were launched,
/// which is the order a reader follows.
pub fn Run::ordered_rows(self : Run) -> Array[Row] {
  let rows = self.rows.copy()
  rows.sort_by(fn(a, b) { a.ordinal - b.ordinal })
  rows
}

///|
/// How many of a run's children are still running.
pub fn Run::running(self : Run) -> Int {
  self.rows.filter(row => row.status is None).length()
}

///|
/// Total tokens across the run's resolved children.
pub fn Run::tokens(self : Run) -> Int {
  self.rows.fold(init=0, (sum, row) => sum + row.tokens)
}

///|
/// Total cost across children that reported one; `None` when none did.
pub fn Run::cost_usd(self : Run) -> Double? {
  let mut total : Double? = None
  for row in self.rows {
    if row.cost_usd is Some(cost) {
      total = Some(total.unwrap_or(0.0) + cost)
    }
  }
  total
}

///|
/// What a row's status cell says, and the class that styles it. A row still
/// running after its run CLOSED never got its finish — the snippet died, or
/// the finish was lost — and is shown as unresolved rather than pulsing
/// forever; a run's close is the last word its brackets will say.
pub fn row_status(row : Row, closed~ : Bool) -> (String, String) {
  match row.status {
    None =>
      if closed {
        ("unresolved", "failed")
      } else {
        ("running", "running")
      }
    Some("captured") => ("done", "done")
    Some(other) => (other.replace_all(old="_", new=" "), "failed")
  }
}
