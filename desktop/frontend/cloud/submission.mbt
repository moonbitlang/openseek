///|
/// Keep one pending command on the conversation across session creation.
fn State::submit_command(
  self : State,
  session : String,
  submission : PendingCommand,
  emit : @cmd.Emit[Msg],
  token : String,
  navigation : Int32,
) -> (State, @cmd.Cmd) {
  let conversation = self.conversations[session]
  guard conversation.outgoing is None else { return (self, @cmd.none) }
  let next = { ..self, sequence: submission.request, notice: None, }.replace(
    session,
    { ..conversation, outgoing: Some(submission), },
  )
  if self.creation is Some(creation) && creation.id == session {
    return (
      {
        ..next,
        creation: Some({ ..creation, request: submission.request, navigation, }),
      },
      run(emit, () => {
        Created(
          self.epoch,
          submission.request,
          required_string(
            request(CloudOrigin, "/v1/sessions", Post, token~),
            "id",
          ),
        ) catch {
          @cloud_client.RequestError(error) =>
            CreateFailed(self.epoch, submission.request, error)
          _ => CreateFailed(self.epoch, submission.request, Unreachable)
        }
      }),
    )
  }
  next.send_pending(session, Some(token), emit)
}

///|
/// Called once observation is ready; reconnecting never repeats an HTTP handoff.
fn State::send_pending(
  self : State,
  session : String,
  token : String?,
  emit : @cmd.Emit[Msg],
) -> (State, @cmd.Cmd) {
  let conversation = self.conversations[session]
  guard token is Some(token) && conversation.outgoing is Some(submission) else {
    return (self, @cmd.none)
  }
  let request = submission.request
  let conversation = {
    ..conversation,
    // Fence history reads begun before this command, including its refusal.
    request,
    outgoing: None,
    watch_status: Watching,
  }
  let conversation = match submission.input {
    Native(_) => conversation
    Prompt(content~, ..) => {
      let tasks = conversation.records
        .filter(record => record.kind == "user")
        .map(record => record.task_id)
      if conversation.task is Some(task) && !tasks.contains(task) {
        tasks.push(task)
      }
      {
        ..conversation.clear_progress(),
        send_request: request,
        sending: true,
        heartbeat: Some({
          stage: @composer.Starting,
          started_ms: None,
          tokens: 0,
        }),
        history_required: true,
        notice: None,
        pending: Some({ content, known_tasks: tasks, }),
      }
    }
  }
  let effect = @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let result : Result[ControlResult, Failure] = try {
        let (command, task_id) = match submission.input {
          Native(command) =>
            (command, conversation.control.bind(c => c.active_task_id))
          Prompt(draft~, attachments~, ..) => {
            let prepared = prepare_submission(
              token,
              session,
              draft,
              attachments,
              conversation.uploads,
              (source, path) => {
                scheduler.add(
                  emit(
                    AttachmentStored(self.epoch, session, request, source, path),
                  ),
                )
              },
            )
            let content = prompt_content(prepared)
            scheduler.add(
              emit(
                MessagePrepared(self.epoch, session, request, prepared, content),
              ),
            )
            (@wire.Prompt(content~, submission_id=None), None)
          }
        }
        Ok(send_command(token, session, command, task_id?))
      } catch {
        @cloud_client.RequestError(failure) => Err(failure)
        _ => Err(Unreachable)
      }
      let message = match (submission.input, result) {
        (Native(command), Ok(result)) =>
          CommandFinished(
            self.epoch,
            session,
            request.to_string(),
            command,
            result,
          )
        (Native(command), Err(failure)) =>
          CommandFailed(
            self.epoch,
            session,
            request.to_string(),
            command,
            failure,
          )
        (Prompt(..), Ok(Accepted)) => SendAccepted(self.epoch, session, request)
        (Prompt(..), Ok(Rejected(_))) =>
          SendFailed(self.epoch, session, request, Busy)
        (Prompt(..), Err(failure)) =>
          SendFailed(self.epoch, session, request, failure)
      }
      scheduler.add(emit(message))
    })
    |> ignore
  })
  (self.replace(session, conversation), effect)
}
