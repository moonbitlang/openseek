///|
async fn AgentLoop::flush_usage_records(self : Self) -> Unit {
  while !self.pending_attempts.is_empty() {
    let record = self.pending_attempts[0]
    let next = (self.append_usage)(self.last_session, record)
    self.last_session = next
    self.pending_attempts.remove(0) |> ignore
  }
}

///|
fn AgentLoop::reserve_usage_call(self : Self) -> Int32 {
  let call = self.next_usage_call
  self.next_usage_call += 1
  call
}

///|
fn AgentLoop::queue_usage_record(
  self : Self,
  record : @agent_session.UsageRecord,
) -> Unit {
  self.pending_attempts.push(record)
  // Observation remains available even if its subsequent durable write fails.
  @emit.emit_usage(Json(record))
}
