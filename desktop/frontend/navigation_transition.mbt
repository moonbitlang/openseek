///|
priv enum NavigationWrite {
  Keep
  Push(@routes.Location)
  Replace(@routes.Location)
}

///|
/// Decide whether an accepted update owns a history entry. Background results
/// can replace an identity, but cannot acquire a new foreground visit.
fn NavigationObservation::write(
  self : NavigationObservation,
  navigation : AppNavigation,
  previous_revision : Int32,
  desktop~ : Bool,
) -> NavigationWrite {
  guard self.location is Some(location) else { return Keep }
  if self.explicit &&
    !(navigation.new_chat_requested && navigation.revision != previous_revision) &&
    (Some(location) != navigation.location || self.repeat_visit) {
    Push(location)
  } else if navigation.location is None && desktop {
    Replace(location)
  } else if self.session_rotated &&
    navigation.location is Some({ target: Chat | ChatNew, .. }) {
    Replace(location)
  } else if navigation.location is Some(current) &&
    current != location &&
    current.target is (Session(id) | ChatDraft(id)) &&
    self.retired.contains(id) {
    Replace(location)
  } else {
    Keep
  }
}

///|
fn NavigationObservation::addresses_blank(
  self : NavigationObservation,
  navigation : AppNavigation,
) -> Bool {
  guard !self.user_visit &&
    !self.session_rotated &&
    navigation.phase is Active &&
    navigation.location is Some(current) &&
    self.location is Some(projected) else {
    return false
  }
  (current.target is ChatNew && projected.target is (ChatDraft(_) | Session(_))) ||
  (
    current.target is CodexNew &&
    projected.target is (CodexDraft(_) | Thread(_))
  )
}

///|
fn promote_navigation(
  model : Model,
  old : @routes.Location,
  promoted : @routes.Location,
) -> (@cmd.Cmd, Model) {
  let navigation = model.navigation
  (
    if !model.is_desktop &&
      navigation.browser_ready &&
      old.path() is Some(old_path) &&
      promoted.path() is Some(new_path) {
      @navigation_browser.promote(old_path, new_path)
    } else {
      @cmd.none
    },
    {
      ..model,
      navigation: {
        ..navigation,
        history: navigation.history.promote(old, promoted),
        location: navigation.location.map(location => {
          if location == old {
            promoted
          } else {
            location
          }
        }),
      },
    },
  )
}
