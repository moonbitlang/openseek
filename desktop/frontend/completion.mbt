// The composer's completion menu: a leading `/` lists built-in conversation
// commands, while a trailing `$` or `#` token lists installed skills or
// workspace symbols after ordinary prompt text. All three filter as the user
// types and are driven from the model so the keyboard (↑/↓, Enter/Tab, Esc)
// and the popup view stay in sync.

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
    {
      label: "/goal",
      detail: "Set or clear this conversation's standing goal",
      command: "goal",
      insert: "",
      path: None,
      range: None,
    },
  ]
}

///|
/// The live completion token at the end of a draft. Slash commands keep their
/// whole-draft semantics and therefore only parse at the beginning; `$` and
/// `#` mentions parse after any whitespace so they can follow ordinary prompt
/// text. `task_without_token` is the exact preceding text that accepting a
/// mention preserves.
priv struct CompletionTrigger {
  kind : CompletionKind
  query : String
  task_without_token : String
}

///|
fn CompletionTrigger::parse(text : String) -> CompletionTrigger? {
  if text =~ (re"^/", after=query) && query =~ re"^[^[:space:]]*$" {
    return Some({
      kind: SlashCommands,
      query: query.to_owned(),
      task_without_token: "",
    })
  }
  // The trailing anchor skips earlier `$`/`#` text. The separate boundary
  // check rejects a marker embedded in a word without consuming the whitespace
  // that accepting the completion must preserve.
  guard text =~ (re"[$#][^[:space:]]*$" as token, before=task) &&
    (task.is_empty() || task =~ re"[[:space:]]$") &&
    token =~ (re"^[$#]" as trigger, after=query) else {
    return None
  }
  Some({
    kind: if trigger is '$' {
      SkillMentions
    } else {
      Symbols
    },
    query: query.to_owned(),
    task_without_token: task.to_owned(),
  })
}

///|
/// Build the composer completion menu for a draft, or `None` when the draft
/// has no live trigger. The menu opens on a leading `/` command or a trailing
/// `$`/`#` token after any whitespace. Once the user types whitespace past the
/// token, the mention/reference is complete and the menu closes. The highlight
/// resets to the first row on every rebuild, since filtering reorders what is
/// shown.
///
/// Symbols differ from the other two: their rows are fetched asynchronously and
/// arrive via `SymbolsLoaded`, so they come from `symbols` (cached against
/// conversation owner) rather than being computed here. The menu still opens immediately
/// for a `#` query — empty and `loading` until the cache catches up.
fn compute_completion(
  text : String,
  installed : Array[@transcript.InstalledSkillItem],
  symbols : SymbolCache,
  owner : @interop.ConversationKey,
) -> Completion? {
  guard CompletionTrigger::parse(text) is Some(trigger) else { return None }
  match trigger.kind {
    SlashCommands => {
      let items = slash_command_items().filter(item => {
        completion_matches(trigger.query, [item.label])
      })
      if items.is_empty() {
        None
      } else {
        Some({
          kind: SlashCommands,
          items,
          selected: 0,
          loading: false,
          task_without_token: trigger.task_without_token,
        })
      }
    }
    SkillMentions => {
      let items : Array[CompletionItem] = []
      for skill in installed {
        if completion_matches(trigger.query, [skill.name, skill.description]) {
          items.push({
            label: "$\{skill.name}",
            detail: skill.description,
            command: "",
            insert: "\{skill.name} ",
            path: None,
            range: None,
          })
        }
      }
      if items.is_empty() {
        None
      } else {
        Some({
          kind: SkillMentions,
          items,
          selected: 0,
          loading: false,
          task_without_token: trigger.task_without_token,
        })
      }
    }
    Symbols => {
      // A bare `#` lists everything — an empty query asks the server for all
      // symbols — and narrows as the user types.
      let items = symbols.items.filter(item => {
        completion_matches(trigger.query, [item.label, item.detail])
      })
      // The cache answers this exact query for this conversation only when both
      // match; otherwise a fetch is in flight (or about to be) and the menu
      // shows whatever the cache narrows to meanwhile, marked loading.
      let loading = symbols.owner != Some(owner) ||
        symbols.query != trigger.query
      Some({
        kind: Symbols,
        items,
        selected: 0,
        loading,
        task_without_token: trigger.task_without_token,
      })
    }
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

///|
fn installed_skill(
  name : String,
  description : String,
) -> @transcript.InstalledSkillItem {
  { id: name, name, description, source: "" }
}

///|
/// The `/` and `$` menus do not depend on symbols, so route their tests through
/// an empty cache and no session.
fn menu_for(
  text : String,
  installed : Array[@transcript.InstalledSkillItem],
) -> Completion? {
  compute_completion(text, installed, empty_symbol_cache(), {
    channel: Local,
    session: "",
  })
}

///|
fn symbol_cache(
  owner : @interop.ConversationKey,
  query : String,
  names : Array[String],
) -> SymbolCache {
  let items = names.map(name => {
    symbol_item(
      name,
      container=None,
      path="src/main.mbt",
      range=@common.Range::Range(1, 1, 1, 1),
    )
  })
  { owner: Some(owner), root: None, query, items }
}

///|
test "slash trigger lists matching commands and filters by the typed name" {
  guard menu_for("/", []) is Some(all) else {
    fail("a bare slash should open the command menu")
  }
  assert_true(all.kind is SlashCommands)
  assert_true(all.items.length() >= 2)
  assert_eq(all.items[0].label, "/compact")
  guard menu_for("/comp", []) is Some(match_) else {
    fail("a command prefix should keep matching rows")
  }
  assert_eq(match_.items[0].command, "compact")
  guard menu_for("/go", []) is Some(goal_match) else {
    fail("the goal command should match its prefix")
  }
  assert_eq(goal_match.items[0].command, "goal")
  // No command contains this, so the menu closes rather than showing nothing.
  assert_true(menu_for("/zzz", []) is None)
}

///|
test "a completed command word closes the menu" {
  // The space marks the command as typed; further text is its argument.
  assert_true(menu_for("/compact now", []) is None)
}

///|
test "dollar trigger lists installed skills, name or description matching" {
  let skills = [
    installed_skill("review-pr", "Review a pull request"),
    installed_skill("refactor", "Tidy code"),
  ]
  guard menu_for("$", skills) is Some(all) else {
    fail("a bare dollar should open the skills menu")
  }
  assert_true(all.kind is SkillMentions)
  assert_eq(all.items.length(), 2)
  assert_eq(all.items[0].label, "$review-pr")
  // Insertion drops the bare name plus a space to keep typing the prompt.
  assert_eq(all.items[0].insert, "review-pr ")
  // Matches the description too, case-insensitively.
  guard menu_for("$TIDY", skills) is Some(desc) else {
    fail("description text should match")
  }
  assert_eq(desc.items[0].label, "$refactor")
  // No installed skills, no menu.
  assert_true(menu_for("$x", []) is None)
}

///|
test "skill completion follows prompt text and preserves that text" {
  let skills = [installed_skill("review-pr", "Review a pull request")]
  guard menu_for("Please use $rev", skills) is Some(menu) else {
    fail("a skill token after prompt text should open the menu")
  }
  assert_true(menu.kind is SkillMentions)
  assert_eq(menu.items[0].label, "$review-pr")
  assert_eq(menu.task_without_token, "Please use ")
  // Newlines are valid token boundaries too.
  guard menu_for("First line\n$rev", skills) is Some(after_newline) else {
    fail("a skill token after a newline should open the menu")
  }
  assert_eq(after_newline.task_without_token, "First line\n")
}

///|
test "inline completion requires a trailing whitespace-delimited token" {
  let skills = [installed_skill("review-pr", "Review a pull request")]
  // A trigger embedded in a word is ordinary prompt text.
  assert_true(menu_for("price$rev", skills) is None)
  // Once more text follows the token, it is no longer the live trailing token.
  assert_true(menu_for("Use $rev for this", skills) is None)
  // Slash commands retain whole-draft semantics: accepting one never discards
  // prompt text that happened to precede it.
  assert_true(menu_for("Please /comp", skills) is None)
}

///|
test "plain text opens no completion menu" {
  assert_true(menu_for("hello world", []) is None)
  assert_true(menu_for("", []) is None)
}

///|
test "highlight movement wraps at both ends" {
  let skills = [
    installed_skill("a", ""),
    installed_skill("b", ""),
    installed_skill("c", ""),
  ]
  guard menu_for("$", skills) is Some(menu) else { fail("menu expected") }
  assert_eq(menu.selected, 0)
  assert_eq(menu.shifted(-1).selected, 2)
  assert_eq(menu.shifted(1).selected, 1)
  assert_eq(menu.shifted(1).shifted(1).shifted(1).selected, 0)
}

///|
test "hash trigger lists cached symbols, filtered, marked not loading on match" {
  let owner : @interop.ConversationKey = { channel: Local, session: "s1" }
  let cache = symbol_cache(owner, "parse", [
    "parse_hover", "parse_range", "render",
  ])
  guard compute_completion("#parse", [], cache, owner) is Some(menu) else {
    fail("a # query should open the symbol menu")
  }
  assert_true(menu.kind is Symbols)
  // The cache answers this exact query/session, so the menu is settled.
  assert_false(menu.loading)
  // "render" is filtered out by the live query; the two parses survive.
  assert_eq(menu.items.length(), 2)
  assert_eq(menu.items[0].label, "parse_hover")
  // Accepting drops a backticked reference plus location into the composer.
  assert_eq(menu.items[0].insert, "`parse_hover` — src/main.mbt:1 ")
}

///|
test "symbol completion follows prompt text and preserves that text" {
  let owner : @interop.ConversationKey = { channel: Local, session: "s1" }
  let cache = symbol_cache(owner, "parse", ["parse_hover"])
  guard compute_completion("Inspect #parse", [], cache, owner) is Some(menu) else {
    fail("a symbol token after prompt text should open the menu")
  }
  assert_true(menu.kind is Symbols)
  assert_false(menu.loading)
  assert_eq(menu.items[0].label, "parse_hover")
  assert_eq(menu.task_without_token, "Inspect ")
}

///|
test "hash menu is loading until the cache catches up to the query" {
  let owner : @interop.ConversationKey = { channel: Local, session: "s1" }
  // A bare # opens the menu (it lists everything), empty and loading until the
  // first results arrive.
  guard compute_completion("#", [], empty_symbol_cache(), owner) is Some(bare) else {
    fail("a bare # should open the symbol menu")
  }
  assert_true(bare.loading)
  assert_eq(bare.items.length(), 0)
  // A query with no cached results yet: the menu opens empty and loading.
  guard compute_completion("#parse", [], empty_symbol_cache(), owner)
    is Some(fresh) else {
    fail("a # query should open even before results arrive")
  }
  assert_true(fresh.loading)
  assert_eq(fresh.items.length(), 0)
  // A cache from another conversation does not answer this one.
  let other = symbol_cache(
    { channel: Remote("other"), session: "s1" },
    "parse",
    ["parse_hover"],
  )
  guard compute_completion("#parse", [], other, owner) is Some(stale) else {
    fail("menu still opens")
  }
  assert_true(stale.loading)
  // Once the empty-query results are cached, a bare # lists them all, settled.
  let full = symbol_cache(owner, "", ["alpha", "beta"])
  guard compute_completion("#", [], full, owner) is Some(menu) else {
    fail("bare # lists the cached symbols")
  }
  assert_false(menu.loading)
  assert_eq(menu.items.length(), 2)
}

///|
test "symbol_item resolves a jump target only when the symbol has a path" {
  let range = @common.Range::Range(5, 4, 5, 15)
  let placed = symbol_item(
    "parse_hover",
    container=None,
    path="src/main.mbt",
    range~,
  )
  assert_true(placed.path is Some("src/main.mbt"))
  assert_true(placed.range is Some(placed_range) && placed_range == range)
  // The reference anchors at the range's (one-based) start line.
  assert_eq(placed.detail, "src/main.mbt:5")
  let unplaced = symbol_item("parse_hover", container=None, path="", range~)
  assert_true(unplaced.path is None)
  assert_true(unplaced.range is None)
}

///|
test "push_mention appends new chips and drops exact duplicates" {
  let skill : Mention = { ref_: Skill(name="review-pr"), range: None }
  let symbol : Mention = {
    ref_: Symbol(name="parse_hover", file="src/main.mbt", line=5),
    range: Some(@common.Range::Range(5, 1, 5, 12)),
  }
  let one = push_mention([], skill)
  assert_eq(one.length(), 1)
  // A different envelope form is a distinct chip.
  let two = push_mention(one, symbol)
  assert_eq(two.length(), 2)
  // Accepting the same skill again is a no-op, not a second chip.
  let still_two = push_mention(two, skill)
  assert_eq(still_two.length(), 2)
  // A symbol of the same name but a different location is its own chip.
  let other_loc : Mention = {
    ref_: Symbol(name="parse_hover", file="src/other.mbt", line=9),
    range: Some(@common.Range::Range(9, 1, 9, 12)),
  }
  assert_eq(push_mention(two, other_loc).length(), 3)
  // A comment chip dedups on its envelope form like the others.
  let note : Mention = {
    ref_: Annotation(
      file="src/main.mbt",
      start_line=5,
      end_line=6,
      quote="fn parse_hover() {",
      comment="rename this",
      side=@mention_context.WorkingRevision,
    ),
    range: Some(@common.Range::Range(5, 1, 6, 1)),
  }
  let three = push_mention(two, note)
  assert_eq(three.length(), 3)
  assert_eq(push_mention(three, note).length(), 3)
}

///|
test "compose_prompt folds the chips into a parseable envelope after the text" {
  let mentions : Array[Mention] = [
    {
      ref_: Symbol(name="parse_hover", file="a.mbt", line=5),
      range: Some(@common.Range::Range(5, 1, 5, 12)),
    },
    { ref_: Skill(name="review-pr"), range: None },
  ]
  // The typed text leads (the engine titles sessions by the first prompt's
  // first line); the chips follow as the tagged block the transcript parses
  // back into chips, live and on session reload alike.
  inspect(
    compose_prompt(mentions, "look at this"),
    content=(
      #|look at this
      #|
      #|<user_mentions>
      #|<symbol name="parse_hover" file="a.mbt" line="5"/>
      #|<skill name="review-pr"/>
      #|</user_mentions>
    ),
  )
  // No chips: just the text, no envelope.
  assert_eq(compose_prompt([], "plain"), "plain")
}

///|
test "a draft of chips alone is not sendable" {
  let conv = {
    ..empty_conversation(@interop.ChannelId::Local, "s"),
    mentions: [{ ref_: Skill(name="review-pr"), range: None }],
  }
  // Chips are context for an instruction; without typed text the draft is
  // retained (not empty) but cannot be submitted.
  assert_false(conv.draft_sendable())
  assert_false(conv.draft_empty())
  assert_true({ ..conv, task: "do it" }.draft_sendable())
}

///|
test "typed symbols retain kind and project one-based completion rows" {
  let symbols = SymbolsProjection({
    symbols: [
      {
        name: "parse_hover",
        kind: Some(12),
        container: Some("Lsp"),
        path: "a/b.mbt",
        range: { start: { line: 4, col: 2 }, end: { line: 4, col: 13 } },
      },
      {
        name: "",
        kind: None,
        container: None,
        path: "x.mbt",
        range: { start: { line: 0, col: 0 }, end: { line: 0, col: 0 } },
      },
    ],
  }).symbols()
  // The blank-name row is dropped; one good row remains.
  assert_eq(symbols.length(), 1)
  assert_eq(symbols[0].name, "parse_hover")
  assert_eq(symbols[0].kind, Some(12))
  let item = symbols[0].completion_item()
  // Detail reads container · path:line (line shown one-based).
  assert_eq(item.detail, "Lsp · a/b.mbt:5")
  // The zero-based wire range arrives as one-based viewer coordinates.
  assert_true(
    item.range is Some(range) && range == @common.Range::Range(5, 3, 5, 14),
  )
}
