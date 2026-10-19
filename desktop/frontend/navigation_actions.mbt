///|
fn navigation_visit(
  model : Model,
  location : @routes.Location,
  replace~ : Bool,
) -> (@cmd.Cmd, Model) {
  let navigation = model.navigation
  let history = if model.is_desktop || !navigation.browser_ready {
    navigation.history.visit(location, replace~)
  } else {
    navigation.history
  }
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
      history,
      can_back: if model.is_desktop || !navigation.browser_ready {
        history.can_back()
      } else {
        navigation.can_back
      },
      can_forward: if model.is_desktop || !navigation.browser_ready {
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
      if location.path() is Some(path) {
        @navigation_browser.visit(path, replace~)
      } else if location.target is Settings {
        @navigation_browser.visit_settings(replace~)
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
    Back | Forward => {
      let allowed = if message is Back {
        model.navigation.can_back
      } else {
        model.navigation.can_forward
      }
      guard allowed else { return (@cmd.none, model) }
      if !model.is_desktop && model.navigation.browser_ready {
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
        pending_project_adoption: history
        .current()
        .bind(location => model.project_adoption_at(location)),
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
    Browser(snapshot) => apply_browser_navigation(dispatch, snapshot, model)
    Link(request) => follow_navigation_link(dispatch, request, model)
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
