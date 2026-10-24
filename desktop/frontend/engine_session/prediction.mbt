///|
/// Keep completed results across older snapshot replies, and retire them only
/// when the native session frontier advances beyond their source record.
pub fn merge_prediction(
  current : @wire.PredictionRecord?,
  incoming : @wire.PredictionRecord?,
  watermark : Int32,
) -> @wire.PredictionRecord? {
  let prediction = if incoming is Some(record) &&
    record.outcome is Completed(..) &&
    (
      current is None ||
      (current is Some(old) && old.source_sequence <= record.source_sequence)
    ) {
    Some(record)
  } else {
    current
  }
  let prediction = if prediction is Some(record) &&
    record.source_sequence >= watermark {
    Some(record)
  } else {
    None
  }
  prediction
}

///|
/// Live completion and restored results use the same native-log frontier.
/// Transport sequence numbers and execution identifiers never identify it.
pub fn prediction_source(
  prediction : @wire.PredictionRecord?,
  watermark : Int32,
  completed~ : Bool,
) -> Int32? {
  if watermark > 0 &&
    (
      completed ||
      prediction.map_or(false, record => record.source_sequence == watermark)
    ) {
    Some(watermark)
  } else {
    None
  }
}
