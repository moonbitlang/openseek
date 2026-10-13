///|
/// Builds a selection from document offsets, anchor at `anchor_offset`. The
/// offset→`Position` boundary lives in the controller layer, not on the
/// pure-geometry `Selection` (mirrors Monaco keeping clipboard/offset concerns
/// out of `core/selection.ts`).
fn selection_from_offsets(
  snapshot : @model.TextSnapshot,
  anchor_offset : Int32,
  focus_offset : Int32,
) -> @core.Selection {
  let anchor = snapshot
    .range_of(OffsetRange(anchor_offset, anchor_offset))
    .get_start_position()
  let focus = snapshot
    .range_of(OffsetRange(focus_offset, focus_offset))
    .get_start_position()
  Selection(anchor, focus)
}

///|
test "selection normalizes model ranges and copies plain source text" {
  let snapshot = @model.TextSnapshot("abc\ndef")
  let selection = selection_from_offsets(snapshot, 6, 1)
  let range = selection_normalized_range(selection, snapshot)
  assert_eq(range.start, 1)
  assert_eq(range.end_exclusive, 6)
  assert_eq(selection_plain_text_to_copy(selection, snapshot), "bc\nde")
}

///|
/// Clipboard ranges and slices use the same normalized LF coordinate space as
/// the model, including trailing EOLs, UTF-16 text, and a retained U+FEFF.
test "selection clipboard uses normalized offsets and text for every EOL form" {
  let cases : Array[(String, String)] = [
    ("a\r\nb", "a\nb"),
    ("a\rb", "a\nb"),
    (
      "a\r\nb\rc\nd",
      (
        #|a
        #|b
        #|c
        #|d
      ),
    ),
    ("tail\r\n", "tail\n"),
    (
      "🙂\r\nβ\r中\n",
      (
        #|🙂
        #|β
        #|中
        #|
      ),
    ),
    ("\u{FEFF}head\r\ntail", "\u{FEFF}head\ntail"),
  ]
  for sample in cases {
    let raw = sample.0
    let normalized = sample.1
    let snapshot = @model.TextSnapshot(raw)
    let selection = selection_from_offsets(snapshot, normalized.length(), 0)
    let range = selection_normalized_range(selection, snapshot)
    assert_eq(snapshot.get_value(), normalized)
    assert_eq(snapshot.get_value().length(), normalized.length())
    assert_eq(range.start, 0)
    assert_eq(range.end_exclusive, normalized.length())
    assert_eq(selection_plain_text_to_copy(selection, snapshot), normalized)
  }
}

///|
test "selection rich copy escapes source text" {
  let snapshot = @model.TextSnapshot("a < b && c")
  let selection = selection_from_offsets(
    snapshot,
    0,
    snapshot.get_value().length(),
  )
  assert_eq(
    selection_rich_text_to_copy(selection, snapshot),
    "<pre class=\"readonly-editor-copy\">a &lt; b &amp;&amp; c</pre>",
  )
}

///|
test "selection copy uses model text not injected text" {
  let snapshot = @model.TextSnapshot("let x = 1")
  let selection = selection_from_offsets(
    snapshot,
    0,
    snapshot.get_value().length(),
  )
  assert_eq(selection_plain_text_to_copy(selection, snapshot), "let x = 1")
}
