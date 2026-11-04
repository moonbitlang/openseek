///|
/// Keep one deliberately selected state per page revision. A later click
/// updates that chip without discarding typed text or other attachments.
pub fn Draft::with_artifact_snapshot(
  self : Draft,
  snapshot : @mention_context.ArtifactSnapshot,
) -> Draft {
  let mentions = self.mentions.filter(mention => {
    !(mention.ref_ is @mention_context.InteractiveAnswer(existing) &&
    existing.reference == snapshot.reference)
  })
  { ..self, mentions, }.with_mention({
    ref_: @mention_context.InteractiveAnswer(snapshot),
    range: None,
  })
}
