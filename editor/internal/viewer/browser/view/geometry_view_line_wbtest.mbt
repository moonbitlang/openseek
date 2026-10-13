// Source-derived slow-rendered-line tests for pinned `viewLine.ts` at
// checked-in source. Fast/zoom/WebKit/GPU rows remain
// explicitly deferred by the approved geometry ledger.

///|
#external
priv type ViewLineFixture

///|
fn geometry_line_input(
  content : String,
  text_direction~ : @view_layout.TextDirection = LTR,
  contains_rtl~ : Bool = false,
  is_basic_ascii~ : Bool = true,
  stop_rendering_line_after~ : Int32 = -1,
  space_width~ : Double = 10.0,
  line_decorations~ : Array[@view_layout.LineDecoration] = [],
  continues_with_wrapped_line~ : Bool = false,
) -> @view_layout.RenderLineInput {
  @view_layout.RenderLineInput::from_view_line(
    {
      min_column: 1,
      max_column: content.length() + 1,
      content,
      continues_with_wrapped_line,
      contains_rtl,
      is_basic_ascii,
      tokens: [],
      inline_decorations: [],
      tab_size: 4,
      start_visible_column: 0,
      text_direction,
      has_variable_fonts: false,
    },
    line_decorations~,
    space_width~,
    stop_rendering_line_after~,
    vertical_scrollbar_size=14.0,
  )
}

///|
fn render_fixture_line(
  input : @view_layout.RenderLineInput,
  fixture : ViewLineFixture,
) -> ViewLine raise {
  let line = ViewLine::ViewLine()
  let builder = StringBuilder()
  assert_true(line.render_line(1, input, 0, 20, builder))
  line.set_dom_node(view_line_fixture_line_node(fixture))
  line
}

///|
fn mapped_fixture_line(
  input : @view_layout.RenderLineInput,
  fixture : ViewLineFixture,
  mapping_length : Int32,
) -> ViewLine {
  let mapping = @view_layout.CharacterMapping(mapping_length)
  for column in 1..<=mapping_length {
    mapping.set_column_info(column, 0, column - 1, column - 1)
  }
  let line = ViewLine::ViewLine()
  let output = @view_layout.render_view_line2(input)
  line.rendered_view_line = Some(
    RenderedViewLine(
      None,
      input,
      mapping,
      foreign_element_facts(output.contains_foreign_elements),
    ),
  )
  line.set_dom_node(view_line_fixture_line_node(fixture))
  line
}

///|
test "ViewLine slow width cache reads once and marks layout" {
  let fixture = new_view_line_fixture(42.0, 10.0)
  let line = render_fixture_line(geometry_line_input("alpha"), fixture)
  assert_false(line.get_width_is_fast())
  let context = DomReadingContext::DomReadingContext(
    view_line_fixture_context(fixture),
    view_line_fixture_end_node(fixture),
  )
  inspect(line.get_width(Some(context)), content="42")
  assert_true(context.did_dom_layout())
  assert_true(line.get_width_is_fast())
  view_line_fixture_set_width(fixture, 55.0)
  inspect(line.get_width(Some(context)), content="42")
}

///|
test "ViewLine absent strategy guards width ranges and layout writes" {
  let absent = ViewLine::ViewLine()
  inspect(absent.get_width(None), content="0")
  assert_true(absent.get_width_is_fast())
  let fixture = new_view_line_fixture(10.0, 10.0)
  let context = DomReadingContext::DomReadingContext(
    view_line_fixture_context(fixture),
    view_line_fixture_end_node(fixture),
  )
  assert_true(absent.get_visible_ranges_for_range(1, 1, 1, context) is None)
  absent.layout_line(1, 7, 23)

  let input = geometry_line_input("a")
  let rendered_without_dom = ViewLine::ViewLine()
  assert_true(
    rendered_without_dom.render_line(1, input, 0, 20, StringBuilder()),
  )
  assert_true(rendered_without_dom.get_dom_node() is None)
  inspect(rendered_without_dom.get_width(Some(context)), content="0")
  assert_false(rendered_without_dom.get_width_is_fast())
  assert_true(
    rendered_without_dom.get_visible_ranges_for_range(1, 1, 1, context) is None,
  )
  rendered_without_dom.layout_line(1, 7, 23)

  let rendered = mapped_fixture_line(input, fixture, 2)
  rendered.layout_line(1, 7, 23)
  inspect(view_line_fixture_style(fixture, "top"), content="7px")
  inspect(view_line_fixture_style(fixture, "height"), content="23px")
  inspect(view_line_fixture_style(fixture, "line-height"), content="23px")
}

///|
test "ViewLine visible ranges preserve collapsed raw and truncation branches" {
  let fixture = new_view_line_fixture(42.0, 10.0)
  let input = geometry_line_input("alpha", stop_rendering_line_after=2)
  let line = mapped_fixture_line(
    input,
    fixture,
    input.line_content.length() + 1,
  )
  let context = DomReadingContext::DomReadingContext(
    view_line_fixture_context(fixture),
    view_line_fixture_end_node(fixture),
  )
  guard line.get_visible_ranges_for_range(1, 2, 2, context)
    is Some((false, collapsed)) else {
    fail("expected collapsed range")
  }
  inspect(collapsed.length(), content="1")
  inspect(collapsed[0].0, content="10")
  inspect(collapsed[0].1, content="0")

  guard line.get_visible_ranges_for_range(1, 4, 4, context)
    is Some((true, truncated)) else {
    fail("expected outside-rendered range")
  }
  inspect(truncated[0].0, content="42")
  inspect(truncated[0].1, content="0")

  guard line.get_visible_ranges_for_range(1, 3, 3, context)
    is Some((false, boundary)) else {
    fail("expected exact truncation boundary")
  }
  inspect(boundary[0].0, content="20")
  guard line.get_visible_ranges_for_range(1, 2, 4, context)
    is Some((false, clamped_end)) else {
    fail("expected one-sided truncation clamp")
  }
  inspect(clamped_end[0].0, content="10")
  inspect(clamped_end[0].1, content="10")

  let rtl_fixture = new_view_line_fixture(42.0, 10.0)
  let rtl_input = geometry_line_input(
    "abc",
    text_direction=RTL,
    is_basic_ascii=false,
  )
  let rtl = mapped_fixture_line(rtl_input, rtl_fixture, 4)
  let rtl_context = DomReadingContext::DomReadingContext(
    view_line_fixture_context(rtl_fixture),
    view_line_fixture_end_node(rtl_fixture),
  )
  guard rtl.get_visible_ranges_for_range(1, 2, 3, rtl_context)
    is Some((false, rtl_ranges)) else {
    fail("expected noncollapsed RTL raw range")
  }
  inspect(rtl_ranges[0].0, content="10")
  inspect(rtl_ranges[0].1, content="10")
}

///|
test "ViewLine basic ASCII stabilization uses exact inclusive one-pixel tolerance" {
  let within_fixture = new_view_line_fixture(40.0, 10.8)
  let within_input = geometry_line_input("abc", space_width=10.0)
  let within = mapped_fixture_line(
    within_input,
    within_fixture,
    within_input.line_content.length() + 1,
  )
  let within_context = DomReadingContext::DomReadingContext(
    view_line_fixture_context(within_fixture),
    view_line_fixture_end_node(within_fixture),
  )
  guard within.get_visible_ranges_for_range(1, 2, 2, within_context)
    is Some((_, within_ranges)) else {
    fail("expected within-tolerance range")
  }
  inspect(within_ranges[0].0, content="10")

  let exact_fixture = new_view_line_fixture(40.0, 11.0)
  let exact_input = geometry_line_input("abc", space_width=10.0)
  let exact = mapped_fixture_line(
    exact_input,
    exact_fixture,
    exact_input.line_content.length() + 1,
  )
  let exact_context = DomReadingContext::DomReadingContext(
    view_line_fixture_context(exact_fixture),
    view_line_fixture_end_node(exact_fixture),
  )
  guard exact.get_visible_ranges_for_range(1, 2, 2, exact_context)
    is Some((_, exact_ranges)) else {
    fail("expected exact-tolerance range")
  }
  inspect(exact_ranges[0].0, content="10")

  let beyond_fixture = new_view_line_fixture(40.0, 11.1)
  let beyond_input = geometry_line_input("abc", space_width=10.0)
  let beyond = mapped_fixture_line(
    beyond_input,
    beyond_fixture,
    beyond_input.line_content.length() + 1,
  )
  let beyond_context = DomReadingContext::DomReadingContext(
    view_line_fixture_context(beyond_fixture),
    view_line_fixture_end_node(beyond_fixture),
  )
  guard beyond.get_visible_ranges_for_range(1, 2, 2, beyond_context)
    is Some((_, beyond_ranges)) else {
    fail("expected above-tolerance range")
  }
  assert_true((beyond_ranges[0].0 - 11.1).abs() < 0.000001)
}

///|
test "ViewLine empty foreign-content branches distinguish none after before and both" {
  let fixture = new_view_line_fixture(40.0, 10.0)
  view_line_fixture_set_first_span_width(fixture, 13.0)
  let cases : Array[(Array[@view_layout.LineDecoration], Double)] = [
    ([], 0.0),
    (
      [
        LineDecoration(
          1,
          1,
          "letter-spacing",
          decoration_type=RegularAffectingLetterSpacing,
        ),
      ],
      0.0,
    ),
    ([LineDecoration(1, 1, "after", decoration_type=After)], 0.0),
    ([LineDecoration(1, 1, "before", decoration_type=Before)], 40.0),
    (
      [
        LineDecoration(1, 1, "before", decoration_type=Before),
        LineDecoration(1, 1, "after", decoration_type=After),
      ],
      13.0,
    ),
  ]
  for case in cases {
    let decorations = case.0
    let expected = case.1
    let input = geometry_line_input("", line_decorations=decorations)
    let line = mapped_fixture_line(input, fixture, 0)
    let context = DomReadingContext::DomReadingContext(
      view_line_fixture_context(fixture),
      view_line_fixture_end_node(fixture),
    )
    guard line.get_visible_ranges_for_range(1, 1, 1, context)
      is Some((_, ranges)) else {
      fail("expected empty-line range")
    }
    assert_true((ranges[0].0 - expected).abs() < 0.000001)
  }

  let missing_first_child_fixture = new_view_line_fixture(40.0, 10.0)
  view_line_fixture_set_content_first_child(missing_first_child_fixture, false)
  let both_input = geometry_line_input("", line_decorations=[
    LineDecoration(1, 1, "before", decoration_type=Before),
    LineDecoration(1, 1, "after", decoration_type=After),
  ])
  let both = mapped_fixture_line(both_input, missing_first_child_fixture, 0)
  let both_context = DomReadingContext::DomReadingContext(
    view_line_fixture_context(missing_first_child_fixture),
    view_line_fixture_end_node(missing_first_child_fixture),
  )
  guard both.get_visible_ranges_for_range(1, 1, 1, both_context)
    is Some((_, both_ranges)) else {
    fail("expected both-foreign range without first child")
  }
  inspect(both_ranges[0].0, content="0")
  assert_false(both_context.did_dom_layout())
}

///|
test "ViewLine pixel cache whitespace endpoint and prior DOM reuse" {
  let cache_fixture = new_view_line_fixture(40.0, 10.3)
  let cache_input = geometry_line_input("abc", is_basic_ascii=false)
  let cached = mapped_fixture_line(cache_input, cache_fixture, 4)
  let cache_context = DomReadingContext::DomReadingContext(
    view_line_fixture_context(cache_fixture),
    view_line_fixture_end_node(cache_fixture),
  )
  assert_true(
    cached.get_visible_ranges_for_range(1, 2, 2, cache_context) is Some(_),
  )
  inspect(view_line_fixture_range_read_count(cache_fixture), content="1")
  assert_true(
    cached.get_visible_ranges_for_range(1, 2, 2, cache_context) is Some(_),
  )
  inspect(view_line_fixture_range_read_count(cache_fixture), content="1")
  let whitespace_fixture = new_view_line_fixture(42.0, 10.0)
  let whitespace_input = geometry_line_input("   ")
  let whitespace = mapped_fixture_line(whitespace_input, whitespace_fixture, 4)
  guard whitespace.rendered_view_line is Some(whitespace_rendered) else {
    fail("expected whitespace rendered strategy")
  }
  assert_true(whitespace_rendered.is_whitespace_only)
  assert_false(whitespace_rendered.foreign_elements.before)
  assert_false(whitespace_rendered.foreign_elements.after)
  inspect(whitespace_rendered.character_mapping.length, content="4")
  let whitespace_context = DomReadingContext::DomReadingContext(
    view_line_fixture_context(whitespace_fixture),
    view_line_fixture_end_node(whitespace_fixture),
  )
  guard whitespace.get_visible_ranges_for_range(1, 4, 4, whitespace_context)
    is Some((false, final_column)) else {
    fail("expected whitespace final-column range")
  }
  inspect(final_column[0].0, content="42")
  inspect(view_line_fixture_range_read_count(whitespace_fixture), content="0")

  let prior_fixture = new_view_line_fixture(20.0, 10.0)
  let prior = render_fixture_line(geometry_line_input("a"), prior_fixture)
  guard prior.get_dom_node() is Some(prior_dom_node) else {
    fail("expected attached prior DOM")
  }
  prior.on_tokens_changed()
  assert_true(
    prior.render_line(1, geometry_line_input("b"), 0, 20, StringBuilder()),
  )
  guard prior.get_dom_node() is Some(reused_dom_node) else {
    fail("expected reused DOM")
  }
  assert_true(prior_dom_node.is_same_node(reused_dom_node.as_node()))
}

///|
test "ViewLine row HTML preserves direction padding class and geometry CSS" {
  let rtl = ViewLine::ViewLine()
  let rtl_builder = StringBuilder()
  assert_true(
    rtl.render_line(
      7,
      geometry_line_input("abc", text_direction=RTL),
      30,
      21,
      rtl_builder,
    ),
  )
  let rtl_html = rtl_builder.to_string()
  assert_true(rtl_html.contains("dir=\"rtl\""))
  assert_true(rtl_html.contains("padding-right:14"))
  assert_true(rtl_html.contains("top:30px;height:21px;line-height:21px"))
  assert_true(rtl_html.contains("class=\"view-line\""))

  let mixed = ViewLine::ViewLine()
  let mixed_builder = StringBuilder()
  assert_true(
    mixed.render_line(
      1,
      geometry_line_input("abc", contains_rtl=true),
      0,
      20,
      mixed_builder,
    ),
  )
  assert_true(mixed_builder.to_string().contains("dir=\"ltr\""))
  assert_false(mixed_builder.to_string().contains("padding-right"))

  let plain = ViewLine::ViewLine()
  let plain_builder = StringBuilder()
  assert_true(
    plain.render_line(1, geometry_line_input("abc"), 0, 20, plain_builder),
  )
  assert_false(plain_builder.to_string().contains("dir="))
}

///|
test "panic ViewLine setDomNode rejects absent rendered strategy" {
  ViewLine::ViewLine().set_dom_node(
    new_view_line_fixture(1.0, 1.0) |> view_line_fixture_line_node,
  )
}

///|
extern "js" fn new_view_line_fixture(
  width : Double,
  advance : Double,
) -> ViewLineFixture =
  #| (width, advance) => {
  #|   const fixture = { width, advance, firstSpanWidth: 0, rangeReadCount: 0 };
  #|   const document = {
  #|     createRange() {
  #|       return {
  #|         setStart(node, offset) { this.startNode = node; this.startOffset = offset; },
  #|         setEnd(node, offset) { this.endNode = node; this.endOffset = offset; },
  #|         getClientRects() {
  #|           if (this.startNode.fixture) this.startNode.fixture.rangeReadCount++;
  #|           const left = this.startNode.base + this.startOffset * this.startNode.advance;
  #|           const right = this.endNode.base + this.endOffset * this.endNode.advance;
  #|           return [{ left, width: Math.max(0, right - left) }];
  #|         },
  #|         selectNodeContents(_node) {},
  #|       };
  #|     },
  #|   };
  #|   const textNode = {
  #|     textContent: "abcdefghijklmnopqrstuvwxyz",
  #|     base: 100,
  #|     advance,
  #|     fixture,
  #|     ownerDocument: document,
  #|   };
  #|   const span = { firstChild: textNode, getClientRects: () => [{ left: 100, width: 0 }] };
  #|   Object.defineProperty(span, "offsetWidth", { get: () => fixture.firstSpanWidth });
  #|   const content = { children: [span], firstChild: span };
  #|   Object.defineProperty(content, "offsetWidth", { get: () => fixture.width });
  #|   fixture.lineNode = {
  #|     firstChild: content,
  #|     style: { setProperty(name, value) { this[name] = value; } },
  #|   };
  #|   fixture.context = {
  #|     offsetWidth: 100,
  #|     getBoundingClientRect: () => ({ left: 100, width: 100 }),
  #|   };
  #|   fixture.endNode = {};
  #|   return fixture;
  #| }

///|
extern "js" fn view_line_fixture_line_node(
  fixture : ViewLineFixture,
) -> @rdom.Element = "(fixture) => fixture.lineNode"

///|
extern "js" fn view_line_fixture_context(
  fixture : ViewLineFixture,
) -> @rdom.Element = "(fixture) => fixture.context"

///|
extern "js" fn view_line_fixture_end_node(
  fixture : ViewLineFixture,
) -> @rdom.Element = "(fixture) => fixture.endNode"

///|
extern "js" fn view_line_fixture_set_width(
  fixture : ViewLineFixture,
  width : Double,
) -> Unit = "(fixture, width) => { fixture.width = width; }"

///|
extern "js" fn view_line_fixture_set_first_span_width(
  fixture : ViewLineFixture,
  width : Double,
) -> Unit = "(fixture, width) => { fixture.firstSpanWidth = width; }"

///|
extern "js" fn view_line_fixture_set_content_first_child(
  fixture : ViewLineFixture,
  present : Bool,
) -> Unit =
  #| (fixture, present) => {
  #|   const content = fixture.lineNode.firstChild;
  #|   content.firstChild = present ? content.children[0] : null;
  #| }

///|
extern "js" fn view_line_fixture_range_read_count(
  fixture : ViewLineFixture,
) -> Int32 = "(fixture) => fixture.rangeReadCount"

///|
extern "js" fn view_line_fixture_style(
  fixture : ViewLineFixture,
  name : String,
) -> String = "(fixture, name) => fixture.lineNode.style[name] || ''"
