// Workspace registry transitions shared by conversations.

///|
/// Adopt one canonical workspace registry snapshot. Conversations from a
/// detached workspace leave this page with its sidebar section: their durable
/// records stay on disk and return when the directory is attached again. If
/// the active conversation leaves, select the newest remaining durable chat,
/// or rotate into a fresh scratch chat when none remains.
fn adopt_workspaces(
  dispatch : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
  model : Model,
  paths : Array[@common.Uri],
) -> (@cmd.Cmd, Model) {
  guard model.device_state(channel) is Some(dev) else {
    return (@cmd.none, model)
  }
  let active_detached = channel == model.focused &&
    model.find_conversation(channel, model.active_session) is Some(active) &&
    active.workspace is Some(workspace) &&
    !paths.contains(workspace)
  let active_workspace = if dev.active_workspace is None ||
    (dev.active_workspace is Some(active) && paths.contains(active)) {
    dev.active_workspace
  } else {
    None
  }
  // Each workspace's worktree list refreshes with the adopted registry; a
  // detached workspace's cached rows drop with its section. One request
  // token covers the whole fan-out round.
  let worktrees_request_generation = dev.worktrees_request_generation + 1
  let commands : Array[@cmd.Cmd] = []
  for path in paths {
    commands.push(
      fetch_worktrees(
        dispatch,
        channel,
        path,
        dev.connection_generation,
        worktrees_request_generation,
      ),
    )
  }
  let worktrees = dev.worktrees.filter(group => paths.contains(group.workspace))
  // The old whole-session snapshot can outlive the workspace commit
  // broadcast. Prune it immediately so neither the sidebar nor fallback
  // selection can retain a conversation whose store is no longer attached.
  let sessions = dev.sessions.filter(item => {
    item.workspace is None ||
    (item.workspace is Some(workspace) && paths.contains(workspace))
  })
  let conversations = model.conversations.filter(conv => {
    conv.device != channel ||
    conv.workspace is None ||
    (conv.workspace is Some(workspace) && paths.contains(workspace))
  })
  let loading_conversation = if model.loading_conversation is Some(owner) &&
    owner.channel == channel &&
    !conversations
    .iter()
    .any(conv => {
      conv.device == owner.channel && conv.session_id == owner.session
    }) {
    None
  } else {
    model.loading_conversation
  }
  let (refresh_cmd, next) = request_sessions_refresh(dispatch, channel, {
    ..model.replace_device({
      ..dev,
      sessions,
      workspaces: paths,
      active_workspace,
      worktrees,
      worktrees_request_generation,
    }),
    conversations,
    loading_conversation,
  })
  commands.push(refresh_cmd)
  if active_detached {
    if sessions.get(0) is Some(fallback) {
      // The retained list is newest-first. Activate its first entry before
      // starting the reload so no render can address the detached session id
      // as an empty scratch conversation while the snapshot is in flight.
      let activated = {
        ..next.activate(channel, fallback.id),
        transcript_pinned: true,
      }.with_active_workspace(fallback.workspace)
      let activated = activated.replace_conversation({
        ..activated.active(),
        workspace: fallback.workspace,
      })
      let (fallback_cmd, next) = open_session_on(
        dispatch,
        channel,
        activated,
        fallback.id,
      )
      commands.push(fallback_cmd)
      return (@cmd.batch(commands), next)
    }
    // Session ids are generated inside a Cmd so update remains pure. Clear
    // the dead identity now; SessionRotated installs the fresh scratch chat
    // on the next update-loop turn, exactly as it does at app startup.
    commands.push(rotate_session(dispatch, channel))
    return (
      @cmd.batch(commands),
      {
        ..next,
        active_session: "",
        loading_conversation: None,
        screen: Chat,
        transcript_pinned: true,
        completion: None,
      },
    )
  }
  (@cmd.batch(commands), next)
}
