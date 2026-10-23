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
  let (controls, command) = conv.controls.act(
    action,
    id,
    conv.durable_frontier(),
    running=conv.is_running(),
  )
  let next = model.replace_conversation({ ..conv, controls, })
  guard command is Some(command) else { return (@cmd.none, next) }
  let (next, _) = next.allocate_submission_id()
  (send_session_command(dispatch, next, conv, id, command), next)
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
      moonbit_guide: Some(conv.moonbit_guide),
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
  if command is (@wire.GoalSet(..) | @wire.GoalClear) &&
    conv.goal_creates_worktree() is Some(workspace) {
    return send_command_in_new_worktree(
      model.locale,
      dispatch,
      conv.device,
      workspace,
      payload,
      id,
    )
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
  let result = @interop.bridge_request(
    channel, @commands.agent_command, payload,
  ) catch {
    error => {
      let refused = @interop.bridge_failure(error) is (Refused | Unsent)
      scheduler.add(
        dispatch(
          FromDevice(
            channel,
            SessionCommandDelivered(
              session=payload.settings.session,
              id~,
              command=payload.command,
              // Preserve Local's existing compact transport-failure presentation.
              delivery=if refused || payload.command is @wire.Compact {
                @engine_session.Rejected
              } else {
                @engine_session.Unknown
              },
              message=Some(@interop.bridge_error_text(error)),
            ),
          ),
        ),
      )
      return
    }
  }
  scheduler.add(
    dispatch(
      FromDevice(
        channel,
        SessionCommandDelivered(
          session=payload.settings.session,
          id~,
          command=payload.command,
          delivery=if result.accepted {
            @engine_session.Accepted
          } else {
            @engine_session.Rejected
          },
          message=if result.accepted {
            None
          } else {
            Some("The host did not accept the command")
          },
        ),
      ),
    ),
  )
}
