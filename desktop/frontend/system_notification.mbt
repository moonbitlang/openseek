// System notifications are a frontend-owned Proton extension operation.
// Keeping the operation in a Rabbita command leaves `update` pure and also
// makes browser pages harmless: they never expose the notification namespace.

///|
/// Notification banners get roughly two lines; anything longer is noise.
const NotificationBodyMaxChars : Int32 = 180

///|
priv struct FinishedSystemNotification {
  payload : String
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
  locale~ : @i18n.Locale = English,
  self : FinishedSystemNotification,
) -> String? {
  match self.status {
    "finished" =>
      Some(
        match locale {
          SimplifiedChinese => "任务已完成"
          TraditionalChinese => "任務已完成"
          Japanese => "タスクが完了しました"
          English => "Task finished"
          Spanish => "Tarea finalizada"
        },
      )
    "cancelled" => None
    "max_steps_exhausted" =>
      Some(
        match locale {
          SimplifiedChinese => "任务达到步数上限，已停止"
          TraditionalChinese => "任務達到步數上限，已停止"
          Japanese =>
            "ステップ数の上限に達したためタスクを停止しました"
          English => "Task stopped at the step limit"
          Spanish => "La tarea se detuvo al alcanzar el límite de pasos"
        },
      )
    _ =>
      Some(
        match locale {
          SimplifiedChinese => "任务失败"
          TraditionalChinese => "任務失敗"
          Japanese => "タスクが失敗しました"
          English => "Task failed"
          Spanish => "La tarea falló"
        },
      )
  }
}

///|
/// Use the final answer when present and keep the existing fallback otherwise.
fn FinishedSystemNotification::body(
  locale~ : @i18n.Locale = English,
  self : FinishedSystemNotification,
) -> String {
  guard self.answer is Some(answer) && !answer.is_blank() else {
    return match locale {
      SimplifiedChinese => "对话已就绪，请查看。"
      TraditionalChinese => "對話已就緒，請檢視。"
      Japanese =>
        "チャットの準備ができました。ご確認ください。"
      English => "The conversation is ready for you."
      Spanish => "La conversación está lista para ti."
    }
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
  target : String,
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
    payload["payload"] = target
    @js.Promise::from_async(() => {
      let _ : @js.Value = @interop.js_method_promise(
        notification,
        "show",
        payload.to_value(),
      ).wait() catch {
        _ => return
      }
    })
    |> ignore
  })
}

///|
/// The application badge is the number of conversations that still need
/// attention: either a permission decision or a background result the user has
/// not opened. It is derived from replicated conversation state rather than
/// incremented by events, so replay and reconnect converge to one value.
fn Model::notification_badge_count(self : Model) -> Int32 {
  let local_count = self.conversations.count_if(conv => {
    conv.device is Local &&
    (
      conv.pending_approval is Some({ answered: false, .. }) ||
      conv.unseen_finish
    )
  })
  local_count +
  self.cloud.conversations
  .iter()
  .count_if(entry => {
    let (id, conversation) = entry
    conversation.unseen_finish &&
    !self.cloud.is_archived(id) &&
    self.account is Some(account) &&
    self.cloud.user_id == Some(account.user.user_id)
  })
}

///|
/// Set the absolute native application badge count. Ordinary browsers do not
/// expose the notification extension; unsupported platforms and rejected
/// commands stay silent because the conversation cards remain authoritative.
fn set_notification_badge_count(count : Int32) -> @cmd.Cmd {
  @cmd.custom_cmd(_scheduler => {
    guard @interop.moonbit_bridge_root() is Some(root) &&
      @interop.js_prop(root, "notification") is Some(notification) &&
      @interop.js_prop(notification, "setBadge") is Some(_) else {
      return
    }
    let payload = @js.Object::new()
    payload["count"] = count
    @js.Promise::from_async(() => {
      let _ : @js.Value = @interop.js_method_promise(
        notification,
        "setBadge",
        payload.to_value(),
      ).wait() catch {
        _ => return
      }
    })
    |> ignore
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
  locale~ : @i18n.Locale = English,
  self : FinishedSystemNotification,
) -> @cmd.Cmd {
  guard self.title(locale~) is Some(title) else { return @cmd.none }
  show_system_notification(title, self.body(locale~), self.payload)
}

///|
/// Adapt only a newly accepted live terminal event. History and control
/// snapshots do not replay notifications, and duplicates cannot mark a read
/// conversation unread again.
fn cloud_finished_notification(
  previous : @cloud.State,
  next : @cloud.State,
  message : @cloud.Msg,
) -> (String, FinishedSystemNotification)? {
  let (id, event) = match message {
    @cloud.WatchEvent(_, id, _, @cloud.EngineEvent(event))
    | @cloud.StreamEvent(_, id, _, event) => (id, event)
    _ => return None
  }
  guard event.kind == "task_finished" &&
    previous.user_id == next.user_id &&
    next.user_id is Some(account) &&
    previous.conversations.get(id) is Some(before) &&
    next.conversations.get(id) is Some(after) &&
    after.events.contains(event) &&
    !before.events.contains(event) &&
    before.last_finished_task != Some(event.task_id) else {
    return None
  }
  let status = match cloud_record_status(Ready, event.kind, event.data) {
    Finished(Completed) => "finished"
    Finished(Aborted) => "cancelled"
    Finished(MaxStepsExhausted) => "max_steps_exhausted"
    Finished(ContextYield) => "context_yield"
    _ => "failed"
  }
  let mut answer = None
  for item in after.records {
    if item.task_id == event.task_id &&
      item.kind == "assistant_message" &&
      item.data is { "content": String(text), .. } {
      answer = Some(text)
    }
  }
  if after.notification_answer is Some(text) {
    answer = Some(text)
  }
  if event.data
    is { "result": { "output": { "answer": String(text), .. }, .. }, .. } {
    answer = Some(text)
  }
  let owner : @interop.ConversationIdentity = Cloud(account~, session=id)
  Some((id, { payload: owner.key(), status, answer, }))
}

///|
fn ApprovalSystemNotification::title(
  locale~ : @i18n.Locale = English,
  _self : ApprovalSystemNotification,
) -> String {
  match locale {
    SimplifiedChinese => "需要授权"
    TraditionalChinese => "需要授權"
    Japanese => "許可が必要です"
    English => "Permission required"
    Spanish => "Se requiere permiso"
  }
}

///|
fn ApprovalSystemNotification::body(
  locale~ : @i18n.Locale = English,
  self : ApprovalSystemNotification,
) -> String {
  truncate_notification_body(
    match locale {
      SimplifiedChinese => "\{self.tool_name} 请求授权：\{self.detail}"
      TraditionalChinese => "\{self.tool_name} 請求授權：\{self.detail}"
      Japanese =>
        "\{self.tool_name} が許可を要求しています：\{self.detail}"
      English => "\{self.tool_name} is asking permission to \{self.detail}"
      Spanish => "\{self.tool_name} solicita permiso para \{self.detail}"
    },
  )
}

///|
fn ApprovalSystemNotification::command(
  locale~ : @i18n.Locale = English,
  self : ApprovalSystemNotification,
) -> @cmd.Cmd {
  show_system_notification(self.title(locale~), self.body(locale~), self.run_id)
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
    payload: "r1",
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
