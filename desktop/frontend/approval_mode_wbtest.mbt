///|
/// The OpenSeek composer's approval mode menu, read off the root's
/// projection.
fn approval_select(model : Model) -> @composer.ApprovalSelect? {
  for status in model.composer_input().presentation.status {
    if status is ApprovalStatus(select) {
      return Some(select)
    }
  }
  None
}

///|
fn approval_action(model : Model, action : @composer.Action) -> Model {
  let (_, next) = update(test_dispatch(), ComposerAction(action), model)
  next
}

///|
fn choose_approval(model : Model, mode : @protocol.OpenSeekApproval) -> Model {
  let identity = model.composer_input().identity
  let opened = approval_action(model, ApprovalMenuToggled(identity~))
  approval_action(opened, ApprovalSelected(identity~, mode~))
}

///|
test "an OpenSeek conversation asks until auto-review is chosen" {
  let model = test_model()
  assert_true(
    approval_select(model)
    is Some({ mode: ApprovalAsk, open: false, enabled: true, }),
  )
  let conv = model.active()
  assert_true(model.approval_for(conv.device, conv.session_id) is ApprovalAsk)
}

///|
test "the approval menu opens and closes from the composer" {
  let model = test_model()
  let identity = model.composer_input().identity
  let opened = approval_action(model, ApprovalMenuToggled(identity~))
  assert_true(approval_select(opened) is Some({ open: true, .. }))
  let dismissed = approval_action(opened, SelectMenuDismissed(identity~))
  assert_true(approval_select(dismissed) is Some({ open: false, .. }))
}

///|
test "auto-review is remembered for that conversation only" {
  let model = test_model()
  let conv = model.active()
  let on = choose_approval(model, ApprovalReview)
  assert_true(
    approval_select(on)
    is Some({ mode: ApprovalReview, open: false, enabled: true, }),
  )
  assert_true(on.approval_for(conv.device, conv.session_id) is ApprovalReview)
  // Another conversation is untouched: the reviewer is never inherited.
  assert_true(on.approval_for(conv.device, "another-session") is ApprovalAsk)
  // Choosing to answer again forgets it.
  let off = choose_approval(on, ApprovalAsk)
  assert_true(approval_select(off) is Some({ mode: ApprovalAsk, .. }))
  assert_true(off.reviewed_conversations.is_empty())
}

///|
test "the reviewed list keeps the newest choices within the cap" {
  let keys : Array[String] = [
    for index in 0..<(ConversationModelsLimit + 5) => "local/s\{index}"
  ]
  let folded = keys.fold(init=[], (acc, key) => {
    approvals_with(acc, key, ApprovalReview)
  })
  assert_eq(folded.length(), ConversationModelsLimit)
  assert_eq(folded[0], "local/s\{ConversationModelsLimit + 4}")
  assert_eq(parse_conversation_approvals(Json(folded).stringify()), folded)
  assert_eq(parse_conversation_approvals("not json"), [])
}

///|
/// A running turn keeps the policy its engine started with, so the menu is
/// locked until the turn ends rather than showing a mode not in effect.
test "the approval mode is locked while a turn runs" {
  let model = test_model().replace_conversation(running_conversation())
  assert_true(
    approval_select(model)
    is Some({ mode: ApprovalAsk, open: false, enabled: false, }),
  )
  let conv = model.active()
  let identity = model.composer_input().identity
  let toggled = approval_action(model, ApprovalMenuToggled(identity~))
  assert_true(toggled.select_menu is None)
  let chosen = approval_action(
    model,
    ApprovalSelected(identity~, mode=ApprovalReview),
  )
  assert_true(chosen.approval_for(conv.device, conv.session_id) is ApprovalAsk)
}
