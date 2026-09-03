///|
test "viewer options default to no soft wrap view model options" {
  let options = CodeEditorOptions(tab_size=7)
  assert_false(options.smooth_scrolling)
  assert_true(options.handle_mouse_wheel)
  assert_eq(options.soft_wrap_column_for_content_width(720.0, 7.2), 0)
  let view_model_options = options.view_model_options(
    100,
    font_info=@config.FontInfo::default(),
  )
  assert_false(view_model_options.is_soft_wrap_enabled())
  assert_eq(view_model_options.tab_size, 7)
}

///|
test "viewer wheel ownership is a live non-layout option" {
  let defaults = CodeEditorOptions::default()
  let external = defaults.with_handle_mouse_wheel(false)
  assert_false(external.handle_mouse_wheel)
  assert_true(defaults.same_layout_options(external))
}

///|
test "CodeLens defaults and optional font overrides are immutable non-layout options" {
  let defaults = CodeEditorOptions::default()
  assert_true(defaults.code_lens)
  assert_true(defaults.code_lens_font_family is None)
  assert_true(defaults.code_lens_font_size is None)
  let updated = defaults
    .with_code_lens(false)
    .with_code_lens_font_family(Some("Lens Mono"))
    .with_code_lens_font_size(Some(11.5))
  assert_false(updated.code_lens)
  assert_eq(updated.code_lens_font_family, Some("Lens Mono"))
  assert_eq(updated.code_lens_font_size, Some(11.5))
  assert_true(defaults.code_lens)
  assert_true(defaults.same_layout_options(updated))
}

///|
test "viewer options derive soft wrap columns from measured glyphs" {
  let options = CodeEditorOptions(soft_wrap=true, tab_size=4)
  assert_eq(options.soft_wrap_column_for_content_width(72.0, 7.2), 10)
  let view_model_options = options.view_model_options(
    10,
    font_info=@config.FontInfo::default(),
  )
  assert_true(view_model_options.is_soft_wrap_enabled())
  assert_eq(view_model_options.soft_wrap_column, 10)
  assert_eq(view_model_options.tab_size, 4)
}

///|
test "viewer font-family updates preserve the remaining options" {
  let updated = CodeEditorOptions(placeholder="Choose a file").with_font_family(
    "Example Mono, monospace",
  )
  assert_eq(updated.font_family, "Example Mono, monospace")
  assert_eq(updated.placeholder, "Choose a file")
}

///|
test "viewer font-size updates preserve the remaining options" {
  let updated = CodeEditorOptions(placeholder="Choose a file").with_font_size(
    14.0,
  )
  assert_eq(updated.font_size, 14.0)
  assert_eq(updated.placeholder, "Choose a file")
}
