///|
test "test section stays collapsed including an all-test initial selection" {
  let harness = install_references_peek_test_browser()
  defer harness.dispose()
  let ordinary = references_peek_test_location("/workspace/a.mbt", 1, 1)
  let test_ref = {
    ..references_peek_test_location("/workspace/a.mbt", 2, 1),
    is_test: Some(true),
  }
  for locations in [[ordinary, test_ref], [test_ref]] {
    let widget = ReferencesPeekWidget(
      References,
      ReferencesPeekTestLog().callbacks(),
    )
    let model = references_peek_test_model(locations)
    let selected = model.references[model.references.length() - 1]
    widget.set_results(model, Some(selected))
    let tree = references_peek_test_class_descendant(
      widget.get_dom_node(),
      "moonbit-viewer-reference-results-tree",
      0,
    )
    let section = references_peek_test_class_descendant(
      tree, "moonbit-viewer-reference-results-tests", 0,
    )
    assert_eq(references_peek_test_attribute(section, "aria-expanded"), "false")
    assert_eq(references_peek_test_visible_row_count(tree), locations.length())
    assert_eq(references_peek_test_visible_tabstop_count(tree), 1)
    assert_eq(references_peek_test_key(section, "ArrowRight"), "true:true")
    assert_eq(references_peek_test_attribute(section, "aria-expanded"), "true")
    assert_eq(
      references_peek_test_visible_row_count(tree),
      locations.length() + 2,
    )
    assert_eq(references_peek_test_key(section, "ArrowLeft"), "true:true")
    widget.set_selected(selected)
    assert_eq(references_peek_test_attribute(section, "aria-expanded"), "true")
    assert_eq(references_peek_test_visible_tabstop_count(tree), 1)
    widget.set_results(model, Some(selected))
    let section = references_peek_test_class_descendant(
      tree, "moonbit-viewer-reference-results-tests", 0,
    )
    assert_eq(references_peek_test_attribute(section, "aria-expanded"), "false")
    widget.dispose()
  }
}
