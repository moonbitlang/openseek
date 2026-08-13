///|
test "viewer options default to no soft wrap view model options" {
  let options = ViewerOptions(tab_size=7)
  assert_false(options.smooth_scrolling)
  assert_eq(options.soft_wrap_column_for_content_width(720.0, 7.2), 0)
  let view_model_options = options.view_model_options(
    100,
    font_info=@config.FontInfo::default(),
  )
  assert_false(view_model_options.is_soft_wrap_enabled())
  assert_eq(view_model_options.tab_size, 7)
}

///|
test "viewer options derive soft wrap columns from measured glyphs" {
  let options = ViewerOptions(soft_wrap=true, tab_size=4)
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
  let updated = ViewerOptions(placeholder="Choose a file").with_font_family(
    "Example Mono, monospace",
  )
  assert_eq(updated.font_family, "Example Mono, monospace")
  assert_eq(updated.placeholder, "Choose a file")
}

///|
test "viewer font-size updates preserve the remaining options" {
  let updated = ViewerOptions(placeholder="Choose a file").with_font_size(14.0)
  assert_eq(updated.font_size, 14.0)
  assert_eq(updated.placeholder, "Choose a file")
}
