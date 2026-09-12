///|
fn view_zones_branch_model(path : String, text : String) -> @model.TextModel {
  TextModel(
    @base_common.Uri::file(path),
    path,
    "plaintext",
    1,
    "view-zones-branch-rev-1",
    text,
  )
}

///|
extern "js" fn view_zones_branch_style(
  element : @rdom.Element,
  name : String,
) -> String =
  #| (element, name) => String(element.style[name] ?? "")

///|
priv suberror ViewZonesBranchCallbackFailure {
  ViewZonesBranchCallbackFailure
}

///|
priv struct ViewZonesBranchFixture {
  view : View
  view_model : @view_model.ViewModel
  model : @model.TextModel
  configuration : Ref[(Int, Double, Double)]
  emitted_changes : Ref[Int]
  memory : @log.MemoryLogger
}

///|
fn view_zones_branch_fixture_from_model(
  model : @model.TextModel,
  options : @view_model.ViewModelOptions,
  line_height : Int,
) -> ViewZonesBranchFixture {
  let configuration : Ref[(Int, Double, Double)] = Ref(
    (line_height, 320.0, 40.0),
  )
  let emitted_changes = Ref(0)
  let view_model = @view_model.ViewModel::with_options(model, options)
  let view = View::View(view_zones_configuration_reader=() => configuration.val)
  let memory = @log.MemoryLogger()
  view.install_view_zones_context(
    view_model,
    @log.LogService(logger=memory).log_handle(),
    () => configuration.val,
    () => emitted_changes.val += 1,
  )
  { view, view_model, model, configuration, emitted_changes, memory, }
}

///|
fn view_zones_branch_fixture(
  path : String,
  text : String,
  options : @view_model.ViewModelOptions,
  line_height : Int,
) -> ViewZonesBranchFixture {
  view_zones_branch_fixture_from_model(
    view_zones_branch_model(path, text),
    options,
    line_height,
  )
}

///|
fn ViewZonesBranchFixture::dispose(self : ViewZonesBranchFixture) -> Unit {
  self.view.dispose()
  self.view_model.dispose()
  self.model.dispose()
}

///|
fn ViewZonesBranchFixture::add_zone(
  self : ViewZonesBranchFixture,
  zone : @editor_browser.ViewZone,
) -> String {
  let id = Ref("")
  self.view.change_view_zones(accessor => id.val = accessor.add_zone(zone))
  id.val
}

///|
fn ViewZonesBranchFixture::whitespace(
  self : ViewZonesBranchFixture,
  id : String,
) -> @view_layout.EditorWhitespace {
  for whitespace in self.view_model.get_whitespaces() {
    if whitespace.id == id {
      return whitespace
    }
  }
  abort("missing ViewZones whitespace")
}

///|
fn ViewZonesBranchFixture::has_whitespace(
  self : ViewZonesBranchFixture,
  id : String,
) -> Bool {
  for whitespace in self.view_model.get_whitespaces() {
    if whitespace.id == id {
      return true
    }
  }
  false
}

///|
fn ViewZonesBranchFixture::add_height_zone(
  self : ViewZonesBranchFixture,
  ordinal : Int,
  height_in_lines : Double?,
  height_in_px : Double?,
  computed_height : Ref[Double],
) -> String {
  self.add_zone(
    ViewZone(
      0,
      @rdom.document().create_element("div"),
      ordinal~,
      height_in_lines?,
      height_in_px?,
      on_computed_height=height => computed_height.val = height,
    ),
  )
}

///|
fn ViewZonesBranchFixture::assert_single_callback_report(
  self : ViewZonesBranchFixture,
  callback_name : String,
) -> Unit raise {
  let entries = self.memory.entries()
  assert_eq(entries.length(), 1)
  assert_eq(entries[0].category, "viewer.viewZones")
  assert_eq(entries[0].message, "\{callback_name} callback failed")
}

///|
fn view_zones_branch_callback_step(
  index : Int,
  throw_index : Int,
  calls : Array[Int],
) -> Unit raise ViewZonesBranchCallbackFailure {
  calls.push(index)
  if index == throw_index {
    raise ViewZonesBranchCallbackFailure
  }
}

///|
test "ViewZones maps zero, first, middle, last, and clamped model anchors" {
  install_view_lifecycle_test_browser()
  defer restore_view_lifecycle_test_browser()
  let fixture = view_zones_branch_fixture(
    "/view-zones-anchor-matrix.txt",
    (
      #|abcdefgh
      #|ijklmnop
      #|qrstuvwx
      #|yz
    ),
    @view_model.ViewModelOptions::soft_wrap(4),
    20,
  )
  defer fixture.dispose()
  let line_cases : Array[(Int, Int)] = [(0, 0), (1, 2), (2, 4), (4, 7), (99, 7)]
  for index, pair in line_cases {
    let (after_line_number, expected_view_line) = pair
    let id = fixture.add_zone(
      ViewZone(
        after_line_number,
        @rdom.document().create_element("div"),
        ordinal=index,
        height_in_px=1.0,
      ),
    )
    assert_eq(fixture.whitespace(id).after_line_number, expected_view_line)
  }

  // Absent uses EOL; 1/middle stay on the first wrap; column 5 is the wrap
  // boundary; max column 9 is EOL; a beyond-EOL column validates back to 9.
  let column_cases : Array[(Int?, Int)] = [
    (None, 2),
    (Some(1), 1),
    (Some(3), 1),
    (Some(5), 2),
    (Some(9), 2),
    (Some(999), 2),
  ]
  for index, pair in column_cases {
    let (after_column, expected_view_line) = pair
    let id = fixture.add_zone(
      ViewZone(
        1,
        @rdom.document().create_element("div"),
        after_column?,
        ordinal=100 + index,
        height_in_px=1.0,
      ),
    )
    assert_eq(fixture.whitespace(id).after_line_number, expected_view_line)
  }
}

///|
test "ViewZones forwards every affinity at wrap and injected-text boundaries" {
  install_view_lifecycle_test_browser()
  defer restore_view_lifecycle_test_browser()
  let wrap_fixture = view_zones_branch_fixture(
    "/view-zones-wrap-affinity.txt",
    "abcdefgh",
    @view_model.ViewModelOptions::soft_wrap(4),
    20,
  )
  let wrap_cases : Array[(@model.PositionAffinity, Int)] = [
    (None, 2),
    (Left, 1),
    (Right, 2),
    (LeftOfInjectedText, 2),
    (RightOfInjectedText, 2),
  ]
  for index, pair in wrap_cases {
    let (affinity, expected_view_line) = pair
    let id = wrap_fixture.add_zone(
      ViewZone(
        1,
        @rdom.document().create_element("div"),
        after_column=5,
        after_column_affinity=affinity,
        ordinal=index,
        height_in_px=1.0,
      ),
    )
    assert_eq(wrap_fixture.whitespace(id).after_line_number, expected_view_line)
  }
  wrap_fixture.dispose()

  let injected_model = view_zones_branch_model(
    "/view-zones-injected-affinity.txt", "abcdef",
  )
  injected_model.delta_decorations([], [
    {
      range: Range(1, 3, 1, 3),
      options: ModelDecorationOptions(
        "",
        description="injected-boundary",
        show_if_collapsed=true,
        after=InjectedTextOptions(
          "XXXX",
          inline_class_name="injected-boundary",
          attached_index=0,
        ),
      ),
    },
  ])
  |> ignore
  let injected_fixture = view_zones_branch_fixture_from_model(
    injected_model,
    @view_model.ViewModelOptions::soft_wrap(4),
    20,
  )
  defer injected_fixture.dispose()
  let injected_cases : Array[(@model.PositionAffinity, Int)] = [
    (None, 1),
    (Left, 1),
    (Right, 2),
    (LeftOfInjectedText, 1),
    (RightOfInjectedText, 1),
  ]
  for index, pair in injected_cases {
    let (affinity, expected_view_line) = pair
    let id = injected_fixture.add_zone(
      ViewZone(
        1,
        @rdom.document().create_element("div"),
        after_column=3,
        after_column_affinity=affinity,
        ordinal=index,
        height_in_px=1.0,
      ),
    )
    assert_eq(
      injected_fixture.whitespace(id).after_line_number,
      expected_view_line,
    )
  }
}

///|
test "ViewZones hidden-area omitted false and true toggle exact heights" {
  install_view_lifecycle_test_browser()
  defer restore_view_lifecycle_test_browser()
  let fixture = view_zones_branch_fixture(
    "/view-zones-hidden-matrix.txt",
    (
      #|first
      #|hidden
      #|third
    ),
    @view_model.ViewModelOptions::no_wrap(),
    20,
  )
  defer fixture.dispose()
  assert_true(
    fixture.view_model.set_hidden_areas(
      [Range(2, 1, 2, 1)],
      source="view-zones-branch",
    ),
  )
  let omitted_callbacks : Array[Double] = []
  let false_callbacks : Array[Double] = []
  let true_callbacks : Array[Double] = []
  let omitted_id = fixture.add_zone(
    ViewZone(
      1,
      @rdom.document().create_element("div"),
      ordinal=0,
      height_in_px=19.0,
      on_computed_height=height => omitted_callbacks.push(height),
    ),
  )
  let false_id = fixture.add_zone(
    ViewZone(
      1,
      @rdom.document().create_element("div"),
      show_in_hidden_areas=false,
      ordinal=1,
      height_in_px=19.0,
      on_computed_height=height => false_callbacks.push(height),
    ),
  )
  let true_id = fixture.add_zone(
    ViewZone(
      1,
      @rdom.document().create_element("div"),
      show_in_hidden_areas=true,
      ordinal=2,
      height_in_px=19.0,
      on_computed_height=height => true_callbacks.push(height),
    ),
  )
  assert_eq(fixture.whitespace(omitted_id).height, 0)
  assert_eq(fixture.whitespace(false_id).height, 0)
  assert_eq(fixture.whitespace(true_id).height, 19)
  assert_eq(omitted_callbacks.length(), 1)
  assert_eq(false_callbacks.length(), 1)
  assert_true((1.0 / omitted_callbacks[0]).is_pos_inf())
  assert_true((1.0 / false_callbacks[0]).is_pos_inf())
  assert_eq(true_callbacks.length(), 1)
  assert_eq(true_callbacks[0], 19.0)

  assert_true(
    fixture.view_model.set_hidden_areas([], source="view-zones-branch"),
  )
  assert_true(fixture.view.view_zones.on_line_mapping_changed())
  assert_eq(fixture.whitespace(omitted_id).height, 19)
  assert_eq(fixture.whitespace(false_id).height, 19)
  assert_eq(omitted_callbacks.length(), 2)
  assert_eq(false_callbacks.length(), 2)
  assert_eq(omitted_callbacks[1], 19.0)
  assert_eq(false_callbacks[1], 19.0)
  assert_eq(true_callbacks.length(), 1)

  assert_true(
    fixture.view_model.set_hidden_areas(
      [Range(2, 1, 2, 1)],
      source="view-zones-branch",
    ),
  )
  assert_true(fixture.view.view_zones.on_line_mapping_changed())
  assert_eq(fixture.whitespace(omitted_id).height, 0)
  assert_eq(fixture.whitespace(false_id).height, 0)
  assert_eq(omitted_callbacks.length(), 3)
  assert_eq(false_callbacks.length(), 3)
  assert_true((1.0 / omitted_callbacks[2]).is_pos_inf())
  assert_true((1.0 / false_callbacks[2]).is_pos_inf())
  assert_eq(fixture.whitespace(true_id).height, 19)
  assert_eq(true_callbacks.length(), 1)

  // VZ-043: afterLineNumber=0 returns before hidden-area probing. Hiding the
  // first model line therefore never marks this zone hidden or clamps height.
  let zero_fixture = view_zones_branch_fixture(
    "/view-zones-zero-anchor-hidden.txt",
    "hidden-first\nvisible-second",
    @view_model.ViewModelOptions::no_wrap(),
    20,
  )
  zero_fixture.view_model.view_layout.set_viewport_size(
    width=300.0,
    height=200.0,
  )
  |> ignore
  assert_true(
    zero_fixture.view_model.set_hidden_areas(
      [Range(1, 1, 1, 1)],
      source="view-zones-zero-anchor",
    ),
  )
  let zero_node = @rdom.document().create_element("div")
  let zero_callbacks : Array[Double] = []
  let zero_id = zero_fixture.add_zone(
    ViewZone(0, zero_node, height_in_px=17.0, on_computed_height=height => {
      zero_callbacks.push(height)
    }),
  )
  assert_eq(zero_fixture.whitespace(zero_id).height, 17)
  assert_eq(zero_callbacks.length(), 1)
  assert_eq(zero_callbacks[0], 17.0)
  let hidden_zero_visible = zero_fixture.view_model.view_layout.get_whitespace_viewport_data()
  zero_fixture.view.view_zones.render(hidden_zero_visible, 0, 0.0, 300.0)
  assert_eq(view_zones_branch_style(zero_node, "display"), "block")
  assert_eq(zero_node.get_attribute("monaco-visible-view-zone"), Some("true"))

  assert_true(
    zero_fixture.view_model.set_hidden_areas(
      [],
      source="view-zones-zero-anchor",
    ),
  )
  assert_false(zero_fixture.view.view_zones.on_line_mapping_changed())
  assert_eq(zero_fixture.whitespace(zero_id).height, 17)
  assert_eq(zero_callbacks.length(), 1)
  assert_eq(zero_fixture.emitted_changes.val, 1)
  let shown_zero_visible = zero_fixture.view_model.view_layout.get_whitespace_viewport_data()
  zero_fixture.view.view_zones.render(shown_zero_visible, 0, 0.0, 300.0)
  assert_eq(view_zones_branch_style(zero_node, "display"), "block")
  assert_eq(zero_node.get_attribute("monaco-visible-view-zone"), Some("true"))
  assert_eq(zero_callbacks.length(), 1)
  zero_fixture.dispose()
}

///|
test "ViewZones hidden-source precedence uses declared anchors and covers EOF" {
  install_view_lifecycle_test_browser()
  defer restore_view_lifecycle_test_browser()

  // At a non-EOF anchor, the default Monaco branch probes the position after
  // the zone (line 3), while either source-excluding branch probes the
  // declared anchor side itself (line 2).
  let middle = view_zones_branch_fixture(
    "/view-zones-hidden-source-middle.txt",
    (
      #|first
      #|markdown
      #|folded
      #|fourth
      #|fifth
    ),
    @view_model.ViewModelOptions::no_wrap(),
    20,
  )
  assert_true(
    middle.view_model.set_hidden_areas([Range(2, 1, 2, 1)], source="markdown"),
  )
  assert_true(
    middle.view_model.set_hidden_areas([Range(3, 1, 3, 1)], source="folding"),
  )
  let middle_default = middle.add_zone(
    ViewZone(2, @rdom.document().create_element("div"), height_in_px=17.0),
  )
  let middle_show_all = middle.add_zone(
    ViewZone(
      2,
      @rdom.document().create_element("div"),
      show_in_hidden_areas=true,
      height_in_px=17.0,
    ),
  )
  let middle_ignore_own = middle.add_zone(
    ViewZone(
      2,
      @rdom.document().create_element("div"),
      ignore_hidden_area_source="markdown",
      height_in_px=17.0,
    ),
  )
  let middle_ignore_other = middle.add_zone(
    ViewZone(
      2,
      @rdom.document().create_element("div"),
      ignore_hidden_area_source="folding",
      height_in_px=17.0,
    ),
  )
  assert_eq(middle.whitespace(middle_default).height, 0)
  assert_eq(middle.whitespace(middle_show_all).height, 17)
  assert_eq(middle.whitespace(middle_ignore_own).height, 17)
  assert_eq(middle.whitespace(middle_ignore_other).height, 0)
  middle.dispose()

  // At EOF, the default after-zone position validates back onto the hidden
  // final line. Ignoring the owning source restores the replacement zone;
  // another source on that same line still suppresses it.
  let eof_own = view_zones_branch_fixture(
    "/view-zones-hidden-source-eof-own.txt",
    (
      #|first
      #|second
      #|third
      #|markdown
    ),
    @view_model.ViewModelOptions::no_wrap(),
    20,
  )
  assert_true(
    eof_own.view_model.set_hidden_areas([Range(4, 1, 4, 1)], source="markdown"),
  )
  let eof_default = eof_own.add_zone(
    ViewZone(4, @rdom.document().create_element("div"), height_in_px=23.0),
  )
  let eof_show_all = eof_own.add_zone(
    ViewZone(
      4,
      @rdom.document().create_element("div"),
      show_in_hidden_areas=true,
      height_in_px=23.0,
    ),
  )
  let eof_ignore_own = eof_own.add_zone(
    ViewZone(
      4,
      @rdom.document().create_element("div"),
      ignore_hidden_area_source="markdown",
      height_in_px=23.0,
    ),
  )
  let eof_ignore_other_zone = @editor_browser.ViewZone(
    4,
    @rdom.document().create_element("div"),
    ignore_hidden_area_source="folding",
    height_in_px=23.0,
  )
  let eof_ignore_other = eof_own.add_zone(eof_ignore_other_zone)
  assert_eq(eof_own.whitespace(eof_default).height, 0)
  assert_eq(eof_own.whitespace(eof_show_all).height, 23)
  assert_eq(eof_own.whitespace(eof_ignore_own).height, 23)
  assert_eq(eof_own.whitespace(eof_ignore_other).height, 0)
  eof_ignore_other_zone.ignore_hidden_area_source = Some("markdown")
  eof_own.view.change_view_zones(accessor => {
    accessor.layout_zone(eof_ignore_other)
  })
  assert_eq(eof_own.whitespace(eof_ignore_other).height, 23)
  eof_own.dispose()

  let eof_other = view_zones_branch_fixture(
    "/view-zones-hidden-source-eof-other.txt",
    (
      #|first
      #|second
      #|third
      #|markdown
    ),
    @view_model.ViewModelOptions::no_wrap(),
    20,
  )
  assert_true(
    eof_other.view_model.set_hidden_areas(
      [Range(4, 1, 4, 1)],
      source="markdown",
    ),
  )
  // This overlapping source does not change the merged projection, but it is
  // present in the raw source map before the zone is computed.
  assert_false(
    eof_other.view_model.set_hidden_areas([Range(4, 1, 4, 1)], source="folding"),
  )
  let eof_ignore_own_with_other = eof_other.add_zone(
    ViewZone(
      4,
      @rdom.document().create_element("div"),
      ignore_hidden_area_source="markdown",
      height_in_px=23.0,
    ),
  )
  assert_eq(eof_other.whitespace(eof_ignore_own_with_other).height, 0)
  eof_other.dispose()
}

///|
test "ViewZones refresh source-aware visibility when merged projection is unchanged" {
  install_view_lifecycle_test_browser()
  defer restore_view_lifecycle_test_browser()
  let fixture = view_zones_branch_fixture(
    "/view-zones-hidden-source-live-overlap.txt",
    (
      #|first
      #|markdown
      #|third
    ),
    @view_model.ViewModelOptions::no_wrap(),
    20,
  )
  assert_true(
    fixture.view_model.set_hidden_areas([Range(2, 1, 2, 1)], source="markdown"),
  )
  let zone_id = fixture.add_zone(
    ViewZone(
      2,
      @rdom.document().create_element("div"),
      ignore_hidden_area_source="markdown",
      height_in_px=19.0,
    ),
  )
  assert_eq(fixture.whitespace(zone_id).height, 19)

  // Folding is wholly contained by the Markdown source, so the merged
  // projection does not change. The raw-source refresh must still suppress
  // the zone, then restore it when folding releases the line.
  assert_false(
    fixture.view_model.set_hidden_areas([Range(2, 1, 2, 1)], source="folding"),
  )
  assert_true(fixture.view.view_zones.refresh_hidden_area_source_visibility())
  assert_eq(fixture.whitespace(zone_id).height, 0)
  assert_false(fixture.view_model.set_hidden_areas([], source="folding"))
  assert_true(fixture.view.view_zones.refresh_hidden_area_source_visibility())
  assert_eq(fixture.whitespace(zone_id).height, 19)
  assert_false(fixture.view.view_zones.refresh_hidden_area_source_visibility())
  fixture.dispose()
}

///|
test "ViewZones layout snapshot preserves model anchors after hidden source" {
  install_view_lifecycle_test_browser()
  defer restore_view_lifecycle_test_browser()
  let fixture = view_zones_branch_fixture(
    "/view-zones-layout-info-hidden-source.txt",
    (
      #|first
      #|markdown-a
      #|markdown-b
      #|markdown-c
      #|last
    ),
    @view_model.ViewModelOptions::no_wrap(),
    20,
  )
  defer fixture.dispose()
  assert_true(
    fixture.view_model.set_hidden_areas([Range(2, 1, 4, 1)], source="markdown"),
  )
  let zone_id = fixture.add_zone(
    ViewZone(
      4,
      @rdom.document().create_element("div"),
      ignore_hidden_area_source="markdown",
      height_in_px=19.75,
    ),
  )
  // The projected whitespace can only retain the nearest visible view line.
  assert_eq(fixture.whitespace(zone_id).after_line_number, 1)
  guard fixture.view.view_zone_layout_infos() is [info] else {
    fail("expected one ViewZone layout snapshot")
  }
  let (id, after_model_line_number, height_in_px) = info
  assert_eq(id, zone_id)
  assert_eq(after_model_line_number, 4)
  assert_eq(height_in_px, 19.0)
}

///|
test "ViewZones preserves raw height callbacks through retained ToInt32" {
  install_view_lifecycle_test_browser()
  defer restore_view_lifecycle_test_browser()
  let fixture = view_zones_branch_fixture(
    "/view-zones-height-matrix.txt",
    "one",
    @view_model.ViewModelOptions::no_wrap(),
    20,
  )
  defer fixture.dispose()
  let precedence = Ref(999.0)
  let lines_only = Ref(999.0)
  let default_height = Ref(999.0)
  let positive_zero = Ref(999.0)
  let negative_zero = Ref(999.0)
  let fractional = Ref(999.0)
  let negative = Ref(999.0)
  let not_a_number = Ref(999.0)
  let positive_infinity = Ref(999.0)
  let negative_infinity = Ref(999.0)
  let raw_not_a_number = 0.0 / 0.0
  let raw_positive_infinity = 1.0 / 0.0
  let raw_negative_infinity = -1.0 / 0.0
  let ids : ReadOnlyArray[String] = [
    fixture.add_height_zone(0, Some(99.0), Some(3.75), precedence),
    fixture.add_height_zone(1, Some(1.5), None, lines_only),
    fixture.add_height_zone(2, None, None, default_height),
    fixture.add_height_zone(3, None, Some(0.0), positive_zero),
    fixture.add_height_zone(4, None, Some(-0.0), negative_zero),
    fixture.add_height_zone(5, None, Some(7.9), fractional),
    fixture.add_height_zone(6, None, Some(-7.9), negative),
    fixture.add_height_zone(7, None, Some(raw_not_a_number), not_a_number),
    fixture.add_height_zone(
      8,
      None,
      Some(raw_positive_infinity),
      positive_infinity,
    ),
    fixture.add_height_zone(
      9,
      None,
      Some(raw_negative_infinity),
      negative_infinity,
    ),
  ]
  assert_eq(precedence.val, 3.75)
  assert_eq(lines_only.val, 30.0)
  assert_eq(default_height.val, 20.0)
  assert_true((1.0 / positive_zero.val).is_pos_inf())
  assert_true((1.0 / negative_zero.val).is_neg_inf())
  assert_eq(fractional.val, 7.9)
  assert_eq(negative.val, -7.9)
  assert_true(not_a_number.val.is_nan())
  assert_true(positive_infinity.val.is_pos_inf())
  assert_true(negative_infinity.val.is_neg_inf())
  let expected_retained_heights : ReadOnlyArray[Int] = [
    3, 30, 20, 0, 0, 7, -7, 0, 0, 0,
  ]
  for i in 0..<ids.length() {
    assert_eq(fixture.whitespace(ids[i]).height, expected_retained_heights[i])
  }
}

///|
test "ViewZones layoutZone rereads geometry and width but retains ordinal and nodes" {
  install_view_lifecycle_test_browser()
  defer restore_view_lifecycle_test_browser()
  let fixture = view_zones_branch_fixture(
    "/view-zones-live-delegate.txt",
    "abcdefgh\nijklmnop",
    @view_model.ViewModelOptions::soft_wrap(4),
    20,
  )
  defer fixture.dispose()
  let original_node = @rdom.document().create_element("div")
  let original_margin = @rdom.document().create_element("div")
  let mut original_callback_count = 0
  let mut replacement_callback_count = 0
  let mut replacement_callback_height = -1.0
  let zone = @editor_browser.ViewZone(
    1,
    original_node,
    after_column=1,
    after_column_affinity=None,
    show_in_hidden_areas=false,
    ordinal=17,
    height_in_px=5.5,
    min_width_in_px=42.9,
    margin_dom_node=original_margin,
    on_computed_height=_ => original_callback_count += 1,
  )
  let id = fixture.add_zone(zone)
  let initial = fixture.whitespace(id)
  assert_eq(initial.after_line_number, 1)
  assert_eq(initial.height, 5)
  assert_eq(initial.ordinal, 17)
  assert_eq(initial.min_width, 42)
  assert_eq(original_callback_count, 1)
  assert_true(
    view_lifecycle_test_has_parent(
      original_node,
      fixture.view.view_zones.dom_node(),
    ),
  )
  assert_true(
    view_lifecycle_test_has_parent(
      original_margin,
      fixture.view.view_zones.margin_dom_node(),
    ),
  )

  let replacement_node = @rdom.document().create_element("div")
  let replacement_margin = @rdom.document().create_element("div")
  zone.after_line_number = 2
  zone.after_column = Some(5)
  zone.after_column_affinity = Some(Left)
  zone.show_in_hidden_areas = Some(true)
  zone.ordinal = Some(-99)
  zone.height_in_px = None
  zone.height_in_lines = Some(2.0)
  zone.min_width_in_px = Some(999.0)
  zone.dom_node = replacement_node
  zone.margin_dom_node = Some(replacement_margin)
  zone.on_computed_height = Some(height => {
    replacement_callback_count += 1
    replacement_callback_height = height
  })
  fixture.view.change_view_zones(accessor => accessor.layout_zone(id))

  let updated = fixture.whitespace(id)
  assert_eq(updated.after_line_number, 3)
  assert_eq(updated.height, 40)
  assert_eq(updated.ordinal, 17)
  assert_eq(updated.min_width, 999)
  assert_eq(original_callback_count, 1)
  assert_eq(replacement_callback_count, 1)
  assert_eq(replacement_callback_height, 40.0)
  assert_true(
    view_lifecycle_test_has_parent(
      original_node,
      fixture.view.view_zones.dom_node(),
    ),
  )
  assert_true(
    view_lifecycle_test_has_parent(
      original_margin,
      fixture.view.view_zones.margin_dom_node(),
    ),
  )
  assert_false(
    view_lifecycle_test_has_parent(
      replacement_node,
      fixture.view.view_zones.dom_node(),
    ),
  )
  assert_false(
    view_lifecycle_test_has_parent(
      replacement_margin,
      fixture.view.view_zones.margin_dom_node(),
    ),
  )
  assert_eq(original_node.get_attribute("monaco-view-zone"), Some(id))
  assert_eq(original_node.get_attribute("aria-hidden"), Some("true"))
  assert_eq(replacement_node.get_attribute("monaco-view-zone"), Some(""))
}

///|
test "ViewZones disposal restores caller aria-hidden state" {
  install_view_lifecycle_test_browser()
  defer restore_view_lifecycle_test_browser()
  let fixture = view_zones_branch_fixture(
    "/view-zones-dispose-accessibility.txt",
    "abcdef",
    @view_model.ViewModelOptions::no_wrap(),
    20,
  )
  defer fixture.dispose()
  let absent = @rdom.document().create_element("div")
  let visible = @rdom.document().create_element("div")
  visible.set_attribute("aria-hidden", "false")
  fixture.add_zone(ViewZone(1, absent, height_in_px=1.0)) |> ignore
  fixture.add_zone(ViewZone(1, visible, height_in_px=1.0)) |> ignore
  assert_eq(absent.get_attribute("aria-hidden"), Some("true"))
  assert_eq(visible.get_attribute("aria-hidden"), Some("true"))

  fixture.view.dispose()
  assert_false(view_zone_element_has_attribute(absent, "aria-hidden"))
  assert_eq(visible.get_attribute("aria-hidden"), Some("false"))
}

///|
test "ViewZones derives explicit zero equal and fallback ordinals" {
  install_view_lifecycle_test_browser()
  defer restore_view_lifecycle_test_browser()
  let fixture = view_zones_branch_fixture(
    "/view-zones-ordinal-matrix.txt",
    "abcdef",
    @view_model.ViewModelOptions::no_wrap(),
    20,
  )
  defer fixture.dispose()
  let explicit_zero = fixture.add_zone(
    ViewZone(
      1,
      @rdom.document().create_element("div"),
      after_column=6,
      ordinal=0,
      height_in_px=1.0,
    ),
  )
  let equal_first = fixture.add_zone(
    ViewZone(
      1,
      @rdom.document().create_element("div"),
      after_column=3,
      height_in_px=1.0,
    ),
  )
  let equal_second = fixture.add_zone(
    ViewZone(
      1,
      @rdom.document().create_element("div"),
      after_column=3,
      height_in_px=1.0,
    ),
  )
  let fallback_absent = fixture.add_zone(
    ViewZone(1, @rdom.document().create_element("div"), height_in_px=1.0),
  )
  assert_eq(fixture.whitespace(explicit_zero).ordinal, 0)
  assert_eq(fixture.whitespace(equal_first).ordinal, 3)
  assert_eq(fixture.whitespace(equal_second).ordinal, 3)
  assert_eq(fixture.whitespace(fallback_absent).ordinal, 10000)
  let rows = fixture.view_model.get_whitespaces()
  assert_eq(rows.length(), 4)
  assert_eq(rows[0].id, explicit_zero)
  assert_eq(rows[1].id, equal_first)
  assert_eq(rows[2].id, equal_second)
  assert_eq(rows[3].id, fallback_absent)
}

///|
test "ViewZones line-height bit recomputes and unchanged layout keeps cadence" {
  install_view_lifecycle_test_browser()
  defer restore_view_lifecycle_test_browser()
  let fixture = view_zones_branch_fixture(
    "/view-zones-configuration-matrix.txt",
    "one\ntwo",
    @view_model.ViewModelOptions::no_wrap(),
    10,
  )
  defer fixture.dispose()
  fixture.view_model.view_layout.set_viewport_size(width=300.0, height=200.0)
  |> ignore
  assert_false(
    fixture.view.should_suppress_mouse_down_on_view_zone("missing-zone-id"),
  )
  let lines_callbacks : Array[Double] = []
  let pixels_callbacks : Array[Double] = []
  let fractional_callbacks : Array[Double] = []
  let lines_id = fixture.add_zone(
    ViewZone(
      0,
      @rdom.document().create_element("div"),
      ordinal=0,
      height_in_lines=1.5,
      on_computed_height=height => lines_callbacks.push(height),
    ),
  )
  let pixels_id = fixture.add_zone(
    ViewZone(
      0,
      @rdom.document().create_element("div"),
      ordinal=1,
      height_in_px=7.0,
      on_computed_height=height => pixels_callbacks.push(height),
    ),
  )
  let fractional_id = fixture.add_zone(
    ViewZone(
      0,
      @rdom.document().create_element("div"),
      ordinal=2,
      height_in_px=7.9,
      on_computed_height=height => fractional_callbacks.push(height),
    ),
  )
  assert_eq(fixture.whitespace(lines_id).height, 15)
  assert_eq(fixture.whitespace(pixels_id).height, 7)
  assert_eq(fixture.whitespace(fractional_id).height, 7)
  assert_eq(lines_callbacks.length(), 1)
  assert_eq(pixels_callbacks.length(), 1)
  assert_eq(fractional_callbacks.length(), 1)
  assert_eq(fractional_callbacks[0], 7.9)
  assert_eq(fixture.emitted_changes.val, 3)

  // Width-only refresh retains contentLeft and never recomputes a height.
  fixture.configuration.val = (10, 500.0, 40.0)
  assert_true(fixture.view.view_zones.on_configuration_changed(false))
  assert_eq(fixture.whitespace(lines_id).height, 15)
  assert_eq(lines_callbacks.length(), 1)
  assert_eq(pixels_callbacks.length(), 1)
  assert_eq(fractional_callbacks.length(), 1)
  assert_eq(fixture.emitted_changes.val, 3)
  let width_visible = fixture.view_model.view_layout.get_whitespace_viewport_data()
  fixture.view.view_zones.render(width_visible, 0, 0.0, 100.0)
  assert_eq(
    view_zones_branch_style(fixture.view.view_zones.dom_node(), "width"),
    "500px",
  )
  assert_eq(
    view_zones_branch_style(fixture.view.view_zones.margin_dom_node(), "width"),
    "40px",
  )

  // contentLeft-only refresh retains content width and likewise skips height.
  fixture.configuration.val = (10, 500.0, 50.0)
  assert_true(fixture.view.view_zones.on_configuration_changed(false))
  assert_eq(fixture.whitespace(lines_id).height, 15)
  assert_eq(lines_callbacks.length(), 1)
  assert_eq(pixels_callbacks.length(), 1)
  assert_eq(fractional_callbacks.length(), 1)
  assert_eq(fixture.emitted_changes.val, 3)
  let left_visible = fixture.view_model.view_layout.get_whitespace_viewport_data()
  fixture.view.view_zones.render(left_visible, 0, 0.0, 100.0)
  assert_eq(
    view_zones_branch_style(fixture.view.view_zones.dom_node(), "width"),
    "500px",
  )
  assert_eq(
    view_zones_branch_style(fixture.view.view_zones.margin_dom_node(), "width"),
    "50px",
  )

  fixture.view.change_view_zones(accessor => accessor.layout_zone(lines_id))
  assert_eq(lines_callbacks.length(), 2)
  assert_eq(lines_callbacks[1], 15.0)
  assert_eq(fractional_callbacks.length(), 1)
  assert_eq(fixture.emitted_changes.val, 4)

  fixture.configuration.val = (20, 500.0, 50.0)
  assert_true(fixture.view.view_zones.on_configuration_changed(true))
  assert_eq(fixture.whitespace(lines_id).height, 30)
  assert_eq(fixture.whitespace(pixels_id).height, 7)
  assert_eq(lines_callbacks.length(), 3)
  assert_eq(lines_callbacks[2], 30.0)
  assert_eq(pixels_callbacks.length(), 1)
  assert_eq(fixture.whitespace(fractional_id).height, 7)
  assert_eq(fractional_callbacks.length(), 2)
  assert_eq(fractional_callbacks[1], 7.9)
  assert_eq(fixture.emitted_changes.val, 5)
  let height_visible = fixture.view_model.view_layout.get_whitespace_viewport_data()
  fixture.view.view_zones.render(height_visible, 0, 0.0, 100.0)
  assert_eq(
    view_zones_branch_style(fixture.view.view_zones.dom_node(), "width"),
    "500px",
  )
  assert_eq(
    view_zones_branch_style(fixture.view.view_zones.margin_dom_node(), "width"),
    "50px",
  )
  assert_true(fixture.view.view_zones.on_configuration_changed(true))
  assert_eq(lines_callbacks.length(), 3)
  assert_eq(fixture.whitespace(fractional_id).height, 7)
  assert_eq(fractional_callbacks.length(), 3)
  assert_eq(fractional_callbacks[2], 7.9)
  assert_eq(fixture.emitted_changes.val, 6)

  // Raw 7.9 never equals retained Int 7, so every mapping/config recompute
  // queues a change and callback, then the layout boundary truncates to 7.
  assert_true(fixture.view.view_zones.on_line_mapping_changed())
  assert_eq(fixture.whitespace(fractional_id).height, 7)
  assert_eq(fractional_callbacks.length(), 4)
  assert_eq(fractional_callbacks[3], 7.9)
  assert_eq(fixture.emitted_changes.val, 7)

  // Static render/scroll signals never call onComputedHeight or emit a zone
  // change. Only top callbacks belong to the render phase.
  let before_static_callbacks = lines_callbacks.length()
  let before_static_events = fixture.emitted_changes.val
  let visible = fixture.view_model.view_layout.get_whitespace_viewport_data()
  fixture.view.view_zones.render(visible, 0, 0.0, 100.0)
  assert_false(fixture.view.view_zones.on_scroll_changed(false, false))
  assert_true(fixture.view.view_zones.on_scroll_changed(true, false))
  assert_true(fixture.view.view_zones.on_scroll_changed(false, true))
  assert_true(fixture.view.view_zones.on_scroll_changed(true, true))
  assert_eq(lines_callbacks.length(), before_static_callbacks)
  assert_eq(fixture.emitted_changes.val, before_static_events)
}

///|
test "ViewZones recompute freezes keys but reads future delegates live" {
  install_view_lifecycle_test_browser()
  defer restore_view_lifecycle_test_browser()
  let fixture = view_zones_branch_fixture(
    "/view-zones-recompute-reentrancy.txt",
    "one\ntwo",
    @view_model.ViewModelOptions::no_wrap(),
    10,
  )
  defer fixture.dispose()
  let mut first_id = ""
  let future_id = Ref("")
  let added_id = Ref("")
  let first_callbacks : Array[Double] = []
  let future_callbacks : Array[Double] = []
  let added_callbacks : Array[Double] = []
  let did_reenter = Ref(false)
  let future_zone = @editor_browser.ViewZone(
    0,
    @rdom.document().create_element("div"),
    ordinal=1,
    height_in_lines=2.0,
    on_computed_height=height => future_callbacks.push(height),
  )
  let added_zone = @editor_browser.ViewZone(
    0,
    @rdom.document().create_element("div"),
    ordinal=2,
    height_in_lines=1.0,
    on_computed_height=height => added_callbacks.push(height),
  )
  let first_zone = @editor_browser.ViewZone(
    0,
    @rdom.document().create_element("div"),
    ordinal=0,
    height_in_lines=1.0,
    on_computed_height=height => {
      first_callbacks.push(height)
      if height == 20.0 && !did_reenter.val {
        did_reenter.val = true
        // The future key is looked up after this callback, so its live
        // delegate mutation participates in the same recompute pass.
        future_zone.height_in_lines = Some(3.0)
        fixture.view.change_view_zones(accessor => {
          added_id.val = accessor.add_zone(added_zone)
          accessor.remove_zone(first_id)
        })
        // The new key was absent from Object.keys' frozen snapshot. Mutating
        // it after add distinguishes "skipped now" (20) from recomputed (80).
        added_zone.height_in_lines = Some(4.0)
      }
    },
  )
  first_id = fixture.add_zone(first_zone)
  future_id.val = fixture.add_zone(future_zone)
  assert_eq(first_callbacks.length(), 1)
  assert_eq(first_callbacks[0], 10.0)
  assert_eq(future_callbacks.length(), 1)
  assert_eq(future_callbacks[0], 20.0)

  fixture.configuration.val = (20, 320.0, 40.0)
  assert_true(fixture.view.view_zones.on_configuration_changed(true))
  assert_false(fixture.has_whitespace(first_id))
  assert_true(fixture.has_whitespace(future_id.val))
  assert_true(fixture.has_whitespace(added_id.val))
  assert_eq(fixture.whitespace(future_id.val).height, 60)
  assert_eq(future_callbacks.length(), 2)
  assert_eq(future_callbacks[1], 60.0)
  assert_eq(fixture.whitespace(added_id.val).height, 20)
  assert_eq(added_callbacks.length(), 1)
  assert_eq(added_callbacks[0], 20.0)

  // The next frozen snapshot includes the added key and catches up to its
  // already-mutated delegate value.
  assert_true(fixture.view.view_zones.on_configuration_changed(true))
  assert_eq(fixture.whitespace(added_id.val).height, 80)
  assert_eq(added_callbacks.length(), 2)
  assert_eq(added_callbacks[1], 80.0)
}

///|
test "ViewZones render freezes keys, writes after callback, and reads live values" {
  install_view_lifecycle_test_browser()
  defer restore_view_lifecycle_test_browser()
  let fixture = view_zones_branch_fixture(
    "/view-zones-render-reentrancy.txt",
    "one\ntwo",
    @view_model.ViewModelOptions::no_wrap(),
    20,
  )
  defer fixture.dispose()
  fixture.view_model.view_layout.set_viewport_size(width=300.0, height=200.0)
  |> ignore
  let mut current_id = ""
  let future_id = Ref("")
  let added_id = Ref("")
  let current_node = @rdom.document().create_element("div")
  let future_node = @rdom.document().create_element("div")
  let added_node = @rdom.document().create_element("div")
  let mut callback_display = "unset"
  let mut callback_top = "unset"
  let mut callback_height = "unset"
  let mut old_future_top_callbacks = 0
  let mut live_future_top_callbacks = 0
  let mut added_top_callbacks = 0
  let did_reenter = Ref(false)
  let future_zone = @editor_browser.ViewZone(
    0,
    future_node,
    ordinal=1,
    height_in_px=11.0,
    on_dom_node_top=_ => old_future_top_callbacks += 1,
  )
  let added_zone = @editor_browser.ViewZone(
    0,
    added_node,
    ordinal=2,
    height_in_px=12.0,
    on_dom_node_top=_ => added_top_callbacks += 1,
  )
  let current_zone = @editor_browser.ViewZone(
    0,
    current_node,
    ordinal=0,
    height_in_px=10.0,
    on_dom_node_top=_ => {
      if !did_reenter.val {
        did_reenter.val = true
        callback_display = view_zones_branch_style(current_node, "display")
        callback_top = view_zones_branch_style(current_node, "top")
        callback_height = view_zones_branch_style(current_node, "height")
        // The future key's registered record is fetched after this callback,
        // so the replacement delegate callback is used immediately.
        future_zone.on_dom_node_top = Some(_ => live_future_top_callbacks += 1)
        fixture.view.change_view_zones(accessor => {
          added_id.val = accessor.add_zone(added_zone)
          accessor.remove_zone(current_id)
        })
      }
    },
  )
  current_id = fixture.add_zone(current_zone)
  future_id.val = fixture.add_zone(future_zone)
  let visible = fixture.view_model.view_layout.get_whitespace_viewport_data()
  assert_eq(visible.length(), 2)
  fixture.view.view_zones.render(visible, 0, 0.0, 300.0)

  // onDomNodeTop runs before top/height/display writes. Removing the current
  // key detaches it, but the already-captured record still receives writes.
  assert_eq(callback_display, "none")
  assert_eq(callback_top, "")
  assert_eq(callback_height, "")
  assert_eq(view_zones_branch_style(current_node, "top"), "0px")
  assert_eq(view_zones_branch_style(current_node, "height"), "10px")
  assert_eq(view_zones_branch_style(current_node, "display"), "block")
  assert_false(
    view_lifecycle_test_has_parent(
      current_node,
      fixture.view.view_zones.dom_node(),
    ),
  )
  assert_false(fixture.has_whitespace(current_id))

  assert_eq(old_future_top_callbacks, 0)
  assert_eq(live_future_top_callbacks, 1)
  assert_true(fixture.has_whitespace(future_id.val))
  // The key added during the callback was absent from the frozen key list.
  assert_eq(added_top_callbacks, 0)
  assert_true(fixture.has_whitespace(added_id.val))
  assert_eq(view_zones_branch_style(added_node, "display"), "none")
  assert_eq(view_zones_branch_style(added_node, "top"), "")
  assert_eq(view_zones_branch_style(added_node, "height"), "")
}

///|
test "panic ViewZones render exposes source stale-future-key failure" {
  install_view_lifecycle_test_browser()
  defer restore_view_lifecycle_test_browser()
  let fixture = view_zones_branch_fixture(
    "/view-zones-render-stale-future.txt",
    "one",
    @view_model.ViewModelOptions::no_wrap(),
    20,
  )
  defer fixture.dispose()
  fixture.view_model.view_layout.set_viewport_size(width=300.0, height=200.0)
  |> ignore
  let future_id = Ref("")
  fixture.add_zone(
    ViewZone(
      0,
      @rdom.document().create_element("div"),
      ordinal=0,
      height_in_px=10.0,
      on_dom_node_top=_ => {
        fixture.view.change_view_zones(accessor => {
          accessor.remove_zone(future_id.val)
        })
      },
    ),
  )
  |> ignore
  future_id.val = fixture.add_zone(
    ViewZone(
      0,
      @rdom.document().create_element("div"),
      ordinal=1,
      height_in_px=10.0,
    ),
  )
  let visible = fixture.view_model.view_layout.get_whitespace_viewport_data()
  assert_eq(visible.length(), 2)
  // The frozen key array still contains the removed future id. Like the
  // pinned source's indexed `this._zones[id]`, its later live lookup fails.
  fixture.view.view_zones.render(visible, 0, 0.0, 300.0)
}

///|
test "ViewZones contains computed-height throws at first middle and last" {
  install_view_lifecycle_test_browser()
  defer restore_view_lifecycle_test_browser()
  for throw_index in 0..<3 {
    let fixture = view_zones_branch_fixture(
      "/view-zones-computed-callback-containment.txt",
      "one",
      @view_model.ViewModelOptions::no_wrap(),
      20,
    )
    let calls : Array[Int] = []
    fixture.view.change_view_zones(accessor => {
      accessor.add_zone(
        ViewZone(
          0,
          @rdom.document().create_element("div"),
          ordinal=0,
          height_in_px=10.0,
          on_computed_height=_ => {
            view_zones_branch_callback_step(0, throw_index, calls)
          },
        ),
      )
      |> ignore
      accessor.add_zone(
        ViewZone(
          0,
          @rdom.document().create_element("div"),
          ordinal=1,
          height_in_px=11.0,
          on_computed_height=_ => {
            view_zones_branch_callback_step(1, throw_index, calls)
          },
        ),
      )
      |> ignore
      accessor.add_zone(
        ViewZone(
          0,
          @rdom.document().create_element("div"),
          ordinal=2,
          height_in_px=12.0,
          on_computed_height=_ => {
            view_zones_branch_callback_step(2, throw_index, calls)
          },
        ),
      )
      |> ignore
    })
    assert_eq(calls.length(), 3)
    assert_eq(calls[0], 0)
    assert_eq(calls[1], 1)
    assert_eq(calls[2], 2)
    assert_eq(fixture.view_model.get_whitespaces().length(), 3)
    fixture.assert_single_callback_report("onComputedHeight")
    fixture.dispose()
  }
}

///|
test "ViewZones contains DOM-top throws at first middle and last" {
  install_view_lifecycle_test_browser()
  defer restore_view_lifecycle_test_browser()
  for throw_index in 0..<3 {
    let fixture = view_zones_branch_fixture(
      "/view-zones-top-callback-containment.txt",
      "one",
      @view_model.ViewModelOptions::no_wrap(),
      20,
    )
    fixture.view_model.view_layout.set_viewport_size(width=300.0, height=200.0)
    |> ignore
    let calls : Array[Int] = []
    let first_node = @rdom.document().create_element("div")
    let middle_node = @rdom.document().create_element("div")
    let last_node = @rdom.document().create_element("div")
    fixture.add_zone(
      ViewZone(0, first_node, ordinal=0, height_in_px=10.0, on_dom_node_top=_ => {
        view_zones_branch_callback_step(0, throw_index, calls)
      }),
    )
    |> ignore
    fixture.add_zone(
      ViewZone(0, middle_node, ordinal=1, height_in_px=11.0, on_dom_node_top=_ => {
        view_zones_branch_callback_step(1, throw_index, calls)
      }),
    )
    |> ignore
    fixture.add_zone(
      ViewZone(0, last_node, ordinal=2, height_in_px=12.0, on_dom_node_top=_ => {
        view_zones_branch_callback_step(2, throw_index, calls)
      }),
    )
    |> ignore
    let visible = fixture.view_model.view_layout.get_whitespace_viewport_data()
    assert_eq(visible.length(), 3)
    fixture.view.view_zones.render(visible, 0, 0.0, 300.0)
    assert_eq(calls.length(), 3)
    assert_eq(calls[0], 0)
    assert_eq(calls[1], 1)
    assert_eq(calls[2], 2)
    assert_eq(view_zones_branch_style(first_node, "display"), "block")
    assert_eq(view_zones_branch_style(middle_node, "display"), "block")
    assert_eq(view_zones_branch_style(last_node, "display"), "block")
    fixture.assert_single_callback_report("onDomNodeTop")
    fixture.dispose()
  }
}
