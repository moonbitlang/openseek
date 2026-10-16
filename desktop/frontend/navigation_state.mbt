///|
priv enum NavigationMsg {
  Back
  Forward
  Retry
  SessionReady(@interop.ConversationKey, revision~ : Int32)
  CodexDraftReady(cwd~ : String, id~ : String, revision~ : Int32)
}

///|
priv enum NavigationPhase {
  Waiting
  Active
  Missing
  PreparingNew
  Failed(String)
} derive(Eq)

///|
priv struct AppNavigation {
  location : @navigation.Location?
  phase : NavigationPhase
  history : @navigation.History
  can_back : Bool
  can_forward : Bool
  sessions : Result[Unit, String]?
  archived : Result[Unit, String]?
  skills : Result[Unit, String]?
  new_chat_requested : Bool
  revision : Int32
} derive(Eq)

///|
fn AppNavigation::empty() -> AppNavigation {
  {
    location: None,
    phase: Active,
    history: @navigation.History::empty(),
    can_back: false,
    can_forward: false,
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
