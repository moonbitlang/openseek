// The composer's `!` mode at the application root. A command runs in a
// terminal tab of its conversation's workspace — where the user can watch it
// and interrupt it — and when that tab reports, its output is sent the way a
// typed message is: it starts a turn while the conversation is idle, and
// steers or queues behind an open one. The agent therefore answers a command's
// output like any other message, and nothing about delivery is special to `!`.

///|
/// How long a `!` command waits for its conversation's checkout to become
/// known before it is handed back: `ShellPlacementRetries` checks,
/// `ShellPlacementRetryMs` apart.
const ShellPlacementRetries = 30

///|
const ShellPlacementRetryMs = 100

///|
/// The conversation whose `!` command `id` is still running.
fn Model::conversation_by_shell(self : Model, id : String) -> Conversation? {
  self.conversations
  .iter()
  .find_first(conv => conv.shell_commands.any(pending => pending.id == id))
}

///|
/// A `!` command was submitted from `conv`'s composer: list it as running and
/// start it. A fresh worktree-mode conversation creates its worktree first,
/// as its first prompt or goal would.
fn submit_shell_command(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  conv : Conversation,
  command : String,
) -> (@cmd.Cmd, Model) {
  // Advancing the submission sequence is the composer's acceptance signal: it
  // clears the `!` draft the way it clears a sent prompt. The id it mints
  // names the command's terminal tab.
  let (model, id) = model.allocate_submission_id()
  let model = model.replace_conversation({
    ..conv,
    task: "",
    images: [],
    mentions: [],
    composer_draft_present: false,
    shell_commands: [..conv.shell_commands, { id, command, }],
  })
  match conv.goal_creates_worktree() {
    Some(workspace) =>
      (
        run_shell_in_new_worktree(
          locale=model.locale,
          dispatch,
          conv.device,
          conv.session_id,
          workspace,
          id~,
          command~,
        ),
        model,
      )
    None =>
      run_shell_command(
        dispatch,
        model,
        conv.device,
        conv.session_id,
        id,
        command,
        0,
      )
  }
}

///|
/// Open the terminal tab that runs `!` command `id`.
fn run_shell_command(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  channel : @interop.ChannelId,
  session : String,
  id : String,
  command : String,
  attempt : Int,
) -> (@cmd.Cmd, Model) {
  // The tab belongs to the command's conversation, which need not be the one
  // on screen by now: project that conversation, as a send does.
  let target = {
    ..model,
    screen: Chat,
    focused: channel,
    active_session: session,
  }
  match
    model.terminal.run_command(
      dispatch.map(next => Terminal(next)),
      target.terminal_input(),
      shell=id,
      command~,
      on_screen=model.screen is Chat &&
        model.focused == channel &&
        model.active_session == session,
    ) {
    @terminal.CommandStarted(cmd, terminal) => (cmd, { ..model, terminal, })
    // A worktree created a moment ago is bound before its registry row
    // arrives (`worktree.changed`), and the terminal needs that row to know
    // the checkout. Ask again shortly, for a bounded while.
    @terminal.CommandUnresolved if attempt < ShellPlacementRetries =>
      (
        @cmd.delay(
          dispatch(
            RunShellCommand(
              channel~,
              session~,
              id~,
              command~,
              attempt=attempt + 1,
            ),
          ),
          ShellPlacementRetryMs,
        ),
        model,
      )
    @terminal.CommandUnresolved | @terminal.CommandUnavailable =>
      shell_not_started(
        dispatch,
        model,
        channel,
        session,
        id,
        shell_text(model.locale, ShellTerminalUnavailable),
      )
  }
}

///|
/// `!` command `id` never ran: retire its row, say why, and hand the command
/// back to the composer the way a rejected prompt restores its draft. Newer
/// writing there is never overwritten.
fn shell_not_started(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  channel : @interop.ChannelId,
  session : String,
  id : String,
  message : String,
) -> (@cmd.Cmd, Model) {
  guard model.find_conversation(channel, session) is Some(conv) &&
    conv.shell_commands.iter().find_first(pending => pending.id == id)
    is Some(pending) else {
    return (@cmd.none, model)
  }
  let restore = conv.task.is_blank() && !conv.composer_draft_present
  model
  .replace_conversation({
    ..conv,
    shell_commands: conv.shell_commands.filter(other => other.id != id),
    task: if restore {
      "!" + pending.command
    } else {
      conv.task
    },
    composer_draft_present: conv.composer_draft_present || restore,
  })
  .notify_error(dispatch, message)
}

///|
/// The terminal tab of `!` command `shell` reported: the command is over.
/// `exit_code` is `None` when it did not exit on its own account (its tab was
/// closed, its connection dropped, a signal killed it), and `output` is the
/// plain text its terminal showed. The result is wrapped in the
/// `<user_shell_command>` envelope — which the transcript renders as a card —
/// and sent.
fn shell_command_finished(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  shell : String,
  exit_code : Int?,
  output : String,
  truncated : Bool,
) -> (@cmd.Cmd, Model) {
  guard model.conversation_by_shell(shell) is Some(conv) &&
    conv.shell_commands.iter().find_first(pending => pending.id == shell)
    is Some(pending) else {
    return (@cmd.none, model)
  }
  let conv = {
    ..conv,
    shell_commands: conv.shell_commands.filter(other => other.id != shell),
  }
  send_shell_result(
    dispatch,
    model.replace_conversation(conv),
    conv,
    @command_context.encode(
      pending.command,
      Ok({ exit_code, text: output, output_limit_reached: truncated, }),
    ),
  )
}

///|
/// Send a `!` command's result as a message from `conv`, through the same
/// `Send` a typed message takes. The user's own unsent draft is set aside for
/// the send and put back afterwards.
///
/// When it cannot be sent, the result waits in the composer, ahead of the
/// user's own text, to be sent by hand: a command's output is never dropped.
/// That happens when `Send` declines (a compaction in progress, a turn being
/// cancelled, a device that is away), and when `conv` lives on a device other
/// than the focused one — the page mirrors host settings (credentials,
/// follow-up behavior) for the focused device only, so it cannot send on
/// another device's terms.
fn send_shell_result(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  conv : Conversation,
  envelope : String,
) -> (@cmd.Cmd, Model) {
  let held = {
    ..conv,
    task: if conv.task.is_blank() {
      envelope
    } else {
      envelope + "\n\n" + conv.task
    },
    composer_draft_present: true,
    // The draft now holds the result, so it is no longer the edit of a queued
    // message: saving it must not rewrite that message, and the reply to an
    // edit already in flight must not clear it.
    queue_edit_id: None,
  }
  guard model.focused == conv.device else {
    return (@cmd.none, model.replace_conversation(held))
  }
  let target = {
    ..model.replace_conversation({
      ..conv,
      task: envelope,
      mentions: [],
      images: [],
      composer_draft_present: true,
      // The result is a new message, never an edit of a queued one.
      queue_edit_id: None,
    }),
    active_session: conv.session_id,
  }
  // Only the conversation on screen is re-pinned to its newest message.
  let visible = model.screen is Chat && model.active_session == conv.session_id
  let (cmd, sent) = update_msg(
    dispatch,
    if visible {
      Send
    } else {
      SendInBackground
    },
    target,
  )
  let sent = { ..sent, active_session: model.active_session, }
  guard sent.find_conversation(conv.device, conv.session_id) is Some(after) else {
    return (cmd, sent)
  }
  let after = if after.task == envelope {
    // `Send` declined and left the draft where it was.
    held
  } else {
    {
      ..after,
      task: conv.task,
      mentions: conv.mentions,
      images: conv.images,
      composer_draft_present: conv.composer_draft_present,
      queue_edit_id: conv.queue_edit_id,
    }
  }
  (cmd, sent.replace_conversation(after))
}
