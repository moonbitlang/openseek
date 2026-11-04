///|
/// What the page itself holds: the filter box's text. The rows come from the
/// stores the shell owns, so they are inputs, not page state.
#derive(Eq, Debug)
pub struct State {
  query : String
}

///|
/// The page as it opens: an empty filter.
pub fn State::empty() -> State {
  { query: "", }
}

///|
pub(all) enum Msg {
  QueryChanged(String)
}

///|
pub fn State::update(_ : State, msg : Msg) -> State {
  match msg {
    QueryChanged(query) => { query, }
  }
}

///|
pub extend State with Debug::{to_repr}

///|
pub extend State with Eq::{equal, not_equal}
