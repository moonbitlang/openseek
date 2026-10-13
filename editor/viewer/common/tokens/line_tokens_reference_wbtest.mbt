///| Faithful conformance port of vscode's `LineTokens` suite.
///
/// Source: `src/vs/editor/test/common/core/lineTokens.test.ts` (pinned `vscode/`
/// submodule). All 7 `test(...)` cases are ported with their original names; the
/// `createTestLineTokens` / `renderLineTokens` / `assertViewLineTokens` helpers
/// mirror the source.

///|
/// Mirrors the suite's `createLineTokens(text, tokens)`: `tokens` is a list of
/// `(startIndex, foreground)` pairs.
fn create_line_tokens(
  text : String,
  tokens : Array[(Int32, Int32)],
) -> LineTokens {
  let bin_tokens : Array[UInt32] = Array::make(tokens.length() << 1, 0U)
  for i in 0..<tokens.length() {
    let end_index = if i + 1 < tokens.length() {
      tokens[i + 1].0
    } else {
      text.length()
    }
    bin_tokens[i << 1] = end_index.reinterpret_as_uint()
    bin_tokens[(i << 1) + 1] = (tokens[i].1 << METADATA_FOREGROUND_OFFSET).reinterpret_as_uint()
  }
  LineTokens(bin_tokens, text, @services.language_id_codec)
}

///|
fn create_test_line_tokens() -> LineTokens {
  create_line_tokens("Hello world, this is a lovely day", [
    (0, 1), // Hello_
    (6, 2), // world,_
    (13, 3), // this_
    (18, 4), // is_
    (21, 5), // a_
    (23, 6), // lovely_
    (30, 7), // day
  ])
}

///|
fn render_line_tokens(tokens : LineTokens) -> String {
  let result = StringBuilder()
  let str = tokens.get_line_content()
  let mut last_offset = 0
  for i in 0..<tokens.get_count() {
    result <+
      "\{substr(str, last_offset, tokens.get_end_offset(i))}(\{tokens.get_metadata(i).to_uint()})"
    last_offset = tokens.get_end_offset(i)
  }
  result.to_string()
}

///|
/// Mirrors `assertViewLineTokens`: compares `(endIndex, foreground)` per token.
fn assert_view_line_tokens(
  actual : ViewLineTokens,
  expected : Array[(Int32, Int32)],
) -> Unit raise {
  // Assert scalar fields per element (avoids the deprecated `Show`-based
  // `assert_eq` on tuples/arrays while keeping per-element failure detail).
  assert_eq(actual.get_count(), expected.length())
  for i in 0..<expected.length() {
    assert_eq(actual.get_end_offset(i), expected[i].0)
    assert_eq(actual.get_class_name(i), "mtk\{expected[i].1.to_string()}")
  }
}

///|
test "withInserted 1" {
  let line_tokens = create_test_line_tokens()
  assert_eq(
    render_line_tokens(line_tokens),
    "Hello (32768)world, (65536)this (98304)is (131072)a (163840)lovely (196608)day(229376)",
  )
  let line_tokens2 = line_tokens.with_inserted([
    { offset: 0, text: "1", token_metadata: TokenMetadata(0U), },
    { offset: 6, text: "2", token_metadata: TokenMetadata(0U), },
    { offset: 9, text: "3", token_metadata: TokenMetadata(0U), },
  ])
  assert_eq(
    render_line_tokens(line_tokens2),
    "1(0)Hello (32768)2(0)wor(65536)3(0)ld, (65536)this (98304)is (131072)a (163840)lovely (196608)day(229376)",
  )
}

///|
test "withInserted (tokens at the same position)" {
  let line_tokens = create_test_line_tokens()
  assert_eq(
    render_line_tokens(line_tokens),
    "Hello (32768)world, (65536)this (98304)is (131072)a (163840)lovely (196608)day(229376)",
  )
  let line_tokens2 = line_tokens.with_inserted([
    { offset: 0, text: "1", token_metadata: TokenMetadata(0U), },
    { offset: 0, text: "2", token_metadata: TokenMetadata(0U), },
    { offset: 0, text: "3", token_metadata: TokenMetadata(0U), },
  ])
  assert_eq(
    render_line_tokens(line_tokens2),
    "1(0)2(0)3(0)Hello (32768)world, (65536)this (98304)is (131072)a (163840)lovely (196608)day(229376)",
  )
}

///|
test "withInserted (tokens at the end)" {
  let line_tokens = create_test_line_tokens()
  assert_eq(
    render_line_tokens(line_tokens),
    "Hello (32768)world, (65536)this (98304)is (131072)a (163840)lovely (196608)day(229376)",
  )
  let len = "Hello world, this is a lovely day".length()
  let line_tokens2 = line_tokens.with_inserted([
    { offset: len - 1, text: "1", token_metadata: TokenMetadata(0U), },
    { offset: len, text: "2", token_metadata: TokenMetadata(0U), },
  ])
  assert_eq(
    render_line_tokens(line_tokens2),
    "Hello (32768)world, (65536)this (98304)is (131072)a (163840)lovely (196608)da(229376)1(0)y(229376)2(0)",
  )
}

///|
test "basics" {
  let line_tokens = create_test_line_tokens()
  assert_eq(line_tokens.get_line_content(), "Hello world, this is a lovely day")
  assert_eq(line_tokens.get_line_content().length(), 33)
  assert_eq(line_tokens.get_count(), 7)
  assert_eq(line_tokens.get_start_offset(0), 0)
  assert_eq(line_tokens.get_end_offset(0), 6)
  assert_eq(line_tokens.get_start_offset(1), 6)
  assert_eq(line_tokens.get_end_offset(1), 13)
  assert_eq(line_tokens.get_start_offset(2), 13)
  assert_eq(line_tokens.get_end_offset(2), 18)
  assert_eq(line_tokens.get_start_offset(3), 18)
  assert_eq(line_tokens.get_end_offset(3), 21)
  assert_eq(line_tokens.get_start_offset(4), 21)
  assert_eq(line_tokens.get_end_offset(4), 23)
  assert_eq(line_tokens.get_start_offset(5), 23)
  assert_eq(line_tokens.get_end_offset(5), 30)
  assert_eq(line_tokens.get_start_offset(6), 30)
  assert_eq(line_tokens.get_end_offset(6), 33)
}

///|
test "findToken" {
  let line_tokens = create_test_line_tokens()
  let expected : ReadOnlyArray[Int32] = [
    0, 0, 0, 0, 0, 0, // offsets 0..5  -> token 0
     1, 1, 1, 1, 1, 1, 1, // offsets 6..12 -> token 1
     2, 2, 2, 2, 2, // offsets 13..17 -> token 2
     3, 3, 3, // offsets 18..20 -> token 3
     4, 4, // offsets 21..22 -> token 4
     5, 5, 5, 5, 5, 5, 5, // offsets 23..29 -> token 5
     6, 6, 6, 6, 6, // offsets 30..34 -> token 6
  ]
  for offset in 0..<expected.length() {
    assert_eq(line_tokens.find_token_index_at_offset(offset), expected[offset])
  }
}

///|
test "inflate" {
  let line_tokens = create_test_line_tokens()
  assert_view_line_tokens(line_tokens.inflate(), [
    (6, 1),
    (13, 2),
    (18, 3),
    (21, 4),
    (23, 5),
    (30, 6),
    (33, 7),
  ])
}

///|
test "sliceAndInflate" {
  let line_tokens = create_test_line_tokens()
  assert_view_line_tokens(line_tokens.slice_and_inflate(0, 33, 0), [
    (6, 1),
    (13, 2),
    (18, 3),
    (21, 4),
    (23, 5),
    (30, 6),
    (33, 7),
  ])
  assert_view_line_tokens(line_tokens.slice_and_inflate(0, 32, 0), [
    (6, 1),
    (13, 2),
    (18, 3),
    (21, 4),
    (23, 5),
    (30, 6),
    (32, 7),
  ])
  assert_view_line_tokens(line_tokens.slice_and_inflate(0, 30, 0), [
    (6, 1),
    (13, 2),
    (18, 3),
    (21, 4),
    (23, 5),
    (30, 6),
  ])
  assert_view_line_tokens(line_tokens.slice_and_inflate(0, 30, 1), [
    (7, 1),
    (14, 2),
    (19, 3),
    (22, 4),
    (24, 5),
    (31, 6),
  ])
  assert_view_line_tokens(line_tokens.slice_and_inflate(6, 18, 0), [
    (7, 2),
    (12, 3),
  ])
  assert_view_line_tokens(line_tokens.slice_and_inflate(7, 18, 0), [
    (6, 2),
    (11, 3),
  ])
  assert_view_line_tokens(line_tokens.slice_and_inflate(6, 17, 0), [
    (7, 2),
    (11, 3),
  ])
  assert_view_line_tokens(line_tokens.slice_and_inflate(6, 19, 0), [
    (7, 2),
    (12, 3),
    (13, 4),
  ])
}
