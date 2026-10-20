// The background tasks card's content, derived from the two places a
// conversation's background work is known: its jobs listing (commands, and
// the subagents the engine runs as jobs) and the workflows its snippets
// announced (subagents a client may see before their job is listed). A
// subagent seen in both is one task, keyed by its child session.

///|
/// A running command.
pub(all) struct RunningJob {
  command : String
  /// Milliseconds since the epoch.
  started_at_ms : Int64
} derive(Eq, Debug)

///|
pub extend RunningJob with Eq::{equal, not_equal}

///|
pub extend RunningJob with @debug.Debug::{to_repr}

///|
/// What the conversation runs in the background, while anything does.
pub(all) struct BackgroundTasks {
  /// Running commands, in the listing's order: newest first.
  jobs : Array[RunningJob]
  /// Running subagents' titles: their kind and task.
  subagents : Array[String]
  /// How many tasks have ended among those known.
  finished : Int32
  /// Whether older jobs are left unlisted, so more may have ended.
  more_finished : Bool
  /// Whether a running task is a job, so the Jobs panel lists it; otherwise
  /// only the Workflows panel does.
  in_jobs : Bool
} derive(Eq, Debug)

///|
pub extend BackgroundTasks with Eq::{equal, not_equal}

///|
pub extend BackgroundTasks with @debug.Debug::{to_repr}

///|
/// The card's content, or `None` when nothing runs: the overview shows the
/// card only while there is something running to show.
pub fn BackgroundTasks::from_listing(
  jobs~ : Array[@protocol.JobView],
  more_jobs~ : Bool,
  workflows~ : Array[@workflow.Run],
) -> BackgroundTasks? {
  let running_jobs : Array[RunningJob] = []
  let subagents : Array[String] = []
  let seen : Set[String] = Set([])
  let mut finished = 0
  for view in jobs {
    let job = view.job
    let terminal = job.state.is_terminal()
    if job.subagent is Some(info) {
      seen.add(info.session)
      if !terminal {
        subagents.push("\{info.kind}: \{info.label}")
      }
    } else if !terminal {
      running_jobs.push({
        command: job.command,
        started_at_ms: job.started_at_ms,
      })
    }
    if terminal {
      finished += 1
    }
  }
  let in_jobs = !running_jobs.is_empty() || !subagents.is_empty()
  for run in workflows {
    for row in run.ordered_rows() {
      guard !seen.contains(row.child) else { continue }
      seen.add(row.child)
      // A row a closed run never finished will not finish; it is not running.
      if row.status is None && !run.closed {
        subagents.push("\{row.kind}: \{row.label}")
      } else {
        finished += 1
      }
    }
  }
  guard !running_jobs.is_empty() || !subagents.is_empty() else { return None }
  Some({
    jobs: running_jobs,
    subagents,
    finished,
    more_finished: more_jobs,
    in_jobs,
  })
}

///|
/// How many tasks are running.
pub fn BackgroundTasks::running(self : BackgroundTasks) -> Int32 {
  self.jobs.length() + self.subagents.length()
}

///|
/// A running span in the unit a reader thinks in.
fn elapsed(ms : Double) -> String {
  let seconds = (ms.max(0.0) / 1000.0).to_int()
  if seconds < 60 {
    "\{seconds}s"
  } else if seconds < 3600 {
    "\{seconds / 60}m \{seconds % 60}s"
  } else {
    "\{seconds / 3600}h \{seconds % 3600 / 60}m"
  }
}
