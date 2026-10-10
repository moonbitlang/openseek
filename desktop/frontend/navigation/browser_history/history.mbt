///|
priv struct Entry {
  key : String
  path : String
  original : String
} derive(Eq)

///|
/// The known segment of a browser tab's history. Browser entry keys identify
/// positions; original paths allow a covered draft to be promoted without
/// rewriting browser entries that are not currently selected.
struct History {
  prefix : String
  group : String
  previous : Array[Entry]
  current : Entry
  following : Array[Entry]
} derive(Eq)

///|
pub fn History::History(
  path : String,
  group~ : String,
  key~ : String,
) -> History {
  {
    prefix: path.split("/").take(3).join("/") + "/",
    group,
    previous: [],
    current: { key, path, original: path, },
    following: [],
  }
}

///|
pub fn History::owns(self : History, path : String) -> Bool {
  path.has_prefix(self.prefix)
}

///|
pub fn History::path(self : History) -> String {
  self.current.path
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
/// The v1 wire format is retained so already-open tabs can refresh into this
/// implementation. Missing/null/malformed fields cannot identify an entry;
/// unknown fields are ignored.
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
  let prefix = initial_path.split("/").take(3).join("/") + "/"
  let entries : Array[Entry] = []
  for item in items {
    guard item
      is {
        "key": String(key),
        "path": String(path),
        "original": String(original),
        ..
      } &&
      path.has_prefix(prefix) &&
      original.has_prefix(prefix) else {
      return None
    }
    entries.push({ key, path, original, })
  }
  select_entry(prefix, group, entries, key, pathname)
}

///|
fn select_entry(
  prefix : String,
  group : String,
  entries : Array[Entry],
  key : String,
  pathname : String,
) -> History? {
  for index, entry in entries {
    if entry.key == key &&
      (entry.path == pathname || entry.original == pathname) {
      return Some({
        prefix,
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
    self.prefix,
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
  guard self.owns(path) else { return None }
  if path == self.current.path {
    Some(self)
  } else if replace {
    Some({ ..self, current: { ..self.current, path, original: path, }, })
  } else {
    Some({
      ..self,
      previous: [..self.previous, self.current],
      current: { key, path, original: path, },
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
