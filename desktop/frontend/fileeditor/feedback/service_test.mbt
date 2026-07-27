///|
test "Desktop feedback backing connects host controls to the Viewer handle" {
  let service = @feedback.DesktopFeedbackService()
  let resource = @common.Uri::parse("file:///workspace/main.mbt")
  let added : Ref[String?] = Ref(None)
  let changes = Ref(0)
  service.on_did_add_feedback(event => added.val = Some(event.feedback.id))
  |> ignore
  let handle = service.agent_feedback_handle()
  handle.on_did_change_feedback(_event => changes.val += 1) |> ignore
  service.set_feedback_enabled(resource, true)
  assert_true(handle.is_feedback_enabled(resource))
  let item = handle.add_feedback(
    resource,
    @common.Range(2, 1, 2, 5),
    "rename this",
  )
  assert_eq(added.val, Some(item.id))
  assert_eq(handle.get_feedback(resource).length(), 1)
  assert_true(changes.val >= 2)
  service.clear_feedback(resource)
  assert_true(handle.get_feedback(resource).is_empty())
}

///|
test "Desktop feedback backing implements every stateful handle mutation" {
  let service = @feedback.DesktopFeedbackService()
  let resource = @common.Uri::parse("file:///workspace/lib.mbt")
  let handle = service.agent_feedback_handle()
  let item = handle.add_feedback(
    resource,
    @common.Range(4, 2, 4, 8),
    "draft",
    state=@agent_feedback_api.Created,
  )
  handle.accept_feedback(resource, item.id)
  handle.update_feedback(resource, item.id, "reworded")
  handle.add_reply(resource, item.id, "done")
  handle.mark_feedback_submitted(resource)
  let stored = handle.get_feedback(resource).get(0)
  assert_eq(stored.map(item => item.text), Some("reworded"))
  assert_eq(stored.map(item => item.replies), Some(["done"]))
  assert_eq(stored.map(item => item.state), Some(@agent_feedback_api.Submitted))
  let navigation_id = "agentFeedback:" + item.id
  handle.set_navigation_anchor(resource, Some(navigation_id))
  let bearing = handle.get_navigation_bearing(resource, [navigation_id])
  assert_eq(bearing.active_idx, 0)
  assert_eq(bearing.total_count, 1)
  handle.remove_feedback(resource, item.id)
  assert_true(handle.get_feedback(resource).is_empty())
}
