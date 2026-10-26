///|
fn submit_cloud_shell(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  owner : @interop.ConversationIdentity,
  command : String,
) -> (@cmd.Cmd, Model) {
  guard owner is @interop.Cloud(account~, session~) &&
    model.cloud.user_id == Some(account) &&
    model.cloud.can_compose(session) &&
    model.cloud.conversations.get(session) is Some(conv) &&
    conv.outgoing is None else {
    return (@cmd.none, model)
  }
  let (model, id) = model.allocate_submission_id()
  let shell : ShellCommand = { id, command, }
  let conversations = model.cloud.conversations.copy()
  conversations[session] = {
    ..conv,
    shell_commands: [..conv.shell_commands, shell],
    submission_sequence: conv.submission_sequence + 1,
    initial_submission: None,
    initial_attachments: [],
  }
  let model = { ..model, cloud: { ..model.cloud, conversations, }, }
  if model.cloud.draft_identity() == Some(owner) {
    update_cloud(dispatch, @cloud.TerminalRequested(owner, Some(shell)), model)
  } else {
    run_cloud_shell(dispatch, model, owner, shell)
  }
}

///|
fn run_cloud_shell(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  owner : @interop.ConversationIdentity,
  shell : ShellCommand,
) -> (@cmd.Cmd, Model) {
  guard owner is @interop.Cloud(account~, session~) else {
    return (@cmd.none, model)
  }
  let target = {
    ..model,
    screen: Chat,
    selected_conversation: Some(CloudSelection(account~, session~)),
  }
  match
    model.terminal.run_command(
      dispatch.map(msg => Terminal(msg)),
      target.terminal_input(),
      shell=shell.id,
      command=shell.command,
      on_screen=model.screen is Chat && model.cloud_identity() == Some(owner),
    ) {
    @terminal.CommandStarted(command, terminal) =>
      (command, { ..model, terminal, })
    @terminal.CommandUnavailable | @terminal.CommandUnresolved =>
      cloud_shell_not_started(
        dispatch,
        model,
        shell.id,
        shell_text(model.locale, ShellTerminalUnavailable),
      )
  }
}

///|
fn cloud_shell_not_started(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  id : String,
  message : String,
) -> (@cmd.Cmd, Model) {
  guard model.cloud.user_id is Some(account) &&
    model.cloud.conversations
    .iter()
    .find_first(pair => pair.1.shell_commands.any(p => p.id == id))
    is Some((session, conv)) &&
    conv.shell_commands.iter().find_first(p => p.id == id) is Some(pending) else {
    return (@cmd.none, model)
  }
  let conversations = model.cloud.conversations.copy()
  conversations[session] = {
    ..conv,
    shell_commands: conv.shell_commands.filter(p => p.id != id),
  }
  let model = { ..model, cloud: { ..model.cloud, conversations, }, }
  let owner = @interop.Cloud(account~, session~)
  let restore = model
    .command_result_input(owner)
    .map_or(@cmd.none, input => {
      dispatch(
        ComposerCommandResult(@composer.Restore(input, "!" + pending.command)),
      )
    })
  let (report, model) = model.notify_error(dispatch, message)
  (@cmd.batch([report, restore]), model)
}
