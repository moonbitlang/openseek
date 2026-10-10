///|
async test "completed predictions survive reopening without changing the transcript" {
  let store = new_store()
  defer @fs.rmdir(store.root(), recursive=true)
  let id = @agent_session.SessionId("prediction")
  let session = @agent_session.Session(id, system_prompt="system")
    .append(User(UserMessage(Content([Text("fix it")]))))
    .append(Terminal(Finished("fixed")))
  store.create(session)
  let transcript = @fs.read_file(store.session_file(id)).text()
  assert_true(@store.SessionStore(store.root()).prediction(id) is None)
  let record : @protocol.PredictionRecord = {
    source_sequence: 2,
    request_id: "first",
    outcome: Completed(text=Some("commit it"), input_tokens=8, output_tokens=4),
  }
  store.save_prediction(session, record)
  let reopened = @store.SessionStore(store.root())
  assert_eq(reopened.prediction(id), Some(record))
  assert_eq(@fs.read_file(store.session_file(id)).text(), transcript)
  let running = reopened.append(
    session,
    User(UserMessage(Content([Text("next")]))),
  )
  reopened.save_prediction(running, { ..record, source_sequence: 3, })
  assert_eq(reopened.prediction(id), Some(record))
  let next = reopened.append(running, Terminal(Finished("done")))
  let latest : @protocol.PredictionRecord = {
    source_sequence: 4,
    request_id: "next",
    outcome: Completed(text=None, input_tokens=8, output_tokens=4),
  }
  reopened.save_prediction(next, latest)
  // Another process finishing an old request must not replace the new result.
  store.save_prediction(session, record)
  assert_eq(reopened.prediction(id), Some(latest))
}

///|
async test "legacy attempts and failures do not block a completed result" {
  let store = new_store()
  defer @fs.rmdir(store.root(), recursive=true)
  let session = @agent_session.Session(
      SessionId("legacy"),
      system_prompt="system",
    )
    .append(User(UserMessage(Content([Text("fix it")]))))
    .append(Terminal(Finished("fixed")))
  store.create(session)
  let path = store.root() + "/sessions/legacy/prediction.json"
  for
    outcome in [
      Json::null(),
      { "kind": "failed", "message": "timeout" },
      { "kind": "cancelled" },
    ] {
    let legacy : Json = {
      "version": 1,
      "source_sequence": 2,
      "request_id": "legacy",
      "outcome": outcome,
    }
    @fs.write_file(path, legacy.stringify())
    assert_true(
      @store.SessionStore(store.root()).prediction(session.id()) is None,
    )
  }
  let record : @protocol.PredictionRecord = {
    source_sequence: 2,
    request_id: "retry",
    outcome: Completed(text=Some("commit it"), input_tokens=8, output_tokens=4),
  }
  store.save_prediction(session, record)
  assert_eq(
    @store.SessionStore(store.root()).prediction(session.id()),
    Some(record),
  )
}

///|
async test "corrupt prediction metadata remains an error rather than a cache miss" {
  let store = new_store()
  defer @fs.rmdir(store.root(), recursive=true)
  let id = @agent_session.SessionId("corrupt")
  store.create(Session(id, system_prompt="system"))
  @fs.write_file(store.root() + "/sessions/corrupt/prediction.json", "broken")
  try store.prediction(id) catch {
    _ => ()
  } noraise {
    _ => fail("corrupt metadata was hidden")
  }
}
