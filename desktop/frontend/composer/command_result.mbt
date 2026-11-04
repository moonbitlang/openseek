///|
/// A terminal result is a standalone message, independent of editable text,
/// images and attachments. Delivery updates are correlated by the command id.
pub(all) enum CommandResult {
  Ready(Input, String, String)
  Restore(Input, String)
  Settled(@interop.ConversationIdentity, String, Bool)
}

///|
pub(all) struct ShellCommand {
  id : String
  command : String
} derive(Eq)

///|
pub extend ShellCommand with Eq::{equal, not_equal}

///|
priv struct ResultSubmission {
  id : String
  text : String
  recovered : Bool
} derive(Eq)

///|
fn Entry::hold_result(self : Entry, text : String) -> Entry {
  let task = if self.draft.task.is_empty() {
    text
  } else {
    text + "\n\n" + self.draft.task
  }
  { ..self, draft: { ..self.draft, task, }, completion: None, }
}

///|
fn Model::command_result(
  self : Model,
  message : CommandResult,
  action_emit : @cmd.Emit[Action],
) -> (Model, @cmd.Cmd) {
  match message {
    Ready(input, id, text) => {
      let entry = self.active(input)
      if entry.results.any(result => result.id == id) {
        return (self, @cmd.none)
      }
      let can_send = entry.pending_submission is None &&
        { ..entry, image_reads: 0, attachment_requests: [], }.can_send(input)
      if !can_send {
        return self.commit_entry_change(
          entry,
          entry.hold_result(text),
          action_emit(CommandResultRecovered(identity=entry.identity())),
          action_emit,
        )
      }
      let choice = if entry.followup_choice is Some(choice) {
        Some(choice)
      } else {
        match input.presentation.primary_action {
          Running(submit=Queue, ..) => Some(QueueNext)
          Running(..) => Some(SteerNow)
          _ => None
        }
      }
      (
        self.with_entry({
          ..entry,
          results: [..entry.results, { id, text, recovered: false, }],
        }),
        action_emit(
          CommandResultSubmitted(identity=entry.identity(), id~, text~, choice~),
        ),
      )
    }
    Restore(input, text) => {
      let entry = self.active(input)
      if entry.holds_draft() {
        return (self, @cmd.none)
      }
      self.commit_entry_change(
        entry,
        entry.hold_result(text),
        @cmd.none,
        action_emit,
      )
    }
    Settled(owner, id, accepted) => {
      guard self.entries.iter().find_first(entry => entry.owner == owner)
        is Some(entry) &&
        entry.results.iter().find_first(result => result.id == id)
        is Some(result) else {
        return (self, @cmd.none)
      }
      if !accepted {
        if result.recovered {
          return (self, @cmd.none)
        }
        let recovered = {
          ..entry,
          results: [
            { ..result, recovered: true, },
            ..entry.results.filter(result => result.id != id),
          ],
        }
        return self.commit_entry_change(
          entry,
          recovered.hold_result(result.text),
          action_emit(CommandResultRecovered(identity=entry.identity())),
          action_emit,
        )
      }
      let results = entry.results.filter(result => result.id != id)
      let old_prefix = entry.results
        .filter(result => result.recovered)
        .map(result => result.text)
        .join("\n\n")
      let new_prefix = results
        .filter(result => result.recovered)
        .map(result => result.text)
        .join("\n\n")
      let task = if result.recovered && entry.draft.task == old_prefix {
        new_prefix
      } else if result.recovered &&
        entry.draft.task.strip_prefix(old_prefix + "\n\n") is Some(tail) {
        (if new_prefix.is_empty() { "" } else { new_prefix + "\n\n" }) +
        tail.to_owned()
      } else {
        entry.draft.task
      }
      self.commit_entry_change(
        entry,
        { ..entry, results, draft: { ..entry.draft, task, }, },
        @cmd.none,
        action_emit,
      )
    }
  }
}
