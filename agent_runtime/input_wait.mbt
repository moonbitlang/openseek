///|
/// Await nonblank user steering or command context without consuming it.
/// The loop remains the sole consumer of the lossless input queue. Notices
/// cannot win this wait: a job waiter separately selects its target jobs.
pub async fn AgentRuntime::wait_for_user_input(self : AgentRuntime) -> Unit {
  while !self.user_input_pending {
    self.user_input_changed.wait()
  }
}
