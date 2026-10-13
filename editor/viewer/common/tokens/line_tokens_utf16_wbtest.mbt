///| Raw UTF-16 regression matrix for `LineTokens` content and slice operations.
///
/// Monaco's offsets are UTF-16 code-unit offsets. These tests freeze lone
/// D800/DBFF/DC00/DFFF values, either half of a valid pair, U+FEFF, ordinary
/// BMP content, and empty/end boundaries without scalar-boundary validation.

///|
fn utf16_unit(code : Int32) -> String {
  Int32::unsafe_to_char(code).to_string()
}

///|
fn assert_utf16_units(actual : String, expected : Array[Int32]) -> Unit raise {
  assert_eq(actual.length(), expected.length())
  for index in 0..<expected.length() {
    assert_eq(actual[index].to_int(), expected[index])
  }
}

///|
test "LineTokens raw UTF-16 token content preserves lone surrogate matrix" {
  let text = "\{utf16_unit(0xD800)}\{utf16_unit(0xDBFF)}\{utf16_unit(0xDC00)}\{utf16_unit(0xDFFF)}\u{FEFF}A"
  let metadata = LineTokens::default_token_metadata()
  let tokens = LineTokens(
    [
      1U,
      metadata.to_uint(),
      2U,
      metadata.to_uint(),
      3U,
      metadata.to_uint(),
      4U,
      metadata.to_uint(),
      5U,
      metadata.to_uint(),
      6U,
      metadata.to_uint(),
    ],
    text,
    @services.language_id_codec,
  )
  let expected : ReadOnlyArray[Int32] = [
    0xD800, 0xDBFF, 0xDC00, 0xDFFF, 0xFEFF, 0x41,
  ]
  for index in 0..<expected.length() {
    assert_utf16_units(tokens.get_token_text(index), [expected[index]])
    let slice = tokens.slice_and_inflate(index, index + 1, 0)
    assert_utf16_units(slice.get_line_content(), [expected[index]])
    assert_utf16_units(slice.get_token_text(0), [expected[index]])
  }
}

///|
test "LineTokens raw UTF-16 slices preserve both halves of a valid pair" {
  let pair = "\u{10000}"
  assert_utf16_units(pair, [0xD800, 0xDC00])
  let tokens = LineTokens(
    [2U, LineTokens::default_token_metadata().to_uint()],
    pair,
    @services.language_id_codec,
  )
  let high = tokens.slice_and_inflate(0, 1, 0)
  assert_utf16_units(high.get_line_content(), [0xD800])
  assert_utf16_units(high.get_token_text(0), [0xD800])
  let low = tokens.slice_and_inflate(1, 2, 0)
  assert_utf16_units(low.get_line_content(), [0xDC00])
  assert_utf16_units(low.get_token_text(0), [0xDC00])
  assert_eq(tokens.slice_and_inflate(0, 0, 0).get_line_content(), "")
  assert_eq(tokens.slice_and_inflate(2, 2, 0).get_line_content(), "")
}

///|
test "LineTokens withInserted accepts a valid-pair interior UTF-16 offset" {
  let pair = "\u{10000}"
  let tokens = LineTokens(
    [2U, LineTokens::default_token_metadata().to_uint()],
    pair,
    @services.language_id_codec,
  )
  let inserted = tokens.with_inserted([
    InsertedToken(1, "X", LineTokens::default_token_metadata()),
  ])
  assert_utf16_units(inserted.get_line_content(), [0xD800, 0x58, 0xDC00])
}
