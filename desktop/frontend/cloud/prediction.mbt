///|
fn Conversation::with_prediction(
  self : Conversation,
  incoming : @wire.PredictionRecord?,
) -> Conversation {
  {
    ..self,
    prediction: @engine_session.merge_prediction(
      self.prediction,
      incoming,
      self.prediction_watermark(),
    ),
  }
}

///|
/// Normalize host-specific availability; the shared composer owns draft,
/// identity, Tab acceptance and all prediction presentation.
pub fn Conversation::prediction_source(
  self : Conversation,
  ready~ : Bool,
) -> Int32? {
  guard ready &&
    self.controls.compaction is NotCompacting &&
    self.controls.edit is None &&
    self.queue_edit is None &&
    self.control_inputs.is_empty() &&
    self.control.map_or(true, control => {
      control.queue.is_empty() &&
      !control.steers.any(steer => steer.status is (Pending | Unknown))
    }) else {
    return None
  }
  let events = self.document.events.unwrap_or([])
  let completed = events
    .last()
    .map_or(false, event => {
      event.item is @protocol.Terminal(@protocol.Finished(_))
    })
  @engine_session.prediction_source(
    self.prediction,
    self.prediction_watermark(),
    completed~,
  )
}

///|
/// Native record sequence, matching Local's derived session watermark.
fn Conversation::prediction_watermark(self : Conversation) -> Int32 {
  self.document.events
  .unwrap_or([])
  .fold(init=0, (maximum, event) => maximum.max(event.sequence))
}
