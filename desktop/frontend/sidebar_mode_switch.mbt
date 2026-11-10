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
/// Follow a promoted identity, as the history entries do: a draft that became
/// its conversation while the other mode was on screen reopens as that
/// conversation.
fn ModeReturns::promote(
  self : ModeReturns,
  old : @routes.Location,
  promoted : @routes.Location,
) -> ModeReturns {
  {
    chat: if self.chat == Some(old) {
      Some(promoted)
    } else {
      self.chat
    },
    work: match self.work {
      Some((channel, location)) if location == old => Some((channel, promoted))
      other => other
    },
  }
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
  // Cloud home shows a draft at `/cloud`; remember the draft itself so its
  // promotion to a conversation can find this return.
  let location : @routes.Location = match
    (location.target, self.cloud_draft_identity()) {
    (Cloud, Some(@interop.Cloud(account~, session=id))) =>
      { device: None, target: CloudDraft(account=Some(account), id~), }
    _ => location
  }
  match location_mode(location) {
    ChatMode if self.mode_returns.chat != Some(location) =>
      { ..self, mode_returns: { ..self.mode_returns, chat: Some(location), }, }
    WorkMode if self.mode_returns.work != Some((self.focused, location)) =>
      {
        ..self,
        mode_returns: {
          ..self.mode_returns,
          work: Some((self.focused, location)),
        },
      }
    _ => self
  }
}

///|
/// Where switching to `mode` lands, with the channel a Work page needs
/// focused. A remembered conversation deleted since, a Cloud draft no longer
/// pending, or a Cloud page of an account no longer signed in, falls back to the mode's fresh page: Cloud
/// home for Chat, a new chat in the last project for Work. A missing Work
/// draft needs no check here: activation replaces it with a new chat itself.
fn Model::mode_destination(
  self : Model,
  mode : @sidebar.Mode,
) -> (@interop.ChannelId, @routes.Location) {
  match mode {
    ChatMode => {
      let location = match self.mode_returns.chat {
        Some({ target: CloudDraft(account=Some(owner), id~), .. }) if self.cloud.draft_identity() !=
          Some(@interop.Cloud(account=owner, session=id)) => None
        Some({ target: CloudSession(account=Some(owner), ..), .. }) if self.cloud.user_id !=
          Some(owner) => None
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
        Session(id) =>
          self.session_project(channel, id) is Some(_) ||
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
/// This is a foreground visit: it adds a history entry and retires the
/// pending sign-in and SSH intents that `chat_navigation_generation` fences.
fn switch_mode_column(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  mode : @sidebar.Mode,
  replace~ : Bool,
) -> (@cmd.Cmd, Model) {
  let (channel, location) = model.mode_destination(mode)
  let (focus, next) = focus_channel(dispatch, model, channel)
  let next = {
    ..next,
    chat_navigation_generation: next.chat_navigation_generation + 1,
    // A Work page resolves against the conversation its device still holds;
    // the Cloud selection being left must not cover it.
    selected_conversation: if mode is WorkMode {
      None
    } else {
      next.selected_conversation
    },
  }
  let (enter, next) = enter_location(dispatch, next, location, replace~)
  // Opening a Cloud row closes the narrow drawer; the switch keeps it open
  // so the list just picked stays in view.
  (
    @cmd.batch([focus, enter]),
    {
      ..next,
      sidebar_mode: mode,
      sidebar_open: model.sidebar_open,
      mode_switch_revision: if next.navigation.phase is PreparingNew {
        Some(next.navigation.revision)
      } else {
        None
      },
    },
  )
}

///|
/// Whether `msg` brings the new chat a mode switch left preparing.
fn Model::completes_mode_switch(self : Model, msg : Msg) -> Bool {
  match msg {
    Navigation(SessionReady(_, revision~) | CodexDraftReady(revision~, ..)) =>
      self.mode_switch_revision == Some(revision)
    _ => false
  }
}

///|
/// Apply a stored Chat pick once the start page is known: a blank Work start
/// page reopens in Chat. A page the URL names, or one that is already Cloud,
/// stays.
fn settle_launch_mode(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> (@cmd.Cmd, Model) {
  guard model.reopen_in_chat && model.navigation.location is Some(location) else {
    return (@cmd.none, model)
  }
  let model = { ..model, reopen_in_chat: false, }
  guard location.target is (Chat | ChatNew) else { return (@cmd.none, model) }
  switch_mode_column(dispatch, model, ChatMode, replace=true)
}
