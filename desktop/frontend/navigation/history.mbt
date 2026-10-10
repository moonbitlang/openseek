///|
/// Window-local history for the desktop adapter. Browser history is owned by
/// the browser; its adapter reports the current entry instead of mirroring it.
struct History {
  previous : Array[Location]
  current : Location?
  following : Array[Location]
} derive(Eq)

///|
pub fn History::empty() -> History {
  { previous: [], current: None, following: [], }
}

///|
pub fn History::current(self : History) -> Location? {
  self.current
}

///|
pub fn History::can_back(self : History) -> Bool {
  !self.previous.is_empty()
}

///|
pub fn History::can_forward(self : History) -> Bool {
  !self.following.is_empty()
}

///|
pub fn History::visit(
  self : History,
  location : Location,
  replace~ : Bool,
) -> History {
  if self.current == Some(location) {
    return self
  }
  if replace || self.current is None {
    { ..self, current: Some(location), }
  } else {
    {
      previous: [
        ..self.previous,
        ..self.current.map(value => [value]).unwrap_or([]),
      ],
      current: Some(location),
      following: [],
    }
  }
}

///|
pub fn History::back(self : History) -> History {
  guard self.previous is [.. rest, last] else { return self }
  {
    previous: rest.to_owned(),
    current: Some(last),
    following: [
      ..self.current.map(value => [value]).unwrap_or([]),
      ..self.following,
    ],
  }
}

///|
pub fn History::forward(self : History) -> History {
  guard self.following is [first, .. rest] else { return self }
  {
    previous: [
      ..self.previous,
      ..self.current.map(value => [value]).unwrap_or([]),
    ],
    current: Some(first),
    following: rest.to_owned(),
  }
}

///|
/// Promotion changes identity everywhere, including entries behind management
/// pages, without recording another user visit.
pub fn History::promote(
  self : History,
  old : Location,
  next : Location,
) -> History {
  {
    previous: self.previous.map(entry => if entry == old { next } else { entry }),
    current: self.current.map(entry => if entry == old { next } else { entry }),
    following: self.following.map(entry => {
      if entry == old {
        next
      } else {
        entry
      }
    }),
  }
}

///|
pub extend History with Eq::{equal, not_equal}
