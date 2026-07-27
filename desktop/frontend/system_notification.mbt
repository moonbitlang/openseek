// System notifications are a frontend-owned Proton extension operation.
// Keeping the operation in a Rabbita command leaves `update` pure.

///|
/// Notification banners get roughly two lines; anything longer is noise.
const NotificationBodyMaxChars : Int = 180

///|
/// Cancellation is user-initiated and stays quiet. Other terminal statuses
/// preserve the titles used by the former direct native notification path.
fn RunOutcome::notification_title(self : RunOutcome) -> String? {
  match self {
    Completed => Some("Task finished")
    Cancelled => None
    MaxStepsExhausted => Some("Task stopped at the step limit")
    _ => Some("Task failed")
  }
}

///|
/// Post one terminal notification through `__MoonBit__.notification.show`.
/// A missing extension, denied permission, or rejected promise is deliberately
/// silent because the transcript remains the authoritative result.
fn notify_run_finished(
  run_id : Int,
  outcome : RunOutcome,
  answer : String?,
) -> @cmd.Cmd {
  guard outcome.notification_title() is Some(title) else { return @cmd.none }
  // Keep a Unicode character boundary while fitting the system banner.
  let body = if answer is Some(answer) && !answer.trim().is_empty() {
    let out = StringBuilder()
    let mut count = 0
    for ch in answer.trim() {
      if count >= NotificationBodyMaxChars {
        out.write_string("…")
        break
      }
      out.write_char(ch)
      count += 1
    }
    out.to_string()
  } else {
    "The conversation is ready for you."
  }
  @cmd.custom_cmd(_scheduler => {
    guard @interop.moonbit_bridge_root() is Some(root) &&
      @interop.js_prop(root, "notification") is Some(notification) &&
      @interop.js_prop(notification, "show") is Some(_) else {
      return
    }
    let payload = @js.Object::new()
    payload["title"] = title
    payload["body"] = body
    payload["payload"] = run_id.to_string()
    @js.async_run(() => {
      let _ : @js.Value = @interop.js_method_promise(
        notification,
        "show",
        payload.to_value(),
      ).wait() catch {
        _ => return
      }
    })
  })
}

///|
test "system notifications preserve terminal status titles" {
  assert_eq(Completed.notification_title(), Some("Task finished"))
  assert_eq(Cancelled.notification_title(), None)
  assert_eq(
    MaxStepsExhausted.notification_title(),
    Some("Task stopped at the step limit"),
  )
  assert_eq(RunOutcome::RunFailed.notification_title(), Some("Task failed"))
}
