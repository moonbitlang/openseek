// Headless end-to-end tests for the quick-diff contribution: service
// original → Line-diff-backed computer → gutter decorations on the model,
// through the registered `quickDiff.decorator` contribution.

///|
/// The gutter decorations the quick-diff contribution currently maintains on
/// the viewer's model, rendered `"<range> <linesDecorationsClassName>"`.
fn quick_diff_gutter_decorations_for_model(
  model : @model.TextModel,
) -> Array[String] {
  let rendered : Array[String] = []
  for decoration in model.get_decorations_in_range(model.get_full_model_range()) {
    match decoration.options.lines_decorations_class_name {
      Some(class_name) =>
        if class_name.contains("dirty-diff") {
          rendered.push("\{decoration.range.to_string()} \{class_name}")
        }
      None => ()
    }
  }
  rendered
}

///|
fn quick_diff_gutter_decorations(viewer : CodeEditorWidget) -> Array[String] {
  guard viewer.get_model() is Some(model) else { return [] }
  quick_diff_gutter_decorations_for_model(model)
}

///|
test "quick diff: stored original decorates the gutter on model attach" {
  let backings = RootTestServiceBackings::RootTestServiceBackings()
  let quick_diff = backings.quick_diff
  let viewer = CodeEditorWidget::CodeEditorWidget(services=backings.services)
  let resource = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/test-model",
  )
  quick_diff.set_original_content(
    resource,
    Some(["a", "old", "b", "tail"].join("\n")),
  )
  // test_model builds its TextModel on the same inmemory://model/test-model
  // resource the service was primed with.
  viewer.set_model(
    Some(
      test_model(
        (
          #|a
          #|new
          #|b
          #|inserted
          #|tail
        ),
      ),
    ),
  )
  assert_eq(
    quick_diff_gutter_decorations(viewer).join("; "),
    "[2,1 -> 2,1] dirty-diff-glyph dirty-diff-modified primary; [4,1 -> 4,1] dirty-diff-glyph dirty-diff-added primary",
  )
  viewer.dispose()
  backings.dispose()
}

///|
test "quick diff: original arriving after attach updates, clearing removes" {
  let backings = RootTestServiceBackings::RootTestServiceBackings()
  let quick_diff = backings.quick_diff
  let viewer = CodeEditorWidget::CodeEditorWidget(services=backings.services)
  let resource = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/test-model",
  )
  viewer.set_model(Some(test_model("a\nb")))
  assert_eq(quick_diff_gutter_decorations(viewer).length(), 0)
  // The service event re-decorates the already-attached model. The
  // decorator requests the MAX_VALUE column and the model validates it down
  // to the end of line 1 ("a" → column 2), as Monaco's deltaDecorations
  // does.
  quick_diff.set_original_content(
    resource,
    Some(
      (
        #|a
        #|x
        #|b
      ),
    ),
  )
  assert_eq(
    quick_diff_gutter_decorations(viewer).join("; "),
    "[1,2 -> 1,2] dirty-diff-glyph dirty-diff-deleted primary",
  )
  // Clearing the original clears the gutter.
  quick_diff.set_original_content(resource, None)
  assert_eq(quick_diff_gutter_decorations(viewer).length(), 0)
  viewer.dispose()
  backings.dispose()
}

///|
test "quick diff: an original for another resource does not decorate" {
  let backings = RootTestServiceBackings::RootTestServiceBackings()
  let quick_diff = backings.quick_diff
  let viewer = CodeEditorWidget::CodeEditorWidget(services=backings.services)
  let other = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/other-model",
  )
  viewer.set_model(Some(test_model("a\nb")))
  quick_diff.set_original_content(
    other,
    Some(
      (
        #|a
        #|x
        #|b
      ),
    ),
  )
  assert_eq(quick_diff_gutter_decorations(viewer).length(), 0)
  viewer.dispose()
  backings.dispose()
}

///|
test "quick diff: identical original decorates nothing" {
  let backings = RootTestServiceBackings::RootTestServiceBackings()
  let quick_diff = backings.quick_diff
  let viewer = CodeEditorWidget::CodeEditorWidget(services=backings.services)
  let resource = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/test-model",
  )
  quick_diff.set_original_content(resource, Some("a\nb"))
  viewer.set_model(Some(test_model("a\nb")))
  assert_eq(quick_diff_gutter_decorations(viewer).length(), 0)
  viewer.dispose()
  backings.dispose()
}

///|
test "quick diff: one central state follows model swap, removal, and reattach" {
  let backings = RootTestServiceBackings::RootTestServiceBackings()
  let quick_diff = backings.quick_diff
  let viewer = CodeEditorWidget::CodeEditorWidget(services=backings.services)
  let state = viewer.quick_diff_contribution().unwrap()
  let resource = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/test-model",
  )
  let first = test_model(
    (
      #|a
      #|first
      #|tail
    ),
  )
  let second = test_model(
    (
      #|a
      #|second
      #|tail
    ),
  )
  quick_diff.set_original_content(
    resource,
    Some(
      (
        #|a
        #|old
        #|tail
      ),
    ),
  )
  viewer.set_model(Some(first))
  assert_true(state.collection.length() > 0)
  assert_true(quick_diff_gutter_decorations_for_model(first).length() > 0)
  viewer.set_model(Some(second))
  assert_true(physical_equal(state, viewer.quick_diff_contribution().unwrap()))
  assert_eq(quick_diff_gutter_decorations_for_model(first).length(), 0)
  assert_true(quick_diff_gutter_decorations_for_model(second).length() > 0)
  viewer.set_model(None)
  assert_eq(state.collection.length(), 0)
  assert_eq(quick_diff_gutter_decorations_for_model(second).length(), 0)
  viewer.set_model(Some(first))
  assert_true(physical_equal(state, viewer.quick_diff_contribution().unwrap()))
  assert_true(quick_diff_gutter_decorations_for_model(first).length() > 0)
  viewer.dispose()
  first.dispose()
  second.dispose()
  backings.dispose()
}

///|
test "quick diff: disposal window is live and later service events are silent" {
  let backings = RootTestServiceBackings::RootTestServiceBackings()
  let quick_diff = backings.quick_diff
  let viewer = CodeEditorWidget::CodeEditorWidget(services=backings.services)
  let state = viewer.quick_diff_contribution().unwrap()
  let resource = try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/test-model",
  )
  let model = test_model(
    (
      #|a
      #|new
      #|tail
    ),
  )
  quick_diff.set_original_content(
    resource,
    Some(
      (
        #|a
        #|old
        #|tail
      ),
    ),
  )
  viewer.set_model(Some(model))
  assert_true(state.collection.length() > 0)
  let mut original_change_deliveries = 0
  state.listeners.push(
    quick_diff
    .quick_diff_handle()
    .on_did_change_original(_ => original_change_deliveries += 1),
  )
  let mut callback_seen = false
  let mut contribution_live_in_callback = false
  viewer.on_did_dispose(() => {
    callback_seen = true
    contribution_live_in_callback = viewer.contributions.lookup(
        "quickDiff.decorator",
      )
      is Some(_)
    // Contribution listeners are intentionally live during `onDidDispose`;
    // with the model already detached this synchronous service emission is a
    // guarded no-op.
    quick_diff.set_original_content(resource, Some("replacement"))
  })
  |> ignore
  viewer.dispose()
  assert_true(callback_seen)
  assert_true(contribution_live_in_callback)
  assert_eq(original_change_deliveries, 1)
  assert_eq(state.collection.length(), 0)
  quick_diff.set_original_content(resource, Some("after dispose"))
  assert_eq(original_change_deliveries, 1)
  assert_eq(state.collection.length(), 0)
  model.dispose()
  backings.dispose()
}
