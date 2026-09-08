///|
/// Plain text alone cannot disambiguate completion from waiting for a job.
/// Explicit finish is handled elsewhere and never calls this guard.
fn AgentLoop::background_finish_notice(self : AgentLoop) -> String? {
  guard self.tools.background_jobs is Some(jobs) else { return None }
  let pending = jobs.pending()
  guard !pending.is_empty() else { return None }
  let labels = pending
    .map(job => "\{job.id}: \{@agent_tool.brief_line(job.command, limit=100)}")
    .join("\n")
  Some(
    "Background jobs still need a decision:\n\{labels}\nIf your work is complete, call finish. If you need their results and have no other work, call job_wait with job_ids. Otherwise keep working, or stop unneeded jobs with job_stop.",
  )
}

///|
/// Only the selected jobs and user input can complete the wait. The losing
/// branch is cancelled by any(); it observes state and owns no process.
async fn AgentLoop::wait_for_jobs(
  self : AgentLoop,
  ids : Array[String],
) -> String {
  guard self.tools.background_jobs is Some(jobs) else {
    fail("no background job registry is available")
  }
  guard !ids.is_empty() else { fail("job_wait requires at least one job id") }
  for id in ids {
    guard jobs.snapshot(id) is Some(_) else {
      fail("no background job with id \{id}")
    }
  }
  let completed = @async.any([
    () => {
      jobs.wait_any(ids)
      true
    },
    () => {
      self.runtime.wait_for_user_input()
      false
    },
  ])
  // CondVar wakeups can win a simultaneous cancellation; honor cancellation
  // before recording success or making another model request.
  @async.pause()
  let reason = if completed { "job_completed" } else { "user_input" }
  let states = ids
    .map(id => {
      match jobs.snapshot(id) {
        Some(job) => {
          let status = match job.status {
            Running => "running"
            Exited(code) => "exit=\{code}"
            Stopped if job.killed_by_output_limit =>
              "stopped killed_at_output_cap=true"
            Stopped if job.killed_by_time_limit =>
              "stopped killed_at_time_cap=true"
            Stopped => "stopped"
          }
          "\{id} \{status}"
        }
        None => "\{id} unavailable"
      }
    })
    .join("\n")
  "job_wait reason=\{reason}\n\{states}\nRead output with job_output."
}
