///|
/// Session lines in the current encoding, one per event kind and optional
/// field combination (key order included). Each must round-trip byte for
/// byte.
let canonical_lines : Array[String] = [
  "{\"sequence\":1,\"ts\":1790120995444,\"item\":{\"kind\":\"user\",\"payload\":{\"content\":\"hi\"}}}",
  "{\"sequence\":2,\"ts\":1790120995445,\"item\":{\"kind\":\"user\",\"payload\":{\"content\":\"x\",\"submission_id\":\"s-1\"}}}",
  "{\"sequence\":3,\"ts\":1790120995446,\"item\":{\"kind\":\"user\",\"payload\":{\"content\":[{\"type\":\"text\",\"text\":\"look\"},{\"type\":\"image\",\"media_type\":\"image/png\",\"data\":\"iVBORw0KGgo=\"}]}}}",
  "{\"sequence\":4,\"ts\":1790120997016,\"item\":{\"kind\":\"assistant\",\"payload\":{\"content\":\"\",\"tool_calls\":[{\"id\":\"c1\",\"name\":\"read\",\"arguments\":\"{\\\"path\\\":\\\"a.mbt\\\"}\"}],\"reasoning_content\":\"think\",\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":2,\"total_tokens\":12,\"prompt_cache_hit_tokens\":8,\"prompt_cache_miss_tokens\":2}}}}",
  "{\"sequence\":5,\"ts\":1790120997017,\"item\":{\"kind\":\"assistant\",\"payload\":{\"content\":\"done\",\"tool_calls\":[],\"is_replay\":true}}}",
  "{\"sequence\":6,\"ts\":1790120997018,\"item\":{\"kind\":\"tool_result\",\"payload\":{\"tool_call_id\":\"c1\",\"tool_name\":\"read\",\"content\":\"ok\",\"is_error\":false}}}",
  "{\"sequence\":7,\"ts\":1790120997019,\"item\":{\"kind\":\"tool_result\",\"payload\":{\"tool_call_id\":\"c1\",\"tool_name\":\"multi_edit\",\"content\":\"ok\",\"is_error\":true,\"brief\":\"multi_edit 5 files (19×)\",\"data\":{\"outcome\":\"applied\",\"files\":[{\"path\":\"a\",\"edits\":2}],\"edit_count\":19}}}}",
  "{\"sequence\":8,\"ts\":1790120997020,\"item\":{\"kind\":\"tool_result\",\"payload\":{\"tool_call_id\":\"c2\",\"tool_name\":\"screenshot\",\"content\":[{\"type\":\"image\",\"media_type\":\"image/png\",\"data\":\"iVBORw0KGgo=\"}],\"is_error\":false}}}",
  "{\"sequence\":9,\"ts\":0,\"item\":{\"kind\":\"runtime_notice\",\"payload\":{\"content\":\"[plan reminder]\"}}}",
  "{\"sequence\":10,\"ts\":0,\"item\":{\"kind\":\"summary\",\"payload\":{\"content\":\"s\",\"from_sequence\":1,\"to_sequence\":7}}}",
  "{\"sequence\":11,\"ts\":0,\"item\":{\"kind\":\"terminal\",\"payload\":{\"kind\":\"finished\",\"message\":\"done\"}}}",
  "{\"sequence\":12,\"ts\":0,\"item\":{\"kind\":\"terminal\",\"payload\":{\"kind\":\"finished\",\"message\":\"[context ceiling] echoed\",\"verbatim\":true}}}",
  "{\"sequence\":13,\"ts\":0,\"item\":{\"kind\":\"terminal\",\"payload\":{\"kind\":\"context_yield\",\"message\":\"[context ceiling] checkpointed\"}}}",
  "{\"sequence\":14,\"ts\":0,\"item\":{\"kind\":\"terminal\",\"payload\":{\"kind\":\"max_steps_exhausted\"}}}",
  "{\"sequence\":15,\"ts\":0,\"item\":{\"kind\":\"terminal\",\"payload\":{\"kind\":\"failed\",\"message\":\"max steps exhausted\",\"verbatim\":true}}}",
  "{\"sequence\":16,\"ts\":0,\"item\":{\"kind\":\"terminal\",\"payload\":{\"kind\":\"interrupted\",\"message\":\"cancelled\"}}}",
]

///|
/// Legacy terminal encodings (see session-v1.jsonl): they decode to the
/// dedicated kinds and are re-encoded in the current form.
let legacy_lines : Array[String] = [
  "{\"sequence\":1,\"ts\":0,\"item\":{\"kind\":\"terminal\",\"payload\":{\"kind\":\"finished\",\"message\":\"[context ceiling] This turn reached the model's context window and was checkpointed.\"}}}",
  "{\"sequence\":2,\"ts\":0,\"item\":{\"kind\":\"terminal\",\"payload\":{\"kind\":\"failed\",\"message\":\"max steps exhausted\"}}}",
]

///|
/// Decode through the core `Json` route (`FromJson`), which other packages use.
fn json_decode(line : String) -> @agent_session.SessionEvent raise {
  @json.from_json(@json.parse(line))
}

///|
test "session lines round-trip byte for byte" {
  for line in canonical_lines {
    let event = @agent_session.SessionEvent::from_json_line(line)
    assert_eq(event.to_json_line(), line)
  }
}

///|
test "the text and Json routes agree, including legacy terminals" {
  for line in [..canonical_lines, ..legacy_lines] {
    let event = @agent_session.SessionEvent::from_json_line(line)
    assert_eq(event, json_decode(line))
    assert_eq(event.to_json_line(), ToJson::to_json(event).stringify())
  }
  inspect(
    @agent_session.SessionEvent::from_json_line(legacy_lines[1]).to_json_line(),
    content=(
      #|{"sequence":2,"ts":0,"item":{"kind":"terminal","payload":{"kind":"max_steps_exhausted"}}}
    ),
  )
}

///|
test "decoding errors say what and where" {
  let err = (line : String) => {
    try @agent_session.SessionEvent::from_json_line(line) catch {
      error => "\{error}"
    } noraise {
      _ => "ok"
    }
  }
  inspect(
    err("{\"sequence\":1,\"ts\":0}"),
    content=(
      #|missing field `item`
    ),
  )
  inspect(
    err(
      "{\"sequence\":1,\"ts\":0,\"item\":{\"kind\":\"bogus\",\"payload\":{}}}",
    ),
    content=(
      #|unknown variant `bogus`, expected one of `user`, `assistant`, `tool_result`, `runtime_notice`, `summary`, `terminal` at /item
    ),
  )
  inspect(
    err("{\"sequence\":1,\"ts\":0,\"item\":{\"kind\":\"user\",\"payl"),
    content=(
      #|EOF while parsing a string
    ),
  )
  inspect(
    err(
      "{\"sequence\":1,\"ts\":0,\"item\":{\"kind\":\"terminal\",\"payload\":{\"kind\":\"aborted\"}}}",
    ),
    content=(
      #|expected string at /item/payload/message
    ),
  )
}
