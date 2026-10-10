///|
/// Scope is resolved by session.load, including archive/read leases. Stale
/// metadata is not shown alongside a newer transcript snapshot.
async fn load_prediction(
  root : @pathx.Absolute,
  session : String,
  sequence : Int,
) -> @wire.PredictionRecord? {
  let store = @store.SessionStore(root.to_string())
  if store.prediction(SessionId(session)) is Some(record) &&
    record.source_sequence == sequence {
    Some(record)
  } else {
    None
  }
}

///|
async test "prediction loads offline by exact transcript version and follows archive moves" {
  let dir = @fs.tmpdir(prefix="openseek-prediction-load-")
  defer @fs.rmdir(dir, recursive=true)
  let root = @pathx.Path(dir).resolve()
  let store = @store.SessionStore(dir)
  let session = @agent_session.Session(
      SessionId("cached"),
      system_prompt="system",
    )
    .append(User(UserMessage(Content([Text("fix it")]))))
    .append(Terminal(Finished("done")))
  store.create(session)
  assert_true(load_prediction(root, "cached", 2) is None)
  store.save_prediction(session, {
    source_sequence: 2,
    outcome: Completed(text=Some("commit"), input_tokens=1, output_tokens=1),
  })
  guard load_prediction(root, "cached", 2) is Some(record) else {
    fail("missing cached prediction")
  }
  assert_true(record.outcome is Completed(text=Some("commit"), ..))
  assert_true(load_prediction(root, "cached", 3) is None)
  @fs.mkdir(dir + "/archived")
  @fs.rename(dir + "/sessions", dir + "/archived/sessions")
  assert_eq(load_prediction(root.join("archived"), "cached", 2), Some(record))
}
