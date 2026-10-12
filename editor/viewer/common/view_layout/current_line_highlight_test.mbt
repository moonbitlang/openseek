///|
test "should-render predicates port cLH:184-197 across modes" {
  // _shouldRenderInContent: line/all + empty selection (+ focus option).
  assert_true(
    @view_layout.should_render_line_highlight_in_content(
      Line,
      false,
      false,
      true,
    ),
  )
  assert_true(
    @view_layout.should_render_line_highlight_in_content(
      All,
      false,
      false,
      true,
    ),
  )
  assert_false(
    @view_layout.should_render_line_highlight_in_content(
      Gutter,
      false,
      false,
      true,
    ),
  )
  assert_false(
    @view_layout.should_render_line_highlight_in_content(
      None,
      false,
      false,
      true,
    ),
  )
  // A non-empty selection suppresses the content highlight.
  assert_false(
    @view_layout.should_render_line_highlight_in_content(
      Line,
      false,
      false,
      false,
    ),
  )
  // renderLineHighlightOnlyWhenFocus gates on focus.
  assert_false(
    @view_layout.should_render_line_highlight_in_content(
      Line,
      true,
      false,
      true,
    ),
  )
  assert_true(
    @view_layout.should_render_line_highlight_in_content(Line, true, true, true),
  )
  // _shouldRenderInMargin: gutter/all (+ focus option); selection-independent.
  assert_true(
    @view_layout.should_render_line_highlight_in_margin(Gutter, false, false),
  )
  assert_true(
    @view_layout.should_render_line_highlight_in_margin(All, false, false),
  )
  assert_false(
    @view_layout.should_render_line_highlight_in_margin(Line, false, false),
  )
  assert_false(
    @view_layout.should_render_line_highlight_in_margin(Gutter, true, false),
  )
}

///|
test "class builders port cLH:210 and :226" {
  inspect(
    @view_layout.current_line_content_class(in_margin=false, exact=false),
    content="current-line",
  )
  inspect(
    @view_layout.current_line_content_class(in_margin=true, exact=true),
    content="current-line current-line-both current-line-exact",
  )
  inspect(
    @view_layout.current_line_margin_class(
      in_margin=false,
      other=false,
      exact=true,
    ),
    content="current-line",
  )
  inspect(
    @view_layout.current_line_margin_class(
      in_margin=true,
      other=true,
      exact=true,
    ),
    content="current-line current-line-margin current-line-margin-both current-line-exact-margin",
  )
}

///|
test "view_line_span_of_model_line finds the wrapped span" {
  // View lines 1..6 map to model lines 1,2,2,2,3,3.
  let mapping : ReadOnlyArray[Int32] = [1, 2, 2, 2, 3, 3]
  let model_line_of = (view_line : Int32) => mapping[view_line - 1]
  debug_inspect(
    @view_layout.view_line_span_of_model_line(3, 6, model_line_of),
    content="(2, 4)",
  )
  debug_inspect(
    @view_layout.view_line_span_of_model_line(1, 6, model_line_of),
    content="(1, 1)",
  )
  debug_inspect(
    @view_layout.view_line_span_of_model_line(6, 6, model_line_of),
    content="(5, 6)",
  )
}
