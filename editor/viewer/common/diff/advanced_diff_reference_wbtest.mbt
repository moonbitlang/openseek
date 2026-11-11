// Algorithm-fidelity reference tests for VS Code Advanced diff, pinned at
// 07c20d96cf3f2cbc8142ac7079ba9048cf7f6134.
//
// Source clusters:
// - src/vs/editor/common/diff/defaultLinesDiffComputer/
//   defaultLinesDiffComputer.ts:67-113,221-248
// - src/vs/editor/common/diff/defaultLinesDiffComputer/
//   heuristicSequenceOptimizations.ts:12-180,183-472
// - src/vs/editor/test/node/diffing/fixtures/{shifting-parameters,
//   word-shared-letters}/advanced.expected.diff.json

///|
fn advanced_compute(original : String, modified : String) -> DocumentDiff {
  get_line_document_diff_provider().compute_diff(
    TextSnapshot(original),
    TextSnapshot(modified),
    { ignore_trim_whitespace: false, },
  )
}

///|
test "reference: one natural parameter insertion is not fragmented" {
  // `shifting-parameters`: optimizeSequenceDiffs keeps the comma-delimited
  // insertion as one range at the stronger punctuation/whitespace boundary.
  let result = advanced_compute(
    "function x(alignments: RangeMapping[]): x[] { }", "function x(alignments: RangeMapping[], originalLines: string[], modifiedLines: string[]): x[] { }",
  )
  guard result.changes is [{ mapping: change, .. }] &&
    change.inner_changes is Some([inner]) else {
    fail("expected one line hunk with one inner insertion")
  }
  assert_eq(inner.original, Range(1, 38, 1, 38))
  assert_eq(inner.modified, Range(1, 38, 1, 88))
}

///|
test "reference: Array to FixedArray highlights only the inserted subword" {
  // This is the review's 84bfd310 representative edit. Whole-word expansion
  // keeps the sufficiently large shared `Array` suffix unchanged.
  let result = advanced_compute(
    "let values : Array[Int] = []", "let values : FixedArray[Int] = []",
  )
  guard result.changes is [{ mapping: change, .. }] &&
    change.inner_changes is Some([inner]) else {
    fail("expected one inserted subword")
  }
  assert_eq(inner.original, Range(1, 14, 1, 14))
  assert_eq(inner.modified, Range(1, 14, 1, 19))
}

///|
test "reference: shared letters do not split ordinary identifier replacements" {
  // `word-shared-letters`, test case 2: private -> protected. The raw LCS can
  // retain internal letters; extendDiffsToEntireWordIfAppropriate marks the
  // natural identifier boundary instead.
  let result = advanced_compute(
    "\tconst private = 1;", "\tconst protected = 1;",
  )
  guard result.changes is [{ mapping: change, .. }] &&
    change.inner_changes is Some([inner]) else {
    fail("expected one whole-identifier replacement")
  }
  assert_eq(inner.original, Range(1, 8, 1, 15))
  assert_eq(inner.modified, Range(1, 8, 1, 17))
}

///|
test "reference: repeated identifier letters shift insertion to punctuation" {
  // `ts-diff-word-split`: the insertion belongs at the comma-delimited item
  // boundary, not inside the shared I/Foo/Bar identifier letters.
  let result = advanced_compute(
    "import { IFooBar, IFoo } from 'foo';", "import { IFooBar, IBar, IFoo } from 'foo';",
  )
  guard result.changes is [{ mapping: change, .. }] &&
    change.inner_changes is Some([inner]) else {
    fail("expected one punctuation-aligned insertion")
  }
  assert_eq(inner.original, Range(1, 18, 1, 18))
  assert_eq(inner.modified, Range(1, 18, 1, 24))
}

///|
test "reference: tiny unchanged structural line joins substantial refactor hunks" {
  // removeVeryShortMatchingLinesBetweenDiffs joins two substantial changes
  // separated only by `}` (one non-whitespace UTF-16 code unit).
  let original = [
    "fn old_header() {", "  old_alpha()", "  old_beta()", "}", "fn old_tail() {",
    "  old_gamma()", "  old_delta()",
  ]
  let modified = [
    "fn new_header() {", "  new_alpha()", "  new_beta()", "}", "fn new_tail() {",
    "  new_gamma()", "  new_delta()",
  ]
  let result = advanced_compute(original.join("\n"), modified.join("\n"))
  guard result.changes is [{ mapping: change, .. }] else {
    fail("expected the refactor to form one readable hunk")
  }
  assert_eq(change.original, LineRange(1, 8))
  assert_eq(change.modified, LineRange(1, 8))
}

///|
test "reference: substantial edits absorb at most twenty UTF-16 units of matching text" {
  let cases : Array[(String, String, @base_common.Range)] = [
    (
      "a".repeat(80) + " + " + "c".repeat(80),
      "b".repeat(80) + " + " + "d".repeat(80),
      Range(1, 1, 1, 164),
    ),
    (
      "a".repeat(80) + " 12345678901234567890 " + "c".repeat(80),
      "b".repeat(80) + " 12345678901234567890 " + "d".repeat(80),
      Range(1, 1, 1, 183),
    ),
  ]
  for (original, modified, expected) in cases {
    let result = advanced_compute(original, modified)
    guard result.changes
      is [{ mapping: { inner_changes: Some([inner]), .. }, .. }] else {
      fail("expected one long-diff refinement")
    }
    assert_eq(inner.original, expected)
    assert_eq(inner.modified, expected)
  }

  let separated = advanced_compute(
    "a".repeat(80) + " 123456789012345678901 " + "c".repeat(80),
    "b".repeat(80) + " 123456789012345678901 " + "d".repeat(80),
  )
  guard separated.changes
    is [{ mapping: { inner_changes: Some(inner), .. }, .. }] else {
    fail("expected refined long diff")
  }
  assert_eq(inner.length(), 2)
  assert_eq(inner[0].original, Range(1, 1, 1, 81))
  assert_eq(inner[0].modified, Range(1, 1, 1, 81))
  assert_eq(inner[1].original, Range(1, 104, 1, 184))
  assert_eq(inner[1].modified, Range(1, 104, 1, 184))
}

///|
test "reference: only changes over one hundred UTF-16 units absorb short line trim" {
  let expanded = advanced_compute(
    "  " + "a".repeat(60) + " ; ",
    "  " + "b".repeat(60) + " ; ",
  )
  guard expanded.changes
    is [{ mapping: { inner_changes: Some([inner]), .. }, .. }] else {
    fail("expected one expanded long diff")
  }
  assert_eq(inner.original, Range(1, 1, 1, 66))
  assert_eq(inner.modified, Range(1, 1, 1, 66))

  let exact_guard = advanced_compute(
    "  " + "a".repeat(50),
    "  " + "b".repeat(50),
  )
  guard exact_guard.changes
    is [{ mapping: { inner_changes: Some([inner]), .. }, .. }] else {
    fail("expected one unexpanded threshold diff")
  }
  assert_eq(inner.original, Range(1, 3, 1, 53))
  assert_eq(inner.modified, Range(1, 3, 1, 53))
}

///|
test "reference: two emoji are a four-unit match and stay between small diffs" {
  let result = advanced_compute("aa😀😀cc", "bb😀😀dd")
  guard result.changes is [{ mapping: { inner_changes: Some(inner), .. }, .. }] else {
    fail("expected refined emoji-gap changes")
  }
  assert_eq(inner.length(), 2)
  assert_eq(inner[0].original, Range(1, 1, 1, 3))
  assert_eq(inner[0].modified, Range(1, 1, 1, 3))
  assert_eq(inner[1].original, Range(1, 7, 1, 9))
  assert_eq(inner[1].modified, Range(1, 7, 1, 9))
}
