///|
fn record(
  session : @agent_session.Session,
  call~ : Int32 = 1,
) -> @agent_session.UsageRecord {
  UsageRecord(
    session,
    call~,
    attempt=1,
    purpose="manual_compaction",
    model="mock",
    outcome="completed",
    report=@deepseek.UsageReport::from_response({
      "usage": { "prompt_tokens": 0, "completion_tokens": 5 },
    }),
  )
}

///|
async test "usage-only records round trip without becoming model messages or steps" {
  let store = new_store()
  defer @fs.rmdir(store.root(), recursive=true)
  let session = store.append(
    Session(SessionId("usage"), system_prompt="s"),
    User(UserMessage(Content([Text("go")]))),
  )
  let original = session.chat_messages().map(message => message.content.text())
  let next = store.append_usage(session, record(session))
  assert_eq(next.last_sequence(), session.last_sequence())
  assert_eq(
    next.chat_messages().map(message => message.content.text()),
    original,
  )
  let loaded = store.load(SessionId("usage"))
  assert_eq(loaded, next)
  assert_eq(loaded.usage_records().length(), 1)
  assert_eq(loaded.usage_records()[0].report.prompt_tokens, Some(0))
  assert_eq(loaded.usage_records()[0].report.total_tokens, None)
  assert_eq(loaded.next_usage_call(), 2)
  let text = @fs.read_file(session_file(store, "usage")).text()
  let parsed = @session_log.parse_events(text)
  assert_eq(parsed.events.length(), 1)
  assert_eq(parsed.errors.length(), 0)
  ignore(store.append(next, Terminal(Finished("done"))))
  let stale = try {
    ignore(store.append_usage(session, record(session, call=2)))
    false
  } catch {
    _ => true
  }
  assert_true(stale)
  let duplicate = try {
    ignore(store.append_usage(next, record(next)))
    false
  } catch {
    _ => true
  }
  assert_true(duplicate)
}

///|
async test "old version one log upgrades on write without changing conversation records" {
  let store = new_store()
  defer @fs.rmdir(store.root(), recursive=true)
  @fs.mkdir("\{store.root()}/sessions/old", recursive=true)
  let legacy = "{\"version\":1,\"id\":\"old\",\"system_prompt\":\"s\"}\n{\"sequence\":1,\"ts\":0,\"item\":{\"kind\":\"user\",\"payload\":{\"content\":\"go\"}}}\n"
  @fs.write_file(session_file(store, "old"), legacy)
  let loaded = store.load(SessionId("old"))
  let next = store.append_usage(loaded, record(loaded))
  let reloaded = store.load(SessionId("old"))
  assert_eq(reloaded, next)
  assert_eq(reloaded.events(), loaded.events())
  let first = @fs.read_file(session_file(store, "old"))
    .text()
    .split_once("\n")
    .unwrap().0
  assert_true(@json.parse(first) is { "version": 2, .. })
}

///|
async test "usage tail repair and stale checks include accounting-only appends" {
  let store = new_store()
  defer @fs.rmdir(store.root(), recursive=true)
  let empty = @agent_session.Session(SessionId("tail"), system_prompt="s")
  let first = store.append_usage(empty, record(empty))
  append_raw(store, "tail", "{\"type\":\"model_usage\",\"record\":")
  let loaded = store.load(SessionId("tail"))
  assert_eq(loaded, first)
  let next = store.append_usage(loaded, record(loaded, call=2))
  assert_eq(store.load(SessionId("tail")), next)
  let stale = try {
    ignore(store.append_usage(first, record(first, call=3)))
    false
  } catch {
    _ => true
  }
  assert_true(stale)
}

///|
async test "legacy append_item-only adapters flush queued accounting with the next message" {
  let store = new_store()
  defer @fs.rmdir(store.root(), recursive=true)
  let current = store.append(
    Session(SessionId("adapter"), system_prompt="s"),
    User(UserMessage(Content([Text("go")]))),
  )
  let pending = current.append_usage(record(current))
  let saved = store.append(pending, Terminal(Failed("summary failed")))
  assert_eq(store.load(SessionId("adapter")), saved)
  assert_eq(saved.usage_records().length(), 1)
  let (parsed, records) = @session_log.parse_with_usage(
    @fs.read_file(session_file(store, "adapter")).text(),
  )
  assert_eq(parsed.errors.length(), 0)
  assert_eq(parsed.events.length(), 2)
  assert_eq(records, saved.usage_records())
  let snapshot : @agent_session.Session = @json.from_json(Json(saved))
  assert_eq(snapshot, saved)
}

///|
async test "forked history retains original accounting identity for cross-session deduplication" {
  let store = new_store()
  defer @fs.rmdir(store.root(), recursive=true)
  let parent = store.append(
    Session(SessionId("parent"), system_prompt="s"),
    User(UserMessage(Content([Text("go")]))),
  )
  let parent = store.append_usage(parent, record(parent))
  ignore(store.append(parent, Terminal(Finished("done"))))
  let fork = store.fork(
    SessionId("parent"),
    SessionId("fork"),
    system_prompt="s",
  )
  assert_eq(fork.usage_records().length(), 1)
  assert_eq(fork.usage_records()[0].session_id, "parent")
  assert_eq(store.load(SessionId("fork")).usage_records(), fork.usage_records())
}
