///|
test "file SSE keeps event names and joins CRLF data lines" {
  let parser = SseParser::new()
  assert_true(parser.line(": keepalive\r") is None)
  assert_true(parser.line("event: workspace_invalidated\r") is None)
  assert_true(parser.line("data: {\r") is None)
  assert_true(parser.line("data: \"detail\":\"🌙\"}\r") is None)
  let frame = parser.line("\r")
  assert_eq(frame, Some(("workspace_invalidated", "{\n\"detail\":\"🌙\"}")))
  let (event, data) = frame.unwrap()
  assert_true(workspace_invalidated(event, data))
  assert_true(parser.line("") is None)
}

///|
test "SSE resets event names and supports empty data and colonless fields" {
  let parser = SseParser::new()
  ignore(parser.line("event: workspace_invalidated"))
  // An event without a data field is not dispatched, and its name is reset.
  assert_true(parser.line("") is None)
  ignore(parser.line("data"))
  assert_eq(parser.line(""), Some(("message", "")))
  ignore(parser.line("event: ignored"))
  ignore(parser.line("event:"))
  ignore(parser.line("data:  preserve one space"))
  assert_eq(parser.line(""), Some(("message", " preserve one space")))
  ignore(parser.line("data: unfinished"))
  assert_true(parser.line("id: 7") is None)
  assert_true(parser.line("retry: 1000") is None)
}

///|
test "only named object invalidations reach the workspace watcher" {
  assert_true(workspace_invalidated("workspace_invalidated", "{}"))
  assert_true(workspace_invalidated("workspace_invalidated", "{\"new\":true}"))
  assert_false(workspace_invalidated("message", "{}"))
  assert_false(workspace_invalidated("unknown", "not JSON"))
  for payload in ["null", "[]", "true", "\"text\"", "{invalid"] {
    let malformed = try {
      ignore(workspace_invalidated("workspace_invalidated", payload))
      false
    } catch {
      RequestError(Malformed) => true
      _ => false
    }
    assert_true(malformed)
  }
}

///|
test "watcher HTTP failures preserve terminal authentication and missing status" {
  let failure = fn(status) {
    try {
      check_status(status)
      None
    } catch {
      RequestError(failure) => Some(failure)
    }
  }
  assert_true(failure(200) is None)
  assert_true(failure(401) is Some(Unauthorized))
  assert_true(failure(404) is Some(Http(404)))
  assert_true(failure(503) is Some(Http(503)))
}
