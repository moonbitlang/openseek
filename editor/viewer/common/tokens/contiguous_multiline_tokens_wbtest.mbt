///| Conformance coverage for the readonly consumed closures of:
///
/// - `vscode/src/vs/editor/common/tokens/contiguousMultilineTokensBuilder.ts`
/// - `vscode/src/vs/editor/common/tokens/contiguousMultilineTokens.ts`
///
/// Oracle: checked-in reference tree.

///|
fn assert_words(actual : Array[UInt32], expected : Array[UInt32]) -> Unit raise {
  assert_eq(actual.length(), expected.length())
  for index in 0..<expected.length() {
    assert_eq(actual[index], expected[index])
  }
}

///|
fn assert_line_range(
  actual : @base_common.LineRange,
  start_line_number : Int32,
  end_line_number_exclusive : Int32,
) -> Unit raise {
  assert_eq(actual.start_line_number, start_line_number)
  assert_eq(actual.end_line_number_exclusive, end_line_number_exclusive)
}

///|
test "ContiguousMultilineTokensBuilder starts empty" {
  let builder = ContiguousMultilineTokensBuilder()
  assert_eq(builder.finalize().length(), 0)
}

///|
test "ContiguousMultilineTokensBuilder add groups only exact successors" {
  let builder = ContiguousMultilineTokensBuilder()
  builder.add(5, [1U, 11U])
  builder.add(6, [2U, 12U])
  builder.add(8, [3U, 13U])
  builder.add(7, [4U, 14U])
  let batches = builder.finalize()
  assert_eq(batches.length(), 3)
  assert_eq(batches[0].start_line_number(), 5)
  assert_eq(batches[0].end_line_number(), 6)
  assert_line_range(batches[0].get_line_range(), 5, 7)
  assert_words(batches[0].get_line_tokens(5), [1U, 11U])
  assert_words(batches[0].get_line_tokens(6), [2U, 12U])
  assert_eq(batches[1].start_line_number(), 8)
  assert_eq(batches[1].end_line_number(), 8)
  assert_eq(batches[2].start_line_number(), 7)
  assert_eq(batches[2].end_line_number(), 7)
}

///|
test "ContiguousMultilineTokens retains order and append extends inclusive end" {
  let batch = ContiguousMultilineTokens(10, [[1U, 21U], [2U, 22U]])
  assert_eq(batch.start_line_number(), 10)
  assert_eq(batch.end_line_number(), 11)
  assert_line_range(batch.get_line_range(), 10, 12)
  assert_words(batch.get_line_tokens(10), [1U, 21U])
  assert_words(batch.get_line_tokens(11), [2U, 22U])
  batch.append_line_tokens([3U, 23U])
  assert_eq(batch.end_line_number(), 12)
  assert_line_range(batch.get_line_range(), 10, 13)
  assert_words(batch.get_line_tokens(12), [3U, 23U])
}
