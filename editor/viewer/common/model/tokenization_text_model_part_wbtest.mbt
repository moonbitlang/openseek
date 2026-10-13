///| Part-level conformance: the whole-document sweep threads lexer state line
/// to line, encodes every line into the binary store, and round-trips
/// language ids through the process-wide codec.

///|
/// Toy two-state tokenizer: `/* ... */` block comments carried across lines,
/// a leading `let` tagged as a keyword, everything else untokenized.
priv struct BlockCommentToy {}

///|
let toy_code : @syntax.TokenizerState = TokenizerState()

///|
let toy_comment : @syntax.TokenizerState = toy_code.push_mode(b'c')

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
  let mut at = 0
  let mut in_comment = state == toy_comment
  if !in_comment &&
    line_text.length() >= 3 &&
    line_text[0] == 'l' &&
    line_text[1] == 'e' &&
    line_text[2] == 't' {
    tokens.push({ start: 0, end: 3, tag: Keyword, })
    at = 3
  }
  while at < line_text.length() {
    if in_comment {
      let close = find_marker(line_text, at, '*', '/')
      let end = match close {
        Some(index) => index + 2
        None => line_text.length()
      }
      tokens.push({ start: at, end, tag: Comment, })
      in_comment = close is None
      at = end
    } else {
      match find_marker(line_text, at, '/', '*') {
        Some(index) => {
          in_comment = true
          at = index
        }
        None => at = line_text.length()
      }
    }
  }
  (tokens, if in_comment { toy_comment } else { toy_code })
}

///|
fn find_marker(
  line_text : StringView,
  from : Int32,
  first : Char,
  second : Char,
) -> Int32? {
  for i in from..<(line_text.length() - 1) {
    if line_text[i].to_int() == first.to_int() &&
      line_text[i + 1].to_int() == second.to_int() {
      return Some(i)
    }
  }
  None
}

///|
fn toy_part(
  text : String,
  language_id : String,
) -> (TokenizationTextModelPart, AttachedViewImpl) {
  @syntax.tokenization_registry.register(language_id, BlockCommentToy::{ })
  |> ignore
  let lines : Array[String] = []
  let mut start = 0
  for i in 0..<text.length() {
    if text[i] == '\n' {
      lines.push(text[start:i].to_owned())
      start = i + 1
    }
  }
  lines.push(text[start:text.length()].to_owned())
  part_with_view_from_lines(lines, language_id)
}

///|
fn test_model_state(
  lines : Array[String],
  language_id : String,
) -> TokenizationModelState {
  test_model_state_with_disposing(lines, language_id, Ref(false))
}

///|
fn test_model_state_with_disposing(
  lines : Array[String],
  language_id : String,
  disposing : Ref[Bool],
) -> TokenizationModelState {
  test_tokenization_model_state(
    lines,
    language_id,
    Ref(0),
    false,
    disposing,
    Ref(None),
    _ => (),
  )
}

///|
fn part_from_lines(
  lines : Array[String],
  language_id : String,
) -> TokenizationTextModelPart {
  TokenizationTextModelPart(
    test_model_state(lines, language_id),
    AttachedViews(),
  )
}

///|
fn part_with_view_from_lines(
  lines : Array[String],
  language_id : String,
) -> (TokenizationTextModelPart, AttachedViewImpl) {
  let attached_views = AttachedViews()
  let part = TokenizationTextModelPart(
    test_model_state(lines, language_id),
    attached_views,
  )
  (part, attached_views.attach_view())
}

///|
test "the sweep threads state across lines and encodes every line" {
  let (part, view) = toy_part(
    (
      #|let a = 1
      #|/* two
      #|line comment */
      #|let b = 2
    ),
    "part-toy",
  )
  view.set_visible_lines([{ start_line_number: 1, end_line_number: 4, }], true)

  // Every line's stored `LineTokens` reproduces the line text.
  assert_eq(part.get_line_tokens(1).get_line_content(), "let a = 1")
  assert_eq(part.get_line_tokens(2).get_line_content(), "/* two")
  assert_eq(part.get_line_tokens(3).get_line_content(), "line comment */")
  assert_eq(part.get_line_tokens(4).get_line_content(), "let b = 2")

  // Line 1: "let" (keyword) then " a = 1" (gap, default fg).
  let line1 = part.get_line_tokens(1)
  let line1_view = line1.inflate()
  assert_eq(line1.get_count(), 2)
  assert_eq(line1_view.get_class_name(0), "mtk3") // Keyword
  assert_eq(line1_view.get_end_offset(0), 3)
  assert_eq(line1_view.get_class_name(1), "mtk1") // gap -> default foreground

  // The block comment carries the comment color and standard token type on
  // the interior lines the threaded state covers.
  let line2 = part.get_line_tokens(2)
  assert_eq(line2.inflate().get_class_name(0), "mtk7") // Comment
  assert_eq(
    ((
      line2.get_metadata(0).to_uint() >>
      @common_tokens.METADATA_TOKEN_TYPE_OFFSET
    ) &
    0x3U).reinterpret_as_int(),
    @common_tokens.STANDARD_TOKEN_TYPE_COMMENT,
  )
  assert_eq(part.get_line_tokens(3).inflate().get_class_name(0), "mtk7")
}

///|
/// Every token of a part tagged with a language decodes back to it (gap,
/// syntax, and blank-line tokens alike), and the packed metadata's low 8 bits
/// equal the process-wide codec's numeric id. The `mtk<fg>` classes are
/// unchanged — the language field is presentation-neutral.
test "language id uses the process-wide codec id" {
  // A blank middle line exercises the empty-line token path; no tokenizer is
  // registered for this language, exercising the null-tokenization path too.
  let part = part_from_lines(
    ["let a = 1", "", "let b = 2"],
    "part-null-language",
  )
  let expected_id = @services.language_id_codec.register("part-null-language")
  assert_true(expected_id != 0)
  for line_number in 1..<=3 {
    let tokens = part.get_line_tokens(line_number)
    assert_true(tokens.get_count() >= 1)
    for i in 0..<tokens.get_count() {
      let language_id = ((
        tokens.get_metadata(i).to_uint() >>
        @common_tokens.METADATA_LANGUAGEID_OFFSET
      ) &
      0xffU).reinterpret_as_int()
      assert_eq(language_id, expected_id)
    }
  }
}

///|
/// The part's own registry subscription (the backend constructor's
/// `_register(TokenizationRegistry.onDidChange(...))`): a (re)registration
/// touching the part's language resets the memo and fires
/// `on_did_change_tokens`; `dispose` unsubscribes.
test "registry changes reset the part and fire on_did_change_tokens" {
  let (part, view) = part_with_view_from_lines(
    ["let a = 1", "let b = 2"],
    "part-registry-sub",
  )
  let events : Array[ModelTokensChangedEvent] = []
  part.on_did_change_tokens(event => events.push(event)) |> ignore
  // Registry miss reads one passive default token without warming state.
  assert_eq(part.get_line_tokens(1).get_count(), 1)
  let registration = @syntax.tokenization_registry.register(
    "part-registry-sub",
    BlockCommentToy::{ },
  )
  // The part observed the registration itself: memo dropped, whole-document
  // change announced.
  assert_eq(events.length(), 1)
  assert_false(events[0].semantic_tokens_applied)
  assert_eq(events[0].ranges.length(), 1)
  assert_eq(events[0].ranges[0].from_line_number, 1)
  assert_eq(events[0].ranges[0].to_line_number, 2)
  // Re-read remains passive; a stable attached range drives production lexing.
  assert_eq(part.get_line_tokens(1).get_count(), 1)
  view.set_visible_lines([{ start_line_number: 1, end_line_number: 2, }], true)
  assert_eq(part.get_line_tokens(1).get_count(), 2)
  // Other languages' registrations do not touch the part.
  let other = @syntax.tokenization_registry.register(
    "part-registry-sub-other",
    BlockCommentToy::{ },
  )
  assert_eq(events.length(), 2)
  other.dispose()
  // dispose unsubscribes: the deregistration no longer reaches the part.
  part.dispose()
  registration.dispose()
  assert_eq(events.length(), 2)
}

///|
test "panic get_line_tokens rejects line zero" {
  let part = part_from_lines(["one"], "invalid-line-zero")
  ignore(part.get_line_tokens(0))
}

///|
test "token_count is a passive stored/default read" {
  let lines = ["one", "two", "three"]
  let calls : Array[String] = []
  let attached_views = AttachedViews()
  let part = TokenizationTextModelPart::new_with_support_resolver(
    test_model_state(lines, "passive-count"),
    attached_views,
    _ => Some(logging_support(calls, Ref(0))),
  )
  assert_eq(part.token_count(), 3)
  assert_true(calls.is_empty())
  let view = attached_views.attach_view()
  view.set_visible_lines([{ start_line_number: 1, end_line_number: 2, }], true)
  let before = calls.length()
  assert_eq(part.token_count(), 3)
  assert_eq(calls.length(), before)
}

///|
test "dispose releases subscriptions emitters and backend before marking disposed" {
  let part = part_from_lines(["one"], "part-dispose-order")
  let subscription_order : Array[String] = []
  match part.backend_token_subscription {
    Some(subscription) => subscription.dispose()
    None => ()
  }
  part.backend_token_subscription = Some(
    @base_common.Disposable::from(() => {
      if part.disposed {
        abort("token subscription disposed after terminal flag")
      }
      subscription_order.push("tokens")
    }),
  )
  part.did_change_tokens.event(_ => ()) |> ignore

  part.dispose()
  assert_true(part.disposed)
  assert_eq(subscription_order.length(), 1)
  assert_eq(subscription_order[0], "tokens")
  assert_true(part.backend_token_subscription is None)
  assert_false(part.did_change_tokens.has_listeners())
  assert_true(part.backend.disposed)

  part.dispose()
  assert_eq(subscription_order.length(), 1)
}

///|
test "assert_not_disposed continues on the live branch" {
  let part = part_from_lines(["one"], "part-live-guard")
  part.assert_not_disposed()
}

///|
test "panic assert_not_disposed rejects a disposed part" {
  let part = part_from_lines(["one"], "part-disposed-guard")
  part.dispose()
  part.assert_not_disposed()
}

///|
test "panic token_count rejects guarded work after disposal" {
  let part = part_from_lines(["one"], "part-disposed-token-count")
  part.dispose()
  ignore(part.token_count())
}
