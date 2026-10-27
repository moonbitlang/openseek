///|
/// Resolve the owning composer without changing navigation or borrowing a
/// different host's credentials.
fn Model::command_result_input(
  self : Model,
  owner : @interop.ConversationIdentity,
) -> @composer.Input? {
  match owner {
    @interop.Host(key) => {
      guard self.find_conversation(key.channel, key.session) is Some(conv) else {
        return None
      }
      let target = {
        ..self.activate(key.channel, key.session, conv.project()),
        screen: Chat,
      }
      let input = target.composer_input()
      Some(
        if self.focused == key.channel {
          input
        } else {
          {
            ..input,
            presentation: {
              ..input.presentation,
              primary_action: @composer.Send(available=false),
            },
          }
        },
      )
    }
    @interop.Cloud(account~, session~) => {
      guard self.account.map(a => a.user.user_id) == Some(account) &&
        self.cloud.user_id == Some(account) &&
        self.cloud.conversations.contains(session) else {
        return None
      }
      {
        ..self,
        screen: Chat,
        selected_conversation: Some(CloudSelection(account~, session~)),
      }.cloud_composer_input()
    }
  }
}

///|
fn submit_command_result(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  identity : @composer.Identity,
  id : String,
  text : String,
  choice : @composer.FollowupChoice?,
) -> (@cmd.Cmd, Model) {
  guard model.accepts_composer_action(identity) else {
    return (@cmd.none, model)
  }
  let owner = identity.owner
  match owner {
    @interop.Host(key) => {
      guard model.find_conversation(key.channel, key.session) is Some(conv) else {
        return (@cmd.none, model)
      }
      let target = {
        ..model,
        followup_behavior: match choice {
          Some(@composer.QueueNext) => FollowupQueue
          Some(@composer.SteerNow) => FollowupSteer
          None => model.followup_behavior
        },
      }
      let (command, next) = send_shell_result(
        dispatch,
        target,
        conv,
        text,
        recover=false,
      )
      let next = { ..next, followup_behavior: model.followup_behavior, }
      let accepted = next
        .find_conversation(key.channel, key.session)
        .map_or(false, c => c.task != text && c.task == conv.task)
      // A declined handoff restores the original root draft; the composer owns
      // recovery of this independent result.
      let accepted = accepted &&
        next.submission_sequence != model.submission_sequence
      (
        @cmd.batch([
          command,
          dispatch(
            ComposerCommandResult(@composer.Settled(owner, id, accepted)),
          ),
        ]),
        next,
      )
    }
    @interop.Cloud(session~, ..) => {
      guard model.cloud.conversations.get(session) is Some(before) else {
        return (@cmd.none, model)
      }
      let draft : @composer.Draft = { task: text, mentions: [], images: [], }
      // A command result is a new message, never an edit of a queued draft.
      let conversations = model.cloud.conversations.copy()
      conversations[session] = { ..before, queue_edit: None, }
      let target = { ..model, cloud: { ..model.cloud, conversations, }, }
      let message = match choice {
        Some(choice) =>
          @cloud.ControlAction(
            owner,
            @composer.FollowupSubmitted(identity~, draft~, choice~, attachments=[]),
          )
        None => @cloud.Submit(owner, draft)
      }
      let (command, next) = update_cloud(dispatch, message, target)
      guard next.cloud.conversations.get(session) is Some(after) else {
        return (command, next)
      }
      let (after, admitted) = after.with_command_result(before, id)
      let conversations = next.cloud.conversations.copy()
      conversations[session] = after
      let next = { ..next, cloud: { ..next.cloud, conversations, }, }
      (
        @cmd.batch([
          command,
          if admitted {
            @cmd.none
          } else {
            dispatch(ComposerCommandResult(@composer.Settled(owner, id, false)))
          },
        ]),
        next,
      )
    }
  }
}

///|
/// Reuse Cloud's admission and receipt decisions, keeping terminal results
/// separate from editable drafts. HTTP acceptance alone never applies a steer.
fn cloud_command_results(
  dispatch : @cmd.Emit[Msg],
  before : @cloud.State,
  after : @cloud.State,
  message : @cloud.Msg,
) -> @cmd.Cmd {
  guard before.epoch == after.epoch &&
    before.user_id == after.user_id &&
    before.user_id is Some(account) else {
    return @cmd.none
  }
  let commands : Array[@cmd.Cmd] = []
  for session, previous in before.conversations {
    guard after.conversations.get(session) is Some(current) else { continue }
    if current == previous {
      continue
    }
    let owner = @interop.Cloud(account~, session~)
    if previous.pending is Some({ result_id: Some(id), known_tasks, .. }) {
      let failed = message is @cloud.SendFailed(epoch, target, request, _) &&
        epoch == before.epoch &&
        target == session &&
        request == previous.send_request
      let admitted = current.pending is None &&
        (
          current.task.map_or(false, task => !known_tasks.contains(task)) ||
          current.records.any(record => {
            record.kind == "user" && !known_tasks.contains(record.task_id)
          })
        )
      if failed || admitted {
        commands.push(
          dispatch(
            ComposerCommandResult(@composer.Settled(owner, id, admitted)),
          ),
        )
      }
    }
    for input in previous.control_inputs {
      guard input.result_id is Some(id) else { continue }
      let remaining = current.control_inputs
        .iter()
        .find_first(item => item.key == input.key)
      let applied = match input.operation {
        @cloud.QueueAdd(id~, ..) =>
          current.control.map_or(false, state => {
            state.queue.any(item => item.id == id)
          }) ||
          remaining.map_or(false, item => item.acknowledged)
        @cloud.Steer(submission_id~, ..) =>
          match message {
            @cloud.WatchEvent(_, target, _, @cloud.NativeEvent(frame)) if target ==
              session &&
              frame.task_id == Some(input.task_id) =>
              @wire.parse(frame.data)
              is Some(@wire.SteerApplied(submission_id=received, ..)) &&
              received == Some(submission_id)
            _ =>
              current.control.map_or(false, state => {
                state.steers.any(receipt => {
                  receipt.submission_id == submission_id &&
                  receipt.status is @cloud.Applied
                })
              })
          }
        _ => false
      }
      if applied ||
        remaining is None ||
        remaining.map_or(false, item => item.unknown) {
        commands.push(
          dispatch(ComposerCommandResult(@composer.Settled(owner, id, applied))),
        )
      }
    }
  }
  @cmd.batch(commands)
}

///|
/// A recovered result is a new message, never a replacement for a queued item.
fn recover_command_result(
  model : Model,
  identity : @composer.Identity,
) -> (@cmd.Cmd, Model) {
  guard model.accepts_composer_action(identity) else {
    return (@cmd.none, model)
  }
  match identity.owner {
    @interop.Host(key) => {
      guard model.find_conversation(key.channel, key.session) is Some(conv) else {
        return (@cmd.none, model)
      }
      let queue_edit = match conv.queue_edit {
        Some(Saving(id~, run_id~, ..) | SavingDetached(id~, run_id~)) =>
          Some(SavingDetached(id~, run_id~))
        _ => None
      }
      (@cmd.none, model.replace_conversation({ ..conv, queue_edit, }))
    }
    @interop.Cloud(account~, session~) => {
      guard model.cloud.user_id == Some(account) &&
        model.cloud.conversations.get(session) is Some(conv) else {
        return (@cmd.none, model)
      }
      let conversations = model.cloud.conversations.copy()
      conversations[session] = { ..conv, queue_edit: None, }
      (@cmd.none, { ..model, cloud: { ..model.cloud, conversations, }, })
    }
  }
}
