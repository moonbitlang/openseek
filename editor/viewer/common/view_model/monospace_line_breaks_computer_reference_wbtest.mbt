///| Faithful conformance port of vscode's monospace line-break computer with
/// `wrappingIndent`.
///
/// Source: `src/vs/editor/common/viewModel/monospaceLineBreaksComputer.ts`
/// (`createLineBreaks` + `computeWrappedTextIndentLength`) and
/// `src/vs/editor/common/modelLineProjectionData.ts` (the indent stored as
/// `wrappedTextIndentLength` and surfaced through `getMinOutputOffset`). Each
/// case pins both the break boundaries **and** the per-continuation indent for a
/// representative line, mirroring the token `*_reference_wbtest`s. White-box so
/// the `ModelLineProjectionData.segments` can be read directly.
///
/// The default (estimated) `FontInfo` measures full-width characters at twice
/// the half-width advance, so `columnsForFullWidthChar` is `2.0` throughout.

///|
/// Runs one line through the batch computer (`createLineBreaksComputer` →
/// `addRequest` → `finalize`).
fn compute_line_breaks(
  wrapping_column : Int32,
  tab_size~ : Int32,
  wrapping_indent~ : @editor_api.WrappingIndent,
  line_text : String,
) -> ModelLineProjectionData? {
  let computer = monospace_line_breaks_computer_factory.create_line_breaks_computer(
    font_info=@config.FontInfo::default(),
    tab_size~,
    wrapping_column~,
    wrapping_indent~,
  )
  computer.add_request(1, line_text, [])
  computer.finalize()[0]
}

///|
/// `(start_offset, end_offset, wrapped_text_indent_length)` per view-line
/// segment — the break boundaries plus the indent applied to each segment
/// (`0` for the first, the model line's indent for continuations).
fn segment_breaks(
  data : ModelLineProjectionData?,
) -> Array[(Int32, Int32, Int32)] {
  data.unwrap().segments.map(s => {
    (s.start_offset, s.end_offset, s.wrapped_text_indent_length)
  })
}

///|
fn assert_segment_breaks(
  actual : Array[(Int32, Int32, Int32)],
  expected : Array[(Int32, Int32, Int32)],
) -> Unit raise {
  assert_eq(actual.length(), expected.length())
  for i in 0..<expected.length() {
    assert_eq(actual[i].0, expected[i].0)
    assert_eq(actual[i].1, expected[i].1)
    assert_eq(actual[i].2, expected[i].2)
  }
}

///|
/// `Same` indent: continuation lines indent under the model line's two leading
/// spaces, shrinking each continuation's break width by 2.
test "wrappingIndent Same indents continuations under leading spaces" {
  let data = compute_line_breaks(
    6,
    tab_size=2,
    wrapping_indent=Same,
    "  abcdefghij",
  )
  assert_segment_breaks(segment_breaks(data), [
    (0, 6, 0),
    (6, 10, 2),
    (10, 12, 2),
  ])
}

///|
/// `Same` indent with a tab: the tab's visible width (4 at tab size 4) becomes
/// the continuation indent.
test "wrappingIndent Same measures a leading tab by its visible width" {
  let data = compute_line_breaks(
    8,
    tab_size=4,
    wrapping_indent=Same,
    "\tabcdefgh",
  )
  assert_segment_breaks(segment_breaks(data), [(0, 5, 0), (5, 9, 4)])
}

///|
/// `Indent` adds one tab stop past the model line's own indent (2 spaces + a
/// 2-column tab = 4), so continuations indent 4 and wrap sooner.
test "wrappingIndent Indent adds one tab stop" {
  let data = compute_line_breaks(
    6,
    tab_size=2,
    wrapping_indent=Indent,
    "  abcdefghij",
  )
  assert_segment_breaks(segment_breaks(data), [
    (0, 6, 0),
    (6, 8, 4),
    (8, 10, 4),
    (10, 12, 4),
  ])
}

///|
/// `DeepIndent` adds two tab stops (2 spaces + two 2-column tabs = 6), which
/// exceeds the wrap column once a full-width char is reserved, so the indent is
/// dropped to 0 and wrapping behaves like `None`.
test "wrappingIndent DeepIndent drops indent that leaves no room" {
  let data = compute_line_breaks(
    6,
    tab_size=2,
    wrapping_indent=DeepIndent,
    "  abcdefghij",
  )
  // wrapped_text_indent_length 6 + columnsForFullWidthChar 2 > 6 -> dropped to 0,
  // so breaking is identical to `None` (and the leading spaces break off first,
  // since the full break width 6 still lets the space at offset 2 win).
  assert_segment_breaks(segment_breaks(data), [(0, 2, 0), (2, 8, 0), (8, 12, 0)])
}

///|
/// Ideographic break with a leading space: width-2 ideographs break per-segment
/// and continuations carry the 1-column indent.
test "wrappingIndent Same with ideographic break points" {
  let data = compute_line_breaks(
    4,
    tab_size=2,
    wrapping_indent=Same,
    " 中文中",
  )
  assert_segment_breaks(segment_breaks(data), [(0, 2, 0), (2, 3, 1), (3, 4, 1)])
}

///|
/// `None` leaves every continuation flush-left (indent 0), the pre-`wrappingIndent`
/// behavior.
test "wrappingIndent None leaves continuations flush-left" {
  let data = compute_line_breaks(
    6,
    tab_size=2,
    wrapping_indent=None,
    "  abcdefghij",
  )
  // With the full break width the leading spaces break onto their own segment;
  // every continuation indent stays 0.
  assert_segment_breaks(segment_breaks(data), [(0, 2, 0), (2, 8, 0), (8, 12, 0)])
}

///|
/// A line that fits its wrapping column is Monaco's `null` result, and so is
/// any line when wrapping is off.
test "lines that need no wrapping produce no projection data" {
  assert_true(
    compute_line_breaks(80, tab_size=2, wrapping_indent=Same, "short") is None,
  )
  assert_true(
    compute_line_breaks(0, tab_size=2, wrapping_indent=Same, "any text at all")
    is None,
  )
}

///|
/// A surrogate pair is an unbreakable width-2 unit (`createLineBreaks`'s
/// `isHighSurrogate` arms): the break lands before or after the pair, never
/// inside it.
test "surrogate pairs never break apart" {
  // "aaaa" + U+1F600 (2 UTF-16 code units) + "bbbb" at column 5: the pair
  // at offsets 4-5 straddles the first break, which clamps to before the
  // pair; no segment boundary ever lands at offset 5 (inside the pair).
  let data = compute_line_breaks(
    5,
    tab_size=2,
    wrapping_indent=None,
    "aaaa😀bbbb",
  )
  assert_segment_breaks(segment_breaks(data), [(0, 4, 0), (4, 9, 0), (9, 10, 0)])
}

///|
/// `wordBreak: 'keepAll'` disables the ideographic break points, so CJK runs
/// wrap only at the forced column like unbroken words.
test "wordBreak keepAll disables ideographic breaks" {
  let computer = monospace_line_breaks_computer_factory.create_line_breaks_computer(
    font_info=@config.FontInfo::default(),
    tab_size=2,
    wrapping_column=4,
    wrapping_indent=None,
    word_break=KeepAll,
  )
  computer.add_request(1, "中文中文", [])
  let data = computer.finalize()[0]
  // Every ideograph is width 2: the forced break fits two per segment, with
  // no per-character ideographic break candidates.
  assert_segment_breaks(segment_breaks(data), [(0, 2, 0), (2, 4, 0)])
}
