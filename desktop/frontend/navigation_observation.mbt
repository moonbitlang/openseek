///|
/// Facts accepted by the application update. This adapter alone interprets
/// root messages and compares domain state; history policy consumes these facts.
priv struct NavigationObservation {
  location : @routes.Location?
  user_visit : Bool
  session_rotated : Bool
  explicit : Bool
  repeat_visit : Bool
  retired : Array[String]
  promotion : (@routes.Location, @routes.Location)?
  durable : Array[(@routes.Location, @routes.Location)]
}

///|
fn Msg::is_navigation_visit(self : Msg) -> Bool {
  match self {
    OpenSetup
    | Ssh(Open)
    | OpenSchedules
    | OpenSkills
    | OpenCodex
    | OpenCloudConversation(..)
    | CloudAction(@cloud.Create)
    | OpenSession(_, _)
    | OpenSessionHere(_)
    | OpenArchivedSession(_, ..)
    | CodexOpenThread(_)
    | CodexDraftRotated(..)
    | NotificationClicked(..)
    | QuickOpen(_)
    | SchedulePage(_)
    | ProjectPicker(_) => true
    Skills(PreviewInstalled(_) | PreviewMarket(_) | BackToList) => true
    _ => false
  }
}

///|
fn observe_navigation_catalogs(message : Msg, model : Model) -> AppNavigation {
  // Readiness is independent from empty lists and errors. Only accepted
  // generation-bearing replies establish absence.
  if message is FromDevice(channel, reply) &&
    channel == model.focused &&
    model.device_state(channel) is Some(dev) {
    let navigation = match reply {
      BridgeReady =>
        { ..model.navigation, sessions: None, archived: None, skills: None, }
      SessionsLoaded(_, connection_generation~, request_generation~) if connection_generation ==
        dev.connection_generation &&
        request_generation == dev.sessions_request_generation =>
        { ..model.navigation, sessions: Some(Ok(())), }
      ArchivedLoaded(_, connection_generation~, request_generation~, ..) if connection_generation ==
        dev.connection_generation &&
        request_generation == dev.archived_request_generation =>
        { ..model.navigation, archived: Some(Ok(())), }
      ArchivedFailed(message~, connection_generation~, request_generation~) if connection_generation ==
        dev.connection_generation &&
        request_generation == dev.archived_request_generation =>
        { ..model.navigation, archived: Some(Err(message)), }
      SessionsFailed(message~, connection_generation~, request_generation~) if connection_generation ==
        dev.connection_generation &&
        request_generation == dev.sessions_request_generation =>
        {
          ..model.navigation,
          sessions: Some(Err(message)),
          archived: Some(Err(message)),
        }
      InstalledSkillsLoaded(_) => { ..model.navigation, skills: Some(Ok(())), }
      InstalledSkillsFailed(message) =>
        { ..model.navigation, skills: Some(Err(message)), }
      _ => model.navigation
    }
    return navigation
  }
  model.navigation
}

///|
fn observe_navigation(
  message : Msg,
  previous : Model,
  next : Model,
) -> NavigationObservation {
  let old_codex = previous.codex.navigation_target()
  let new_codex = next.codex.navigation_target()
  let promotion : (@routes.Location, @routes.Location)? = if message
    is (ModelPicked(_, ..)
    | ComposerAction(@composer.ModelSelected(..))
    | CodexComposerAction(@composer.ModelSelected(..))) &&
    previous.screen != next.screen &&
    previous.navigation_location() is Some(old) &&
    next.navigation_location() is Some(promoted) {
    Some((old, promoted))
  } else if message is CloudAction(@cloud.Created(epoch, request, session)) &&
    epoch == previous.cloud.epoch &&
    previous.cloud.creation is Some(creation) &&
    creation.request == request &&
    next.cloud.creation is None &&
    previous.cloud.user_id is Some(account) {
    Some(
      (
        {
          device: None,
          target: CloudDraft(account=Some(account), id=creation.id),
        },
        { device: None, target: CloudSession(account=Some(account), session~), },
      ),
    )
  } else if message is Codex(_, ..) &&
    old_codex is CodexDraft(_) &&
    new_codex is Thread(_) &&
    next.console.page_device is Some(device) {
    Some(
      (
        { device: Some(device), target: old_codex, },
        { device: Some(device), target: new_codex, },
      ),
    )
  } else {
    None
  }
  // A successful RPC may settle in the background or be rejected as stale.
  // Only the accepted foreground transition owns a new history entry.
  let fork_opened = message is ForkCompleted(pending, Ok(reply), ..) &&
    previous.conversation_fork == Some(pending) &&
    previous.screen is Chat &&
    previous.navigation.phase is Active &&
    previous.navigation.location is Some({ target: Session(source), .. }) &&
    source == pending.source.session &&
    previous.conversation_selection() == Some(pending.source) &&
    next
    .conversation_selection()
    .map(selection => (selection.channel, selection.session)) ==
    Some((pending.source.channel, reply.session))
  // A cleared selection on a Cloud URL is not a visit: it keeps that URL's
  // unavailable state instead of falling back to the Cloud landing page.
  let cloud_opened = message is (CloudAction(_) | AccountLoaded(_, _)) &&
    (next.cloud_identity() is Some(_) || next.cloud_draft_identity() is Some(_)) &&
    next.selected_conversation != previous.selected_conversation
  let explicit = message.is_navigation_visit() ||
    cloud_opened ||
    fork_opened ||
    (message is SessionRotated(_) && previous.navigation.new_chat_requested)
  // Conversations this page itself deleted. Their replacement draft takes
  // over the current entry; a delete from elsewhere is only observed through
  // the missing target.
  let retired : Array[String] = match message {
    FromDevice(channel, SessionsChanged(change="deleted", key~, ..)) if channel ==
      previous.focused &&
      previous.owns_deletion(channel, key) => [key.session]
    // Only a reply the update accepts removed anything; a stale one is
    // discarded there and must not move navigation either.
    FromDevice(
      channel,
      ArchivedDeleted(
        sessions~,
        connection_generation~,
        request_generation~,
        ..
      )
    ) if channel == previous.focused &&
      previous.device_state(channel) is Some(dev) &&
      connection_generation == dev.connection_generation &&
      request_generation == dev.archived_request_generation => sessions
    _ => []
  }
  let durable : Array[(@routes.Location, @routes.Location)] = []
  if next.console.page_device is Some(device) {
    for conv in next.conversations {
      if conv.has_begun() &&
        previous.find_conversation(conv.device, conv.session_id) is Some(old) &&
        !old.has_begun() {
        durable.push(
          (
            { device: Some(device), target: ChatDraft(conv.session_id), },
            { device: Some(device), target: Session(conv.session_id), },
          ),
        )
      }
    }
  }
  {
    location: next.navigation_location(),
    user_visit: message.is_navigation_visit() || cloud_opened,
    session_rotated: message is SessionRotated(_),
    explicit,
    repeat_visit: message
    is (OpenSetup
    | Ssh(Open)
    | OpenSkills
    | OpenSchedules
    | OpenCodex
    | OpenSession(_, _)
    | OpenSessionHere(_)
    | CodexDraftRotated(..)
    | CodexOpenThread(_)),
    retired,
    promotion,
    durable,
  }
}
