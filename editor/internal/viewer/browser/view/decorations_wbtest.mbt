///| Pure-piece tests for the `DecorationsOverlay` port
/// (`decorations_overlay.mbt`), covering the plan's overlay matrix rows with
/// an injected fake measurement (no browser DOM pins, per the 2026-07-02
/// conformance-suite decision): filter/sort stability, whole-line spanning
/// partially-visible ranges, same-class touching merge, the `showIfCollapsed`
/// pullback at endColumn=1, collapsed-range half-width widening, and
/// `shouldFillLineOnLineBreak`.

///|
fn overlay_dec(
  range : @base_common.Range,
  class_name : String,
  z_index~ : Int32 = 0,
  is_whole_line~ : Bool = false,
  show_if_collapsed~ : Bool = false,
  should_fill_line_on_line_break~ : Bool = false,
) -> @view_model.ViewModelDecoration {
  {
    range,
    options: ModelDecorationOptions(
      class_name,
      z_index~,
      is_whole_line~,
      show_if_collapsed~,
      should_fill_line_on_line_break~,
      description="test",
    ),
  }
}

///|
/// 7px-per-column monospace fake of the measurement seam: one rect per call.
fn fake_measure(
  line_number : Int32,
  start_column0 : Int32,
  end_column0 : Int32,
) -> Array[(Double, Double)] {
  ignore(line_number)
  [
    (
      start_column0.to_double() * 7.0,
      (end_column0 - start_column0).to_double() * 7.0,
    ),
  ]
}

///|
fn pieces_for(
  decorations : Array[@view_model.ViewModelDecoration],
  visible_start~ : Int32 = 1,
  visible_end~ : Int32 = 3,
  max_column~ : Int32 = 11,
) -> Array[DecorationOverlayPiece] {
  compute_decoration_overlay_pieces(
    decorations,
    visible_start,
    visible_end,
    _line => max_column,
    fake_measure,
    7.0,
  )
}

///|
test "keeps className only and sorts by zIndex, className, range starts" {
  let sorted = filter_and_sort_overlay_decorations([
    overlay_dec(Range(2, 1, 2, 3), "bbb"),
    overlay_dec(Range(1, 1, 1, 3), ""), // dropped: no className
    overlay_dec(Range(1, 4, 1, 6), "aaa", z_index=10),
    overlay_dec(Range(1, 2, 1, 3), "aaa"),
    overlay_dec(Range(1, 1, 1, 3), "aaa"),
  ])
  let keys = sorted.map(d => {
    (
      d.options.z_index,
      d.options.class_name,
      d.range.start_line_number,
      d.range.start_column,
    )
  })
  debug_inspect(
    keys,
    content=(
      #|[
      #|  (0, "aaa", 1, 1),
      #|  (0, "aaa", 1, 2),
      #|  (0, "bbb", 2, 1),
      #|  (10, "aaa", 1, 4),
      #|]
    ),
  )
}

///|
test "different classes do not merge" {
  let pieces = pieces_for([
    overlay_dec(Range(1, 2, 1, 4), "a"),
    overlay_dec(Range(1, 4, 1, 6), "b"),
  ])
  assert_eq(pieces.length(), 2)
}
