// Headless matrix for the public read-API getter cluster (`public_read_api.mbt`),
// the MoonBit analog of vscode's codeEditorWidget read-state tests. Runs over the
// unattached `with_test_viewer` harness (no DOM), so it covers every non-DOM
// getter across the behavior-switching variables the plan calls out: model
// present {no, yes} x wrap {off, on} x scroll
// {top, scrolled} x position {start, mid, past-EOL}. The DOM-measured
// trio (`get_offset_for_column` / `get_width_of_line` /
// `get_scrolled_visible_position`) is asserted in the browser suite.

///|
/// Injects layout-only whitespace (no DOM node), the headless analog of
/// `change_view_zones`, so the `include_view_zones` branch of the vertical-offset
/// getters can be exercised without a rendered view.
fn CodeEditorWidget::test_set_layout_view_zones(
  self : CodeEditorWidget,
  zones : Array[(Int32, Int32)],
) -> Unit {
  match self.get_view_model() {
    Some(view_model) =>
      view_model.view_layout.change_whitespace(accessor => {
        for ordinal, zone in zones {
          accessor.insert_whitespace(zone.0, ordinal, zone.1.to_double(), 0.0)
          |> ignore
        }
      })
      |> ignore
    None => ()
  }
}

///|
/// No model: every getter returns its exact Monaco sentinel. The column getters
/// return the *raw input column*, not `-1` — a load-bearing distinction.
test "read API: no-model getters return Monaco sentinels" {
  let viewer = CodeEditorWidget::CodeEditorWidget()
  assert_eq(viewer.get_value(), "")
  assert_eq(viewer.get_visible_ranges().length(), 0)
  assert_eq(viewer.get_visible_ranges_plus_viewport_above_below().length(), 0)
  assert_eq(viewer.get_top_for_line_number(1), -1.0)
  assert_eq(viewer.get_top_for_position(1, 1), -1.0)
  assert_eq(viewer.get_bottom_for_line_number(1), -1.0)
  assert_eq(viewer.get_line_height_for_position(Position(1, 1)), -1.0)
  assert_eq(viewer.get_visible_column_from_position(Position(5, 7)), 7)
  assert_eq(viewer.get_statusbar_column(Position(5, 7)), 7)
  assert_true(viewer.get_position() is None)
  assert_true(viewer.get_selection() is None)
  assert_true(viewer.get_selections() is None)
  assert_eq(viewer.get_content_width(), -1.0)
  assert_eq(viewer.get_scroll_width(), -1.0)
  assert_eq(viewer.get_scroll_left(), -1.0)
  assert_eq(viewer.get_content_height(), -1.0)
  assert_eq(viewer.get_scroll_height(), -1.0)
  assert_eq(viewer.get_scroll_top(), -1.0)
  viewer.dispose()
}

///|
/// No model: the scroll setters no-op (`cew:1003-1029`) and `save_view_state`
/// returns `None` (`cew:1038-1041`).
test "read API: no-model scroll writes no-op and view state is None" {
  let viewer = CodeEditorWidget::CodeEditorWidget()
  viewer.set_scroll_top(120.0)
  viewer.set_scroll_left(80.0)
  viewer.set_scroll_position(scroll_top=50.0, scroll_left=60.0)
  assert_eq(viewer.get_scroll_top(), -1.0)
  assert_eq(viewer.get_scroll_left(), -1.0)
  assert_true(viewer.save_view_state() is None)
  viewer.restore_view_state(
    Some({ scroll_top: 10.0, scroll_left: 20.0, folding_state: None, }),
  )
  assert_eq(viewer.get_scroll_top(), -1.0)
  viewer.dispose()
}

///|
/// Swapping models starts the fresh model at the scroll origin *structurally*
/// (the layout lives on the per-model view model, `viewModelImpl.ts:126`) —
/// no manual reset runs in `set_model`.
test "read API: set_model twice starts the new model at the origin" {
  let viewer = CodeEditorWidget::CodeEditorWidget()
  viewer.set_model(Some(test_model(long_document(200))))
  viewer.test_set_viewport(width=800.0, height=180.0)
  viewer.set_scroll_top(500.0)
  assert_eq(viewer.get_scroll_top(), 500.0)
  let second = test_model(long_document(150))
  viewer.set_model(Some(second))
  assert_eq(viewer.get_scroll_top(), 0.0)
  assert_eq(viewer.get_scroll_left(), 0.0)
  viewer.dispose()
}

///|
/// `get_value` emits the normalized LF document text.
test "read API: get_value returns the normalized document text" {
  let cases : Array[(String, String)] = [
    ("alpha\r\nbeta", "alpha\nbeta"),
    ("alpha\rbeta", "alpha\nbeta"),
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
    with_test_viewer(raw, viewer => assert_eq(viewer.get_value(), normalized))
  }
}

///|
/// Vertical offsets at the uniform 18px line height: top of line k = (k-1)*18,
/// bottom of line k = k*18.
test "read API: vertical offsets at uniform line height" {
  with_test_viewer(
    (
      #|a
      #|b
      #|c
      #|d
      #|e
    ),
    viewer => {
      assert_eq(viewer.get_top_for_line_number(1), 0.0)
      assert_eq(viewer.get_top_for_line_number(3), 36.0)
      assert_eq(viewer.get_top_for_position(3, 1), 36.0)
      assert_eq(viewer.get_top_for_line_number(5), 72.0)
      assert_eq(viewer.get_bottom_for_line_number(1), 18.0)
      assert_eq(viewer.get_bottom_for_line_number(5), 90.0)
    },
  )
}

///|
/// `include_view_zones` both ways with a 30px zone anchored after line 2: the
/// default offset of line 3 sits below the zone (36 + 30), `include_view_zones`
/// places it at the zone's own top (36) — Monaco's
/// `getVerticalOffsetForLineNumber(n, includeViewZones)` whitespace-before delta.
test "read API: include_view_zones shifts the vertical offset past a zone" {
  with_test_viewer(
    (
      #|a
      #|b
      #|c
      #|d
      #|e
    ),
    viewer => {
      viewer.test_set_layout_view_zones([(2, 30)])
      assert_eq(
        viewer.get_top_for_line_number(3, include_view_zones=false),
        66.0,
      )
      assert_eq(
        viewer.get_top_for_line_number(3, include_view_zones=true),
        36.0,
      )
      // The bottom of line 5 includes the zone height regardless.
      assert_eq(viewer.get_bottom_for_line_number(5), 120.0)
    },
  )
}

///|
/// Reveal bounds use the same line box as the ordinary reveal pipeline. A zone
/// before the start shifts the whole box; a zone inside a multi-line range
/// expands that box without changing its first-line anchor.
test "read API: vertical reveal bounds match line reveal geometry" {
  with_test_viewer(
    (
      #|a
      #|b
      #|c
      #|d
      #|e
    ),
    viewer => {
      viewer.test_set_layout_view_zones([(2, 30)])
      assert_eq(
        viewer.get_vertical_reveal_bounds(Range(3, 1, 3, 1)),
        Some((66.0, 84.0)),
      )
      assert_eq(
        viewer.get_vertical_reveal_bounds(Range(2, 1, 3, 1)),
        Some((18.0, 84.0)),
      )
    },
  )
}

///|
/// Scroll and content extents over a known content size and scroll position.
test "read API: scroll and content extents" {
  with_test_viewer(long_document(200), viewer => {
    viewer.test_set_viewport(width=800.0, height=400.0)
    viewer.set_scroll_position(scroll_top=720.0, scroll_left=0.0)
    assert_eq(viewer.get_scroll_top(), 720.0)
    assert_eq(viewer.get_scroll_left(), 0.0)
    assert_eq(viewer.get_content_height(), 3600.0) // 200 lines * 18px
    assert_eq(viewer.get_scroll_height(), 3600.0) // max(viewport 400, 3600)
    // Content narrower than the viewport: scroll width clamps up to the viewport.
    assert_eq(viewer.get_scroll_width(), 800.0)
    assert_true(viewer.get_content_width() >= 0.0)
  })
}

///|
/// Visible ranges at the top: a single model range from line 1 to the last line
/// fully on screen (400px / 18px → lines 1..22).
test "read API: visible ranges at top span the on-screen model lines" {
  with_test_viewer(long_document(200), viewer => {
    viewer.test_set_viewport(width=800.0, height=400.0)
    viewer.set_scroll_position(scroll_top=0.0, scroll_left=0.0)
    let ranges = viewer.get_visible_ranges()
    assert_eq(ranges.length(), 1)
    assert_eq(ranges[0].start_line_number, 1)
    assert_eq(ranges[0].end_line_number, 22)
  })
}

///|
/// Visible ranges scrolled: the window tracks the scrolled, fully-visible band.
test "read API: visible ranges track the scrolled window" {
  with_test_viewer(long_document(200), viewer => {
    viewer.test_set_viewport(width=800.0, height=400.0)
    viewer.set_scroll_position(scroll_top=720.0, scroll_left=0.0) // 40 lines down
    let ranges = viewer.get_visible_ranges()
    assert_eq(ranges.length(), 1)
    assert_eq(ranges[0].start_line_number, 41)
    assert_eq(ranges[0].end_line_number, 62)
  })
}

///|
/// `getVisibleRangesPlusViewportAboveBelow`: completely-visible band grown by
/// `linesAround = max(20, round(height/lineHeight))` on each side, clamped to the
/// document.
test "read API: visible ranges plus viewport padding grows the window" {
  with_test_viewer(long_document(200), viewer => {
    viewer.test_set_viewport(width=800.0, height=400.0)
    viewer.set_scroll_position(scroll_top=720.0, scroll_left=0.0)
    let padded = viewer.get_visible_ranges_plus_viewport_above_below()
    assert_eq(padded.length(), 1)
    // completely visible [41,62]; linesAround = max(20, round(400/18)=22) = 22.
    assert_eq(padded[0].start_line_number, 19) // max(1, 41-22)
    assert_eq(padded[0].end_line_number, 84) // min(200, 62+22)
  })
}

///|
/// Word-wrap on: a model line spans multiple view lines, so the completely
/// visible *view* range must convert back to a model range. "abcdefghij" wrapped
/// at column 6 makes 2 view lines for 1 model line; the visible range is the one
/// model line.
test "read API: visible ranges convert view to model coordinates under wrap" {
  let options = CodeEditorOptions(soft_wrap=true)
  with_test_viewer(
    "abcdefghij",
    viewer => {
      viewer.test_set_soft_wrap_column(6)
      viewer.test_set_viewport(width=800.0, height=400.0)
      let ranges = viewer.get_visible_ranges()
      assert_eq(ranges.length(), 1)
      assert_eq(ranges[0].start_line_number, 1)
      assert_eq(ranges[0].end_line_number, 1)
      // The model range closes at the model line's max column (10 chars → 11).
      assert_eq(ranges[0].end_column, 11)
    },
    options~,
  )
}

///|
/// Columns: tab expansion and the `+1` offset. With tab size 4, a tab snaps to
/// stop 4; column 2 (just after the tab) reports visible column 5. Past-EOL
/// columns are validated down to the line's max column first.
test "read API: visible and statusbar columns expand tabs" {
  let options = CodeEditorOptions(tab_size=4)
  with_test_viewer(
    "\tabc",
    viewer => {
      assert_eq(viewer.get_visible_column_from_position(Position(1, 1)), 1)
      assert_eq(viewer.get_statusbar_column(Position(1, 1)), 1)
      assert_eq(viewer.get_visible_column_from_position(Position(1, 2)), 5)
      assert_eq(viewer.get_statusbar_column(Position(1, 2)), 5)
      // column 99 validates down to max column 5 ("\tabc" is 4 chars):
      // tab(→4) + a + b + c = 7, then +1 = 8.
      assert_eq(viewer.get_visible_column_from_position(Position(1, 99)), 8)
    },
    options~,
  )
}

///|
/// Selection and position continue to report model coordinates while wrapping
/// is active; the wrapped presentation does not leak view-line coordinates.
test "read API: selection and position report model coordinates under wrap" {
  let options = CodeEditorOptions(soft_wrap=true)
  with_test_viewer(
    "abcdefghij",
    viewer => {
      viewer.test_set_soft_wrap_column(6)
      viewer.set_position(Position(1, 7))
      let position = viewer.get_position().unwrap()
      assert_eq(position.line_number, 1)
      assert_eq(position.column, 7)
      let selections = viewer.get_selections().unwrap()
      assert_eq(selections.length(), 1)
      let selection = viewer.get_selection().unwrap()
      assert_eq(selection.get_position().line_number, 1)
      assert_eq(selection.get_position().column, 7)
      assert_true(selection.is_empty())
    },
    options~,
  )
}

///|
/// With a model but no interaction yet, the lazily-created cursor is absent;
/// Monaco's view model always has a cursor at `(1,1)`, so the read API reports
/// that default rather than `null`.
test "read API: position defaults to (1,1) before any cursor interaction" {
  with_test_viewer("alpha\nbeta", viewer => {
    let position = viewer.get_position().unwrap()
    assert_eq(position.line_number, 1)
    assert_eq(position.column, 1)
    assert_true(viewer.get_selection().unwrap().is_empty())
    assert_eq(viewer.get_selections().unwrap().length(), 1)
  })
}

///|
/// `getLineHeightForPosition` returns the configured uniform line height.
test "read API: line height reports the uniform height" {
  with_test_viewer(long_document(30), viewer => {
    assert_eq(viewer.get_line_height_for_position(Position(3, 1)), 18.0)
    assert_eq(viewer.get_line_height_for_position(Position(7, 1)), 18.0)
  })
}

///|
/// The DOM-measured trio gates on a real view (Monaco's `hasRealView`). The
/// headless harness never attaches, so they return `-1` / `null`; real
/// client-rect values are asserted in the browser suite.
test "read API: DOM-measured getters return sentinels without a real view" {
  with_test_viewer("alpha\nbeta", viewer => {
    assert_eq(viewer.get_offset_for_column(1, 1), -1.0)
    assert_eq(viewer.get_width_of_line(1), -1.0)
    assert_true(viewer.get_scrolled_visible_position(Position(1, 1)) is None)
  })
}

///|
/// `getLayoutInfo` reduced struct invariants: the glyph-margin width is `0`,
/// the decorations width is the default `lineDecorationsWidth` (10) plus the
/// 16px folding-controls reserve (`editorOptions.ts:2906-2910`, folding on
/// by default), `content_left == line_numbers_width + decorations_width`
/// (the gutter), and the total width is the gutter plus the content box.
test "read API: layout info reduces to gutter + content box" {
  with_test_viewer("alpha\nbeta", viewer => {
    viewer.test_set_viewport(width=800.0, height=400.0)
    let info = viewer.get_layout_info()
    assert_eq(info.glyph_margin_width, 0.0)
    assert_eq(info.decorations_width, 26.0)
    assert_eq(info.content_left, info.line_numbers_width + 26.0)
    assert_eq(info.width, info.content_left + info.content_width)
    assert_eq(info.height, 400.0)
    assert_eq(
      info.horizontal_scrollbar_height,
      @core.editor_horizontal_scrollbar_size,
    )
    assert_eq(
      info.vertical_scrollbar_width,
      @core.editor_vertical_scrollbar_size,
    )
    assert_eq(info.horizontal_scrollbar_height, 12.0)
    assert_eq(info.vertical_scrollbar_width, 14.0)
    assert_true(info.content_left > 0.0)
    // `showFoldingControls: 'never'` drops the reserve back to the raw
    // `lineDecorationsWidth`.
    viewer.update_options(CodeEditorOptions(show_folding_controls=Never))
    assert_eq(viewer.get_layout_info().decorations_width, 10.0)
  })
}
