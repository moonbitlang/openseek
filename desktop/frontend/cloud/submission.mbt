///|
/// Session preparation is independent of the native command being submitted.
fn State::submit_command(
  self : State,
  owner : @interop.ConversationIdentity,
  submission : CommandSubmission,
  emit : @cmd.Emit[Msg],
  token : String?,
  navigation : Int32,
) -> (State, @cmd.Cmd) {
  guard owner is @interop.Cloud(account~, session~) &&
    self.user_id == Some(account) &&
    token is Some(_) else {
    return (self, @cmd.none)
  }
  if self.draft_identity() == Some(owner) && self.creation is Some(creation) {
    guard creation.pending is None else { return (self, @cmd.none) }
    return {
      ..self,
      sequence: submission.request,
      notice: None,
      creation: Some({
        ..creation,
        request: submission.request,
        navigation,
        pending: Some(submission),
      }),
    }.create(token, emit)
  }
  let next = { ..self, sequence: submission.request, }
  next.dispatch_command(session, submission, token, emit)
}

///|
fn State::dispatch_command(
  self : State,
  session : String,
  submission : CommandSubmission,
  token : String?,
  emit : @cmd.Emit[Msg],
) -> (State, @cmd.Cmd) {
  guard token is Some(token) else { return (self, @cmd.none) }
  if submission.prompt is Some((draft, attachments)) &&
    submission.command is @wire.Prompt(content~, ..) {
    return self.dispatch_prompt(
      session,
      submission.request,
      draft,
      attachments,
      content,
      token,
      emit,
    )
  }
  let conversation = self.conversations[session]
  let request = submission.request.to_string()
  let command = submission.command
  (
    // Do not let a history read begun before this command clear its refusal.
    self.replace(session, { ..conversation, request: submission.request, }),
    run(emit, () => {
      CommandFinished(
        self.epoch,
        session,
        request,
        command,
        send_command(
          token,
          session,
          command,
          task_id?=conversation.control.bind(c => c.active_task_id),
        ),
      ) catch {
        @cloud_client.RequestError(failure) =>
          CommandFailed(self.epoch, session, request, command, failure)
        _ => CommandFailed(self.epoch, session, request, command, Unreachable)
      }
    }),
  )
}

///|
fn State::dispatch_prompt(
  state : State,
  id : String,
  request : Int32,
  draft : @composer.Draft,
  attachments : Array[@protocol.AttachmentSource],
  prompt : @wire.Content,
  token : String,
  emit : @cmd.Emit[Msg],
) -> (State, @cmd.Cmd) {
  let conversation = state.conversations[id]
  let next = state.replace(id, {
    ..conversation.clear_progress(),
    request,
    send_request: request,
    sending: true,
    heartbeat: Some({ stage: @composer.Starting, started_ms: None, tokens: 0, }),
    history_required: true,
    notice: None,
    pending: Some({
      content: prompt,
      known_tasks: {
        let tasks = conversation.records
          .filter(record => record.kind == "user")
          .map(record => record.task_id)
        if conversation.task is Some(task) && !tasks.contains(task) {
          tasks.push(task)
        }
        tasks
      },
    }),
  })
  let command = @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let task : async () -> Msg = () => {
        try {
          let prepared = prepare_submission(
            token,
            id,
            draft,
            attachments,
            conversation.uploads,
            (source, path) => {
              scheduler.add(
                emit(AttachmentStored(state.epoch, id, request, source, path)),
              )
            },
          )
          let prompt = prompt_content(prepared)
          scheduler.add(
            emit(MessagePrepared(state.epoch, id, request, prepared, prompt)),
          )
          match
            send_command(
              token,
              id,
              @wire.Prompt(content=prompt, submission_id=None),
            ) {
            Accepted => ()
            Rejected(_) => raise @cloud_client.RequestError(Busy)
          }
          SendAccepted(state.epoch, id, request)
        } catch {
          @cloud_client.RequestError(error) =>
            SendFailed(state.epoch, id, request, error)
          _ => SendFailed(state.epoch, id, request, Unreachable)
        }
      }
      scheduler.add(emit(task()))
    })
    |> ignore
  })
  (next, command)
}
