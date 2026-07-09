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
  compute_completion(text, installed, empty_symbol_cache(), "")
}

///|
fn symbol_cache(
  session : String,
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
  { session, query, items }
}

///|
test "slash trigger lists matching commands and filters by the typed name" {
  guard menu_for("/", []) is Some(all) else {
    fail("a bare slash should open the command menu")
  }
  assert_true(all.kind is SlashCommands)
  assert_true(all.items.length() >= 1)
  assert_eq(all.items[0].label, "/compact")
  guard menu_for("/comp", []) is Some(match_) else {
    fail("a command prefix should keep matching rows")
  }
  assert_eq(match_.items[0].command, "compact")
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
  let cache = symbol_cache("s1", "parse", [
    "parse_hover", "parse_range", "render",
  ])
  guard compute_completion("#parse", [], cache, "s1") is Some(menu) else {
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
test "hash menu is loading until the cache catches up to the query" {
  // A bare # opens the menu (it lists everything), empty and loading until the
  // first results arrive.
  guard compute_completion("#", [], empty_symbol_cache(), "s1") is Some(bare) else {
    fail("a bare # should open the symbol menu")
  }
  assert_true(bare.loading)
  assert_eq(bare.items.length(), 0)
  // A query with no cached results yet: the menu opens empty and loading.
  guard compute_completion("#parse", [], empty_symbol_cache(), "s1")
    is Some(fresh) else {
    fail("a # query should open even before results arrive")
  }
  assert_true(fresh.loading)
  assert_eq(fresh.items.length(), 0)
  // A cache from another conversation does not answer this one.
  let other = symbol_cache("s2", "parse", ["parse_hover"])
  guard compute_completion("#parse", [], other, "s1") is Some(stale) else {
    fail("menu still opens")
  }
  assert_true(stale.loading)
  // Once the empty-query results are cached, a bare # lists them all, settled.
  let full = symbol_cache("s1", "", ["alpha", "beta"])
  guard compute_completion("#", [], full, "s1") is Some(menu) else {
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
  assert_true(
    placed.range is Some(placed_range) && placed_range.equals_range(range),
  )
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
    ..empty_conversation("s"),
    mentions: [{ ref_: Skill(name="review-pr"), range: None }],
  }
  // Chips are context for an instruction; without typed text the draft is
  // retained (not empty) but cannot be submitted.
  assert_false(conv.draft_sendable())
  assert_false(conv.draft_empty())
  assert_true({ ..conv, task: "do it" }.draft_sendable())
}

///|
test "decode_symbols parses rows and skips malformed ones" {
  let text =
    #|{"symbols":[
    #|{"name":"parse_hover","kind":12,"container":"Lsp","path":"a/b.mbt",
    #| "range":{"start":{"line":4,"col":2},"end":{"line":4,"col":13}}},
    #|{"name":"","path":"x.mbt"},
    #|{"path":"y.mbt"}
    #|]}
  guard decode_symbols(text) is Some(items) else { fail("expected rows") }
  // The blank-name and name-less rows are dropped; one good row remains.
  assert_eq(items.length(), 1)
  assert_eq(items[0].label, "parse_hover")
  // Detail reads container · path:line (line shown one-based).
  assert_eq(items[0].detail, "Lsp · a/b.mbt:5")
  // The zero-based wire range arrives as one-based viewer coordinates.
  assert_true(
    items[0].range is Some(range) &&
    range.equals_range(@common.Range::Range(5, 3, 5, 14)),
  )
  assert_true(decode_symbols("not json") is None)
}
