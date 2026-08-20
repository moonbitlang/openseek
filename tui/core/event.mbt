///|
/// A user-driven UI event handed to the application loop.
pub(all) enum Event {
  Queue(Input)
  Steer(Input)
  SlashCommand(name~ : String, arguments~ : String)
  Interrupt
  Quit
} derive(Eq, Debug)

///|
#deprecated
pub extend Event with Debug::{to_repr}

///|
pub extend Event with Eq::{equal, not_equal}
