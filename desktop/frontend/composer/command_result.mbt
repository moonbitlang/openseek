///|
#derive(Eq)
pub(all) enum FeedbackFailure {
  SignInRequired
  Diagnostic(String)
}

///|
#derive(Eq)
priv enum FeedbackStatus {
  Sending(String, String)
  Submitted(String)
  Failed(FeedbackFailure, held~ : String?)
  RetryReady(String)
}

///|
/// Command outcomes delivered to the composer entry that submitted them.
pub(all) enum CommandResult {
  FeedbackSettled(Identity, String, Result[Unit, FeedbackFailure])
  RestoreFeedback(Input, String, String?)
  FeedbackAccountUpdated(signed_in~ : Bool, changed~ : Bool)
  Ready(Input, String, String)
  Restore(Input, String)
  Settled(@interop.ConversationIdentity, String, Bool)
}

///|
#derive(Eq)
pub(all) struct ShellCommand {
  id : String
  command : String
}

///|
pub extend ShellCommand with Eq::{equal, not_equal}

///|
#derive(Eq)
priv struct ResultSubmission {
  id : String
  text : String
  recovered : Bool
}

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
fn Entry::feedback_failed(
  self : Entry,
  command : String,
  reason : FeedbackFailure,
) -> Entry {
  if !self.draft.task.is_empty() || self.holds_draft() {
    { ..self, feedback: Some(Failed(reason, held=Some(command))), }
  } else {
    {
      ..self,
      draft: { ..self.draft, task: command, },
      feedback: Some(Failed(reason, held=None)),
    }
  }
}

///|
fn Model::command_result(
  self : Model,
  message : CommandResult,
  emit : @cmd.Emit[Msg],
  action_emit : @cmd.Emit[Action],
) -> (Model, @cmd.Cmd) {
  match message {
    FeedbackAccountUpdated(signed_in~, changed~) =>
      (
        {
          ..self,
          entries: self.entries.map(entry => {
            match entry.feedback {
              Some(Sending(_, command)) if !signed_in =>
                {
                  ..entry,
                  feedback: Some(Failed(SignInRequired, held=Some(command))),
                }
              Some(Failed(SignInRequired, held=Some(command))) if signed_in =>
                { ..entry, feedback: Some(RetryReady(command)), }
              Some(Failed(SignInRequired, ..)) if !signed_in => entry
              Some(Failed(SignInRequired, ..)) => { ..entry, feedback: None, }
              _ if changed => { ..entry, feedback: None, }
              _ => entry
            }
          }),
        },
        @cmd.none,
      )
    FeedbackSettled(identity, request, result) => {
      guard self.entries
        .iter()
        .find_first(entry => entry.identity() == identity)
        is Some(entry) &&
        entry.feedback is Some(Sending(active, submitted)) &&
        active == request else {
        return (self, @cmd.none)
      }
      let (next, command) = match result {
        Ok(_) =>
          (
            { ..entry, feedback: Some(Submitted(request)), },
            @cmd.delay(emit(FeedbackConfirmationExpired(request)), 3000),
          )
        Err(reason) => (entry.feedback_failed(submitted, reason), @cmd.none)
      }
      self.commit_entry_change(entry, next, command, action_emit)
    }
    RestoreFeedback(input, draft, held) => {
      let entry = self.active(input)
      let next = if entry.holds_draft() {
        entry
      } else {
        entry.hold_result(draft)
      }
      self.commit_entry_change(
        entry,
        { ..next, feedback: held.map(command => RetryReady(command)), },
        @cmd.none,
        action_emit,
      )
    }
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
