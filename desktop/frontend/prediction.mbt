///|
/// Keep the newest completed result even when its broadcast precedes the
/// transcript follower or races an older session-load response.
fn Conversation::with_prediction(
  self : Conversation,
  incoming : @wire.PredictionRecord?,
) -> Conversation {
  let prediction = if incoming is Some(record) &&
    record.outcome is Completed(..) &&
    (
      self.prediction is None ||
      (
        self.prediction is Some(old) &&
        old.source_sequence <= record.source_sequence
      )
    ) {
    Some(record)
  } else {
    self.prediction
  }
  let prediction = if prediction is Some(record) &&
    record.source_sequence >= self.watermark {
    Some(record)
  } else {
    None
  }
  { ..self, prediction, }
}

///|
test "prediction broadcasts are pure and survive snapshots that started before completion" {
  let base = test_model().replace_conversation({
    ..test_conversation(),
    watermark: 2,
  })
  let record : @wire.PredictionRecord = {
    source_sequence: 2,
    outcome: Completed(text=Some("Commit"), input_tokens=1, output_tokens=2),
  }
  let message = PredictionReceived(session="desktop-test", prediction=record)
  let (_, first) = update_dev(test_dispatch(), message, base)
  let (_, second) = update_dev(test_dispatch(), message, base)
  assert_eq(first.active().prediction, Some(record))
  assert_eq(first.active().prediction, second.active().prediction)
  assert_eq(base.active().prediction, None)
  let loading = first.replace_conversation({
    ..first.active(),
    sync: Reloading(
      generation=1,
      attempt=0,
      buffered=[],
      reload_after_current=false,
    ),
  })
  let (_, refreshed) = update_dev(
    test_dispatch(),
    SessionRefreshed(
      session="desktop-test",
      items=[],
      watermark=2,
      goal=None,
      goal_markers=[],
      prediction=None,
      generation=1,
    ),
    loading,
  )
  assert_eq(refreshed.active().prediction, Some(record))
  let (_, stale) = update_dev(
    test_dispatch(),
    PredictionReceived(session="desktop-test", prediction={
      ..record,
      source_sequence: 1,
    }),
    refreshed,
  )
  assert_eq(stale.active().prediction, Some(record))
}

///|
test "prediction may arrive ahead of transcript commits but never for an older version" {
  let conv = { ..test_conversation(), watermark: 1, }
  let record : @wire.PredictionRecord = {
    source_sequence: 2,
    outcome: Completed(text=Some("Commit"), input_tokens=1, output_tokens=2),
  }
  let early = conv.with_prediction(Some(record))
  assert_eq(early.prediction, Some(record))
  assert_eq(early.with_prediction(None).prediction, Some(record))
  let newer = { ..conv, watermark: 3, }
  assert_eq(newer.with_prediction(Some(record)).prediction, None)
}
