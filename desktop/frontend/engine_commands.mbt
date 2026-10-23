///|
fn Conversation::engine_controls(self : Conversation) -> @engine_session.State {
  {
    goal: self.goal,
    edit: self.goal_edit.map(edit => edit.draft),
    pending: self.goal_pending,
    compaction: self.compaction,
  }
}

///|
fn Conversation::with_engine_controls(
  self : Conversation,
  controls : @engine_session.State,
) -> Conversation {
  {
    ..self,
    goal: controls.goal,
    goal_edit: controls.edit.map(draft => { draft, }),
    goal_pending: controls.pending,
    compaction: controls.compaction,
  }
}

///|
/// Both hosts use engine_session to interpret composer actions. Only this
/// adapter needs Local placement, launch settings and the Desktop bridge.
fn apply_engine_action(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  conv : Conversation,
  action : @engine_session.Action,
) -> (@cmd.Cmd, Model) {
  let id = "\{model.page_namespace}-submission-\{model.submission_sequence + 1}"
  let (controls, command) = conv
    .engine_controls()
    .act(action, id, conv.durable_frontier(), running=conv.is_running())
  let next = model.replace_conversation(conv.with_engine_controls(controls))
  guard command is Some(command) else { return (@cmd.none, next) }
  let (next, _) = next.allocate_submission_id()
  if command is (@wire.GoalSet(..) | @wire.GoalClear) {
    let text = match command {
      @wire.GoalSet(text~, ..) => Some(text)
      _ => None
    }
    (send_goal(dispatch, next, conv, id, text), next)
  } else {
    (send_session_command(dispatch, next, conv, id, command), next)
  }
}

///|
fn send_session_command(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  conv : Conversation,
  id : String,
  command : @wire.Command,
) -> @cmd.Cmd {
  let workspace = conv.project()
  guard @resource.belongs_to(workspace, conv.device) else { return @cmd.none }
  let payload : @protocol.SessionCommandPayload = {
    command,
    run_id: match conv.run {
      Open(run_id~, ..) => Some(run_id)
      _ => None
    },
    settings: {
      session: conv.session_id,
      model: Some(conv.engine_model.wire()),
      thinking: conv.engine_model.thinking(
        model.reasoning_for(conv.engine_model),
      ),
      max_steps: parsed_max_steps(model.max_steps),
      workspace: Some(workspace.path),
      approval: Some(model.approval_for(conv.device, conv.session_id)),
    },
  }
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      @interop.in_ordered_lane(
        @interop.session_command_lane(conv.device, conv.session_id),
        () => {
          request_session_command(scheduler, dispatch, conv.device, payload, id)
        },
      ) catch {
        _ => ()
      }
    })
    |> ignore
  })
}

///|
async fn request_session_command(
  scheduler : &@cmd.Scheduler,
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  payload : @protocol.SessionCommandPayload,
  id : String,
) -> Unit noraise {
  ignore(
    @interop.bridge_request(channel, @commands.agent_command, payload) catch {
      error => {
        let command = payload.command
        let refused = @interop.bridge_failure(error) is (Refused | Unsent)
        let message = @interop.bridge_error_text(error)
        let session = payload.settings.session
        let failure = if command is (@wire.GoalSet(..) | @wire.GoalClear) {
          let draft = match command {
            @wire.GoalSet(text~, ..) => Some(text)
            _ => None
          }
          if refused {
            GoalRejected(session~, command=id, draft~, message~)
          } else {
            GoalUndelivered(session~, command=id, draft~, message~)
          }
        } else {
          // Preserve Local's existing compact failure behavior.
          SessionCommandFailed(
            session~,
            id~,
            command~,
            refused=refused || command is @wire.Compact,
            message~,
          )
        }
        scheduler.add(dispatch(FromDevice(channel, failure)))
        return
      }
    },
  )
}
