// Whitebox tests for the package's internal wire helpers: accessors no other
// package calls, but whose contract this package's transport boundary depends
// on. They moved here from `desktop_transport_test.mbt` when the accessor
// stopped being exported.

///|
test "a notification's kind is its payload-free identity" {
  let notification = Notification::SessionShareProgress({
    generation: 7,
    progress: Uploading(attempt=2),
  })
  assert_eq(notification.kind(), SessionShareProgress)
  assert_true(NotificationKind::all().contains(notification.kind()))
  guard Notification::from_wire("workflow.entry", {
      "workflow": "wf-5",
      "session": "run7",
      "child": "run7-sr-5",
      "kind": "explore",
      "label": "scout:x",
      "phase": "survey",
      "status": "captured",
      "steps": 12,
      "prompt_tokens": 3000,
      "completion_tokens": 400,
      "started_at": 1788535817640,
      "finished_at": 1788535817648,
    })
    is Some(event) else {
    fail("known notification was rejected")
  }
  assert_eq(event.kind(), WorkflowEntry)
}
