// Behavior tests for the trimmed agent-feedback service
// (`agent_feedback_service.mbt`). Upstream's `agentFeedbackService.test.ts`
// leans on the sessions/chat stack; these cover the store role directly:
// the item lifecycle and its events, the anchor-clearing remove rule, the
// submit transition and counts, and prev/next navigation with wrap-around.
// The `uri` and `feedback_at` helpers are shared with
// `editor_comments_wbtest.mbt` (same wbtest package).

///|
fn uri(value : String) -> @base_common.Uri {
  try! @base_common.Uri::parse(value)
}

///|
fn feedback_at(
  id : String,
  resource : @base_common.Uri,
  line : Int,
  text? : String = "note",
  kind? : @agent_feedback_api.AgentFeedbackKind = UserReview,
  replies? : Array[String] = [],
  state? : @agent_feedback_api.AgentFeedbackState = Accepted,
) -> @agent_feedback_api.AgentFeedback {
  {
    id,
    text,
    resource,
    range: Range(line, 1, line, 1),
    selected_text: None,
    kind,
    replies,
    state,
  }
}

///|
test "remove_feedback drops the item and a navigation anchor pointing at it" {
  let service = AgentFeedbackService()
  let resource = uri("memory://session/a.mbt")
  let item = service.add_feedback(resource, Range(4, 1, 4, 8), "typo")
  let keep = service.add_feedback(resource, Range(9, 1, 9, 8), "keep")
  service.set_navigation_anchor(
    resource,
    Some(to_session_editor_comment_id(item.id)),
  )
  service.remove_feedback(resource, item.id)
  assert_eq(service.get_feedback(resource).map(i => i.id).join(","), keep.id)
  let bearing = service.get_navigation_bearing(resource, [
    to_session_editor_comment_id(item.id),
    to_session_editor_comment_id(keep.id),
  ])
  assert_eq(bearing.active_idx, -1)
  // Removing the last item empties the store for the resource.
  service.remove_feedback(resource, keep.id)
  assert_eq(service.get_feedback(resource).length(), 0)
}

///|
test "mark_feedback_submitted transitions accepted items and reports counts" {
  let service = AgentFeedbackService()
  let resource = uri("memory://session/a.mbt")
  let mut submitted_ids = ""
  let mut user_count = -1
  let mut agent_review_count = -1
  let mut reply_count = -1
  service.on_did_submit_feedback(event => {
    submitted_ids = event.items.map(item => item.id).join(",")
    user_count = event.user_count
    agent_review_count = event.agent_review_count
    reply_count = event.reply_count
  })
  |> ignore
  // Nothing accepted yet: no event.
  service.mark_feedback_submitted(resource)
  assert_eq(user_count, -1)
  let user_item = service.add_feedback(resource, Range(1, 1, 1, 1), "a")
  service.add_reply(resource, user_item.id, "more")
  let agent_item = service.add_feedback(
    resource,
    Range(5, 1, 5, 1),
    "b",
    kind=AgentReview,
  )
  let pending = service.add_feedback(
    resource,
    Range(9, 1, 9, 1),
    "c",
    state=Created,
  )
  service.mark_feedback_submitted(resource)
  assert_eq(submitted_ids, "\{user_item.id},\{agent_item.id}")
  assert_eq(user_count, 1)
  assert_eq(agent_review_count, 1)
  assert_eq(reply_count, 1)
  let states = service.get_feedback(resource).map(item => item.state)
  debug_inspect(states, content="[Submitted, Submitted, Created]")
  assert_eq(service.get_feedback(resource)[2].id, pending.id)
}

///|
test "agent_feedback_handle preserves defaults and selected text through lifecycle" {
  let service = AgentFeedbackService()
  let resource = uri("memory://session/handle.mbt")
  let handle = service.agent_feedback_handle()
  let mut change_count = 0
  let subscription = handle.on_did_change_feedback(_ => change_count += 1)
  let submitted_selections : Array[String?] = []
  let submitted_subscription = service.on_did_submit_feedback(event => {
    for item in event.items {
      submitted_selections.push(item.selected_text)
    }
  })
  service.set_feedback_enabled(resource, true)
  assert_true(handle.is_feedback_enabled(resource))
  let defaulted = handle.add_feedback(resource, Range(1, 1, 1, 3), "defaulted")
  assert_eq(defaulted.kind, UserReview)
  assert_eq(defaulted.state, Accepted)
  assert_eq(defaulted.selected_text, None)
  let explicit = handle.add_feedback(
    resource,
    Range(3, 1, 3, 3),
    "explicit",
    kind=AgentReview,
    state=Created,
    selected_text="  selected words\nnext line  ",
  )
  assert_eq(explicit.kind, AgentReview)
  assert_eq(explicit.state, Created)
  assert_eq(handle.get_feedback(resource).length(), 2)
  assert_eq(explicit.selected_text, Some("  selected words\nnext line  "))
  let image = handle.add_feedback(
    resource,
    Range(5, 1, 5, 20),
    "image",
    selected_text="",
  )
  handle.accept_feedback(resource, explicit.id)
  handle.update_feedback(resource, explicit.id, "updated")
  handle.add_reply(resource, explicit.id, "reply")
  let updated = handle.get_feedback(resource)[1]
  assert_eq(updated.text, "updated")
  assert_eq(updated.replies, ["reply"])
  assert_eq(updated.selected_text, explicit.selected_text)
  handle.set_navigation_anchor(resource, Some(explicit.id))
  assert_eq(
    handle.get_navigation_bearing(resource, [defaulted.id, explicit.id]),
    { active_idx: 1, total_count: 2, },
  )
  handle.mark_feedback_submitted(resource)
  assert_eq(submitted_selections, [None, explicit.selected_text, Some("")])
  assert_eq(handle.get_feedback(resource)[2].selected_text, image.selected_text)
  handle.remove_feedback(resource, defaulted.id)
  assert_true(change_count >= 7)
  subscription.dispose()
  submitted_subscription.dispose()
  service.dispose()
}
