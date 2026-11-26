///|
async fn ApiState::deliver_actions_notice(
  self : ApiState,
  notice : @actions_monitor.Notice,
) -> Unit {
  let { session, url, head, outcome, } = notice
  let state = match outcome {
    Failed => "CI failed for"
    Passed => "Observed CI checks are green for"
  }
  let message = "SeekMoon PR monitor: \{state} \{url} at commit \{head}. Continue the PR work in this conversation using this result."
  self.deliver_session_input(session, message, @uuid.mint(), retry_dropped=true) catch {
    error => {
      if @xlog.warn() is Some(w) {
        w
        ..write_object_begin()
        ..write_object_field("event", "actions_monitor_delivery_failed")
        ..write_object_field("session", session)
        ..write_object_field("pr", url)
        ..write_object_field("head", head)
        ..write_object_field("error", "\{error}")
        .write_object_end()
      }
      self.publish(
        AgentEvent({
          run_id: None,
          session,
          event: SessionError(
            error="\{message} Automatic delivery failed: \{error}",
          ),
        }),
      )
    }
  }
}
