///|
fn Model::session_starts_emit(
  self : Model,
  emit : @cmd.Emit[Msg],
  channel : @interop.ChannelId,
) -> @cmd.Emit[@session_start.Msg] {
  let connection_generation = self
    .device_state(channel)
    .map(dev => dev.connection_generation)
    .unwrap_or(0)
  emit.map(msg => SessionStarts(channel~, connection_generation~, msg))
}

///|
fn Model::fetch_session_starts(
  self : Model,
  channel : @interop.ChannelId,
  session : String,
  emit : @cmd.Emit[@session_start.Msg],
) -> @cmd.Cmd {
  let source = self
    .find_conversation(channel, session)
    .map(conv => conv.session_start_source())
    .unwrap_or({ session, workspace: None, archived: false, })
  @session_start.fetch(channel, source, emit)
}

///|
fn Model::session_start_here_available(
  self : Model,
  conv : Conversation,
) -> Bool {
  !conv.is_archived_read_only() &&
  !self.scheduled_session_read_only(conv) &&
  conv.pending_semantic_submission is None &&
  !conv.saving_queue_edit() &&
  (if conv.is_running() {
    conv.run is Open(stage~, ..) && !(stage is Cancelling)
  } else {
    conv.compaction is NotCompacting
  })
}

///|
fn open_session_start_target(
  emit : @cmd.Emit[Msg],
  model : Model,
  target : String,
) -> (@cmd.Cmd, Model) {
  guard model.console.page_device is Some(device) &&
    model.focused_device() is Some(dev) else {
    return (@cmd.none, model)
  }
  let (write, next) = navigation_visit(
    model,
    { device: Some(device), target: Session(target), },
    replace=false,
  )
  let commands = [write]
  let known = model.find_conversation(model.focused, target) is Some(_) ||
    model.session_project(model.focused, target) is Some(_) ||
    dev.archived.any(item => item.id == target)
  let next = if known {
    next
  } else {
    // A durable suggestion names its target, but cannot assert that the target
    // is still live. Resolve unknown identities through the ordinary catalogs.
    let (live, next) = request_sessions_refresh(emit, model.focused, next)
    let (archived, next) = request_archived_refresh(emit, model.focused, next)
    commands.push(live)
    commands.push(archived)
    {
      ..next,
      navigation: { ..next.navigation, sessions: None, archived: None, },
    }
  }
  let (activate, next) = activate_navigation(emit, {
    ..next,
    navigation: { ..next.navigation, phase: Waiting, },
  })
  commands.push(activate)
  (@cmd.batch(commands), next)
}

///|
fn Conversation::session_start_source(
  self : Conversation,
) -> @session_start.Source {
  {
    session: self.session_id,
    workspace: Some(self.project().path),
    archived: self.record is ArchivedRecord,
  }
}
