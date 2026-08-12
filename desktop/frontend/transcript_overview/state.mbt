// The rail machine. `update` is pure and command-free: the cross-package
// effect of a click (scrolling the transcript, unpinning auto-follow) is the
// root update's to command off the same message.

///|
pub(all) struct State {
  // The tick the pointer is on, owning the preview popover.
  hover : TurnKey?
  // The turn the transcript viewport currently reads, highlighted on the
  // rail. Reported by the root's scroll watcher.
  active : TurnKey?
} derive(Eq, Debug)

///|
pub fn State::empty() -> State {
  { hover: None, active: None }
}

///|
pub(all) enum Msg {
  // The pointer entered a tick: its preview popover opens. The popover
  // closes on `Left` — leaving the whole rail — rather than per tick, so
  // sliding along the rail never blanks the preview between ticks.
  Entered(TurnKey)
  Left
  // A tick was clicked. The highlight moves eagerly on the click's own
  // render; the scroll watcher would only confirm it after the jump settles.
  Clicked(TurnKey)
  // Which turn the transcript viewport sits in, `None` above the first one.
  ActiveChanged(TurnKey?)
}

///|
pub fn update(msg : Msg, state : State) -> State {
  match msg {
    Entered(key) => { ..state, hover: Some(key) }
    Left => { ..state, hover: None }
    Clicked(key) => { ..state, active: Some(key) }
    ActiveChanged(key) => { ..state, active: key }
  }
}
