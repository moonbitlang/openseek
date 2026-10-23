///|
/// The OpenSeek composer's Approve for me switch, read off the root's
/// projection.
fn approval_toggle(model : Model) -> @composer.ApprovalToggle? {
  for status in model.composer_input().presentation.status {
    if status is ApprovalStatus(toggle) {
      return Some(toggle)
    }
  }
  None
}

///|
fn toggle_approval(model : Model) -> Model {
  let (_, next) = update(
    test_dispatch(),
    ComposerAction(
      ApprovalModeToggled(identity=model.composer_input().identity),
    ),
    model,
  )
  next
}

///|
test "an OpenSeek conversation asks until Approve for me is switched on" {
  let model = test_model()
  assert_true(approval_toggle(model) is Some({ on: false, enabled: true, }))
  let conv = model.active()
  assert_true(model.approval_for(conv.device, conv.session_id) is ApprovalAsk)
}

///|
test "Approve for me is remembered for that conversation only" {
  let model = test_model()
  let conv = model.active()
  let on = toggle_approval(model)
  assert_true(approval_toggle(on) is Some({ on: true, enabled: true, }))
  assert_true(on.approval_for(conv.device, conv.session_id) is ApprovalReview)
  // Another conversation is untouched: the reviewer is never inherited.
  assert_true(on.approval_for(conv.device, "another-session") is ApprovalAsk)
  // Switching it off forgets it.
  let off = toggle_approval(on)
  assert_true(approval_toggle(off) is Some({ on: false, enabled: true, }))
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
/// A running turn keeps the policy its engine started with, so the switch is
/// locked until the turn ends rather than showing a mode not in effect.
test "Approve for me is locked while a turn runs" {
  let model = test_model().replace_conversation(running_conversation())
  assert_true(approval_toggle(model) is Some({ on: false, enabled: false, }))
  let conv = model.active()
  let clicked = toggle_approval(model)
  assert_true(clicked.approval_for(conv.device, conv.session_id) is ApprovalAsk)
}
