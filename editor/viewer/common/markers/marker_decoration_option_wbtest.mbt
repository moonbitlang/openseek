///|
fn option_for(
  severity : MarkerSeverity,
  tags? : Array[MarkerTag],
) -> @model.ModelDecorationOptions {
  let marker = make_marker(severity, 1, 1, 1, 2, tags?)
  create_decoration_option(marker)
}

///|
test "create_decoration_option severity matrix" {
  let hint = option_for(Hint)
  assert_true(hint.class_name == "squiggly-hint")
  assert_eq(hint.z_index, 0)
  assert_true(hint.overview_ruler == Some({ color: None, position: Right, }))
  assert_true(hint.minimap is None)
  assert_true(hint.inline_class_name is None)
  // constant option fields (markerDecorationsService.ts:284-296)
  assert_true(hint.show_if_collapsed)
  assert_true(hint.stickiness == NeverGrowsWhenTypingAtEdges)
  assert_eq(hint.description, "marker-decoration")
  let info = option_for(Info)
  assert_true(info.class_name == "squiggly-info")
  assert_eq(info.z_index, 10)
  assert_true(
    info.overview_ruler ==
    Some({ color: Some(overview_ruler_info), position: Right, }),
  )
  assert_true(info.minimap == Some({ color: minimap_info, position: Inline, }))
  let warning = option_for(Warning)
  assert_true(warning.class_name == "squiggly-warning")
  assert_eq(warning.z_index, 20)
  assert_true(
    warning.overview_ruler ==
    Some({ color: Some(overview_ruler_warning), position: Right, }),
  )
  assert_true(
    warning.minimap == Some({ color: minimap_warning, position: Inline, }),
  )
  let error = option_for(Error)
  assert_true(error.class_name == "squiggly-error")
  assert_eq(error.z_index, 30)
  assert_true(
    error.overview_ruler ==
    Some({ color: Some(overview_ruler_error), position: Right, }),
  )
  assert_true(
    error.minimap == Some({ color: minimap_error, position: Inline, }),
  )
}

///|
test "create_decoration_option tag overrides" {
  // Hint + Unnecessary → squiggly-unnecessary className + inline class
  let unnecessary = option_for(Hint, tags=[Unnecessary])
  assert_true(unnecessary.class_name == "squiggly-unnecessary")
  assert_true(
    unnecessary.inline_class_name == Some("squiggly-inline-unnecessary"),
  )
  // Hint + Deprecated → no className (empty), deprecated inline class
  let deprecated = option_for(Hint, tags=[Deprecated])
  assert_true(deprecated.class_name == "")
  assert_true(
    deprecated.inline_class_name == Some("squiggly-inline-deprecated"),
  )
  // both tags → Deprecated overrides inlineClassName (tested first)
  let both = option_for(Hint, tags=[Unnecessary, Deprecated])
  assert_true(both.class_name == "")
  assert_true(both.inline_class_name == Some("squiggly-inline-deprecated"))
  // Error keeps its className; tag only adds the inline class
  let error_unnecessary = option_for(Error, tags=[Unnecessary])
  assert_true(error_unnecessary.class_name == "squiggly-error")
  assert_true(
    error_unnecessary.inline_class_name == Some("squiggly-inline-unnecessary"),
  )
}
