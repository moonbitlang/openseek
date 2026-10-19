///|
priv struct Entry {
  key : String
  path : String
  original : String
  // Device-less Settings covers the current addressable page until refresh.
  settings : Bool
} derive(Eq)

///|
/// The known segment of a browser tab's history. Browser entry keys identify
/// positions; original records the path actually written to each browser
/// entry. Covered entries retain that path across identity promotions.
struct History {
  device : String?
  group : String
  previous : Array[Entry]
  current : Entry
  following : Array[Entry]
} derive(Eq)

///|
/// Compare valid destinations using the shared codec. Keep invalid paths intact
/// so the application can display its invalid-route state.
fn canonical_path(path : String) -> String {
  match @routes.parse(path) {
    Ok(location) => location.path().unwrap_or(path)
    Err(_) => path
  }
}

///|
pub fn History::History(
  path : String,
  group~ : String,
  key~ : String,
) -> History {
  let original = path
  let path = canonical_path(path)
  {
    device: @routes.device(path),
    group,
    previous: [],
    current: { key, path, original, settings: false, },
    following: [],
  }
}

///|
pub fn History::owns(self : History, path : String) -> Bool {
  @routes.is_cloud_path(path) ||
  (self.device is Some(device) && @routes.device(path) == Some(device))
}

///|
pub fn History::path(self : History) -> String {
  self.current.path
}

///|
pub fn History::settings(self : History) -> Bool {
  self.current.settings
}

///|
pub fn History::visit_settings(
  self : History,
  replace~ : Bool,
  key~ : String,
) -> History {
  if self.current.settings {
    self
  } else if replace {
    { ..self, current: { ..self.current, settings: true, }, }
  } else {
    {
      ..self,
      previous: [..self.previous, self.current],
      current: {
        key,
        path: self.current.path,
        original: self.current.path,
        settings: true,
      },
      following: [],
    }
  }
}

///|
/// Acknowledge that the adapter wrote the current canonical path. Only this
/// entry changed in the browser; covered entries still have their old URLs.
pub fn History::written(self : History) -> History {
  { ..self, current: { ..self.current, original: self.current.path, }, }
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
/// Missing/null/malformed fields cannot identify an entry; unknown fields are
/// ignored.
pub fn storage_group(marker : Json) -> String? {
  match marker {
    { "group": String(group), .. } => Some(group)
    _ => None
  }
}

///|
pub fn History::marker(self : History) -> Json {
  { "group": self.group, "key": self.current.key }
}

///|
pub fn History::stored(self : History) -> Json {
  let entries = [..self.previous, self.current, ..self.following]
  {
    "entries": entries.map(entry => {
      "key": entry.key,
      "path": entry.path,
      "original": entry.original,
    }),
  }
}

///|
pub fn History::storage_group(self : History) -> String {
  self.group
}

///|
pub fn History::restore(
  initial_path : String,
  pathname : String,
  marker : Json,
  stored : Json,
) -> History? {
  guard marker is { "group": String(group), "key": String(key), .. } &&
    stored is { "entries": Array(items), .. } else {
    return None
  }
  let mut device = @routes.device(initial_path)
  if device is None && !@routes.is_cloud_path(initial_path) {
    return None
  }
  let entries : Array[Entry] = []
  for item in items {
    guard item
      is {
        "key": String(key),
        "path": String(path),
        "original": String(original),
        ..
      } else {
      return None
    }
    for candidate in [path, original] {
      if @routes.device(candidate) is Some(owner) {
        if device is Some(existing) && existing != owner {
          return None
        }
        device = Some(owner)
      } else if !@routes.is_cloud_path(candidate) {
        return None
      }
    }
    entries.push({ key, path: canonical_path(path), original, settings: false, })
  }
  select_entry(device, group, entries, key, pathname)
}

///|
fn select_entry(
  device : String?,
  group : String,
  entries : Array[Entry],
  key : String,
  pathname : String,
) -> History? {
  let canonical = canonical_path(pathname)
  for index, entry in entries {
    if entry.key == key &&
      (entry.path == canonical || canonical_path(entry.original) == canonical) {
      return Some({
        device,
        group,
        previous: entries[:index].to_owned(),
        current: entry,
        following: entries[index + 1:].to_owned(),
      })
    }
  }
  None
}

///|
/// None means that the browser reached an entry outside the known segment.
/// The host starts a fresh segment there (or reloads for another device).
pub fn History::select(
  self : History,
  pathname : String,
  marker : Json,
) -> History? {
  guard marker is { "group": String(group), "key": String(key), .. } &&
    group == self.group else {
    return None
  }
  select_entry(
    self.device,
    group,
    [..self.previous, self.current, ..self.following],
    key,
    pathname,
  )
}

///|
pub fn History::visit(
  self : History,
  path : String,
  replace~ : Bool,
  key~ : String,
) -> History? {
  let path = canonical_path(path)
  guard self.owns(path) else { return None }
  if path == self.current.path && !self.current.settings {
    Some(self)
  } else if replace {
    Some({
      ..self,
      current: { ..self.current, path, original: path, settings: false, },
    })
  } else {
    Some({
      ..self,
      previous: [..self.previous, self.current],
      current: { key, path, original: path, settings: false, },
      following: [],
    })
  }
}

///|
pub fn History::promote(
  self : History,
  old_path : String,
  new_path : String,
) -> History? {
  let old_path = canonical_path(old_path)
  let new_path = canonical_path(new_path)
  guard self.owns(new_path) else { return None }
  let promote = (entry : Entry) => {
    if entry.path == old_path {
      { ..entry, path: new_path, }
    } else {
      entry
    }
  }
  Some({
    ..self,
    previous: self.previous.map(promote),
    current: promote(self.current),
    following: self.following.map(promote),
  })
}

///|
pub extend History with Eq::{equal, not_equal}
