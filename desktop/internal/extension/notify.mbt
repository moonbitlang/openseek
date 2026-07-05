// System notification when a run ends, so a user who switched to another
// app still learns the agent is done. Cancellation is user-initiated and
// stays quiet. A post that fails (platform without notifications, denied
// permission) is dropped silently — the transcript already tells the story.

///|
/// Notification banners get roughly two lines; anything longer is noise.
const NotificationBodyMaxChars : Int = 180

///|
fn notify_run_finished(payload : @engine.FinishedPayload) -> Unit {
  let title = match payload.status {
    "finished" => "Task finished"
    "cancelled" => return
    "max_steps_exhausted" => "Task stopped at the step limit"
    _ => "Task failed"
  }
  let body = if payload.answer is Some(answer) && !answer.trim().is_empty() {
    notification_snippet(answer)
  } else {
    "The conversation is ready for you."
  }
  // The run id rides on the notification: clicking it reveals the window
  // (native side) and the frontend jumps to the run's conversation via the
  // `proton.notification_clicked` event.
  ignore(
    @proton_native.post_notification(
      Some(title),
      body,
      payload=payload.run_id.to_string(),
    ),
  )
}

///|
fn notification_snippet(text : String) -> String {
  let out = StringBuilder()
  let mut count = 0
  for ch in text.trim() {
    if count >= NotificationBodyMaxChars {
      out.write_string("…")
      break
    }
    out.write_char(ch)
    count += 1
  }
  out.to_string()
}
