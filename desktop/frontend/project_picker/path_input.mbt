// Pure path-input projection for the project picker. Typing never reaches the
// Host: it narrows the already loaded directory rows, ranks prefix matches
// first, and turns the selected row back into the same path `Navigate` uses.

///|
fn State::editable_path(self : State) -> String {
  match self.location {
    Some(Directory(resource)) => resource.path
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
    Some(Directory(resource)) => {
      let base = if resource.path.has_suffix("/") {
        resource.path
      } else {
        resource.path + "/"
      }
      let draft_lower = draft.to_lower()
      let base_lower = base.to_lower()
      if draft_lower == resource.path.to_lower() || draft_lower == base_lower {
        return ""
      }
      match draft_lower.strip_prefix(base_lower) {
        Some(suffix) => {
          let suffix = "\{suffix}"
          if suffix.contains("/") {
            ""
          } else {
            suffix
          }
        }
        None => if draft.contains("/") { "" } else { draft_lower }
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
/// Stable local filtering: directory order is preserved inside two buckets,
/// with prefix matches before looser contains matches.
fn State::visible_entries(self : State) -> Array[String] {
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
  for name in contains {
    prefixes.push(name)
  }
  prefixes
}

///|
fn State::entry_target(self : State, name : String) -> String {
  match self.location {
    Some(Directory(resource)) => resource.picker_child_path(name)
    Some(DriveList) => "/" + name + "/"
    None => name
  }
}

///|
/// Suggestions are active only for a real filter. Opening the editor with the
/// current directory prefilled must not make Enter unexpectedly choose row 0.
fn State::selected_path_suggestion(self : State) -> String? {
  guard !self.path_filter().is_empty() else { return None }
  self.visible_entries().get(self.path_selection)
}

///|
fn State::move_path_selection(self : State, delta : Int) -> State {
  guard !self.path_filter().is_empty() else { return self }
  let count = self.visible_entries().length()
  guard count > 0 else { return self }
  { ..self, path_selection: (self.path_selection + delta + count) % count }
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
