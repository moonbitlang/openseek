// Path-input projection for the project picker. Ordinary typing narrows the
// already loaded directory rows and ranks prefix matches first. A separator
// after an exact loaded child commits that child immediately, avoiding a stale
// parent listing while still issuing at most one Host request per directory.

///|
fn State::editable_path(self : State) -> String {
  match self.location {
    Some(Directory(path)) => path
    Some(DriveList) => "/"
    None => ""
  }
}

///|
/// The part of the draft that can describe a child of the current listing.
/// An absolute path under another parent remains directly submittable but does
/// not pretend that the current directory's rows are its completions.
fn State::path_filter(self : State) -> String {
  guard self.path_draft is Some(raw) else { return "" }
  let draft = raw.trim().to_owned()
  match self.location {
    Some(Directory(path)) => {
      let base = if path.has_suffix("/") { path } else { path + "/" }
      if draft == path || draft == base {
        return ""
      }
      match draft.strip_prefix(base) {
        Some(suffix) => {
          let suffix = "\{suffix}".to_lower()
          if suffix.contains("/") {
            ""
          } else {
            suffix
          }
        }
        None => if draft.contains("/") { "" } else { draft.to_lower() }
      }
    }
    Some(DriveList) => {
      let query = match draft.to_lower().strip_prefix("/") {
        Some(suffix) => "\{suffix}"
        None => draft.to_lower()
      }
      if query.contains("/") {
        ""
      } else {
        query
      }
    }
    None => ""
  }
}

///|
/// Hide stale rows during a browse; otherwise preserve directory order inside
/// prefix and looser-contains buckets.
fn State::visible_entries(self : State) -> Array[String] {
  if self.loading && self.new_folder is None {
    return []
  }
  let query = self.path_filter()
  if query.is_empty() {
    return self.entries
  }
  let prefixes : Array[String] = []
  let contains : Array[String] = []
  for name in self.entries {
    let candidate = name.to_lower()
    if candidate.has_prefix(query) {
      prefixes.push(name)
    } else if candidate.contains(query) {
      contains.push(name)
    }
  }
  [..prefixes, ..contains]
}

///|
fn State::entry_target(self : State, name : String) -> String {
  match self.location {
    Some(Directory(path)) => path.picker_child_path(name)
    Some(DriveList) => "/" + name + "/"
    None => name
  }
}

///|
/// A trailing separator commits one child from the Host-validated listing.
/// Other paths remain editable and require Enter.
fn State::committed_child_path(self : State, raw : String) -> String? {
  let draft = raw.trim().to_owned()
  guard draft.has_suffix("/") else { return None }
  // DriveList proves Windows semantics. A directory shaped like `/c:/...`
  // may instead be a legal POSIX path, so its identity stays case-sensitive.
  let case_insensitive = self.location is Some(DriveList)
  let key = fn(path : String) -> String {
    if case_insensitive {
      path.to_lower()
    } else {
      path
    }
  }
  let draft = key(draft)
  for name in self.entries {
    let target = self.entry_target(name)
    let path = if target.has_suffix("/") { target } else { target + "/" }
    if draft == key(path) || draft == key(name + "/") {
      return Some(path)
    }
  }
  None
}

///|
/// Suggestions are active only for a real filter. Opening the editor with the
/// current directory prefilled must not make Enter unexpectedly choose row 0.
fn State::selected_path_suggestion(self : State) -> String? {
  guard !self.path_filter().is_empty() else { return None }
  let visible = self.visible_entries()
  guard self.path_draft is Some(raw) else { return None }
  let draft = raw.trim()
  // An exact loaded child is already complete, even when a longer sibling
  // sorts ahead of it after refiltering (`better` beside `betterment`).
  for name in visible {
    if draft == self.entry_target(name) {
      return None
    }
  }
  guard visible.get(self.path_selection) is Some(name) else { return None }
  Some(name)
}

///|
fn State::move_path_selection(self : State, delta : Int) -> State {
  guard !self.path_filter().is_empty() else { return self }
  let count = self.visible_entries().length()
  guard count > 0 else { return self }
  { ..self, path_selection: (self.path_selection + delta + count) % count, }
}

///|
/// Enter accepts the highlighted local completion when one exists; otherwise
/// it submits the trimmed draft verbatim for normal Host validation.
fn State::path_destination(self : State) -> String? {
  match self.selected_path_suggestion() {
    Some(name) => Some(self.entry_target(name))
    None =>
      match self.path_draft {
        Some(raw) => {
          let path = raw.trim()
          if path.is_empty() {
            None
          } else {
            Some(path.to_owned())
          }
        }
        None => None
      }
  }
}
