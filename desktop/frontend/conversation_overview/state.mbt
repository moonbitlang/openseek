// The conversation overview: a column of cards beside the transcript that
// says where the conversation runs and what its engine is connected to.
// Whether the overview is on screen is the root's preference; how it is
// drawn — a rail beside the conversation, or a panel over it when the
// conversation column is too narrow to share — is decided by the stylesheet
// from the main pane's width, so this package keeps only which cards are
// folded.

///|
/// One card of the overview.
pub(all) enum Section {
  Environment
  Connectors
} derive(Eq, Debug)

///|
pub extend Section with Eq::{equal, not_equal}

///|
pub extend Section with @debug.Debug::{to_repr}

///|
pub(all) enum Msg {
  /// The user clicked a card's title.
  Toggled(Section)
}

///|
/// Which cards show their rows. A folded card keeps its title and summary.
pub struct State {
  environment_open : Bool
  connectors_open : Bool
} derive(Eq)

///|
pub extend State with Eq::{equal, not_equal}

///|
/// The environment is what the overview is for, so it starts unfolded; the
/// connectors start as their one-line summary.
pub fn State::initial() -> State {
  { environment_open: true, connectors_open: false, }
}

///|
pub fn State::is_open(self : State, section : Section) -> Bool {
  match section {
    Environment => self.environment_open
    Connectors => self.connectors_open
  }
}

///|
pub fn update(msg : Msg, state : State) -> State {
  match msg {
    Toggled(Environment) =>
      { ..state, environment_open: !state.environment_open, }
    Toggled(Connectors) => { ..state, connectors_open: !state.connectors_open, }
  }
}
