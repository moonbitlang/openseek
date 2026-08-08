///|
/// Toy two-state tokenizer: `/* ... */` block comments carried across
/// lines, everything else untokenized. Small enough to assert exact
/// offsets, real enough to prove the state contract.
priv struct BlockCommentToy {}

///|
let toy_code : @syntax.TokenizerState = TokenizerState("code")

///|
let toy_comment : @syntax.TokenizerState = TokenizerState("comment")

///|
impl @syntax.LineTokenizer for BlockCommentToy with fn initial_state(_self) {
  toy_code
}

///|
impl @syntax.LineTokenizer for BlockCommentToy with fn tokenize_line(
  _self,
  line_text,
  state,
) {
  let tokens : Array[@syntax.LineToken] = []
  let in_comment = for at = 0, view = line_text[:], in_comment = state ==
                         toy_comment; view.length() > 0; {
    lexscan view with longest {
      (re"^(?:/\*|\*/|[^*/]+|.)" as lexeme, after~) => {
        let next = line_text.length() - after.length()
        if in_comment || lexeme is "/*" {
          @syntax.push_token(tokens, at, next, Comment)
        }
        continue next,
          after,
          if lexeme is "/*" {
            true
          } else if lexeme is "*/" {
            false
          } else {
            in_comment
          }
      }
      _ => break in_comment
    }
  } nobreak {
    in_comment
  }
  (tokens, if in_comment { toy_comment } else { toy_code })
}

///|
test "block comment state threads across lines" {
  let toy : &@syntax.LineTokenizer = BlockCommentToy::{  }
  let (line0, after_open) = toy.tokenize_line("aa /* bb", toy.initial_state())
  debug_inspect(
    line0,
    content=(
      #|[{ start: 3, end: 8, tag: Comment }]
    ),
  )
  let (line1, after_close) = toy.tokenize_line("cc */ dd", after_open)
  debug_inspect(
    line1,
    content=(
      #|[{ start: 0, end: 5, tag: Comment }]
    ),
  )
  assert_true(after_close == toy_code)

  let (unicode, after_unicode) = toy.tokenize_line(
    "\u{10348} /* ok */",
    toy.initial_state(),
  )
  assert_eq(unicode, [{ start: 3, end: 11, tag: Comment }])
  assert_true(after_unicode == toy_code)
}

///|
test "tokenizer state equality detects convergence" {
  let toy : &@syntax.LineTokenizer = BlockCommentToy::{  }
  let (_, after_open) = toy.tokenize_line("aa /* bb", toy.initial_state())
  assert_true(after_open == toy_comment)
  let (_, after_close) = toy.tokenize_line("cc */ dd", after_open)
  assert_true(after_close == toy.initial_state())
  let (_, untouched) = toy.tokenize_line("plain line", toy.initial_state())
  assert_true(untouched == toy.initial_state())
}

///|
test "registry lookup resolves registered languages only" {
  let registry = @syntax.TokenizationRegistry()
  assert_true(registry.get("toy") is None)
  registry.register("toy", BlockCommentToy::{  }) |> ignore
  assert_true(registry.get("toy") is Some(_))
  assert_true(registry.get("unknown") is None)
}

///|
test "registry handle_change preserves language order and subscriptions" {
  let registry = @syntax.TokenizationRegistry()
  let first_languages : Array[Array[String]] = []
  let first_color_flags : Array[Bool] = []
  let second_languages : Array[Array[String]] = []
  let first_subscription = registry.on_did_change(event => {
    first_languages.push(event.changed_languages)
    first_color_flags.push(event.changed_color_map)
  })
  registry.on_did_change(event => second_languages.push(event.changed_languages))
  |> ignore

  registry.handle_change(["outer", "embedded", "template"])
  assert_eq(first_languages.length(), 1)
  assert_eq(first_languages[0].join(","), "outer,embedded,template")
  assert_false(first_color_flags[0])
  assert_eq(second_languages[0].join(","), "outer,embedded,template")

  first_subscription.dispose()
  registry.handle_change(["remaining"])
  assert_eq(first_languages.length(), 1)
  assert_eq(second_languages.length(), 2)
  assert_eq(second_languages[1].join(","), "remaining")
}

///|
test "registry replacement makes stale dispose inert and active dispose notifies" {
  let registry = @syntax.TokenizationRegistry()
  let changed_languages : Array[Array[String]] = []
  let color_flags : Array[Bool] = []
  let support_visible_when_registered = Ref(false)
  registry.on_did_change(event => {
    changed_languages.push(event.changed_languages)
    color_flags.push(event.changed_color_map)
    if changed_languages.length() == 1 {
      support_visible_when_registered.val = registry.get("toy") is Some(_)
    }
  })
  |> ignore

  let stale = registry.register("toy", BlockCommentToy::{  })
  let active = registry.register("toy", BlockCommentToy::{  })
  assert_true(support_visible_when_registered.val)
  assert_eq(changed_languages.length(), 2)
  assert_false(color_flags[0])
  assert_false(color_flags[1])

  stale.dispose()
  assert_eq(changed_languages.length(), 2)
  assert_true(registry.get("toy") is Some(_))

  active.dispose()
  assert_eq(changed_languages.length(), 3)
  assert_eq(changed_languages[2].join(","), "toy")
  assert_false(color_flags[2])
  assert_true(registry.get("toy") is None)
}

///|
test "registry is_resolved is true without lazy factory state" {
  let registry = @syntax.TokenizationRegistry()
  assert_true(registry.is_resolved("missing"))
  registry.register("toy", BlockCommentToy::{  }) |> ignore
  assert_true(registry.is_resolved("toy"))
}

///|
test "registry color map retains CSS values and emits active languages" {
  let registry = @syntax.TokenizationRegistry()
  assert_true(registry.get_color_map() is None)
  let changed_languages : Array[Array[String]] = []
  let color_flags : Array[Bool] = []
  registry.on_did_change(event => {
    changed_languages.push(event.changed_languages)
    color_flags.push(event.changed_color_map)
  })
  |> ignore
  registry.register("moonbit", BlockCommentToy::{  }) |> ignore
  registry.register("javascript", BlockCommentToy::{  }) |> ignore
  changed_languages.clear()
  color_flags.clear()

  let colors = ["transparent", "rgb(1 2 3)", "var(--editor-bg)"]
  registry.set_color_map(colors)
  assert_eq(changed_languages.length(), 1)
  assert_eq(changed_languages[0].join(","), "moonbit,javascript")
  assert_true(color_flags[0])
  guard registry.get_color_map() is Some(retained) else {
    fail("expected retained color map")
  }
  assert_eq(retained.join("|"), "transparent|rgb(1 2 3)|var(--editor-bg)")

  // The source stores the supplied array directly. Mutating it proves this
  // adaptation neither parses nor copies CSS expressions.
  colors[0] = "color(display-p3 1 0 0)"
  guard registry.get_color_map() is Some(same_colors) else {
    fail("expected retained color map")
  }
  assert_eq(same_colors[0], "color(display-p3 1 0 0)")
}

///|
test "registry default background requires color index two" {
  let registry = @syntax.TokenizationRegistry()
  assert_true(registry.get_default_background() is None)
  registry.set_color_map([])
  assert_true(registry.get_default_background() is None)
  registry.set_color_map(["zero", "one"])
  assert_true(registry.get_default_background() is None)
  registry.set_color_map(["zero", "one", "two"])
  assert_true(registry.get_default_background() == Some("two"))
}

///|
test "plain tokenizer counts UTF-16 code units and keeps pairs whole" {
  // 𐍈 (U+10348) is two UTF-16 code units; the identifier after it must
  // start at offset 4 and the pair must stay one token.
  let plain : &@syntax.LineTokenizer = @syntax.PlainTokenizer()
  let (tokens, _) = plain.tokenize_line("a \u{10348}b", plain.initial_state())
  debug_inspect(
    tokens,
    content=(
      #|[
      #|  { start: 0, end: 1, tag: Identifier },
      #|  { start: 2, end: 4, tag: Punctuation },
      #|  { start: 4, end: 5, tag: Identifier },
      #|]
    ),
  )
}
