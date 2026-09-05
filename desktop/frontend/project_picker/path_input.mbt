// Path-input projection for the project picker. The listing follows the
// directory the draft names: typing past a separator, or deleting back across
// one, browses that directory while the editor stays open, issuing at most one
// Host request per directory. Rows appear only once the listing is that
// directory; the segment typed after its separator narrows them, prefix
// matches first. Host-native spellings the picker cannot resolve itself
// (`~`) are browsed as typed and rewritten from the reply.

///|
fn State::editable_path(self : State) -> String {
  match self.location {
    Some(Directory(path)) => path
    Some(DriveList) => "/"
    None => ""
  }
}

///|
/// A location as the prefix of its children's paths.
fn Location::base(self : Location) -> String {
  match self {
    Directory(path) => if path.has_suffix("/") { path } else { path + "/" }
    DriveList => "/"
  }
}

///|
/// Where the draft's completions come from: the directory it names up to its
/// last separator, and the segment typed after that separator. A relative
/// draft completes inside the listed location. A draft naming the listed
/// location itself — opened and left untouched, or resumed after a browse —
/// is that location with nothing to narrow. A home-relative draft is the
/// host's to expand: its directory part goes to the host as typed, and the
/// reply supplies the expanded path the way it supplies canonical casing.
fn State::completion(self : State) -> (String, String)? {
  guard self.path_draft is Some(raw) else { return None }
  guard self.location is Some(location) else { return None }
  let draft = raw.trim().to_owned()
  if !draft.is_empty() && self.already_loaded(draft) {
    return Some((draft, ""))
  }
  // Only the home forms the host expands (`~`, `~/…`) are its to resolve —
  // any other `~`-led name is an ordinary child of the listed directory —
  // and, where the host said it is Windows, a drive-letter spelling such as
  // `C:/Users` is its own absolute form. On POSIX that same spelling is an
  // ordinary relative name — `C:` is a legal directory — so there it keeps
  // completing under the listed directory.
  let host_native = draft.has_prefix("/") ||
    draft == "~" ||
    draft.has_prefix("~/") ||
    (self.windows_host && drive_rooted(draft))
  let absolute = if host_native { draft } else { location.base() + draft }
  match absolute.rev_find("/") {
    Some(index) =>
      Some(
        (
          absolute.view(end_offset=index + 1).to_owned(),
          absolute.view(start_offset=index + 1).to_owned(),
        ),
      )
    // Only a bare `~` has no separator: the host expands it whole.
    None => Some((absolute, ""))
  }
}

///|
/// A forward-slash drive-letter spelling (`C:/…`): the Windows host's own
/// absolute form, accepted as typed. Backslash spellings never reach the
/// splitter — the listed base's separator outranks theirs — and stay
/// Enter-only.
fn drive_rooted(draft : String) -> Bool {
  match draft.iter().take(3).collect() {
    [letter, ':', '/'] => letter.is_ascii_alphabetic()
    _ => false
  }
}

///|
/// Whether the rows can complete the draft: the listing is the directory it
/// names. Until that browse answers — or when the host could not list it —
/// the rows of some other directory would only mislead, so none are shown.
fn State::listing_completes_draft(self : State) -> Bool {
  match self.completion() {
    Some((parent, _)) => self.already_loaded(parent)
    None => self.path_draft is None
  }
}

///|
/// The segment narrowing the listed rows, lowercased for matching.
fn State::path_filter(self : State) -> String {
  guard self.completion() is Some((parent, segment)) else { return "" }
  guard self.already_loaded(parent) else { return "" }
  segment.to_lower()
}

///|
/// Hide stale rows during a browse and rows that cannot complete the draft;
/// otherwise preserve directory order inside prefix and looser-contains
/// buckets.
fn State::visible_entries(self : State) -> Array[String] {
  if self.loading && self.new_folder is None {
    return []
  }
  guard self.listing_completes_draft() else { return [] }
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
    Some(Directory(path)) => path.picker_child_path(name)
    Some(DriveList) => "/" + name + "/"
    None => name
  }
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

///|
/// Whether `path` names the location the host last listed. A trailing
/// separator does not change a directory. Everything else stays exact; the
/// host decides whether alternate casing is equivalent on its platform.
fn State::already_loaded(self : State, path : String) -> Bool {
  match self.location {
    Some(Directory(current)) =>
      current == path ||
      (
        current != "/" &&
        current.trim_end(chars="/") == path.trim_end(chars="/")
      )
    Some(DriveList) => path.trim() == "/"
    None => false
  }
}

///|
/// Whether the open path editor still names the listed location: opened and
/// left untouched, or resumed after a separator-committed browse. Submitting
/// such a draft would only close the editor, so actions on the current
/// directory may close it themselves instead of waiting.
fn State::path_draft_names_location(self : State) -> Bool {
  self.path_destination() is Some(path) && self.already_loaded(path)
}
