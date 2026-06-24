// The composer's completion menu: typing a leading `/` lists built-in
// conversation commands, a leading `$` lists installed skills whose name is
// dropped into the prompt. Both filter as the user types and are driven from
// the model so the keyboard (↑/↓, Enter/Tab, Esc) and the popup view stay in
// sync.

///|
/// The built-in slash commands, in menu order. `command` is the id
/// `CompletionAccept` matches to run the action; the label is what the user
/// both sees and types.
fn slash_command_items() -> Array[CompletionItem] {
  [
    {
      label: "/compact",
      detail: "Summarize and shrink this conversation's context",
      command: "compact",
      insert: "",
    },
  ]
}

///|
/// Build the composer completion menu for a draft, or `None` when the draft
/// does not begin with a live trigger. The menu opens on a leading `/`
/// (commands) or `$` (installed skills) and stays open only while the token
/// after the trigger holds no spaces — once the user types past the word, the
/// command or mention is complete and the menu closes. The highlight resets to
/// the first row on every rebuild, since filtering reorders what is shown.
fn compute_completion(
  text : String,
  installed : Array[@transcript.InstalledSkillItem],
) -> Completion? {
  if text.has_prefix("/") {
    let query = trigger_query(text)
    guard query is Some(query) else { return None }
    let items = slash_command_items().filter(item => {
      completion_matches(query, [item.label])
    })
    if items.is_empty() {
      None
    } else {
      Some({ kind: SlashCommands, items, selected: 0 })
    }
  } else if text.has_prefix("$") {
    let query = trigger_query(text)
    guard query is Some(query) else { return None }
    let items : Array[CompletionItem] = []
    for skill in installed {
      if completion_matches(query, [skill.name, skill.description]) {
        items.push({
          label: "$" + skill.name,
          detail: skill.description,
          command: "",
          insert: skill.name + " ",
        })
      }
    }
    if items.is_empty() {
      None
    } else {
      Some({ kind: SkillMentions, items, selected: 0 })
    }
  } else {
    None
  }
}

///|
/// The text after a single-character trigger, or `None` once it contains a
/// space — the marker the user has finished the command/mention word and the
/// menu should close. The trigger is ASCII (`/` or `$`), so slicing one code
/// unit off the front is safe.
fn trigger_query(text : String) -> String? {
  let rest = text[1:].to_owned()
  if rest.contains(" ") {
    None
  } else {
    Some(rest)
  }
}

///|
/// Whether a menu row survives the typed query: a blank query keeps it,
/// otherwise any of its fields must contain the query (case-insensitive). The
/// query already had its trigger stripped, so a `/compact` row is matched
/// against the bare "compact".
fn completion_matches(query : String, fields : Array[String]) -> Bool {
  let query = query.trim().to_owned().to_lower()
  if query.is_empty() {
    return true
  }
  for field in fields {
    if field.to_lower().contains(query) {
      return true
    }
  }
  false
}

///|
/// Move the highlighted row by `delta`, wrapping at both ends so ↑ on the
/// first row lands on the last. A closed menu is left untouched.
fn Completion::shifted(self : Completion, delta : Int) -> Completion {
  let count = self.items.length()
  if count == 0 {
    return self
  }
  let next = (self.selected + delta + count) % count
  { ..self, selected: next }
}

///|
/// The highlighted row, or `None` for an empty menu.
fn Completion::current(self : Completion) -> CompletionItem? {
  self.items.get(self.selected)
}
