///|
/// Hold the integrated Cloud conversation at a canonical control state, as
/// the session's event stream publishes it.
fn Model::with_cloud_control(
  self : Model,
  task~ : String?,
  approval~ : Json,
) -> Model {
  let control : @cloud.ControlState = @json.from_json({
    "active_task_id": match task {
      Some(task) => Json(task)
      None => null
    },
    "status": if task is Some(_) {
      "running"
    } else {
      "idle"
    },
    "paused": false,
    "queue": [],
    "steers": [],
    "approval": approval,
  }) catch {
    error => abort("invalid control fixture: \{error}")
  }
  let conversations = self.cloud.conversations.copy()
  conversations["cloud-a"] = {
    ..conversations["cloud-a"],
    control: Some(control),
    task,
    generating: task is Some(_),
  }
  { ..self, cloud: { ..self.cloud, conversations, }, }
}

///|
let cloud_approval_question : Json = {
  "id": "approval-1",
  "tool_name": "shell",
  "detail": "run make clean",
  "body": null,
}

///|
test "a Cloud approval question asks for attention until it is answered" {
  let model = integrated_cloud_model().with_cloud_control(
    task=Some("task"),
    approval=null,
  )
  let before = model.notification_badge_count()
  let asked = model.with_cloud_control(
    task=Some("task"),
    approval=cloud_approval_question,
  )
  assert_true(
    asked.composer_input().presentation.context
    is [
      @composer.ApprovalRequest(
        {
          tool_name: "shell",
          detail: "run make clean",
          target_label: None,
          answered: false,
          ..
        }
      ),
      ..,
    ],
  )
  assert_eq(asked.notification_badge_count(), before + 1)
  let needs_input = @conversation.RunMark::for_task(
    running=true,
    needs_input=true,
    unseen_outcome=None,
  )
  assert_eq(asked.cloud_chat_rows()[0].1.run_mark, needs_input)
  guard cloud_approval_notifications(model.cloud, asked.cloud) is [notification] else {
    fail("expected one approval notification")
  }
  assert_eq(
    notification.payload,
    @interop.Cloud(account="fixture-user", session="cloud-a").key(),
  )
  assert_eq(notification.body(), "shell is asking permission to run make clean")
  // An unchanged question does not notify again.
  assert_true(cloud_approval_notifications(asked.cloud, asked.cloud).is_empty())
  // Answering is the cloud package's control operation; once this client
  // answered, the card stays answered and no longer asks for attention.
  let conversations = asked.cloud.conversations.copy()
  conversations["cloud-a"] = {
    ..conversations["cloud-a"],
    approval_answered: Some("approval-1"),
  }
  let answered = { ..asked, cloud: { ..asked.cloud, conversations, }, }
  assert_true(
    answered.composer_input().presentation.context
    is [@composer.ApprovalRequest({ answered: true, .. }), ..],
  )
  assert_eq(answered.notification_badge_count(), before)
  assert_eq(
    answered.cloud_chat_rows()[0].1.run_mark,
    @conversation.RunMark::for_task(
      running=true,
      needs_input=false,
      unseen_outcome=None,
    ),
  )
}
