///|
/// Cloud readiness belongs to the account and conversation, independently of
/// the selected computer's bridge and local provider configuration.
fn Model::cloud_display_status(self : Model) -> Status? {
  guard self.account is Some(account) &&
    self.cloud.user_id == Some(account.user.user_id) else {
    return None
  }
  if self.cloud.needs_sign_in {
    return Some(Errored)
  }
  if self.cloud_draft_identity() is Some(_) {
    return Some(
      if self.cloud.notice is Some(_) {
        Errored
      } else if self.cloud.creation is Some({ submission: Some(_), .. }) {
        Starting
      } else {
        Ready
      },
    )
  }
  guard self.cloud_identity() is Some(_) else { return None }
  guard self.cloud_conversation() is Some(conversation) else {
    return Some(Loading)
  }
  if conversation.notice is Some(_) {
    return Some(Errored)
  }
  if conversation.loading {
    return Some(Loading)
  }
  if self.cloud_archived() {
    return Some(ReadOnly)
  }
  if conversation.generating {
    return Some(
      match conversation.heartbeat {
        Some({ stage: @composer.AtStep(step), .. }) => Step(Some(step))
        _ => Running
      },
    )
  }
  if conversation.sending && conversation.pending is Some(_) {
    return Some(Starting)
  }
  let status = cloud_recorded_status(conversation)
  Some(
    if status is Ready && conversation.history_required && !conversation.sending {
      Loading
    } else {
      status
    },
  )
}

///|
fn cloud_recorded_status(conversation : @cloud.Conversation) -> Status {
  let mut status : Status = Ready
  for record in conversation.records {
    status = cloud_record_status(status, record.kind, record.data)
  }
  for event in conversation.events {
    status = cloud_record_status(status, event.kind, event.data)
  }
  status
}

///|
/// A task's outer status describes orchestration; its existing result carries
/// the engine outcome, including a successful checkpoint rather than completion.
fn cloud_record_status(previous : Status, kind : String, data : Json) -> Status {
  match kind {
    "user" | "task_started" => Ready
    "task_finished" => {
      if data
        is {
          "status": "failed",
          "result": { "status": "ok" | "completed", .. },
          ..
        } {
        return Failed
      }
      let status = match data {
        { "result": { "status": String(status), .. }, .. } => status
        { "status": String(status), .. } => status
        _ => return Errored
      }
      match status {
        "ok" | "completed" => Finished(Completed)
        "failed" => Failed
        "interrupted" => Finished(Aborted)
        other => Finished(RunOutcome::parse(other))
      }
    }
    _ => previous
  }
}
