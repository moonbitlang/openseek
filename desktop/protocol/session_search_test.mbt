///|
test "session search codecs round trip title results and reject invalid requests" {
  let request : @protocol.SessionSearchPayload = {
    query: "中文",
    include_archived: true,
  }
  let decoded : @protocol.SessionSearchPayload = @json.from_json(
    request.to_json(),
  )
  assert_true(decoded == request)
  let reply : @protocol.SessionSearchReply = {
    hits: [
      {
        session: "s",
        workspace: "/project",
        title: "Title",
        archived: false,
        updated_at_ms: None,
      },
    ],
    errors: ["unreadable store"],
    has_more: false,
  }
  let decoded : @protocol.SessionSearchReply = @json.from_json(reply.to_json())
  assert_true(decoded == reply)
  let invalid : Array[Json] = [
    { "include_archived": false },
    { "query": "text", "include_archived": "yes" },
    { "query": null, "include_archived": false },
  ]
  for json in invalid {
    try (@json.from_json(json) : @protocol.SessionSearchPayload) catch {
      _ => ()
    } noraise {
      _ => fail("accepted malformed request")
    }
  }
}
