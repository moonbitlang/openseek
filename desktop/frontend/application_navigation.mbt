///|
priv enum NavigationMsg {
  Back
  Forward
  Browser(@navigation_browser.Snapshot)
  Link(@url.UrlRequest)
  Retry
  SessionReady(@interop.ConversationKey, revision~ : Int)
  CodexDraftReady(cwd~ : String, id~ : String, revision~ : Int)
}

///|
priv enum NavigationPhase {
  Waiting
  Active
  Missing
  PreparingNew
  Invalid
  Failed(String)
} derive(Eq)

///|
priv struct AppNavigation {
  location : @navigation.Location?
  phase : NavigationPhase
  history : @navigation.History
  can_back : Bool
  can_forward : Bool
  browser_ready : Bool
  sessions : Result[Unit, String]?
  archived : Result[Unit, String]?
  skills : Result[Unit, String]?
  new_chat_requested : Bool
  revision : Int
} derive(Eq)

///|
fn AppNavigation::empty() -> AppNavigation {
  {
    location: None,
    phase: Active,
    history: @navigation.History::empty(),
    can_back: false,
    can_forward: false,
    browser_ready: false,
    sessions: None,
    archived: None,
    skills: None,
    new_chat_requested: false,
    revision: 0,
  }
}

///|
fn Model::request_new_navigation(self : Model) -> Model {
  {
    ..self,
    navigation: {
      ..self.navigation,
      revision: self.navigation.revision + 1,
      new_chat_requested: true,
    },
  }
}

///|
fn Model::at_blank_new_page(self : Model) -> Bool {
  guard self.navigation.phase is Active else { return false }
  match self.navigation_location() {
    Some({ target: ChatNew, .. }) => self.active_conversation() is Some(_)
    Some({ target: CodexNew, .. }) => self.codex.composing_draft()
    _ => false
  }
}

///|
/// Bootstrap-only read; update and view consume data from the model.
fn navigation_device_from_location() -> String? {
  guard @interop.js_prop(@js.globalThis, "location") is Some(location) &&
    @interop.js_prop(location, "pathname") is Some(value) &&
    (@js.Cast::into(value) : String?) is Some(path) else {
    return None
  }
  if path.split("/").collect() is ["", "device", device, ..] &&
    !device.is_empty() {
    Some(@uri.decode_component(device))
  } else {
    None
  }
}

///|
fn navigation_initial_path(return_to : String, device : String?) -> String {
  let path = return_to.split("?").next().unwrap_or(return_to[:]).to_owned()
  if path.has_prefix("/device/") {
    return path
  }
  if device is Some(device) {
    @navigation.Location::{ device, target: ChatNew, }.path()
  } else {
    path
  }
}

///|
fn Model::navigation_location(self : Model) -> @navigation.Location? {
  guard self.console.page_device is Some(device) else { return None }
  let target : @navigation.Target = match self.screen {
    Settings => Settings
    Schedules => Schedules
    Skills =>
      match self.skills.detail() {
        Some(InstalledRef(id)) => InstalledSkill(id)
        Some(MarketRef(source)) => MarketSkill(source)
        None => Skills
      }
    Codex => self.codex.navigation_target()
    Chat =>
      if self.selected_conversation is Some(selection) &&
        self.loading_conversation is Some(_) {
        Session(selection.session)
      } else if self.active_conversation() is Some(conv) {
        if conv.has_begun() ||
          self
          .focused_device()
          .map_or(false, dev => {
            dev.sessions.any(item => item.id == conv.session_id) ||
            dev.archived.any(item => item.id == conv.session_id)
          }) {
          Session(conv.session_id)
        } else if conv.draft_addressed || !conv.draft_empty() {
          ChatDraft(conv.session_id)
        } else {
          ChatNew
        }
      } else {
        ChatNew
      }
  }
  Some({ device, target, })
}

///|
fn navigation_screen(target : @navigation.Target) -> Screen {
  match target {
    Chat | ChatNew | Session(_) | ChatDraft(_) => Chat
    Codex | CodexNew | Thread(_) | CodexDraft(_) => Codex
    Settings => Settings
    Skills | InstalledSkill(_) | MarketSkill(_) => Skills
    Schedules => Schedules
  }
}

///|
fn navigation_visit(
  model : Model,
  location : @navigation.Location,
  replace~ : Bool,
) -> (@cmd.Cmd, Model) {
  let navigation = model.navigation
  let history = if model.is_desktop {
    navigation.history.visit(location, replace~)
  } else {
    navigation.history
  }
  let next = {
    ..model,
    chat_creation: if navigation.location is Some(_) {
      None
    } else {
      model.chat_creation
    },
    pending_project_adoption: if navigation.location is Some(_) {
      None
    } else {
      model.pending_project_adoption
    },
    navigation: {
      ..navigation,
      location: Some(location),
      phase: Active,
      history,
      can_back: if model.is_desktop {
        history.can_back()
      } else {
        navigation.can_back
      },
      can_forward: if model.is_desktop {
        history.can_forward()
      } else {
        navigation.can_forward
      },
      new_chat_requested: false,
      revision: if navigation.location is Some(_) {
        navigation.revision + 1
      } else {
        navigation.revision
      },
    },
  }
  (
    if !model.is_desktop && navigation.browser_ready {
      @navigation_browser.visit(location.path(), replace~)
    } else {
      @cmd.none
    },
    next,
  )
}

///|
fn update_navigation(
  dispatch : @cmd.Emit[Msg],
  message : NavigationMsg,
  model : Model,
) -> (@cmd.Cmd, Model) {
  match message {
    SessionReady(owner, revision~) => {
      guard revision == model.navigation.revision else {
        return (@cmd.none, model)
      }
      let message = SessionRotated(owner)
      let (command, next) = update_msg(dispatch, message, model)
      let next = if model.navigation.phase is PreparingNew {
        {
          ..next,
          navigation: {
            ..next.navigation,
            phase: Active,
            new_chat_requested: false,
          },
        }
      } else {
        next
      }
      let (navigation, next) = reconcile_navigation(
        dispatch, message, model, next,
      )
      (@cmd.batch([command, navigation]), next)
    }
    CodexDraftReady(cwd~, id~, revision~) => {
      guard revision == model.navigation.revision else {
        return (@cmd.none, model)
      }
      let message = CodexDraftRotated(cwd~, id~)
      let (command, next) = update_msg(dispatch, message, model)
      let next = if model.navigation.phase is PreparingNew {
        {
          ..next,
          navigation: {
            ..next.navigation,
            phase: Active,
            new_chat_requested: false,
          },
        }
      } else {
        next
      }
      let (navigation, next) = reconcile_navigation(
        dispatch, message, model, next,
      )
      (@cmd.batch([command, navigation]), next)
    }
    Back | Forward => {
      let allowed = if message is Back {
        model.navigation.can_back
      } else {
        model.navigation.can_forward
      }
      guard allowed else { return (@cmd.none, model) }
      if !model.is_desktop {
        return (
          if message is Back {
            @nav.back()
          } else {
            @nav.forward()
          },
          model,
        )
      }
      let history = if message is Back {
        model.navigation.history.back()
      } else {
        model.navigation.history.forward()
      }
      activate_navigation(dispatch, {
        ..model,
        chat_creation: None,
        pending_project_adoption: None,
        navigation: {
          ..model.navigation,
          history,
          location: history.current(),
          phase: Waiting,
          can_back: history.can_back(),
          can_forward: history.can_forward(),
          new_chat_requested: false,
          revision: model.navigation.revision + 1,
        },
      })
    }
    Browser(snapshot) => {
      let parsed = @navigation.parse(
        snapshot.path.split("?").next().unwrap_or(snapshot.path[:]).to_owned(),
      )
      let navigation = {
        ..model.navigation,
        browser_ready: true,
        can_back: snapshot.can_back,
        can_forward: snapshot.can_forward,
      }
      match parsed {
        Ok(location) if Some(location.device) == model.console.page_device => {
          let changed = navigation.location != Some(location)
          let model = {
            ..model,
            console: { ..model.console, login_return_to: snapshot.path, },
            chat_creation: if changed && navigation.location is Some(_) {
              None
            } else {
              model.chat_creation
            },
            pending_project_adoption: if changed &&
              navigation.location is Some(_) {
              None
            } else {
              model.pending_project_adoption
            },
            navigation: {
              ..navigation,
              location: Some(location),
              phase: if changed {
                Waiting
              } else {
                navigation.phase
              },
              new_chat_requested: if changed {
                false
              } else {
                navigation.new_chat_requested
              },
              revision: if changed && navigation.location is Some(_) {
                navigation.revision + 1
              } else {
                navigation.revision
              },
            },
          }
          activate_navigation(dispatch, model)
        }
        _ =>
          (
            @cmd.none,
            { ..model, navigation: { ..navigation, phase: Invalid, }, },
          )
      }
    }
    Link(request) =>
      match request {
        Internal(url) =>
          match @navigation.parse(url.path) {
            Ok(location) if Some(location.device) == model.console.page_device => {
              let (write, next) = navigation_visit(
                model,
                location,
                replace=false,
              )
              let (activate, next) = activate_navigation(dispatch, {
                ..next,
                navigation: { ..next.navigation, phase: Waiting, },
              })
              (@cmd.batch([write, activate]), next)
            }
            _ =>
              update_msg(dispatch, ExternalLinkClicked(url.to_string()), model)
          }
        External(url) => update_msg(dispatch, ExternalLinkClicked(url), model)
      }
    Retry => {
      let (live, next) = request_sessions_refresh(
        dispatch,
        model.focused,
        model,
      )
      let (archived, next) = request_archived_refresh(
        dispatch,
        model.focused,
        next,
      )
      let (skills, next) = update_msg(
        dispatch,
        Skills(@skills.RefreshCatalog),
        next,
      )
      let (activate, next) = activate_navigation(dispatch, {
        ..next,
        navigation: {
          ..next.navigation,
          phase: Waiting,
          sessions: None,
          archived: None,
          skills: None,
        },
      })
      (
        @cmd.batch([
          live,
          archived,
          skills,
          fetch_installed_skills(dispatch, model.focused),
          activate,
        ]),
        next,
      )
    }
  }
}

///|
fn replace_with_new_navigation(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  target : @navigation.Target,
) -> (@cmd.Cmd, Model) {
  guard model.console.page_device is Some(device) else {
    return (@cmd.none, model)
  }
  let (write, next) = navigation_visit(model, { device, target, }, replace=true)
  let (activate, next) = activate_navigation(dispatch, {
    ..next,
    navigation: { ..next.navigation, phase: Waiting, },
  })
  (@cmd.batch([write, activate]), next)
}

///|
fn activate_navigation(
  dispatch : @cmd.Emit[Msg],
  model : Model,
) -> (@cmd.Cmd, Model) {
  guard model.navigation.location is Some(location) else {
    return (@cmd.none, model)
  }
  let model = { ..model, screen: navigation_screen(location.target), }
  guard model.navigation.phase is Waiting else { return (@cmd.none, model) }
  // Browser authentication and device gates own connectivity UI. Do not turn
  // an unconnected or not-yet-listed target into a missing target.
  guard model.focused_device() is Some(dev) && dev.bridge is Connected else {
    return (@cmd.none, model)
  }
  let (command, next, phase) = match location.target {
    Settings => {
      let (cmd, next) = update_msg(dispatch, OpenSetup, model)
      (cmd, next, Active)
    }
    Schedules => {
      let (cmd, next) = open_schedules(dispatch, model)
      (cmd, next, Active)
    }
    Skills => {
      let (cmd, next) = update_msg(dispatch, OpenSkills, model)
      (cmd, next, Active)
    }
    Chat | Codex => {
      let target : @navigation.Target = if location.target is Chat {
        ChatNew
      } else {
        CodexNew
      }
      return replace_with_new_navigation(dispatch, model, target)
    }
    ChatNew =>
      if model.active_conversation() is Some(conv) &&
        !conv.has_begun() &&
        !conv.draft_addressed &&
        conv.draft_empty() &&
        model.loading_conversation is None {
        (@cmd.none, model, Active)
      } else if dev.target_project() is None {
        (@cmd.none, model, Active)
      } else {
        let next = model.request_new_navigation()
        (
          rotate_session(dispatch, next.focused, next.navigation.revision),
          next,
          PreparingNew,
        )
      }
    CodexNew =>
      if model.codex.composing_draft() &&
        model.codex.navigation_target() is CodexNew {
        (@cmd.none, model, Active)
      } else if !model.codex.can_start_thread() {
        (
          @cmd.none,
          { ..model, codex: model.codex.prepare_new_navigation(), },
          Active,
        )
      } else {
        let next = {
          ..model.request_new_navigation(),
          codex: model.codex.prepare_new_navigation(),
        }
        let cwd = model
          .focused_device()
          .bind(dev => dev.active_project)
          .bind(project => @resource.path_for(project, model.focused))
          .unwrap_or(model.codex.new_thread_cwd())
        (
          CodexDraftRotation::{ cwd, revision: next.navigation.revision, }.rotate(
            dispatch,
          ),
          next,
          PreparingNew,
        )
      }
    ChatDraft(id) =>
      if model.find_conversation(model.focused, id) is Some(conv) {
        (
          @cmd.none,
          {
            ..model.activate(model.focused, id, conv.project()),
            screen: Chat,
            loading_conversation: None,
          }.with_active_project(Some(conv.project())),
          Active,
        )
      } else {
        return replace_with_new_navigation(dispatch, model, ChatNew)
      }
    Session(id) =>
      if model.find_conversation(model.focused, id) is Some(conv) {
        if conv.sync is ReloadFailed(..) {
          let (cmd, next) = open_session_on(dispatch, model.focused, model, id)
          return (
            cmd,
            { ..next, navigation: { ..next.navigation, phase: Active, }, },
          )
        }
        let next = {
          ..model.activate(model.focused, id, conv.project()),
          screen: Chat,
          loading_conversation: if conv.sync is Reloading(..) {
            Some({ channel: model.focused, session: id, })
          } else {
            None
          },
        }.with_active_project(Some(conv.project()))
        (@cmd.none, next, Active)
      } else if model.session_project(model.focused, id) is Some(_) {
        let (cmd, next) = update_msg(
          dispatch,
          OpenSession(model.focused, id),
          model,
        )
        (cmd, next, Active)
      } else if dev.archived.iter().find_first(item => item.id == id)
        is Some(item) {
        let (cmd, next) = update_msg(
          dispatch,
          OpenArchivedSession(
            model.focused,
            session=id,
            workspace=item.workspace,
          ),
          model,
        )
        (cmd, next, Active)
      } else if model.navigation.sessions is Some(Err(message)) {
        (@cmd.none, model, Failed(message))
      } else if model.navigation.archived is Some(Err(message)) {
        (@cmd.none, model, Failed(message))
      } else if model.navigation.sessions is Some(Ok(_)) &&
        model.navigation.archived is Some(Ok(_)) {
        (@cmd.none, model, Missing)
      } else {
        (@cmd.none, model, Waiting)
      }
    Thread(id) => {
      let (cmd, next) = update_msg(dispatch, CodexOpenThread(id), model)
      (cmd, next, Active)
    }
    CodexDraft(id) =>
      if model.codex.restore_navigation_draft(
          dispatch.map(msg => Codex(channel=model.focused, msg)),
          model.focused,
          id,
        )
        is Some((cmd, codex)) {
        let project = @resource.of_path(model.focused, codex.new_thread_cwd())
        (cmd, { ..model, codex, }.with_active_project(project), Active)
      } else {
        return replace_with_new_navigation(dispatch, model, CodexNew)
      }
    InstalledSkill(id) | MarketSkill(id) as target => {
      let detail : @skills.Detail = if target is InstalledSkill(_) {
        InstalledRef(id)
      } else {
        MarketRef(id)
      }
      if target is InstalledSkill(_) && model.navigation.skills is None {
        return (@cmd.none, model)
      }
      if target is InstalledSkill(_) &&
        model.navigation.skills is Some(Err(message)) {
        return (
          @cmd.none,
          {
            ..model,
            navigation: { ..model.navigation, phase: Failed(message), },
          },
        )
      }
      let (cmd, skills, resolution) = model.skills.open_detail(
        dispatch.map(msg => Skills(msg)),
        model.skills_input(),
        detail,
      )
      (
        cmd,
        { ..model, skills, },
        match resolution {
          Waiting => Waiting
          Opened => Active
          Missing => Missing
          Failed(message) => Failed(message)
        },
      )
    }
  }
  (command, { ..next, navigation: { ..next.navigation, phase, }, })
}

///|
fn Msg::is_navigation_visit(self : Msg) -> Bool {
  match self {
    OpenSetup
    | OpenSchedules
    | OpenSkills
    | OpenCodex
    | OpenSession(_, _)
    | OpenSessionHere(_)
    | OpenArchivedSession(_, ..)
    | CodexOpenThread(_)
    | CodexDraftRotated(..)
    | NotificationClicked(..)
    | QuickOpen(_)
    | SchedulePage(_)
    | ProjectPicker(_)
    | ChatWorkspaceCreated(..) => true
    Skills(PreviewInstalled(_) | PreviewMarket(_) | BackToList) => true
    _ => false
  }
}

///|
fn reconcile_navigation(
  dispatch : @cmd.Emit[Msg],
  message : Msg,
  previous : Model,
  model : Model,
) -> (@cmd.Cmd, Model) {
  let mut next = {
    ..model,
    conversations: model.conversations.map(conv => {
      if !conv.draft_addressed && !conv.draft_empty() {
        { ..conv, draft_addressed: true, }
      } else {
        conv
      }
    }),
  }
  let commands : Array[@cmd.Cmd] = []
  // Readiness is independent from empty lists and errors. Only accepted
  // generation-bearing replies establish absence.
  if message is FromDevice(channel, reply) &&
    channel == model.focused &&
    model.device_state(channel) is Some(dev) {
    let navigation = match reply {
      BridgeReady =>
        { ..next.navigation, sessions: None, archived: None, skills: None, }
      SessionsLoaded(_, connection_generation~, request_generation~) if connection_generation ==
        dev.connection_generation &&
        request_generation == dev.sessions_request_generation =>
        { ..next.navigation, sessions: Some(Ok(())), }
      ArchivedLoaded(_, connection_generation~, request_generation~, ..) if connection_generation ==
        dev.connection_generation &&
        request_generation == dev.archived_request_generation =>
        { ..next.navigation, archived: Some(Ok(())), }
      SessionsFailed(message) =>
        {
          ..next.navigation,
          sessions: Some(Err(message)),
          archived: Some(Err(message)),
        }
      InstalledSkillsLoaded(_) => { ..next.navigation, skills: Some(Ok(())), }
      InstalledSkillsFailed(message) =>
        { ..next.navigation, skills: Some(Err(message)), }
      _ => next.navigation
    }
    next = { ..next, navigation, }
  }
  if !message.is_navigation_visit() &&
    !(message is SessionRotated(_)) &&
    next.navigation.phase is Active &&
    next.navigation.location is Some(current) &&
    next.navigation_location() is Some(projected) &&
    (
      (
        current.target is ChatNew &&
        projected.target is (ChatDraft(_) | Session(_))
      ) ||
      (
        current.target is CodexNew &&
        projected.target is (CodexDraft(_) | Thread(_))
      )
    ) {
    let (command, updated) = navigation_visit(next, projected, replace=true)
    commands.push(command)
    next = updated
  }
  // Codex's first send changes a local draft into a server identity even
  // while a management page covers it. Update all references in place.
  let old_codex = previous.codex.navigation_target()
  let new_codex = next.codex.navigation_target()
  if message is Codex(_, ..) &&
    old_codex is CodexDraft(_) &&
    new_codex is Thread(_) &&
    next.console.page_device is Some(device) {
    let old : @navigation.Location = { device, target: old_codex, }
    let promoted : @navigation.Location = { device, target: new_codex, }
    let history = next.navigation.history.promote(old, promoted)
    next = {
      ..next,
      navigation: {
        ..next.navigation,
        history,
        location: next.navigation.location.map(location => {
          if location == old {
            promoted
          } else {
            location
          }
        }),
      },
    }
    if !next.is_desktop && next.navigation.browser_ready {
      commands.push(@navigation_browser.promote(old.path(), promoted.path()))
    }
  }
  let explicit = message.is_navigation_visit() ||
    (message is SessionRotated(_) && previous.navigation.new_chat_requested)
  if explicit &&
    !(next.navigation.new_chat_requested &&
    next.navigation.revision != previous.navigation.revision) &&
    next.navigation_location() is Some(location) &&
    (
      Some(location) != next.navigation.location ||
      message
      is (OpenSetup
      | OpenSkills
      | OpenSchedules
      | OpenCodex
      | OpenSession(_, _)
      | OpenSessionHere(_)
      | CodexDraftRotated(..)
      | CodexOpenThread(_))
    ) {
    let (cmd, updated) = navigation_visit(next, location, replace=false)
    commands.push(cmd)
    next = updated
  } else if next.navigation.location is None &&
    next.is_desktop &&
    next.navigation_location() is Some(location) {
    let (cmd, updated) = navigation_visit(next, location, replace=true)
    commands.push(cmd)
    next = updated
  } else if message is SessionRotated(_) &&
    next.navigation.location is Some({ target: Chat | ChatNew, .. }) &&
    next.navigation_location() is Some(location) {
    let (cmd, updated) = navigation_visit(next, location, replace=true)
    commands.push(cmd)
    next = updated
  }
  // Promote newly durable OpenSeek drafts even while another page covers them.
  if next.console.page_device is Some(device) {
    for conv in next.conversations {
      if conv.has_begun() &&
        previous.find_conversation(conv.device, conv.session_id)
        is Some(old_conv) &&
        !old_conv.has_begun() {
        let old : @navigation.Location = {
          device,
          target: ChatDraft(conv.session_id),
        }
        let promoted : @navigation.Location = {
          device,
          target: Session(conv.session_id),
        }
        next = {
          ..next,
          navigation: {
            ..next.navigation,
            location: next.navigation.location.map(location => {
              if location == old {
                promoted
              } else {
                location
              }
            }),
            history: next.navigation.history.promote(old, promoted),
          },
        }
        if !next.is_desktop && next.navigation.browser_ready {
          commands.push(
            @navigation_browser.promote(old.path(), promoted.path()),
          )
        }
      }
    }
  }
  // Lifecycle fallback may retire a deleted selection; navigation keeps the
  // requested identity and renders its unavailable state instead of another chat.
  if next.navigation.phase is Active &&
    next.navigation.location is Some(location) {
    match location.target {
      Session(id) | ChatDraft(id) =>
        if next.find_conversation(next.focused, id) is None &&
          next.selected_conversation.map(selection => selection.session) !=
          Some(id) {
          next = { ..next, navigation: { ..next.navigation, phase: Waiting, }, }
        }
      _ => ()
    }
  }
  if next.navigation.phase is Active &&
    next.navigation.location is Some({ target: CodexNew, .. }) &&
    !next.codex.composing_draft() &&
    next.codex.can_start_thread() {
    next = { ..next, navigation: { ..next.navigation, phase: Waiting, }, }
  }
  let (activate, next) = activate_navigation(dispatch, next)
  commands.push(activate)
  (@cmd.batch(commands), next)
}

///|
test "global navigation preserves the visit sequence and is pure" {
  let dispatch = test_dispatch()
  let initial = { ..test_model(), is_desktop: true, }
  let (_, initial) = update(dispatch, ToggleSidebar, initial)
  let (_, settings) = update(dispatch, OpenSetup, initial)
  let (_, skills) = update(dispatch, OpenSkills, settings)
  let (_, back) = update(dispatch, Navigation(Back), skills)
  let (_, again) = update(dispatch, Navigation(Back), skills)
  assert_true(back.screen is Settings)
  assert_true(back.navigation == again.navigation)
  assert_true(skills.navigation.location is Some({ target: Skills, .. }))
  let (_, conversation) = update(dispatch, Navigation(Back), back)
  assert_true(conversation.screen is Chat)
  assert_eq(conversation.active_session, "desktop-test")
  let (_, forward) = update(dispatch, Navigation(Forward), conversation)
  assert_true(forward.screen is Settings)
  let (_, branch) = update(dispatch, OpenSchedules, forward)
  assert_true(!branch.navigation.can_forward)
}

///|
test "deep link waits for successful catalogs and does not confuse failure with absence" {
  let dispatch = test_dispatch()
  let model = {
    ..test_model(),
    navigation: {
      ..AppNavigation::empty(),
      location: Some({ device: "local", target: Session("missing"), }),
      phase: Waiting,
    },
  }
  let (_, waiting) = activate_navigation(dispatch, model)
  assert_true(waiting.navigation.phase is Waiting)
  let (_, failed) = activate_navigation(dispatch, {
    ..model,
    navigation: {
      ..model.navigation,
      sessions: Some(Err("offline")),
      archived: Some(Ok(())),
    },
  })
  assert_true(failed.navigation.phase is Failed("offline"))
  let (_, missing) = activate_navigation(dispatch, {
    ..model,
    navigation: {
      ..model.navigation,
      sessions: Some(Ok(())),
      archived: Some(Ok(())),
    },
  })
  assert_true(missing.navigation.phase is Missing)
}

///|
test "returning to a cached conversation fences a slower foreground read" {
  let dispatch = test_dispatch()
  let base = { ..test_model().with_listed(["second"]), is_desktop: true, }
  let base = {
    ..base,
    conversations: base.conversations.map(conv => {
      ..conv,
      task: "Retained draft",
    }),
  }
  let (_, base) = update(dispatch, ToggleSidebar, base)
  let (_, reading) = update(dispatch, OpenSession(Local, "second"), base)
  let (_, back) = update(dispatch, Navigation(Back), reading)
  assert_eq(back.active_session, "desktop-test")
  assert_true(back.loading_conversation is None)
  let (_, settled) = update_dev(
    dispatch,
    SessionLoaded(
      session="second",
      items=[],
      watermark=0,
      goal=None,
      goal_markers=[],
      generation=1,
    ),
    back,
  )
  assert_eq(settled.active_session, "desktop-test")
  assert_true(settled.navigation.location == back.navigation.location)
}

///|
test "opening a thread does not promote a different Codex draft" {
  let dispatch = test_dispatch()
  let (_, draft) = update(
    dispatch,
    CodexDraftRotated(cwd="/work", id="local-draft"),
    { ..test_model(), is_desktop: true, },
  )
  let (_, draft) = update(
    dispatch,
    CodexComposerAction(
      @composer.DraftPresenceChanged(
        identity={
          owner: { channel: Local, session: "local-draft", },
          archive_generation: 0,
        },
        present=true,
        cleared_source=None,
      ),
    ),
    draft,
  )
  let (_, thread) = update(dispatch, CodexOpenThread("existing-thread"), draft)
  let (_, back) = update(dispatch, Navigation(Back), thread)
  assert_true(
    back.navigation.location is Some({ target: CodexDraft("local-draft"), .. }),
  )
  assert_true(back.codex.composing_draft())
  assert_eq(back.codex.active_id(), Some("local-draft"))
}

///|
test "background rotations do not replace an explicit management destination" {
  let dispatch = test_dispatch()
  let (_, settings) = update(dispatch, OpenSetup, {
    ..test_model(),
    is_desktop: true,
  })
  let (_, late) = update(
    dispatch,
    SessionRotated({ channel: Local, session: "late", }),
    settings,
  )
  assert_true(late.screen is Settings)
  assert_true(late.navigation.location == settings.navigation.location)
  assert_true(late.navigation.history == settings.navigation.history)
}

///|
test "allocated drafts cannot overtake a newer navigation intent" {
  let dispatch = test_dispatch()
  let (_, settings) = update(dispatch, OpenSetup, {
    ..test_model(),
    is_desktop: true,
  })
  let (_, first) = update(dispatch, NewChat, settings)
  let first_revision = first.navigation.revision
  let (_, second) = update(dispatch, NewChat, first)
  let (_, stale) = update(
    dispatch,
    Navigation(
      SessionReady(
        { channel: Local, session: "stale", },
        revision=first_revision,
      ),
    ),
    second,
  )
  assert_true(stale.navigation == second.navigation)
  assert_true(stale.find_conversation(Local, "stale") is None)
  let (_, settings) = update(dispatch, OpenSetup, second)
  let (_, late) = update(
    dispatch,
    Navigation(
      CodexDraftReady(
        cwd="/work",
        id="late",
        revision=second.navigation.revision,
      ),
    ),
    settings,
  )
  assert_true(late.screen is Settings)
  assert_true(late.codex == settings.codex)
}

///|
test "leaving a pending workspace allocation cannot adopt its delayed result" {
  let dispatch = test_dispatch()
  let (_, initial) = update(dispatch, ToggleSidebar, {
    ..test_model(),
    is_desktop: true,
  })
  let (_, creating) = update(dispatch, CreateChat(Local), initial)
  assert_true(creating.chat_creation is Some(_))
  let (_, settings) = update(dispatch, OpenSetup, creating)
  assert_true(settings.chat_creation is None)
  let (_, late) = update(
    dispatch,
    ChatWorkspaceCreated(
      channel=Local,
      generation=creating.chat_creation_sequence,
      result=Ok("/new-work"),
    ),
    settings,
  )
  assert_true(late.pending_project_adoption is None)
  assert_true(late.navigation == settings.navigation)
}

///|
test "blank new entries gain a stable draft identity only after content" {
  let dispatch = test_dispatch()
  let (_, blank) = update(dispatch, ToggleSidebar, {
    ..test_model(),
    is_desktop: true,
  })
  assert_true(blank.navigation.location is Some({ target: ChatNew, .. }))
  let other_default = { ..blank, default_agent: CodexAgent, }
  let (_, unchanged) = update(dispatch, NewChat, other_default)
  let (_, repeated) = update(dispatch, NewChat, other_default)
  assert_true(unchanged.navigation == other_default.navigation)
  assert_true(repeated.navigation == unchanged.navigation)
  assert_eq(unchanged.active_session, blank.active_session)
  let (_, duplicate) = update(dispatch, NewChat, blank)
  assert_true(duplicate.navigation == blank.navigation)
  assert_eq(duplicate.active_session, blank.active_session)
  let identity : @composer.Identity = {
    owner: { channel: Local, session: blank.active_session, },
    archive_generation: 0,
  }
  let action = ComposerAction(
    @composer.DraftPresenceChanged(identity~, present=true, cleared_source=None),
  )
  let (_, draft) = update(dispatch, action, blank)
  let (_, repeated) = update(dispatch, action, blank)
  assert_true(draft.navigation == repeated.navigation)
  assert_true(
    draft.navigation.location is Some({ target: ChatDraft("desktop-test"), .. }),
  )
  assert_true(!draft.navigation.can_back)
  let (_, cleared) = update(
    dispatch,
    ComposerAction(
      @composer.DraftPresenceChanged(
        identity~,
        present=false,
        cleared_source=None,
      ),
    ),
    draft,
  )
  assert_true(cleared.navigation.location == draft.navigation.location)
  assert_true(
    cleared.active_conversation() is Some(conv) && conv.worth_keeping(),
  )
  let (_, other) = update(
    dispatch,
    SessionRotated({ channel: Local, session: "other", }),
    cleared,
  )
  assert_true(other.find_conversation(Local, "desktop-test") is Some(_))
}

///|
test "expired draft replaces its entry with a fresh new page" {
  let dispatch = test_dispatch()
  let expired : @navigation.Location = {
    device: "local",
    target: ChatDraft("expired"),
  }
  let base = {
    ..test_model(),
    is_desktop: true,
    conversations: test_model().conversations.map(conv => {
      ..conv,
      task: "Keep existing input",
      draft_addressed: true,
    }),
    navigation: {
      ..AppNavigation::empty(),
      location: Some(expired),
      phase: Waiting,
      history: @navigation.History::empty().visit(expired, replace=true),
    },
  }
  let (_, pending) = activate_navigation(dispatch, base)
  assert_true(pending.navigation.location is Some({ target: ChatNew, .. }))
  assert_true(pending.navigation.phase is PreparingNew)
  let (_, fresh) = update(
    dispatch,
    Navigation(
      SessionReady(
        { channel: Local, session: "fresh", },
        revision=pending.navigation.revision,
      ),
    ),
    pending,
  )
  assert_true(fresh.navigation.phase is Active)
  assert_true(fresh.navigation.location is Some({ target: ChatNew, .. }))
  assert_eq(fresh.active_session, "fresh")
  assert_true(fresh.selected_conversation is Some({ session: "fresh", .. }))
  assert_true(fresh.active_conversation() is Some(conv) && conv.draft_empty())
  assert_true(!fresh.navigation.can_back)
  assert_true(
    fresh.find_conversation(Local, "desktop-test") is Some(conv) &&
    conv.task == "Keep existing input",
  )
}
