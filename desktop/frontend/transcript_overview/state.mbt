// The rail machine. `update` is pure and command-free: the cross-package
// effect of a click (scrolling the transcript, unpinning auto-follow) is the
// root update's to command off the same message.

///|
/// The tick the pointer is on, owning the preview popover. `flip` and
/// `anchor` are measured from the tick's real position when the pointer
/// entered it: the preview opens upward only when a downward one would
/// leave the scroller while up has more room, and `anchor` is the tick
/// edge it hangs from — the top, or the bottom when flipped — relative to
/// the rail's sticky container. The popover renders outside the scrollable
/// rail (a scroll container would clip it), so it cannot inherit the
/// tick's position and carries this measurement instead.
pub(all) struct Hover {
  key : TurnKey
  flip : Bool
  anchor : Double
} derive(Eq, Debug)

///|
pub(all) struct State {
  hover : Hover?
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
  // The pointer entered a tick: its preview popover opens, upward when the
  // enter-time measurement says a downward one would leave the scroller,
  // hanging from the measured `anchor` edge. The popover closes on `Left` —
  // leaving the whole rail — rather than per tick, so sliding along the
  // rail never blanks the preview between ticks.
  Entered(TurnKey, flip~ : Bool, anchor~ : Double)
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
    Entered(key, flip~, anchor~) =>
      { ..state, hover: Some({ key, flip, anchor }) }
    Left => { ..state, hover: None }
    Clicked(key) => { ..state, active: Some(key) }
    ActiveChanged(key) => { ..state, active: key }
  }
}

///|
#deprecated
pub extend Hover with Debug::{to_repr}

///|
pub extend Hover with Eq::{equal, not_equal}

///|
#deprecated
pub extend State with Debug::{to_repr}

///|
pub extend State with Eq::{equal, not_equal}
