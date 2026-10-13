// Source-derived branch tests for pinned `domReadingContext.ts` and
// `rangeUtil.ts` in the checked-in source.

///|
#external
priv type RangeFixture

///|
extern "js" fn handy_range_create_count(state : HandyRangeState) -> Int32 = "(state) => state.createCount"

///|
extern "js" fn handy_range_detach_count(state : HandyRangeState) -> Int32 = "(state) => state.detachCount"

///|
test "DomReadingContext reads delta and scale once with zero-width fallback" {
  let fixture = new_range_fixture("normal")
  let context = DomReadingContext::DomReadingContext(
    range_fixture_context(fixture),
    range_fixture_end_node(fixture),
  )
  assert_false(context.did_dom_layout())
  inspect(context.client_rect_delta_left(), content="100")
  inspect(context.client_rect_scale(), content="2")
  inspect(range_fixture_context_read_count(fixture), content="1")
  assert_true(context.did_dom_layout())
  inspect(context.client_rect_delta_left(), content="100")
  inspect(range_fixture_context_read_count(fixture), content="1")

  let zero_fixture = new_range_fixture("zero-offset-width")
  let zero_context = DomReadingContext::DomReadingContext(
    range_fixture_context(zero_fixture),
    range_fixture_end_node(zero_fixture),
  )
  inspect(zero_context.client_rect_scale(), content="1")
  inspect(range_fixture_context_read_count(zero_fixture), content="1")

  let below_fixture = new_range_fixture("scale-below")
  let below_context = DomReadingContext::DomReadingContext(
    range_fixture_context(below_fixture),
    range_fixture_end_node(below_fixture),
  )
  inspect(below_context.client_rect_delta_left(), content="100")
  inspect(below_context.client_rect_scale(), content="0.5")
  inspect(range_fixture_context_read_count(below_fixture), content="1")
}

///|
test "RangeUtil reuses one Range and parks it after success and failure" {
  let fixture = new_range_fixture("normal")
  let state = new_handy_range_state()
  let first = read_client_rects_with_state(
    state,
    range_fixture_text_node(fixture, 0),
    0,
    range_fixture_text_node(fixture, 1),
    1,
    range_fixture_end_node(fixture),
  )
  assert_false(client_rect_list_is_null(first))
  inspect(handy_range_create_count(state), content="1")
  inspect(handy_range_detach_count(state), content="1")
  let second = read_client_rects_with_state(
    state,
    range_fixture_text_node(fixture, 0),
    1,
    range_fixture_text_node(fixture, 1),
    2,
    range_fixture_end_node(fixture),
  )
  assert_false(client_rect_list_is_null(second))
  inspect(handy_range_create_count(state), content="1")
  inspect(handy_range_detach_count(state), content="2")
  range_fixture_set_failure(fixture, "start")
  let failed = read_client_rects_with_state(
    state,
    range_fixture_text_node(fixture, 0),
    0,
    range_fixture_text_node(fixture, 1),
    1,
    range_fixture_end_node(fixture),
  )
  assert_true(client_rect_list_is_null(failed))
  inspect(handy_range_create_count(state), content="1")
  inspect(handy_range_detach_count(state), content="3")
  range_fixture_set_failure(fixture, "end")
  let end_failed = read_client_rects_with_state(
    state,
    range_fixture_text_node(fixture, 0),
    0,
    range_fixture_text_node(fixture, 1),
    1,
    range_fixture_end_node(fixture),
  )
  assert_true(client_rect_list_is_null(end_failed))
  inspect(handy_range_create_count(state), content="1")
  inspect(handy_range_detach_count(state), content="4")
  range_fixture_set_failure(fixture, "rects")
  let rects_failed = read_client_rects_with_state(
    state,
    range_fixture_text_node(fixture, 0),
    0,
    range_fixture_text_node(fixture, 1),
    1,
    range_fixture_end_node(fixture),
  )
  assert_true(client_rect_list_is_null(rects_failed))
  inspect(handy_range_create_count(state), content="1")
  inspect(handy_range_detach_count(state), content="5")
  assert_true(range_fixture_was_parked(fixture))
}

///|
test "RangeUtil normalization clamps scales sorts and merges at exact 0.9" {
  guard create_horizontal_ranges_from_client_rects(
      range_rects_at_tolerance(),
      100.0,
      2.0,
    )
    is Some(at_tolerance) else {
    fail("expected normalized ranges")
  }
  inspect(at_tolerance.length(), content="2")
  inspect(at_tolerance[0].0, content="0")
  assert_true((at_tolerance[0].1 - 2.9).abs() < 0.000001)
  inspect(at_tolerance[1].0, content="10")

  guard create_horizontal_ranges_from_client_rects(
      range_rects_above_tolerance(),
      100.0,
      2.0,
    )
    is Some(above_tolerance) else {
    fail("expected normalized ranges")
  }
  inspect(above_tolerance.length(), content="2")
  assert_true(
    create_horizontal_ranges_from_client_rects(empty_client_rects(), 0.0, 1.0)
    is None,
  )
  assert_true(
    create_horizontal_ranges_from_client_rects(null_client_rects(), 0.0, 1.0)
    is None,
  )
  guard create_horizontal_ranges_from_client_rects(
      negative_left_client_rect(),
      100.0,
      2.0,
    )
    is Some(negative_left) else {
    fail("expected clamped negative normalized left")
  }
  inspect(negative_left.length(), content="1")
  inspect(negative_left[0].0, content="0")
  inspect(negative_left[0].1, content="2")
}

///|
test "RangeUtil endpoint branches preserve empty span and prior-span repairs" {
  let empty = new_range_fixture("empty")
  let empty_state = new_handy_range_state()
  let empty_context = DomReadingContext::DomReadingContext(
    range_fixture_context(empty),
    range_fixture_end_node(empty),
  )
  guard range_util_read_horizontal_ranges_with_state(
      empty_state,
      range_fixture_root(empty),
      0,
      0,
      0,
      0,
      empty_context,
    )
    is Some(empty_ranges) else {
    fail("expected empty-span bounding rect")
  }
  inspect(empty_ranges.length(), content="1")
  inspect(empty_ranges[0].0, content="5")
  inspect(empty_ranges[0].1, content="0")
  inspect(handy_range_create_count(empty_state), content="0")

  let crossing = new_range_fixture("normal")
  let crossing_state = new_handy_range_state()
  let crossing_context = DomReadingContext::DomReadingContext(
    range_fixture_context(crossing),
    range_fixture_end_node(crossing),
  )
  guard range_util_read_horizontal_ranges_with_state(
      crossing_state,
      range_fixture_root(crossing),
      -20,
      -20,
      99,
      0,
      crossing_context,
    )
    is Some(crossing_ranges) else {
    fail("expected clamped crossing range")
  }
  inspect(crossing_ranges.length(), content="1")
  inspect(crossing_ranges[0].0, content="0")
  inspect(crossing_ranges[0].1, content="15")
  inspect(range_fixture_last_end_offset(crossing), content="3")

  let missing = new_range_fixture("missing-middle")
  let missing_state = new_handy_range_state()
  let missing_context = DomReadingContext::DomReadingContext(
    range_fixture_context(missing),
    range_fixture_end_node(missing),
  )
  guard range_util_read_horizontal_ranges_with_state(
      missing_state,
      range_fixture_root(missing),
      1,
      0,
      2,
      1,
      missing_context,
    )
    is Some(missing_ranges) else {
    fail("expected prior-span start repair")
  }
  inspect(range_fixture_last_start_offset(missing), content="3")
  inspect(missing_ranges.length(), content="1")
  inspect(missing_ranges[0].0, content="15")
  inspect(missing_ranges[0].1, content="15")

  let missing_end = new_range_fixture("missing-middle")
  let missing_end_context = DomReadingContext::DomReadingContext(
    range_fixture_context(missing_end),
    range_fixture_end_node(missing_end),
  )
  guard range_util_read_horizontal_ranges_with_state(
      new_handy_range_state(),
      range_fixture_root(missing_end),
      0,
      1,
      1,
      0,
      missing_end_context,
    )
    is Some(missing_end_ranges) else {
    fail("expected standalone prior-span end repair")
  }
  inspect(range_fixture_last_end_offset(missing_end), content="3")
  inspect(missing_end_ranges.length(), content="1")
  inspect(missing_end_ranges[0].0, content="5")
  inspect(missing_end_ranges[0].1, content="10")

  assert_true(
    range_util_read_horizontal_ranges_with_state(
      new_handy_range_state(),
      range_fixture_root(missing),
      1,
      1,
      1,
      1,
      missing_context,
    )
    is None,
  )

  let no_children = new_range_fixture("zero-children")
  assert_true(
    range_util_read_horizontal_ranges_with_state(
      new_handy_range_state(),
      range_fixture_root(no_children),
      0,
      0,
      0,
      0,
      DomReadingContext(
        range_fixture_context(no_children),
        range_fixture_end_node(no_children),
      ),
    )
    is None,
  )
}

///|
extern "js" fn new_range_fixture(kind : String) -> RangeFixture =
  #| (kind) => {
  #|   const fixture = {
  #|     failure: "",
  #|     contextReadCount: 0,
  #|     lastStartOffset: -1,
  #|     lastEndOffset: -1,
  #|     parked: false,
  #|   };
  #|   const document = {
  #|     createRange() {
  #|       return {
  #|         startNode: null,
  #|         endNode: null,
  #|         startOffset: 0,
  #|         endOffset: 0,
  #|         setStart(node, offset) {
  #|           if (fixture.failure === "start") throw new Error("setStart");
  #|           this.startNode = node;
  #|           this.startOffset = offset;
  #|           fixture.lastStartOffset = offset;
  #|         },
  #|         setEnd(node, offset) {
  #|           if (fixture.failure === "end") throw new Error("setEnd");
  #|           this.endNode = node;
  #|           this.endOffset = offset;
  #|           fixture.lastEndOffset = offset;
  #|         },
  #|         getClientRects() {
  #|           if (fixture.failure === "rects") throw new Error("rects");
  #|           const start = this.startNode.base + this.startOffset * 10;
  #|           const end = this.endNode.base + this.endOffset * 10;
  #|           return [{ left: start, width: Math.max(0, end - start) }];
  #|         },
  #|         selectNodeContents(node) {
  #|           fixture.parked = node === fixture.endNode;
  #|         },
  #|       };
  #|     },
  #|   };
  #|   const text = (value, base) => ({ textContent: value, base, ownerDocument: document });
  #|   const span = (node, left = 100) => ({
  #|     firstChild: node,
  #|     getClientRects: () => [{ left, width: 0 }],
  #|   });
  #|   let children;
  #|   if (kind === "zero-children") {
  #|     children = [];
  #|   } else if (kind === "empty") {
  #|     children = [span(null, 110)];
  #|   } else if (kind === "missing-middle") {
  #|     children = [span(text("abc", 100)), span(null), span(text("xy", 150))];
  #|   } else {
  #|     children = [span(text("abc", 100)), span(text("de", 130))];
  #|   }
  #|   fixture.root = { children };
  #|   fixture.endNode = {};
  #|   fixture.context = {
  #|     offsetWidth: kind === "zero-offset-width" ? 0 : 100,
  #|     getBoundingClientRect() {
  #|       fixture.contextReadCount++;
  #|       return { left: 100, width: kind === "scale-below" ? 50 : 200 };
  #|     },
  #|   };
  #|   return fixture;
  #| }

///|
extern "js" fn range_fixture_root(fixture : RangeFixture) -> @rdom.Element = "(fixture) => fixture.root"

///|
extern "js" fn range_fixture_context(fixture : RangeFixture) -> @rdom.Element = "(fixture) => fixture.context"

///|
extern "js" fn range_fixture_end_node(fixture : RangeFixture) -> @rdom.Element = "(fixture) => fixture.endNode"

///|
extern "js" fn range_fixture_text_node(
  fixture : RangeFixture,
  index : Int32,
) -> DomNode = "(fixture, index) => fixture.root.children[index].firstChild"

///|
extern "js" fn range_fixture_set_failure(
  fixture : RangeFixture,
  failure : String,
) -> Unit = "(fixture, failure) => { fixture.failure = failure; }"

///|
extern "js" fn range_fixture_context_read_count(
  fixture : RangeFixture,
) -> Int32 = "(fixture) => fixture.contextReadCount"

///|
extern "js" fn range_fixture_last_start_offset(fixture : RangeFixture) -> Int32 = "(fixture) => fixture.lastStartOffset"

///|
extern "js" fn range_fixture_last_end_offset(fixture : RangeFixture) -> Int32 = "(fixture) => fixture.lastEndOffset"

///|
extern "js" fn range_fixture_was_parked(fixture : RangeFixture) -> Bool = "(fixture) => fixture.parked"

///|
extern "js" fn range_rects_at_tolerance() -> ClientRectList =
  #| () => [
  #|   { left: 120, width: 2 },
  #|   { left: 100, width: 2 },
  #|   { left: 103.8, width: 2 },
  #| ]

///|
extern "js" fn range_rects_above_tolerance() -> ClientRectList =
  #| () => [
  #|   { left: 100, width: 2 },
  #|   { left: 103.82, width: 2 },
  #| ]

///|
extern "js" fn empty_client_rects() -> ClientRectList = "() => []"

///|
extern "js" fn null_client_rects() -> ClientRectList = "() => null"

///|
extern "js" fn negative_left_client_rect() -> ClientRectList = "() => [{ left: 90, width: 4 }]"
