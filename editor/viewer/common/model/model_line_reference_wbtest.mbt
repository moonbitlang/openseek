///| Faithful conformance port of
/// `vscode/src/vs/editor/test/common/model/model.line.test.ts` in the checked-in
/// vscode source.
///
/// Readonly-subset triage of the file's 53 cases: only the single
/// `ModelLine - getIndentLevel` case is in scope. It exercises `model/utils.ts`
/// `computeIndentLevel` — pure, readonly logic. White-box because that helper
/// is package-internal (vscode exports it, but the viewer keeps it private).
///
/// SKIPPED (out of scope, not silently dropped): all 52 `ModelLinesTokens`
/// cases route through `testApplyEdits` → `model.applyEdits(...)`; the readonly
/// Viewer has no incremental `applyEdits` seam. Their oracle also installs
/// `ManualTokenizationSupport` and observes the manually supplied line tokens;
/// that manually injected support remains deferred. Exact upstream labels, in
/// source order:
///   - SKIPPED: single delete 1
///   - SKIPPED: single delete 2
///   - SKIPPED: single delete 3
///   - SKIPPED: single delete 4
///   - SKIPPED: single delete 5
///   - SKIPPED: multi delete 6
///   - SKIPPED: multi delete 7
///   - SKIPPED: multi delete 8
///   - SKIPPED: multi delete 9
///   - SKIPPED: single insert 1
///   - SKIPPED: single insert 2
///   - SKIPPED: single insert 3
///   - SKIPPED: single insert 4
///   - SKIPPED: single insert 5
///   - SKIPPED: multi insert 6
///   - SKIPPED: multi insert 7
///   - SKIPPED: multi insert 8
///   - SKIPPED: multi insert 9
///   - SKIPPED: insertion on empty line
///   - SKIPPED: updates tokens on insertion 1
///   - SKIPPED: updates tokens on insertion 2
///   - SKIPPED: updates tokens on insertion 3
///   - SKIPPED: updates tokens on insertion 4
///   - SKIPPED: updates tokens on insertion 5
///   - SKIPPED: updates tokens on insertion 6
///   - SKIPPED: updates tokens on insertion 7
///   - SKIPPED: updates tokens on insertion 8
///   - SKIPPED: updates tokens on insertion 9
///   - SKIPPED: updates tokens on insertion 10
///   - SKIPPED: delete second token 2
///   - SKIPPED: insert right before second token
///   - SKIPPED: delete first char
///   - SKIPPED: delete 2nd and 3rd chars
///   - SKIPPED: delete first token
///   - SKIPPED: delete second token
///   - SKIPPED: delete second token + a bit of the third one
///   - SKIPPED: delete second and third token
///   - SKIPPED: delete everything
///   - SKIPPED: noop
///   - SKIPPED: equivalent to deleting first two chars
///   - SKIPPED: equivalent to deleting from 5 to the end
///   - SKIPPED: updates tokens on replace 1
///   - SKIPPED: updates tokens on replace 2
///   - SKIPPED: split at the beginning
///   - SKIPPED: split at the end
///   - SKIPPED: split inthe middle 1
///   - SKIPPED: split inthe middle 2
///   - SKIPPED: append empty 1
///   - SKIPPED: append empty 2
///   - SKIPPED: append 1
///   - SKIPPED: append 2
///   - SKIPPED: append 3

///|
/// Mirrors the suite's `assertIndentLevel(text, expected, tabSize = 4)`.
fn assert_indent_level(
  text : String,
  expected : Int32,
  tab_size~ : Int32 = 4,
) -> Unit raise {
  assert_eq(compute_indent_level(text, tab_size), expected)
}

///|
test "getIndentLevel" {
  assert_indent_level("", -1)
  assert_indent_level(" ", -1)
  assert_indent_level("   \t", -1)
  assert_indent_level("Hello", 0)
  assert_indent_level(" Hello", 1)
  assert_indent_level("   Hello", 3)
  assert_indent_level("\tHello", 4)
  assert_indent_level(" \tHello", 4)
  assert_indent_level("  \tHello", 4)
  assert_indent_level("   \tHello", 4)
  assert_indent_level("    \tHello", 8)
  assert_indent_level("     \tHello", 8)
  assert_indent_level("\t Hello", 5)
  assert_indent_level("\t \tHello", 8)
}
