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
test "Cloud conversations show the approval picker in the session's mode" {
  let model = integrated_cloud_model()
  assert_true(
    approval_select(model)
    is Some({ mode: ApprovalAsk, open: false, enabled: true, }),
  )
  let identity = model.composer_input().identity
  let opened = approval_action(model, ApprovalMenuToggled(identity~))
  assert_true(approval_select(opened) is Some({ open: true, .. }))
  let dismissed = approval_action(opened, SelectMenuDismissed(identity~))
  assert_true(approval_select(dismissed) is Some({ open: false, .. }))
  let reviewing = {
    ..model,
    cloud: {
      ..model.cloud,
      sessions: model.cloud.sessions.map(item => {
        ..item,
        approval: ApprovalReview,
      }),
    },
  }
  assert_true(approval_select(reviewing) is Some({ mode: ApprovalReview, .. }))
}

///|
test "choosing a Cloud approval mode saves it to the session and holds the picker" {
  let model = integrated_cloud_model()
  let saving = choose_approval(model, ApprovalReview)
  assert_true(
    saving.cloud.metadata_saves.get("cloud-a")
    is Some({ edit: SetApproval(ApprovalReview), .. }),
  )
  assert_true(
    approval_select(saving)
    is Some({ mode: ApprovalAsk, open: false, enabled: false, }),
  )
  // The save holds the next turn: its engine starts in the saved mode.
  assert_true(
    saving.composer_input().presentation.primary_action
    is @composer.Send(available=false),
  )
  let request = saving.cloud.metadata_saves["cloud-a"].request
  let (_, saved) = update(
    test_dispatch(),
    CloudAction(@cloud.Edited(saving.cloud.epoch, "cloud-a", request)),
    saving,
  )
  assert_true(
    approval_select(saved)
    is Some({ mode: ApprovalReview, open: false, enabled: true, }),
  )
  assert_true(
    saved.composer_input().presentation.primary_action
    is @composer.Send(available=true),
  )
}

///|
test "a running Cloud turn locks the approval picker and closes it" {
  let model = integrated_cloud_model()
  let identity = model.composer_input().identity
  let opened = approval_action(model, ApprovalMenuToggled(identity~))
  assert_true(opened.select_menu is Some(OpenSeekApprovalMenu))
  // Sending starts the turn whose engine holds the current mode.
  let sending = approval_action(
    opened,
    DraftSubmitted(identity~, draft={ task: "Go", mentions: [], images: [], }),
  )
  assert_true(sending.select_menu is None)
  assert_true(
    approval_select(sending) is Some({ open: false, enabled: false, .. }),
  )
  let running = model.with_cloud_control(task=Some("task"), approval=null)
  assert_true(
    approval_select(running) is Some({ open: false, enabled: false, .. }),
  )
  let toggled = approval_action(running, ApprovalMenuToggled(identity~))
  assert_true(toggled.select_menu is None)
  let selected = approval_action(
    running,
    ApprovalSelected(identity~, mode=ApprovalReview),
  )
  assert_true(selected.cloud.metadata_saves.is_empty())
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
        },
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
