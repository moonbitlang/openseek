///|
test "overview ruler scales ranges and enforces its minimum marker height" {
  let bands = resolve_code_editor_overview_ruler_bands(
    [
      {
        id: 7,
        start_offset: 500.0,
        end_offset: 501.0,
        color: "red",
        lane: Left,
      },
    ],
    100.0,
    1000.0,
    2.0,
    4.0,
  )
  assert_eq(bands, [{ id: 7, from: 96, to: 104, color: "red", lane: Left, }])
}

///|
test "overview ruler hunk height excludes an alignment zone inside the range" {
  // Three wrapped view lines at 18px occupy 54px. A bottom-position lookup
  // would also include the hypothetical 72px alignment ViewZone; the pinned
  // diff overview contract deliberately derives the end from line count.
  assert_eq(code_editor_overview_ruler_end_offset(90.0, 234.0, 3, 18), 144.0)
}

///|
fn overview_ruler_eof_offset_entry(
  viewer : CodeEditorWidget,
  range : @base_common.LineRange,
) -> CodeEditorOverviewRulerOffsetEntry {
  let ruler : CodeEditorOverviewRuler = {
    editor: viewer,
    root: headless_test_element(),
    external_host: None,
    minimum_marker_height: 4.0,
    on_select: None,
    listeners: [],
    resize_observer: None,
    entries: [{ id: 1, range, color: "red", lane: Full, }],
    bands: [],
    generation: 0,
    render_frame: None,
    continuous_width_resize: false,
    disposed: false,
  }
  ruler.model_offset_entries()[0]
}

///|
test "overview ruler validates an unwrapped EOF hunk endpoint through the converter" {
  let model = test_model("head\nfinal")
  defer model.dispose()
  let viewer = CodeEditorWidget::CodeEditorWidget(
    options=CodeEditorOptions(font_size=12, line_height=18),
  )
  defer viewer.dispose()
  viewer.set_model(Some(model))
  let entry = overview_ruler_eof_offset_entry(viewer, LineRange(2, 3))
  assert_eq(entry.start_offset, 18.0)
  // Position(3, 1) validates to the end of model line 2. Like pinned
  // OverviewZoneManager, a zero view-line delta falls back to one line.
  assert_eq(entry.end_offset, 36.0)
}

///|
test "overview ruler validates a wrapped EOF hunk endpoint through the converter" {
  let model = test_model("head\nabcdefghijklm")
  defer model.dispose()
  let viewer = CodeEditorWidget::CodeEditorWidget(
    options=CodeEditorOptions(font_size=12, line_height=18, soft_wrap=true),
  )
  defer viewer.dispose()
  viewer.set_model(Some(model))
  viewer.test_set_soft_wrap_column(6)
  let entry = overview_ruler_eof_offset_entry(viewer, LineRange(2, 3))
  assert_eq(entry.start_offset, 18.0)
  // The validated EOF lands on the third wrapped segment. Pinned computes
  // height from the two-line view delta instead of adding an inclusive line.
  assert_eq(entry.end_offset, 54.0)
}

///|
test "overview ruler clamps marker bands to both canvas edges" {
  let bands = resolve_code_editor_overview_ruler_bands(
    [
      { id: 1, start_offset: 0.0, end_offset: 0.0, color: "red", lane: Left, },
      {
        id: 2,
        start_offset: 1000.0,
        end_offset: 1000.0,
        color: "green",
        lane: Right,
      },
    ],
    100.0,
    1000.0,
    1.0,
    4.0,
  )
  assert_eq(bands, [
    { id: 1, from: 0, to: 4, color: "red", lane: Left, },
    { id: 2, from: 96, to: 100, color: "green", lane: Right, },
  ])
}

///|
test "overview ruler merges only overlapping bands in the same color lane" {
  let merged = merge_code_editor_overview_ruler_bands([
    { id: 3, from: 2, to: 8, color: "red", lane: Left, },
    { id: 4, from: 7, to: 12, color: "red", lane: Left, },
    { id: 5, from: 7, to: 12, color: "green", lane: Left, },
    { id: 6, from: 7, to: 12, color: "red", lane: Right, },
  ])
  assert_eq(merged, [
    { id: 3, from: 2, to: 12, color: "red", lane: Left, },
    { id: 5, from: 7, to: 12, color: "green", lane: Left, },
    { id: 6, from: 7, to: 12, color: "red", lane: Right, },
  ])
}

///|
test "overview ruler lane geometry is stable for uneven widths" {
  assert_eq(code_editor_overview_ruler_lane_geometry(Left, 11), (0, 3))
  assert_eq(code_editor_overview_ruler_lane_geometry(Center, 11), (3, 5))
  assert_eq(code_editor_overview_ruler_lane_geometry(Right, 11), (8, 3))
  assert_eq(code_editor_overview_ruler_lane_geometry(Full, 11), (0, 11))
}

///|
test "overview ruler pointer selection chooses the nearest narrow band" {
  let bands = [
    { id: 4, from: 20, to: 40, color: "red", lane: Left, },
    { id: 2, from: 28, to: 32, color: "green", lane: Right, },
    { id: 9, from: 70, to: 80, color: "blue", lane: Full, },
  ]
  assert_eq(closest_code_editor_overview_ruler_entry(bands, 30), Some(2))
  assert_eq(closest_code_editor_overview_ruler_entry(bands, 60), Some(9))
  assert_eq(closest_code_editor_overview_ruler_entry([], 60), None)
}

///|
extern "js" fn overview_ruler_test_element() -> @rdom.Element =
  #| () => ({
  #|   attributes: new Map(),
  #|   setAttribute(name, value) {
  #|     this.attributes.set(String(name), String(value));
  #|   },
  #|   getAttribute(name) {
  #|     return this.attributes.has(String(name))
  #|       ? this.attributes.get(String(name))
  #|       : null;
  #|   },
  #| })

///|
test "overview ruler publishes a browser-testable inaccessible DOM contract" {
  let root = overview_ruler_test_element()
  initialize_code_editor_overview_ruler_dom(root)
  assert_eq(
    root.get_attribute("class"),
    Some("decorationsOverviewRuler moonbit-code-overview-ruler"),
  )
  assert_eq(root.get_attribute("data-view-part"), Some("overview-ruler"))
  assert_eq(root.get_attribute("aria-hidden"), Some("true"))
  assert_eq(root.get_attribute("data-overview-ruler-generation"), Some("0"))
  assert_eq(root.get_attribute("data-overview-ruler-entry-count"), Some("0"))
  assert_eq(root.get_attribute("data-overview-ruler-band-count"), Some("0"))
}

///|
test "overview ruler rejects stale generations and accepts refreshes" {
  assert_false(code_editor_overview_ruler_accepts_generation(9, 8))
  assert_true(code_editor_overview_ruler_accepts_generation(9, 9))
  assert_true(code_editor_overview_ruler_accepts_generation(9, 10))
}

///|
extern "js" fn overview_ruler_disposal_test_canvas() -> @rdom.Element =
  #| () => ({
  #|   width: 12,
  #|   height: 80,
  #|   removed: false,
  #|   getContext() { return null; },
  #|   remove() { this.removed = true; },
  #| })

///|
extern "js" fn overview_ruler_disposal_test_width(root : @rdom.Element) -> Int = "(root) => root.width"

///|
extern "js" fn overview_ruler_disposal_test_height(root : @rdom.Element) -> Int = "(root) => root.height"

///|
extern "js" fn overview_ruler_disposal_test_removed(
  root : @rdom.Element,
) -> Bool = "(root) => root.removed"

///|
fn overview_ruler_disposal_test_handle(
  editor : CodeEditorWidget,
  root : @rdom.Element,
  listeners? : Array[@base_common.Disposable] = [],
  resize_observer? : @base_common.Disposable,
) -> CodeEditorOverviewRuler {
  {
    editor,
    root,
    external_host: None,
    minimum_marker_height: 4.0,
    on_select: None,
    listeners,
    resize_observer,
    entries: [{ id: 1, range: LineRange(1, 2), color: "red", lane: Full, }],
    bands: [{ id: 1, from: 0, to: 4, color: "red", lane: Full, }],
    generation: 3,
    render_frame: None,
    continuous_width_resize: false,
    disposed: false,
  }
}

///|
test "overview ruler disposal releases each owned resource exactly once" {
  let editor = CodeEditorWidget::CodeEditorWidget()
  defer editor.dispose()
  let root = overview_ruler_disposal_test_canvas()
  let mut released = 0
  let ruler = overview_ruler_disposal_test_handle(
    editor,
    root,
    listeners=[
      @base_common.Disposable::from(() => released += 1),
      @base_common.Disposable::from(() => released += 1),
    ],
    resize_observer=@base_common.Disposable::from(() => released += 1),
  )
  editor.overview_rulers.push(ruler)
  ruler.dispose()
  ruler.dispose()
  assert_true(ruler.is_disposed())
  assert_eq(ruler.entry_count(), 0)
  assert_eq(editor.overview_rulers.length(), 0)
  assert_eq(released, 3)
  assert_eq(overview_ruler_disposal_test_width(root), 0)
  assert_eq(overview_ruler_disposal_test_height(root), 0)
  assert_true(overview_ruler_disposal_test_removed(root))
}

///|
test "code editor disposal owns and clears registered overview rulers" {
  let editor = CodeEditorWidget::CodeEditorWidget()
  let root = overview_ruler_disposal_test_canvas()
  let ruler = overview_ruler_disposal_test_handle(editor, root)
  editor.overview_rulers.push(ruler)
  editor.dispose()
  assert_true(ruler.is_disposed())
  assert_eq(editor.overview_rulers.length(), 0)
  assert_eq(overview_ruler_disposal_test_width(root), 0)
  assert_eq(overview_ruler_disposal_test_height(root), 0)
  assert_true(overview_ruler_disposal_test_removed(root))
}
