///|
async test "a recorded session model is read back and carried into forks" {
  let store = new_store()
  defer @fs.remove(store.root(), recursive=true)
  let id = @agent_session.SessionId("origin")
  store.create(
    @agent_session.Session(id, system_prompt="system")
    .append(User(UserMessage(Content([Text("first")]))))
    .append(Terminal(Finished("one"))),
  )
  assert_eq(store.model(id), None)
  let pro : @store.SessionModel = { model: Deepseek(V4Pro), thinking: Max, }
  store.save_model(id, pro)
  assert_eq(store.model(id), Some(pro))
  assert_eq(
    @fs.read_text("\{store.root()}/sessions/origin/model.json"),
    "{\"model\":\"deepseek-v4-pro\",\"thinking\":\"max\"}",
  )
  let flash : @store.SessionModel = { model: Deepseek(V4Flash), thinking: No, }
  store.save_model(id, flash)
  assert_eq(store.model(id), Some(flash))
  ignore(store.fork(id, SessionId("fork"), system_prompt="system"))
  assert_eq(store.model(SessionId("fork")), Some(flash))
}

///|
/// An older record without a window uses the custom default. A saved window
/// round-trips and is carried into a fork.
async test "a session model keeps its custom id and window" {
  let store = new_store()
  defer @fs.remove(store.root(), recursive=true)
  let id = @agent_session.SessionId("s1")
  store.create(
    @agent_session.Session(id, system_prompt="system")
    .append(User(UserMessage(Content([Text("first")]))))
    .append(Terminal(Finished("one"))),
  )
  @fs.write_text(
    "\{store.root()}/sessions/s1/model.json",
    "{\"model\":\"gpt-9\",\"thinking\":\"high\"}",
  )
  let recorded : @store.SessionModel = {
    model: Custom("gpt-9", context_window=1_000_000),
    thinking: High,
  }
  assert_eq(store.model(id), Some(recorded))
  let updated = { ..recorded, model: Custom("gpt-9", context_window=131_072), }
  store.save_model(id, updated)
  assert_eq(store.model(id), Some(updated))
  let fork = @agent_session.SessionId("fork")
  ignore(store.fork(id, fork, system_prompt="system"))
  assert_eq(store.model(fork), Some(updated))
}

///|
/// A malformed session model raises instead of reading as absent: a blank name
/// is still refused, a thinking mode that does not exist is refused, and so is
/// a file that is not the object this file records.
async test "a malformed session model raises instead of reading as absent" {
  let store = new_store()
  defer @fs.remove(store.root(), recursive=true)
  let id = @agent_session.SessionId("s1")
  store.create(Session(id, system_prompt="system"))
  for
    payload in [
      "{\"model\":\"\",\"thinking\":\"high\"}", "{\"model\":\"gpt-9\",\"thinking\":\"plenty\"}",
      "{}",
    ] {
    @fs.write_text("\{store.root()}/sessions/s1/model.json", payload)
    let raised = try {
      ignore(store.model(id))
      false
    } catch {
      _ => true
    }
    assert_true(raised)
  }
}
