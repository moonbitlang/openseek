// The composer's completion menu: a leading `/` lists built-in conversation
// commands, while a trailing `$`, `#`, or `@` token lists installed skills,
// workspace symbols, or workspace files after ordinary prompt text. All four
// filter as the user types and are driven from the model so the keyboard
// (↑/↓, Enter/Tab, Esc) and the popup view stay in sync.

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
/// Map the shared trigger grammar to the providers OpenSeek exposes. Keeping
/// provider choice here leaves the composer package independent of application
/// commands and result types.
fn CompletionKind::of_trigger(trigger : @composer.Trigger) -> CompletionKind? {
  match trigger.marker() {
    "/" => Some(SlashCommands)
    "$" => Some(SkillMentions)
    "#" => Some(Symbols)
    "@" => Some(Files)
    _ => None
  }
}

///|
/// Build the composer completion menu for a draft, or `None` when the draft
/// has no live trigger. The menu opens on a leading `/` command or a trailing
/// `$`/`#`/`@` token after any whitespace. Once the user types whitespace past the
/// token, the mention/reference is complete and the menu closes. The highlight
/// resets to the first row on every rebuild, since filtering reorders what is
/// shown.
///
/// Symbols differ from local skill/file rows: they are fetched asynchronously and
/// arrive via `SymbolsLoaded`, so they come from `symbols` (cached against
/// conversation owner) rather than being computed here. The menu still opens immediately
/// for a `#` query — empty and `loading` until the cache catches up.
fn compute_completion(
  text : String,
  installed : Array[@transcript.InstalledSkillItem],
  symbols : SymbolCache,
  owner : @interop.ConversationKey,
  files? : Array[@files.Match] = [],
  files_loading? : Bool = false,
) -> Completion? {
  guard @composer.Trigger::parse(text, inline_markers="$#@") is Some(trigger) &&
    CompletionKind::of_trigger(trigger) is Some(kind) else {
    return None
  }
  match kind {
    SlashCommands => {
      let items = slash_command_items().filter(item => {
        trigger.matches([item.label])
      })
      if items.is_empty() {
        None
      } else {
        Some({
          kind: SlashCommands,
          menu: @composer.Menu(
            items,
            loading=false,
            draft_without_token=trigger.draft_without_token(),
          ),
        })
      }
    }
    SkillMentions => {
      let items : Array[CompletionItem] = []
      for skill in installed {
        if trigger.matches([skill.name, skill.description]) {
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
          menu: @composer.Menu(
            items,
            loading=false,
            draft_without_token=trigger.draft_without_token(),
          ),
        })
      }
    }
    Symbols => {
      // A bare `#` lists everything — an empty query asks the server for all
      // symbols — and narrows as the user types.
      let items = symbols.items.filter(item => {
        trigger.matches([item.label, item.detail])
      })
      // The cache answers this exact query for this conversation only when both
      // match; otherwise a fetch is in flight (or about to be) and the menu
      // shows whatever the cache narrows to meanwhile, marked loading.
      let loading = symbols.owner != Some(owner) ||
        symbols.query != trigger.query()
      Some({
        kind: Symbols,
        menu: @composer.Menu(
          items,
          loading~,
          draft_without_token=trigger.draft_without_token(),
        ),
      })
    }
    Files => {
      let items = files.map(file => CompletionItem::{
        label: file.name,
        detail: file.path.0,
        command: "",
        insert: file.path.0,
        path: Some(file.path.0),
        range: None,
      })
      Some({
        kind: Files,
        menu: @composer.Menu(
          items,
          loading=files_loading,
          draft_without_token=trigger.draft_without_token(),
        ),
      })
    }
  }
}

///|
/// Build the bounded file candidate set shared by composer `@` and Ctrl+P.
/// The workspace index supplies paths; open tabs remain immediately useful
/// while that index is loading.
fn Model::file_search(self : Model) -> @files.Search {
  let indexed = match self.file_panel.index {
    @fileeditor.IndexReady(files~, ..) => files
    _ => []
  }
  @files.Search(
    indexed,
    quick_open_open_files(self),
    @dock.active_file(self.dock),
  )
}

///|
/// Rank an active `@` query through the same candidate ordering and fuzzy
/// matcher as Ctrl+P. Other completion providers receive no file rows.
fn Model::completion_files(
  self : Model,
  text : String,
) -> (Array[@files.Match], Bool) {
  guard @composer.Trigger::parse(text, inline_markers="$#@") is Some(trigger) &&
    trigger.marker() == "@" else {
    return ([], false)
  }
  let can_index = self.conversation_root(self.active()) is Some(_)
  let loading = match self.file_panel.index {
    @fileeditor.IndexEmpty | @fileeditor.IndexLoading(_) => can_index
    @fileeditor.IndexReady(truncated=true, ..) => true
    @fileeditor.IndexFailed | @fileeditor.IndexReady(truncated=false, ..) =>
      false
  }
  (self.file_search().rank(trigger.query()), loading)
}

///|
/// Query the complete Host file snapshot only while the delayed `@` request
/// still names the visible conversation, root, draft, and generation. The
/// file panel owns population of this cache; completion only needs the
/// interactive query when that panel reports a truncated local snapshot.
fn Model::begin_file_completion_request(
  self : Model,
  dispatch : @cmd.Emit[Msg],
  owner : @interop.ConversationKey,
  root : @common.Uri,
  query : String,
  generation : Int,
) -> (@cmd.Cmd, Model) {
  guard self.completion_debounce.accepts(generation) &&
    owner.channel == self.focused &&
    owner.session == self.active().session_id &&
    self.conversation_root(self.active()) == Some(root) &&
    self.file_panel.index is @fileeditor.IndexReady(truncated=true, ..) &&
    @composer.Trigger::parse(self.active().task, inline_markers="$#@")
    is Some(trigger) &&
    trigger.marker() == "@" &&
    trigger.query() == query &&
    self.completion is Some(completion) &&
    completion.kind is Files &&
    completion.menu.loading() else {
    return (@cmd.none, self)
  }
  (
    @files.Request(owner.channel, owner.session, Some(root)).search_cached(
      query,
      generation,
      (files, _limit_hit) => {
        dispatch(
          FileCompletionLoaded(owner~, root~, query~, generation~, files~),
        )
      },
      () => dispatch(FileCompletionFailed(owner~, root~, query~, generation~)),
    ),
    self,
  )
}

///|
/// Settle the exact live `@` request with Host-ranked candidates. A failed
/// query falls back to the bounded local snapshot instead of discarding useful
/// rows; in both cases the spinner stops, while stale replies are ignored.
fn Model::apply_file_completion_reply(
  self : Model,
  owner : @interop.ConversationKey,
  root : @common.Uri,
  query : String,
  generation : Int,
  remote_files : Array[@pathx.Relative]?,
) -> (@cmd.Cmd, Model) {
  let draft = self.active().task
  guard self.completion_debounce.accepts(generation) &&
    owner.channel == self.focused &&
    owner.session == self.active().session_id &&
    self.conversation_root(self.active()) == Some(root) &&
    @composer.Trigger::parse(draft, inline_markers="$#@") is Some(trigger) &&
    trigger.marker() == "@" &&
    trigger.query() == query &&
    self.completion is Some(completion) &&
    completion.kind is Files &&
    completion.menu.loading() else {
    return (@cmd.none, self)
  }
  let matches = match remote_files {
    Some(files) =>
      @files.Search(
        files,
        quick_open_open_files(self),
        @dock.active_file(self.dock),
      ).rank(query)
    None => self.file_search().rank(query)
  }
  (
    @cmd.none,
    {
      ..self,
      completion: compute_completion(
        draft,
        self.installed_skills,
        self.symbol_cache,
        owner,
        files=matches,
        files_loading=false,
      ),
    },
  )
}

///|
/// Continue a live `@` query after the panel's initial index request reveals
/// that its local snapshot was truncated. The current debounce generation is
/// reused because no keystroke occurred while the index was loading.
fn Model::file_completion_query_after_index(
  self : Model,
  dispatch : @cmd.Emit[Msg],
) -> @cmd.Cmd {
  guard self.file_panel.index is @fileeditor.IndexReady(truncated=true, ..) &&
    self.completion is Some(completion) &&
    completion.kind is Files &&
    completion.menu.loading() &&
    @composer.Trigger::parse(self.active().task, inline_markers="$#@")
    is Some(trigger) &&
    trigger.marker() == "@" &&
    self.conversation_root(self.active()) is Some(root) else {
    return @cmd.none
  }
  dispatch(
    FileCompletionDue(
      owner={ channel: self.focused, session: self.active().session_id },
      root~,
      query=trigger.query(),
      generation=self.completion_debounce.generation(),
    ),
  )
}

///|
/// Rebuild a visible `@` menu after the shared file index settles. Reading the
/// current draft again prevents a late index reply from reviving an obsolete
/// or already accepted token. The menu itself is part of that identity: Esc
/// dismisses it without changing the draft, so a later index reply must not
/// recreate it from the still-present token.
fn Model::refresh_file_completion(self : Model) -> Model {
  let text = self.active().task
  guard self.completion is Some(completion) &&
    completion.kind is Files &&
    @composer.Trigger::parse(text, inline_markers="$#@") is Some(trigger) &&
    trigger.marker() == "@" else {
    return self
  }
  let (files, files_loading) = self.completion_files(text)
  let owner : @interop.ConversationKey = {
    channel: self.focused,
    session: self.active().session_id,
  }
  {
    ..self,
    completion: compute_completion(
      text,
      self.installed_skills,
      self.symbol_cache,
      owner,
      files~,
      files_loading~,
    ),
  }
}

///|
/// Restart a visible file query when its conversation moves to a different
/// concrete checkout root. This runs after the file panel has re-rooted, so
/// rebuilding the menu drops paths from the previous index and the follow-up
/// request addresses the new root. A dismissed menu remains dismissed.
fn Model::restart_file_completion_after_root_change(
  self : Model,
  dispatch : @cmd.Emit[Msg],
  previous : Model,
) -> (@cmd.Cmd, Model) {
  guard self.focused == previous.focused &&
    self.active_session == previous.active_session else {
    return (@cmd.none, self)
  }
  let conv = self.active()
  let previous_conv = previous.active()
  guard self.conversation_root(conv) !=
    previous.conversation_root(previous_conv) &&
    self.completion is Some(completion) &&
    completion.kind is Files &&
    @composer.Trigger::parse(conv.task, inline_markers="$#@") is Some(trigger) &&
    trigger.marker() == "@" else {
    return (@cmd.none, self)
  }
  let next = self.refresh_file_completion()
  let command = match next.file_panel.index {
    @fileeditor.IndexEmpty | @fileeditor.IndexFailed =>
      dispatch(FileEditor(@fileeditor.EnsureFileIndex))
    @fileeditor.IndexLoading(_) | @fileeditor.IndexReady(..) => @cmd.none
  }
  (command, next)
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
    CompletionItem::symbol(
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
  assert_true(all.menu.length() >= 2)
  guard all.menu.get(0) is Some(all_first) else { fail("row expected") }
  assert_eq(all_first.label, "/compact")
  guard menu_for("/comp", []) is Some(match_) else {
    fail("a command prefix should keep matching rows")
  }
  guard match_.menu.get(0) is Some(compact) else { fail("row expected") }
  assert_eq(compact.command, "compact")
  guard menu_for("/go", []) is Some(goal_match) else {
    fail("the goal command should match its prefix")
  }
  guard goal_match.menu.get(0) is Some(goal) else { fail("row expected") }
  assert_eq(goal.command, "goal")
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
  assert_eq(all.menu.length(), 2)
  guard all.menu.get(0) is Some(first) else { fail("row expected") }
  assert_eq(first.label, "$review-pr")
  // Insertion drops the bare name plus a space to keep typing the prompt.
  assert_eq(first.insert, "review-pr ")
  // Matches the description too, case-insensitively.
  guard menu_for("$TIDY", skills) is Some(desc) else {
    fail("description text should match")
  }
  guard desc.menu.get(0) is Some(desc_first) else { fail("row expected") }
  assert_eq(desc_first.label, "$refactor")
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
  guard menu.menu.get(0) is Some(first) else { fail("row expected") }
  assert_eq(first.label, "$review-pr")
  assert_eq(menu.menu.draft_without_token(), "Please use ")
  // Newlines are valid token boundaries too.
  guard menu_for("First line\n$rev", skills) is Some(after_newline) else {
    fail("a skill token after a newline should open the menu")
  }
  assert_eq(after_newline.menu.draft_without_token(), "First line\n")
}

///|
test "at trigger lists the same ranked workspace file matches as Ctrl+P" {
  let owner : @interop.ConversationKey = { channel: Local, session: "s1" }
  guard compute_completion(
      "Inspect @main",
      [],
      empty_symbol_cache(),
      owner,
      files=[{ path: @pathx.Relative("src/main.mbt"), name: "main.mbt" }],
      files_loading=false,
    )
    is Some(menu) else {
    fail("an @ token should open the file menu")
  }
  assert_true(menu.kind is Files)
  assert_eq(menu.menu.draft_without_token(), "Inspect ")
  guard menu.menu.get(0) is Some(file) else { fail("file row expected") }
  assert_eq(file.label, "main.mbt")
  assert_eq(file.path, Some("src/main.mbt"))
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
  assert_eq(menu.menu.selected(), 0)
  assert_eq(menu.menu.shifted(-1).selected(), 2)
  assert_eq(menu.menu.shifted(1).selected(), 1)
  assert_eq(menu.menu.shifted(1).shifted(1).shifted(1).selected(), 0)
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
  assert_false(menu.menu.loading())
  // "render" is filtered out by the live query; the two parses survive.
  assert_eq(menu.menu.length(), 2)
  guard menu.menu.get(0) is Some(first) else { fail("row expected") }
  assert_eq(first.label, "parse_hover")
  // Accepting drops a backticked reference plus location into the composer.
  assert_eq(first.insert, "`parse_hover` — src/main.mbt:1 ")
}

///|
test "symbol completion follows prompt text and preserves that text" {
  let owner : @interop.ConversationKey = { channel: Local, session: "s1" }
  let cache = symbol_cache(owner, "parse", ["parse_hover"])
  guard compute_completion("Inspect #parse", [], cache, owner) is Some(menu) else {
    fail("a symbol token after prompt text should open the menu")
  }
  assert_true(menu.kind is Symbols)
  assert_false(menu.menu.loading())
  guard menu.menu.get(0) is Some(first) else { fail("row expected") }
  assert_eq(first.label, "parse_hover")
  assert_eq(menu.menu.draft_without_token(), "Inspect ")
}

///|
test "hash menu is loading until the cache catches up to the query" {
  let owner : @interop.ConversationKey = { channel: Local, session: "s1" }
  // A bare # opens the menu (it lists everything), empty and loading until the
  // first results arrive.
  guard compute_completion("#", [], empty_symbol_cache(), owner) is Some(bare) else {
    fail("a bare # should open the symbol menu")
  }
  assert_true(bare.menu.loading())
  assert_eq(bare.menu.length(), 0)
  // A query with no cached results yet: the menu opens empty and loading.
  guard compute_completion("#parse", [], empty_symbol_cache(), owner)
    is Some(fresh) else {
    fail("a # query should open even before results arrive")
  }
  assert_true(fresh.menu.loading())
  assert_eq(fresh.menu.length(), 0)
  // A cache from another conversation does not answer this one.
  let other = symbol_cache(
    { channel: Remote("other"), session: "s1" },
    "parse",
    ["parse_hover"],
  )
  guard compute_completion("#parse", [], other, owner) is Some(stale) else {
    fail("menu still opens")
  }
  assert_true(stale.menu.loading())
  // Once the empty-query results are cached, a bare # lists them all, settled.
  let full = symbol_cache(owner, "", ["alpha", "beta"])
  guard compute_completion("#", [], full, owner) is Some(menu) else {
    fail("bare # lists the cached symbols")
  }
  assert_false(menu.menu.loading())
  assert_eq(menu.menu.length(), 2)
}

///|
test "symbol_item resolves a jump target only when the symbol has a path" {
  let range = @common.Range::Range(5, 4, 5, 15)
  let placed = CompletionItem::symbol(
    "parse_hover",
    container=None,
    path="src/main.mbt",
    range~,
  )
  assert_true(placed.path is Some("src/main.mbt"))
  assert_true(placed.range is Some(placed_range) && placed_range == range)
  // The reference anchors at the range's (one-based) start line.
  assert_eq(placed.detail, "src/main.mbt:5")
  let unplaced = CompletionItem::symbol(
    "parse_hover",
    container=None,
    path="",
    range~,
  )
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
      #|<user_mentions attributes="xml">
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
  let symbols = @symbols.decode({
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
  })
  // The blank-name row is dropped; one good row remains.
  assert_eq(symbols.length(), 1)
  assert_eq(symbols[0].name, "parse_hover")
  assert_eq(symbols[0].kind, Some(12))
  let item = CompletionItem::from_symbol(symbols[0])
  // Detail reads container · path:line (line shown one-based).
  assert_eq(item.detail, "Lsp · a/b.mbt:5")
  // The zero-based wire range arrives as one-based viewer coordinates.
  assert_true(
    item.range is Some(range) && range == @common.Range::Range(5, 3, 5, 14),
  )
}
