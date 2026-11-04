///|
fn navigation_visit(
  model : Model,
  location : @routes.Location,
  replace~ : Bool,
) -> (@cmd.Cmd, Model) {
  let navigation = model.navigation
  let next = {
    ..model,
    pending_project_adoption: if navigation.location is Some(_) {
      model.project_adoption_at(location)
    } else {
      model.pending_project_adoption
    },
    navigation: {
      ..navigation,
      location: Some(location),
      phase: Active,
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
      if location.path() is Some(path) {
        @navigation_browser.visit(path, replace~)
      } else {
        @cmd.none
      }
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
    Browser(snapshot) => apply_browser_navigation(dispatch, snapshot, model)
    Link(request) => follow_navigation_link(dispatch, request, model)
    Retry => {
      let (projects, model) = if model.focused_device() is Some(dev) &&
        !(dev.project_catalog is Some(Ok(_))) {
        let generation = dev.projects_request_generation + 1
        (
          fetch_projects(
            dispatch,
            model.focused,
            dev.connection_generation,
            generation,
          ),
          model.replace_device({
            ..dev,
            projects_request_generation: generation,
            project_catalog: None,
          }),
        )
      } else {
        (@cmd.none, model)
      }
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
      let (activate, next) = activate_navigation(dispatch, {
        ..next,
        navigation: {
          ..next.navigation,
          phase: Waiting,
          sessions: None,
          archived: None,
        },
      })
      (@cmd.batch([projects, live, archived, activate]), next)
    }
  }
}
