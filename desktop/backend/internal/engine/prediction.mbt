///|
/// Auxiliary work only uses an already loaded live engine; opening a chat
/// never starts a new process merely to generate a suggestion.
pub async fn predict(
  manager : EngineManager,
  payload : @protocol.PredictionPayload,
) -> @protocol.PredictionReply {
  guard manager.pump is Serving(sessions~) &&
    sessions.get(payload.session) is Some(slot) &&
    slot.live() is Some(engine) else {
    return { outcome: Skipped, }
  }
  guard !engine.prediction_requests.contains(payload.request_id) else {
    raise EngineError("duplicate prediction request")
  }
  let reply : @async.Queue[@wire.Event] = Queue(kind=Blocking(1))
  engine.prediction_requests[payload.request_id] = reply
  defer {
    engine.prediction_requests.remove(payload.request_id)
    ignore(
      engine.submit(
        CancelPrediction(request_id=payload.request_id),
        failure_reason="prediction cancellation could not be delivered",
      ),
    )
  }
  let ack : @async.Queue[EngineError?] = Queue(kind=Blocking(1))
  guard engine.submit(
    Predict(
      request_id=payload.request_id,
      source_sequence=payload.source_sequence,
    ),
    failure_reason="prediction request could not be delivered",
    ack~,
  ) else {
    raise EngineError("prediction engine is unavailable")
  }
  @async.with_timeout(12000, () => {
    if ack.get() is Some(error) {
      raise error
    }
    match reply.get() {
      PredictionResult(request_id~, source_sequence~, outcome~) if request_id ==
        payload.request_id &&
        source_sequence == payload.source_sequence => { outcome, }
      _ => raise EngineError("unexpected prediction response")
    }
  })
}

///|
/// Correlation prevents a late cancellation from stopping a newer prediction.
pub fn cancel_prediction(
  manager : EngineManager,
  payload : @protocol.PredictionPayload,
) -> Bool {
  guard manager.pump is Serving(sessions~) &&
    sessions.get(payload.session) is Some(slot) &&
    slot.live() is Some(engine) &&
    engine.prediction_requests.contains(payload.request_id) else {
    return false
  }
  engine.submit(
    CancelPrediction(request_id=payload.request_id),
    failure_reason="prediction cancellation could not be delivered",
  )
}

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
    request_id: "request",
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
