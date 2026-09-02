///|
test "workspace popup payload round-trips and actions stay namespaced" {
  let payload : @protocol.WorkspaceMenuPayload = @json.from_json({
    "x": 12,
    "y": 34,
    "future": true,
  })
  assert_eq(payload.x, 12)
  assert_eq(payload.y, 34)
  @debug.assert_eq(payload.to_json(), { "x": 12, "y": 34 })
  assert_eq(
    @protocol.WorkspaceMenuAction::parse("workspace.settings"),
    Some(OpenWorkspaceSettings),
  )
  assert_eq(
    @protocol.WorkspaceMenuAction::parse("workspace.detach"),
    Some(DetachWorkspace),
  )
  assert_true(
    @protocol.WorkspaceMenuAction::parse("conversation.archive") is None,
  )
}
