// The conversation overview: a column of cards beside the transcript that
// says which pull requests and branches the conversation works on,
// and what it runs in the background.
// Whether the overview is on screen is the root's preference; how it is
// drawn — a rail beside the conversation, or a panel over it when the
// conversation column is too narrow to share — is decided by the stylesheet
// from the main pane's width, so this package keeps only which cards are
// folded.

///|
/// One card of the overview.
#derive(Eq, Debug)
pub(all) enum Section {
  Changes
  BackgroundTasks
}

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
#derive(Eq)
pub struct State {
  changes_open : Bool
  tasks_open : Bool
}

///|
pub extend State with Eq::{equal, not_equal}

///|
/// Changes starts unfolded. The background tasks card starts folded.
pub fn State::initial() -> State {
  { changes_open: true, tasks_open: false, }
}

///|
pub fn State::is_open(self : State, section : Section) -> Bool {
  match section {
    Changes => self.changes_open
    BackgroundTasks => self.tasks_open
  }
}

///|
pub fn update(msg : Msg, state : State) -> State {
  match msg {
    Toggled(Changes) => { ..state, changes_open: !state.changes_open, }
    Toggled(BackgroundTasks) => { ..state, tasks_open: !state.tasks_open, }
  }
}
