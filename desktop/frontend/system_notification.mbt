// System notifications are a frontend-owned Proton extension operation.
// Keeping the operation in a Rabbita command leaves `update` pure and also
// makes browser pages harmless: they never expose the notification namespace.

///|
/// Notification banners get roughly two lines; anything longer is noise.
const NotificationBodyMaxChars : Int = 180

///|
priv struct FinishedSystemNotification {
  run_id : String
  status : String
  answer : String?
}

///|
/// One live permission question shown by the local desktop host. Recovered
/// pending approvals never construct this value, so reconnecting does not
/// replay an old system notification.
priv struct ApprovalSystemNotification {
  run_id : String
  tool_name : String
  detail : String
}

///|
/// Keep a Unicode character boundary while fitting a system banner.
fn truncate_notification_body(body : String) -> String {
  let out = StringBuilder()
  let mut count = 0
  for ch in body.trim() {
    if count >= NotificationBodyMaxChars {
      out.write_string("…")
      break
    }
    out.write_char(ch)
    count += 1
  }
  out.to_string()
}

///|
/// Cancellation is user-initiated and stays quiet. Other terminal statuses
/// preserve the titles used by the former direct native notification path.
fn FinishedSystemNotification::title(
  self : FinishedSystemNotification,
) -> String? {
  match self.status {
    "finished" => Some("Task finished")
    "cancelled" => None
    "max_steps_exhausted" => Some("Task stopped at the step limit")
    _ => Some("Task failed")
  }
}

///|
/// Use the final answer when present and keep the existing fallback otherwise.
fn FinishedSystemNotification::body(
  self : FinishedSystemNotification,
) -> String {
  guard self.answer is Some(answer) && !answer.is_blank() else {
    return "The conversation is ready for you."
  }
  truncate_notification_body(answer)
}

///|
/// Post one notification through `__MoonBit__.notification.show`.
/// A missing extension, denied permission, or rejected promise is deliberately
/// silent because the transcript remains the authoritative result.
fn show_system_notification(
  title : String,
  body : String,
  run_id : String,
) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    guard @interop.moonbit_bridge_root() is Some(root) &&
      @interop.js_prop(root, "notification") is Some(notification) &&
      @interop.js_prop(notification, "show") is Some(_) else {
      return
    }
    let payload = @js.Object::new()
    payload["title"] = title
    payload["body"] = body
    payload["payload"] = run_id
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
/// The application badge is the number of local conversations that still need
/// attention: either a permission decision or a background result the user has
/// not opened. It is derived from replicated conversation state rather than
/// incremented by events, so replay and reconnect converge to one value.
fn Model::notification_badge_count(self : Model) -> Int {
  self.conversations.count_if(conv => {
    conv.device is Local &&
    (
      conv.pending_approval is Some({ answered: false, .. }) ||
      conv.unseen_finish
    )
  })
}

///|
/// Set the absolute native application badge count. Ordinary browsers do not
/// expose the notification extension; unsupported platforms and rejected
/// commands stay silent because the conversation cards remain authoritative.
fn set_notification_badge_count(count : Int) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    guard @interop.moonbit_bridge_root() is Some(root) &&
      @interop.js_prop(root, "notification") is Some(notification) &&
      @interop.js_prop(notification, "setBadge") is Some(_) else {
      return
    }
    let payload = @js.Object::new()
    payload["count"] = count
    @js.async_run(() => {
      let _ : @js.Value = @interop.js_method_promise(
        notification,
        "setBadge",
        payload.to_value(),
      ).wait() catch {
        _ => return
      }
    })
  })
}

///|
/// Synchronize only transitions. `Init` clears any process-external badge
/// left by an unclean shutdown before the first host snapshot restores the
/// current absolute count.
fn notification_badge_command(
  previous : Model,
  next : Model,
  initialize : Bool,
) -> @cmd.Cmd {
  let previous_count = previous.notification_badge_count()
  let next_count = next.notification_badge_count()
  if initialize || previous_count != next_count {
    set_notification_badge_count(next_count)
  } else {
    @cmd.none
  }
}

///|
fn FinishedSystemNotification::command(
  self : FinishedSystemNotification,
) -> @cmd.Cmd {
  guard self.title() is Some(title) else { return @cmd.none }
  show_system_notification(title, self.body(), self.run_id)
}

///|
fn ApprovalSystemNotification::title(
  _self : ApprovalSystemNotification,
) -> String {
  "Permission required"
}

///|
fn ApprovalSystemNotification::body(
  self : ApprovalSystemNotification,
) -> String {
  truncate_notification_body(
    "\{self.tool_name} is asking permission to \{self.detail}",
  )
}

///|
fn ApprovalSystemNotification::command(
  self : ApprovalSystemNotification,
) -> @cmd.Cmd {
  show_system_notification(self.title(), self.body(), self.run_id)
}

///|
/// Select only live approval events from the embedded local desktop. Remote
/// pages cannot post Proton notifications, and approval recovery does not pass
/// through the live engine-event arm that calls this function.
fn approval_system_notification(
  channel : @interop.ChannelId,
  run_id : String?,
  event : @transcript.EngineEvent,
) -> ApprovalSystemNotification? {
  guard channel is Local else { return None }
  guard run_id is Some(run_id) else { return None }
  match event {
    ApprovalRequested(tool_name~, detail~, ..) =>
      Some({ run_id, tool_name, detail, })
    _ => None
  }
}

///|
test "finished system notifications preserve status titles and fallback body" {
  let completed = FinishedSystemNotification::{
    run_id: "r1",
    status: "finished",
    answer: None,
  }
  assert_eq(completed.title(), Some("Task finished"))
  assert_eq(completed.body(), "The conversation is ready for you.")
  let cancelled = { ..completed, status: "cancelled", }
  assert_eq(cancelled.title(), None)
}

///|
test "only live local approval events create system notifications" {
  let event = @transcript.ApprovalRequested(
    id="ap-1",
    tool_name="mbtx",
    detail="run this snippet with no sandbox policy",
    body=None,
  )
  guard approval_system_notification(Local, Some("r1"), event)
    is Some(notification) else {
    fail("expected a local approval notification")
  }
  assert_eq(notification.title(), "Permission required")
  assert_eq(
    notification.body(),
    "mbtx is asking permission to run this snippet with no sandbox policy",
  )
  assert_true(
    approval_system_notification(Remote("device-1"), Some("r1"), event) is None,
  )
  assert_true(approval_system_notification(Local, None, event) is None)
  assert_true(
    approval_system_notification(
      Local,
      Some("r1"),
      @transcript.ApprovalResolved(id="ap-1"),
    )
    is None,
  )
}
