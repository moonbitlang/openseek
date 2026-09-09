///|
/// Plain text alone cannot disambiguate completion from waiting for a job.
/// Explicit finish is handled elsewhere and never calls this guard.
fn AgentLoop::background_finish_notice(self : AgentLoop) -> String? {
  guard self.tools.background_job_runtime() is Some(jobs) else { return None }
  let pending = jobs
    .pending()
    .filter(job => !self.jobs_before_turn.contains(job.id))
  guard !pending.is_empty() else { return None }
  let labels = pending
    .map(job => {
      "\{job.id}: \{@agent_tool.brief_line(job.description.unwrap_or(job.command), limit=100)}"
    })
    .join("\n")
  Some(
    "Background jobs still need a decision:\n\{labels}\nFirst consider useful work on the user's request that can proceed independently of these jobs, such as reviewing changes, investigating another issue, or preparing the next step. Keep doing that work in parallel while the jobs run. Call job_wait with job_ids only when further progress depends on their results and no useful independent work remains; it pauses this turn until a selected job finishes or user input arrives. If your work is complete, call finish. Stop unneeded jobs with job_stop.",
  )
}

///|
/// Only the selected jobs and user input can complete the wait. The losing
/// branch is cancelled by any(); it observes state and owns no process.
async fn AgentLoop::wait_for_jobs(
  self : AgentLoop,
  ids : Array[String],
) -> String {
  guard self.tools.background_job_runtime() is Some(jobs) else {
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
