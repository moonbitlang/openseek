// Source-derived geometry matrix for the font-sensitive branches of
// `vscode/src/vs/editor/common/viewLayout/viewLineRenderer.ts` at vscode
// checked-in submodule.

///|
fn geometry_render_input(
  content : String,
  start_visible_column? : Int = 0,
  tab_size? : Int = 4,
  use_monospace_optimizations? : Bool = false,
  can_use_halfwidth_rightwards_arrow? : Bool = true,
  space_width? : Double = 10.0,
  middot_width? : Double = 10.0,
  wsmiddot_width? : Double = 10.0,
  render_whitespace? : @editor_api.RenderWhitespace = All,
) -> @view_layout.RenderLineInput {
  @view_layout.RenderLineInput::from_view_line(
    {
      min_column: 1,
      max_column: content.length() + 1,
      content,
      continues_with_wrapped_line: false,
      contains_rtl: false,
      is_basic_ascii: true,
      tokens: [LinePart(content.length(), "mtk1")],
      inline_decorations: [],
      tab_size,
      start_visible_column,
      text_direction: LTR,
      has_variable_fonts: false,
    },
    use_monospace_optimizations~,
    can_use_halfwidth_rightwards_arrow~,
    space_width~,
    middot_width~,
    wsmiddot_width~,
    render_whitespace~,
  )
}

///|
test "RenderLineInput normalizes render-space identity" {
  let base = geometry_render_input(
    " ",
    space_width=10.0,
    middot_width=9.0,
    wsmiddot_width=14.0,
  )
  assert_eq(base.render_space_width, 9.0)
  assert_eq(base.render_space_char_code, 0xB7)
  // Raw candidates are not identity axes once they select the same normalized
  // width and glyph.
  let same_normalized = geometry_render_input(
    " ",
    space_width=10.0,
    middot_width=9.0,
    wsmiddot_width=30.0,
  )
  assert_true(base == same_normalized)
  let different_width = geometry_render_input(
    " ",
    space_width=10.0,
    middot_width=8.0,
    wsmiddot_width=30.0,
  )
  assert_false(base == different_width)
  let different_glyph = geometry_render_input(
    " ",
    space_width=10.0,
    middot_width=30.0,
    wsmiddot_width=9.0,
  )
  assert_eq(different_glyph.render_space_width, base.render_space_width)
  assert_eq(different_glyph.render_space_char_code, 0x2E31)
  assert_false(base == different_glyph)
  for
    changed in [
      geometry_render_input(
        " ",
        use_monospace_optimizations=!base.use_monospace_optimizations,
        space_width=10.0,
        middot_width=9.0,
        wsmiddot_width=14.0,
      ),
      geometry_render_input(
        " ",
        can_use_halfwidth_rightwards_arrow=!base.can_use_halfwidth_rightwards_arrow,
        space_width=10.0,
        middot_width=9.0,
        wsmiddot_width=14.0,
      ),
      geometry_render_input(
        " ",
        space_width=base.space_width + 1.0,
        middot_width=9.0,
        wsmiddot_width=14.0,
      ),
    ] {
    assert_false(base == changed)
  }
}

///|
test "RenderLineInput render-space choice uses strict-less and middot tie" {
  let word_separator = geometry_render_input(
    " ",
    space_width=10.0,
    middot_width=12.0,
    wsmiddot_width=9.0,
  )
  assert_eq(word_separator.render_space_width, 9.0)
  assert_eq(word_separator.render_space_char_code, 0x2E31)
  assert_true(
    @view_layout.render_view_line2(word_separator).html.contains("\u{2e31}"),
  )
  let tie = geometry_render_input(
    " ",
    space_width=10.0,
    middot_width=11.0,
    wsmiddot_width=9.0,
  )
  assert_eq(tie.render_space_width, 11.0)
  assert_eq(tie.render_space_char_code, 0xB7)
  assert_true(@view_layout.render_view_line2(tie).html.contains("·"))
}

///|
test "rendered tab arrow matrix covers safe and unsafe one and multi columns" {
  let safe_one = @view_layout.render_view_line2(
    geometry_render_input(
      "\t",
      start_visible_column=3,
      can_use_halfwidth_rightwards_arrow=true,
    ),
  )
  assert_true(safe_one.html.contains("￫"))
  assert_false(safe_one.html.contains("→"))
  let unsafe_one = @view_layout.render_view_line2(
    geometry_render_input(
      "\t",
      start_visible_column=3,
      can_use_halfwidth_rightwards_arrow=false,
    ),
  )
  assert_true(unsafe_one.html.contains("→"))
  assert_false(unsafe_one.html.contains("￫"))
  let safe_multi = @view_layout.render_view_line2(
    geometry_render_input(
      "\t",
      start_visible_column=1,
      can_use_halfwidth_rightwards_arrow=true,
    ),
  )
  assert_true(safe_multi.html.contains("→"))
  assert_false(safe_multi.html.contains("￫"))
  let unsafe_multi = @view_layout.render_view_line2(
    geometry_render_input(
      "\t",
      start_visible_column=1,
      can_use_halfwidth_rightwards_arrow=false,
    ),
  )
  assert_true(unsafe_multi.html.contains("→"))
  assert_false(unsafe_multi.html.contains("￫"))
}

///|
test "nonzero start visible column drives every tab residue and mapping end" {
  for start_visible_column in 1..<=4 {
    let expected_width = 4 - start_visible_column % 4
    let output = @view_layout.render_view_line2(
      geometry_render_input("\t", start_visible_column~),
    )
    assert_eq(output.character_mapping.get_horizontal_offset(1), 0)
    assert_eq(output.character_mapping.get_horizontal_offset(2), expected_width)
  }
}
