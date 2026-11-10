///|
/// The page each sidebar mode last showed. Chat and Work are different
/// backends — Cloud conversations and a host's projects — so each mode keeps
/// its own main column, and the header switch returns to it. A Work page also
/// names its device channel: the location's device is the page's, while the
/// desktop window holds several channels.
#derive(Eq)
priv struct ModeReturns {
  chat : @routes.Location?
  work : (@interop.ChannelId, @routes.Location)?
}

///|
fn ModeReturns::empty() -> ModeReturns {
  { chat: None, work: None, }
}

///|
fn location_mode(location : @routes.Location) -> @sidebar.Mode {
  if location.target.is_cloud() {
    ChatMode
  } else {
    WorkMode
  }
}

///|
/// Whether picking `mode` in the sidebar header moves the main column: the
/// page on screen belongs to the other mode. Picking the mode already on
/// screen only changes the list, and a page without a host shows Chat alone.
fn Model::mode_switch_moves_column(self : Model, mode : @sidebar.Mode) -> Bool {
  self.has_host() &&
  self.navigation.location is Some(location) &&
  location_mode(location) != mode
}

///|
/// Record the settled page as its mode's return. A page still loading, or one
/// that turned out missing, leaves the previous return in place.
fn Model::remember_mode_return(self : Model) -> Model {
  guard self.has_host() &&
    self.navigation.phase is Active &&
    self.navigation.location is Some(location) else {
    return self
  }
  let mode_returns = match location_mode(location) {
    ChatMode => { ..self.mode_returns, chat: Some(location), }
    WorkMode => { ..self.mode_returns, work: Some((self.focused, location)), }
  }
  if mode_returns == self.mode_returns {
    self
  } else {
    { ..self, mode_returns, }
  }
}

///|
/// Where switching to `mode` lands, with the channel a Work page needs
/// focused. A remembered conversation deleted since falls back to the mode's
/// fresh page: Cloud home for Chat, a new chat in the last project for Work.
fn Model::mode_destination(
  self : Model,
  mode : @sidebar.Mode,
) -> (@interop.ChannelId, @routes.Location) {
  match mode {
    ChatMode => {
      let location = match self.mode_returns.chat {
        Some({ target: CloudSession(session~, ..), .. }) if self.cloud.retired.contains(
            session,
          ) => None
        other => other
      }
      (self.focused, location.unwrap_or({ device: None, target: Cloud, }))
    }
    WorkMode => {
      let fresh : @routes.Location = {
        device: self.console.page_device,
        target: ChatNew,
      }
      guard self.mode_returns.work is Some((channel, location)) &&
        self.device_state(channel) is Some(dev) else {
        return (self.focused, fresh)
      }
      let available = match location.target {
        Session(id) | ChatDraft(id) =>
          self.find_conversation(channel, id) is Some(_) ||
          dev.sessions.any(item => item.id == id) ||
          dev.archived.any(item => item.id == id)
        _ => true
      }
      (channel, if available { location } else { fresh })
    }
  }
}

///|
/// Open the page `mode` last showed. The conversation being left keeps
/// running in its own backend, with its draft, so switching back restores it.
/// This is a foreground visit: it adds a history entry, and `update` counts it
/// as a navigation for the pending sign-in and SSH intents it fences.
fn switch_mode_column(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  mode : @sidebar.Mode,
  replace~ : Bool,
) -> (@cmd.Cmd, Model) {
  let (channel, location) = model.mode_destination(mode)
  let (focus, model) = focus_channel(dispatch, model, channel)
  // A Work page resolves against the conversation its device still holds;
  // the Cloud selection being left must not cover it.
  let model = if mode is WorkMode {
    { ..model, selected_conversation: None, }
  } else {
    model
  }
  let (write, next) = navigation_visit(model, location, replace~)
  let (activate, next) = activate_navigation(dispatch, {
    ..next,
    navigation: { ..next.navigation, phase: Waiting, },
  })
  // Opening a Cloud row closes the narrow drawer; the switch keeps it open
  // so the list just picked stays in view.
  (
    @cmd.batch([focus, write, activate]),
    { ..next, sidebar_mode: mode, sidebar_open: model.sidebar_open, },
  )
}

///|
/// Apply the stored pick once the start page is known. A blank Work start page
/// reopens in Chat when Chat was the last mode; a page the URL names, or one
/// that is already Cloud, stays.
fn settle_launch_mode(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> (@cmd.Cmd, Model) {
  guard model.launch_mode is Some(mode) &&
    model.navigation.location is Some(location) else {
    return (@cmd.none, model)
  }
  let model = { ..model, launch_mode: None, }
  guard mode is ChatMode && location.target is (Chat | ChatNew) else {
    return (@cmd.none, model)
  }
  switch_mode_column(
    dispatch,
    {
      ..model,
      chat_navigation_generation: model.chat_navigation_generation + 1,
    },
    ChatMode,
    replace=true,
  )
}
