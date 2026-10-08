///|
test "viewer options default to Selection whitespace and control characters on" {
  let options = CodeEditorOptions::default()
  assert_true(options.render_whitespace == Selection)
  assert_true(options.render_control_characters)
}

///|
/// Mirrors the reviewed constructor boundary in
/// `EditorConfigurationSnapshot::view_lines_configuration`. Equality keeps the
/// browser package's representation abstract while proving every retained
/// CodeEditorWidget option and measured font axis crosses that boundary unchanged. The
/// paired browser-view tests then feed this constructor into the private
/// per-line render-input adapter.
fn expected_view_lines_configuration(
  snapshot : EditorConfigurationSnapshot,
) -> @view.ViewLinesConfiguration {
  ViewLinesConfiguration(
    line_height=snapshot.font_info.line_height,
    typical_halfwidth_character_width=snapshot.font_info.typical_halfwidth_character_width,
    is_viewport_wrapping=snapshot.word_wrap(),
    can_use_layer_hinting=true,
    space_width=snapshot.font_info.space_width,
    middot_width=snapshot.font_info.middot_width,
    wsmiddot_width=snapshot.font_info.wsmiddot_width,
    use_monospace_optimizations=snapshot.font_info.is_monospace,
    can_use_halfwidth_rightwards_arrow=snapshot.font_info.can_use_halfwidth_rightwards_arrow,
    stop_rendering_line_after=10000,
    render_whitespace=snapshot.options.render_whitespace,
    render_control_characters=snapshot.options.render_control_characters,
    font_ligatures=snapshot.font_info.font_feature_settings !=
      @config.editor_font_ligatures_off,
    vertical_scrollbar_size=@core.editor_vertical_scrollbar_size,
  )
}

///|
test "viewer configuration carries each content-only whitespace mode" {
  let modes : Array[@editor_api.RenderWhitespace] = [
    None,
    Boundary,
    Trailing,
    All,
  ]
  for mode in modes {
    with_test_viewer(
      "  abc  ",
      viewer => {
        let snapshot = viewer.configuration.snapshot()
        assert_true(
          snapshot.view_lines_configuration() ==
          expected_view_lines_configuration(snapshot),
        )
        assert_true(snapshot.options.render_whitespace == mode)
      },
      options=CodeEditorOptions(render_whitespace=mode),
    )
  }
}

///|
test "viewer configuration carries render-control characters" {
  with_test_viewer(
    "café\u{202E}",
    viewer => {
      let snapshot = viewer.configuration.snapshot()
      assert_true(
        snapshot.view_lines_configuration() ==
        expected_view_lines_configuration(snapshot),
      )
      assert_true(snapshot.options.render_control_characters)
    },
    options=CodeEditorOptions(render_control_characters=true),
  )
}

///|
test "viewer configuration carries measured font axes" {
  with_test_viewer(" a ", viewer => {
    let snapshot = viewer.configuration.snapshot()
    assert_true(
      snapshot.view_lines_configuration() ==
      expected_view_lines_configuration(snapshot),
    )
  })
}
