///| Verifies the line-local encoder (`line_tokens_from_lexer_tokens`): the
/// faithful `LineTokens` it produces carries a token segment per lexer token
/// with inter-token gaps and trailing text filled by default-metadata tokens.

///|
test "encoder fills gaps and trailing text with default metadata" {
  let line = "let x = 1"
  let tokens : Array[@syntax.LineToken] = [
    { start: 0, end: 3, tag: Keyword, },
    { start: 8, end: 9, tag: Number, },
  ]
  let lt = line_tokens_from_lexer_tokens(
    line, tokens, @services.language_id_codec,
  )
  let view = lt.inflate()
  assert_eq(lt.get_line_content(), line)
  assert_eq(lt.get_count(), 3)
  // "let" | " x = " (gap) | "1"
  assert_eq(view.get_end_offset(0), 3)
  assert_eq(view.get_end_offset(1), 8)
  assert_eq(view.get_end_offset(2), 9)
  assert_eq(view.get_class_name(0), "mtk3") // Keyword
  assert_eq(view.get_class_name(1), "mtk1") // gap -> default foreground
  assert_eq(view.get_class_name(2), "mtk6") // Number
}

///|
test "empty line encodes to a single zero-length default token" {
  let lt = line_tokens_from_lexer_tokens("", [], @services.language_id_codec)
  assert_eq(lt.get_line_content(), "")
  assert_eq(lt.get_count(), 1)
  assert_eq(lt.inflate().get_end_offset(0), 0)
}

///|
test "tokens past the line end clamp to the line" {
  let lt = line_tokens_from_lexer_tokens(
    "ab",
    [{ start: 0, end: 5, tag: Keyword, }],
    @services.language_id_codec,
  )
  assert_eq(lt.get_line_content(), "ab")
  assert_eq(lt.get_count(), 1)
  assert_eq(lt.inflate().get_end_offset(0), 2)
}

///|
fn assert_same_code_units(actual : String, expected : String) -> Unit raise {
  assert_eq(actual.length(), expected.length())
  for i in 0..<expected.length() {
    assert_eq(actual[i].to_int(), expected[i].to_int())
  }
}

///|
test "raw UTF16 encoder preserves lone surrogates pair halves FEFF and BMP boundaries" {
  let d800 = Int32::unsafe_to_char(0xD800).to_string()
  let dbff = Int32::unsafe_to_char(0xDBFF).to_string()
  let dc00 = Int32::unsafe_to_char(0xDC00).to_string()
  let dfff = Int32::unsafe_to_char(0xDFFF).to_string()
  let high = Int32::unsafe_to_char(0xD83D).to_string()
  let low = Int32::unsafe_to_char(0xDE0A).to_string()
  for held in [d800, dbff, dc00, dfff, high, low, "\u{FEFF}", "A"] {
    let line = "\{held}x"
    let words = encode_raw_start_offsets(
      [{ start: 0, end: 1, tag: Keyword, }],
      line.length(),
    )
    assert_eq(words[0], 0)
    assert_eq(words[2], 1)
    start_offsets_to_end_offsets(words, line.length())
    let tokens = @common_tokens.LineTokens(
      words, line, @services.language_id_codec,
    )
    let view = tokens.inflate()
    assert_same_code_units(view.get_token_text(0), held)
    assert_same_code_units(view.get_token_text(1), "x")
  }
}
