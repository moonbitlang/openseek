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
        (
          @cmd.none,
          model
          .activate(model.focused, conv.session_id, conv.project())
          .with_active_project(Some(conv.project())),
          Active,
        )
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
