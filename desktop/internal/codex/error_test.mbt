///|
test "Codex JSON-RPC errors retain method, code, message, and data" {
  let error : @codex.CodexError = JsonRpc(
    method_="thread/resume",
    code=-32602,
    message="invalid thread id",
    data=Some({ "threadId": "abc" }),
  )
  assert_eq(
    "\{error}",
    "Codex app-server request thread/resume failed: JSON-RPC error -32602: invalid thread id; data={\"threadId\":\"abc\"}",
  )
  // Proton's backend diagnostic path renders Error through Repr, so Debug must
  // retain the same fields instead of collapsing this suberror to `...`.
  let diagnostic = @debug.render(Repr(error))
  assert_true(diagnostic.contains("thread/resume"))
  assert_true(diagnostic.contains("-32602"))
  assert_true(diagnostic.contains("invalid thread id"))
  assert_true(diagnostic.contains("threadId"))
}

///|
test "Codex active-writer conflicts have a safe UI classification" {
  let conflict : @codex.CodexError = JsonRpc(
    method_="thread/resume",
    code=-32600,
    message="thread abc already has an active writer",
    data=None,
  )
  assert_true(conflict.is_active_writer())
  let invalid_id : @codex.CodexError = JsonRpc(
    method_="thread/resume",
    code=-32602,
    message="invalid thread id",
    data=None,
  )
  assert_false(invalid_id.is_active_writer())
}

///|
test "Codex unmaterialized task history has a narrow empty-history classification" {
  let empty : @codex.CodexError = JsonRpc(
    method_="thread/read",
    code=-32600,
    message="thread abc is not materialized yet; includeTurns is unavailable before first user message",
    data=None,
  )
  assert_true(empty.is_unmaterialized_thread_history())
  let unrelated : @codex.CodexError = JsonRpc(
    method_="thread/read",
    code=-32600,
    message="thread abc is not materialized yet",
    data=None,
  )
  assert_false(unrelated.is_unmaterialized_thread_history())
}

///|
test "Codex unmaterialized task has a narrow empty-turns classification" {
  let empty : @codex.CodexError = JsonRpc(
    method_="thread/turns/list",
    code=-32600,
    message="thread abc is not materialized yet; thread/turns/list is unavailable before first user message",
    data=None,
  )
  assert_true(empty.is_unmaterialized_thread_turns())
  let wrong_method : @codex.CodexError = JsonRpc(
    method_="thread/read",
    code=-32600,
    message="thread abc is not materialized yet; thread/turns/list is unavailable before first user message",
    data=None,
  )
  assert_false(wrong_method.is_unmaterialized_thread_turns())
}
