///|
async test "a recorded session model is read back and carried into forks" {
  let store = new_store()
  defer @fs.rmdir(store.root(), recursive=true)
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
async test "a malformed session model raises instead of reading as absent" {
  let store = new_store()
  defer @fs.rmdir(store.root(), recursive=true)
  let id = @agent_session.SessionId("s1")
  store.create(Session(id, system_prompt="system"))
  @fs.write_text(
    "\{store.root()}/sessions/s1/model.json",
    "{\"model\":\"gpt-9\",\"thinking\":\"high\"}",
  )
  let raised = try {
    ignore(store.model(id))
    false
  } catch {
    _ => true
  }
  assert_true(raised)
}
