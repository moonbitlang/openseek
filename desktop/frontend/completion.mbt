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
      path: None,
      range: None,
    },
  ]
}

///|
/// Build the composer completion menu for a draft, or `None` when the draft
/// does not begin with a live trigger. The menu opens on a leading `/`
/// (commands), `$` (installed skills), or `#` (workspace symbols) and stays
/// open only while the token after the trigger holds no spaces — once the user
/// types past the word, the command/mention/reference is complete and the menu
/// closes. The highlight resets to the first row on every rebuild, since
/// filtering reorders what is shown.
///
/// Symbols differ from the other two: their rows are fetched asynchronously and
/// arrive via `SymbolsLoaded`, so they come from `symbols` (cached against
/// `session`) rather than being computed here. The menu still opens immediately
/// for a `#` query — empty and `loading` until the cache catches up.
fn compute_completion(
  text : String,
  installed : Array[@transcript.InstalledSkillItem],
  symbols : SymbolCache,
  session : String,
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
      Some({ kind: SlashCommands, items, selected: 0, loading: false })
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
          path: None,
          range: None,
        })
      }
    }
    if items.is_empty() {
      None
    } else {
      Some({ kind: SkillMentions, items, selected: 0, loading: false })
    }
  } else if text.has_prefix("#") {
    let query = trigger_query(text)
    guard query is Some(query) else { return None }
    // A bare `#` lists everything — an empty query asks the server for all
    // symbols — and narrows as the user types.
    let items = symbols.items.filter(item => {
      completion_matches(query, [item.label, item.detail])
    })
    // The cache answers this exact query for this conversation only when both
    // match; otherwise a fetch is in flight (or about to be) and the menu shows
    // whatever the cache narrows to meanwhile, marked loading.
    let loading = symbols.session != session || symbols.query != query
    Some({ kind: Symbols, items, selected: 0, loading })
  } else {
    None
  }
}

///|
/// Append `mention` to `mentions` copy-on-write, unless an equal chip (same
/// envelope form) is already there — accepting the same skill, symbol, or
/// comment twice is a no-op rather than a duplicate chip. Prior model
/// snapshots keep their own array.
fn push_mention(mentions : Array[Mention], mention : Mention) -> Array[Mention] {
  for existing in mentions {
    if existing.ref_ == mention.ref_ {
      return mentions
    }
  }
  let next = mentions.copy()
  next.push(mention)
  next
}

///|
/// Assemble the outgoing prompt from the draft's mention chips and typed text:
/// the text first, then the chips folded into a `<user_mentions>` envelope
/// (`@mention_context.encode`) — the durable form the transcript parses back
/// into chips when the message re-renders, live or from a reloaded session.
/// With no chips this is just the text.
fn compose_prompt(mentions : Array[Mention], task : String) -> String {
  @mention_context.encode(mentions.map(mention => mention.ref_), task)
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
