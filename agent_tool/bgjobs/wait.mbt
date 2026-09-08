///|
/// Jobs still executing or whose completion has not yet been published.
/// Including the latter closes the exit/notice gap in a turn's finish check.
pub fn BgJobRuntime::pending(self : BgJobRuntime) -> Array[BgJobSnapshot] {
  [
    for _, job in self.jobs if !job.completion_published => job.to_snapshot()
  ]
}

///|
/// Wait for any selected job to settle, including its completion notice.
/// Validate every id first; cancellation only removes the waiter, never stops
/// the executions. Predicate-check + CondVar::wait has no intervening yield.
pub async fn BgJobRuntime::wait_any(
  self : BgJobRuntime,
  ids : Array[String],
) -> Unit {
  guard !ids.is_empty() else { fail("job_wait requires at least one job id") }
  for id in ids {
    guard self.jobs.contains(id) else {
      fail("no background job with id \{id}")
    }
  }
  while !ids.any(id => {
          self.jobs.get(id) is Some(job) && job.completion_published
        }) {
    self.settled.wait()
  }
}
