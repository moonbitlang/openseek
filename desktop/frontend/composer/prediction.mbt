///|
fn Entry::prediction_eligible(self : Entry, input : Input) -> Int? {
  guard self.identity() == input.identity &&
    self.draft.is_empty() &&
    self.goal_draft is None &&
    self.pending_submission is None &&
    self.image_reads == 0 &&
    !input.presentation.disabled &&
    input.presentation.primary_action is Send(available=true) else {
    return None
  }
  input.prediction_source
}

///|
/// Suggestions belong to the conversation. Draft edits only affect visibility.
fn Entry::prediction_text(self : Entry, input : Input) -> String? {
  guard input.prediction is Some(record) &&
    self.prediction_eligible(input) == Some(record.source_sequence) &&
    record.outcome is Completed(text~, ..) else {
    return None
  }
  text
}
