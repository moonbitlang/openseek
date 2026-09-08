///|
test "folding decoration controls preserve mouseover always and never policies" {
  let provider = FoldingDecorationProvider(folding_test_model(["line"]))

  let mouseover = provider.get_decoration_option(false, false, false, false)
  assert_eq(
    mouseover.description,
    "folding-expanded-auto-hide-visual-decoration",
  )
  assert_eq(
    mouseover.first_line_decoration_class_name,
    Some(FOLDING_EXPANDED_ICON_CLASS),
  )

  provider.update_options(
    show_folding_controls=Always,
    show_folding_highlights=true,
  )
  let always = provider.get_decoration_option(false, false, false, false)
  assert_eq(always.description, "folding-expanded-visual-decoration")
  assert_eq(
    always.first_line_decoration_class_name,
    Some("alwaysShowFoldIcons \{FOLDING_EXPANDED_ICON_CLASS}"),
  )

  provider.update_options(
    show_folding_controls=Never,
    show_folding_highlights=true,
  )
  let never_expanded = provider.get_decoration_option(
    false, false, false, false,
  )
  assert_eq(never_expanded.description, "folding-no-controls-range-decoration")
  assert_eq(never_expanded.first_line_decoration_class_name, None)
  let never_collapsed = provider.get_decoration_option(
    true, false, false, false,
  )
  assert_eq(never_collapsed.class_name, "folded-background")
  assert_eq(never_collapsed.after_content_class_name, Some("inline-folded"))

  let hidden = provider.get_decoration_option(true, true, false, false)
  assert_eq(hidden.description, "folding-hidden-range-decoration")
}

///|
test "outline body decorations complete the hidden body inline" {
  let provider = FoldingDecorationProvider(folding_test_model(["line"]))
  let collapsed = provider.get_decoration_option(true, false, false, true)
  assert_eq(
    collapsed.description,
    "folding-collapsed-outline-body-highlighted-visual-decoration",
  )
  assert_eq(collapsed.after_content_class_name, Some("inline-folded-body"))
  assert_eq(
    collapsed.first_line_decoration_class_name,
    Some(FOLDING_COLLAPSED_ICON_CLASS),
  )
}
