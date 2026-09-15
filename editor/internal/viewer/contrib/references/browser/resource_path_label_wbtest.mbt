///|
test "both Peek modes use host paths and preserve outside resource labels" {
  let harness = install_references_peek_test_browser()
  defer harness.dispose()
  let label = fn(uri : @base_common.Uri) -> String? {
    uri.path.strip_prefix("/workspace/").map(path => path.to_owned())
  }
  let model = references_peek_test_model([
    references_peek_test_location("/workspace/main.mbt", 1, 1),
    references_peek_test_location("/workspace/src/main.mbt", 2, 1),
    references_peek_test_location("/workspace-other/main.mbt", 3, 1),
  ])
  for mode in [@references.ReferencesPeekMode::Definitions, References] {
    let widget = ReferencesPeekWidget(
      mode,
      ReferencesPeekTestLog().callbacks(),
      resource_path_label=label,
    )
    defer widget.dispose()
    widget.set_results(model, Some(model.references[0]))
    let tree = references_peek_test_class_descendant(
      widget.get_dom_node(),
      "moonbit-viewer-reference-results-tree",
      0,
    )
    for group in model.groups {
      let row = references_peek_test_row(tree, "group", group.group_index)
      match group.uri.path {
        "/workspace/main.mbt" => {
          assert_eq(references_peek_test_attribute(row, "title"), "main.mbt")
          let parent = references_peek_test_class_descendant(
            row, "moonbit-viewer-reference-results-file-parent", 0,
          )
          assert_eq(references_peek_test_text_content(parent), "")
          assert_eq(
            references_peek_test_attribute(row, "aria-label"),
            "1 result in main.mbt",
          )
        }
        "/workspace/src/main.mbt" => {
          assert_eq(
            references_peek_test_attribute(row, "title"),
            "src/main.mbt",
          )
          let parent = references_peek_test_class_descendant(
            row, "moonbit-viewer-reference-results-file-parent", 0,
          )
          assert_eq(references_peek_test_text_content(parent), "src")
          assert_false(
            references_peek_test_attribute(row, "aria-label").contains(
              "/workspace/",
            ),
          )
        }
        _ =>
          assert_eq(
            references_peek_test_attribute(row, "title"),
            group.uri_string,
          )
      }
    }
    let single = references_peek_test_model([
      references_peek_test_location("/workspace/src/main.mbt", 2, 1),
    ])
    widget.set_results(single, Some(single.references[0]))
    assert_eq(
      references_peek_test_attribute(tree, "aria-label"),
      "Found 1 result in src/main.mbt",
    )
  }
}
