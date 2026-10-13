///| Branch-derived conformance coverage for Monaco's `ContiguousTokensStore`.
///
/// Source: `vscode/src/vs/editor/common/tokens/contiguousTokensStore.ts` at
/// checked-in oracle.

///|
fn store_test_codec() -> @services.LanguageIdCodec {
  let codec = @services.language_id_codec
  ignore(codec.register("store-top"))
  ignore(codec.register("store-embedded"))
  codec
}

///|
fn metadata_for(language_id : Int32, foreground~ : Int32 = 1) -> UInt32 {
  ((language_id << METADATA_LANGUAGEID_OFFSET) |
  (foreground << METADATA_FOREGROUND_OFFSET)).reinterpret_as_uint()
}

///|
fn assert_change(
  actual : ContiguousTokensStoreChange,
  from_line_number : Int32,
  to_line_number : Int32,
) -> Unit raise {
  assert_eq(actual.from_line_number, from_line_number)
  assert_eq(actual.to_line_number, to_line_number)
}

///|
test "ContiguousTokensStore missing read returns exact default metadata" {
  let codec = store_test_codec()
  let store = ContiguousTokensStore(codec)
  assert_eq(store.has_tokens(), false)
  let tokens = store.get_tokens("store-top", 0, "abc")
  assert_eq(tokens.get_count(), 1)
  assert_eq(tokens.get_end_offset(0), 3)
  let metadata = tokens.get_metadata(0)
  assert_eq(metadata.get_language_id(), codec.encode_language_id("store-top"))
  assert_eq(metadata.get_token_type(), STANDARD_TOKEN_TYPE_OTHER)
  assert_eq(metadata.get_font_style(), FONT_STYLE_NONE)
  assert_eq(metadata.get_foreground(), COLOR_ID_DEFAULT_FOREGROUND)
  assert_eq(metadata.get_background(), COLOR_ID_DEFAULT_BACKGROUND)
  assert_eq(metadata.contains_balanced_brackets(), true)
}

///|
test "ContiguousTokensStore distinguishes Missing Empty and Words" {
  let codec = store_test_codec()
  let top_id = codec.encode_language_id("store-top")
  let embedded_id = codec.encode_language_id("store-embedded")
  let store = ContiguousTokensStore(codec)

  // The first Missing -> Empty write changes; a repeated Empty write is equal.
  assert_eq(store.set_tokens("store-top", 0, 0, None, true), true)
  assert_eq(store.has_tokens(), true)
  assert_eq(store.set_tokens("store-top", 0, 0, None, true), false)
  assert_eq(store.set_tokens("store-top", 0, 0, Some([]), true), false)
  assert_eq(store.set_tokens("store-top", 0, 0, Some([0U]), true), false)
  let empty_read = store.get_tokens("store-top", 0, "")
  assert_eq(empty_read.get_metadata(0).get_language_id(), top_id)

  // Embedded-language metadata on an empty line must remain Words, not Empty.
  assert_eq(
    store.set_tokens(
      "store-top",
      2,
      0,
      Some([9U, metadata_for(embedded_id)]),
      true,
    ),
    true,
  )
  let embedded_read = store.get_tokens("store-top", 2, "")
  assert_eq(embedded_read.get_end_offset(0), 0)
  assert_eq(embedded_read.get_metadata(0).get_language_id(), embedded_id)
  // The hole introduced by ensure_line remains Missing and reads as fallback.
  let hole_read = store.get_tokens("store-top", 1, "x")
  assert_eq(hole_read.get_end_offset(0), 1)
  assert_eq(hole_read.get_metadata(0).get_language_id(), top_id)

  store.flush()
  assert_eq(store.has_tokens(), false)
  let after_flush = store.get_tokens("store-top", 2, "xy")
  assert_eq(after_flush.get_end_offset(0), 2)
  assert_eq(after_flush.get_metadata(0).get_language_id(), top_id)
}

///|
test "ContiguousTokensStore massages words and compares every state branch" {
  let codec = store_test_codec()
  let top_id = codec.encode_language_id("store-top")
  let store = ContiguousTokensStore(codec)
  let first_metadata = metadata_for(top_id, foreground=3)
  let second_metadata = metadata_for(top_id, foreground=4)

  let first = [1U, first_metadata, 99U, second_metadata]
  assert_eq(store.set_tokens("store-top", 0, 7, Some(first), true), true)
  // The final end offset is forcibly rewritten in the caller-owned word array.
  assert_eq(first[2], 7U)
  let read = store.get_tokens("store-top", 0, "1234567")
  assert_eq(read.get_count(), 2)
  assert_eq(read.get_end_offset(1), 7)

  assert_eq(
    store.set_tokens(
      "store-top",
      0,
      7,
      Some([1U, first_metadata, 7U, second_metadata]),
      true,
    ),
    false,
  )
  // Unequal length and first unequal word are independently observable.
  assert_eq(
    store.set_tokens("store-top", 0, 7, Some([7U, first_metadata]), true),
    true,
  )
  assert_eq(
    store.set_tokens("store-top", 0, 7, Some([7U, second_metadata]), true),
    true,
  )
  // Null/zero input on a nonempty line manufactures the exact fallback Words.
  assert_eq(store.set_tokens("store-top", 0, 7, Some([]), true), true)
  let fallback = store.get_tokens("store-top", 0, "1234567")
  assert_eq(fallback.get_count(), 1)
  assert_eq(fallback.get_end_offset(0), 7)
  assert_eq(fallback.get_metadata(0).contains_balanced_brackets(), true)
  assert_eq(store.set_tokens("store-top", 0, 7, None, true), false)
  // The unchecked lane stores but always returns false.
  assert_eq(
    store.set_tokens("store-top", 0, 7, Some([7U, second_metadata]), false),
    false,
  )
}

///|
test "ContiguousTokensStore equality preserves all representation states" {
  assert_eq(syntactic_line_tokens_equal(Missing, Missing), true)
  assert_eq(syntactic_line_tokens_equal(Empty, Empty), true)
  assert_eq(syntactic_line_tokens_equal(Missing, Empty), false)
  assert_eq(syntactic_line_tokens_equal(Empty, Words([])), false)
  assert_eq(syntactic_line_tokens_equal(Words([]), Words([])), true)
  assert_eq(syntactic_line_tokens_equal(Words([1U]), Words([1U])), true)
  assert_eq(syntactic_line_tokens_equal(Words([1U]), Words([2U])), false)
  assert_eq(syntactic_line_tokens_equal(Words([1U]), Words([1U, 2U])), false)
}

///|
test "ContiguousTokensStore setMultilineTokens reports one suffix range per changed batch" {
  let codec = store_test_codec()
  let top_id = codec.encode_language_id("store-top")
  let metadata_a = metadata_for(top_id, foreground=3)
  let metadata_b = metadata_for(top_id, foreground=4)
  let store = ContiguousTokensStore(codec)
  ignore(store.set_tokens("store-top", 0, 1, Some([1U, metadata_a]), true))
  ignore(store.set_tokens("store-top", 1, 2, Some([2U, metadata_a]), true))
  ignore(store.set_tokens("store-top", 2, 3, Some([3U, metadata_a]), true))

  let line_length_calls : Array[Int32] = []
  let update = store.set_multiline_tokens(
    [
      ContiguousMultilineTokens(1, [
        [1U, metadata_a], // equal prefix
        [2U, metadata_b], // first difference
        [3U, metadata_a], // unchecked suffix still extends max
      ]),
      ContiguousMultilineTokens(5, [[5U, metadata_b]]),
    ],
    "store-top",
    line_number => {
      line_length_calls.push(line_number)
      line_number
    },
  )
  assert_eq(update.changes.length(), 2)
  assert_change(update.changes[0], 2, 3)
  assert_change(update.changes[1], 5, 5)
  assert_eq(line_length_calls.length(), 4)
  for index in 0..<4 {
    assert_eq(line_length_calls[index], [1, 2, 3, 5][index])
  }

  let no_batches = store.set_multiline_tokens([], "store-top", _ => 0)
  assert_eq(no_batches.changes.length(), 0)
  let equal_again = store.set_multiline_tokens(
    [
      ContiguousMultilineTokens(1, [
        [1U, metadata_a],
        [2U, metadata_b],
        [3U, metadata_a],
      ]),
    ],
    "store-top",
    line_number => line_number,
  )
  assert_eq(equal_again.changes.length(), 0)
}
