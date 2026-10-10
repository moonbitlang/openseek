///|
priv enum PredictionState {
  Unrequested
  Predicting(String, Int)
  Predicted(Int, String?)
} derive(Eq)

///|
fn PredictionState::sequence(self : PredictionState) -> Int? {
  match self {
    Unrequested => None
    Predicting(_, sequence) | Predicted(sequence, _) => Some(sequence)
  }
}

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
fn Entry::prediction_text(self : Entry, input : Input) -> String? {
  guard self.prediction is Predicted(sequence, text) &&
    self.prediction_eligible(input) == Some(sequence) else {
    return None
  }
  text
}

///|
/// Reconcile auxiliary work around every edit and reply. Editing cancels pending
/// requests so late replies cannot repopulate a later empty draft. Ready results
/// remain cached for their source sequence: typing hides them, clearing restores
/// them, and loaded metadata restores them without another model request.
fn Model::update(
  self : Model,
  input : Input,
  msg : Msg,
  emit : @cmd.Emit[Msg],
  action_emit : @cmd.Emit[Action],
) -> (Model, @cmd.Cmd) {
  let (next, command) = self.update_inner(input, msg, emit, action_emit)
  let editing = msg
    is (TextChanged(_) | HistoryMoved(_) | ImageRead(_, _) | QuoteReplied(_))
  let entries = next.entries.map(entry => {
    let entry = if editing &&
      entry.owner == input.identity.owner &&
      entry.prediction is Predicting(_, sequence) {
      { ..entry, prediction: Predicted(sequence, None), }
    } else if entry.prediction is Predicting(_, sequence) &&
      entry.prediction_eligible(input) != Some(sequence) {
      // Retire the request identity on navigation, but allow a later session
      // snapshot to restore its durable result. Ready suggestions remain cached.
      { ..entry, prediction: Unrequested, }
    } else {
      entry
    }
    if input.prediction is Some(record) &&
      entry.prediction_eligible(input) == Some(record.source_sequence) &&
      entry.prediction.sequence() != Some(record.source_sequence) {
      let text = match record.outcome {
        Completed(text~, ..) => text
        _ => None
      }
      { ..entry, prediction: Predicted(record.source_sequence, text), }
    } else {
      entry
    }
  })
  let commands = [command]
  for old in self.entries {
    if old.prediction is Predicting(id, sequence) &&
      !entries.any(entry => {
        entry.owner == old.owner && entry.prediction == old.prediction
      }) {
      commands.push(@prediction.cancel(old.owner, id, sequence))
    }
  }
  let next = { ..next, entries, }
  let entry = next.active(input)
  if next.prediction_client is Some(client) &&
    entry.prediction_eligible(input) is Some(sequence) &&
    entry.prediction.sequence() != Some(sequence) {
    let serial = next.prediction_serial + 1
    let id = "\{client}:\{serial}"
    let identity = entry.identity()
    commands.push(
      @prediction.request(
        entry.owner,
        id,
        sequence,
        emit.map(result => PredictionSettled(identity, id, sequence, result)),
      ),
    )
    return (
      {
        ..next.with_entry({ ..entry, prediction: Predicting(id, sequence), }),
        prediction_serial: serial,
      },
      @cmd.batch(commands),
    )
  }
  (next, @cmd.batch(commands))
}
