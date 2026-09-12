// Headless behavior tests for the agent-feedback glue
// (`agent_feedback_host.mbt`): the DOM-free gates of `_updateHoverGlyph`,
// the reserved-lane store/restore, and the focus gate of
// `_onSelectionChanged`. The widget itself (positioning, keyboard, blur) is
// DOM-bound and covered in the browser suite. Runs over the unattached
// `with_test_viewer` harness; the test model's resource is
// `memory://test-model`.

///|
fn test_model_uri() -> @base_common.Uri {
  try! @base_common.Uri::from(
    scheme="inmemory",
    authority="model",
    path="/test-model",
  )
}

///|
/// Whitebox read of the per-editor input-contribution instance.
fn CodeEditorWidget::test_feedback_input_contribution(
  self : CodeEditorWidget,
) -> @agent_feedback_browser.AgentFeedbackEditorInputContribution {
  self.agent_feedback_input_contribution().unwrap()
}

///|
/// Whitebox read of the per-editor widget-contribution instance.
fn CodeEditorWidget::test_feedback_widget_contribution(
  self : CodeEditorWidget,
) -> @agent_feedback_browser.AgentFeedbackEditorWidgetContribution {
  self.agent_feedback_widget_contribution().unwrap()
}

///|
fn feedback_test_uri(path : String) -> @base_common.Uri {
  try! @base_common.Uri::from(
    scheme="inmemory",
    authority="feedback-model",
    path~,
  )
}

///|
fn feedback_test_model(path : String, text : String) -> @model.TextModel {
  TextModel(
    feedback_test_uri(path),
    "feedback-test-model",
    "plaintext",
    1,
    "",
    text,
  )
}

///|
fn with_feedback_test_viewer(
  text : String,
  body : (CodeEditorWidget, @agent_feedback.AgentFeedbackService) -> Unit raise,
) -> Unit raise {
  let backings = RootTestServiceBackings::RootTestServiceBackings()
  let viewer = CodeEditorWidget::CodeEditorWidget(
    services=backings.services,
    options=CodeEditorOptions(font_size=12, line_height=18),
  )
  viewer.set_model(Some(test_model(text)))
  body(viewer, backings.agent_feedback)
  viewer.dispose()
  backings.dispose()
}

///|
test "feedback lane reserves 18px while enabled and restores the base" {
  with_feedback_test_viewer(
    (
      #|alpha
      #|beta
      #|gamma
    ),
    (viewer, service) => {
      assert_eq(viewer.get_options().line_decorations_width, 10)
      service.set_feedback_enabled(test_model_uri(), true)
      assert_eq(viewer.get_options().line_decorations_width, 28)
      service.set_feedback_enabled(test_model_uri(), false)
      assert_eq(viewer.get_options().line_decorations_width, 10)
    },
  )
}

///|
test "host option updates rebase an active feedback lane" {
  with_feedback_test_viewer("alpha", (viewer, service) => {
    service.set_feedback_enabled(test_model_uri(), true)
    assert_eq(viewer.get_options().line_decorations_width, 28)

    viewer.update_host_options(CodeEditorOptions(line_decorations_width=14))
    assert_eq(viewer.get_options().line_decorations_width, 32)
    assert_eq(
      viewer.test_feedback_input_contribution().lane_base_width,
      Some(14),
    )

    service.set_feedback_enabled(test_model_uri(), false)
    assert_eq(viewer.get_options().line_decorations_width, 14)
  })
}

///|
test "hover glyph follows non-empty lines of an enabled resource" {
  with_feedback_test_viewer("alpha\n   \ngamma", (viewer, service) => {
    // Disabled resource: no glyph.
    viewer.update_agent_feedback_hover_glyph(1)
    assert_eq(viewer.test_feedback_input_contribution().hover_line_number, -1)
    service.set_feedback_enabled(test_model_uri(), true)
    viewer.update_agent_feedback_hover_glyph(1)
    assert_eq(viewer.test_feedback_input_contribution().hover_line_number, 1)
    assert_eq(
      viewer.test_feedback_input_contribution().hover_decoration_ids.length(),
      1,
    )
    // Whitespace-only line: cleared.
    viewer.update_agent_feedback_hover_glyph(2)
    assert_eq(viewer.test_feedback_input_contribution().hover_line_number, -1)
    assert_eq(
      viewer.test_feedback_input_contribution().hover_decoration_ids.length(),
      0,
    )
    // Out-of-range line: stays cleared.
    viewer.update_agent_feedback_hover_glyph(9)
    assert_eq(viewer.test_feedback_input_contribution().hover_line_number, -1)
  })
}

///|
test "lines with unresolved feedback refuse the add glyph" {
  with_feedback_test_viewer(
    (
      #|alpha
      #|beta
      #|gamma
    ),
    (viewer, service) => {
      service.set_feedback_enabled(test_model_uri(), true)
      let handle = service.agent_feedback_handle()
      let item = handle.add_feedback(
        test_model_uri(),
        Range(3, 1, 3, 6),
        "note",
      )
      viewer.update_agent_feedback_hover_glyph(3)
      assert_eq(viewer.test_feedback_input_contribution().hover_line_number, -1)
      // Resolved feedback frees the line again.
      service.set_feedback_items(test_model_uri(), [
        { ..item, state: Resolved, },
      ])
      viewer.update_agent_feedback_hover_glyph(3)
      assert_eq(viewer.test_feedback_input_contribution().hover_line_number, 3)
    },
  )
}

///|
test "feedback landing on the glyph line clears the glyph" {
  with_feedback_test_viewer(
    (
      #|alpha
      #|beta
      #|gamma
    ),
    (viewer, service) => {
      service.set_feedback_enabled(test_model_uri(), true)
      let handle = service.agent_feedback_handle()
      viewer.update_agent_feedback_hover_glyph(2)
      assert_eq(viewer.test_feedback_input_contribution().hover_line_number, 2)
      // The change subscription re-evaluates the glyph gates.
      handle.add_feedback(test_model_uri(), Range(2, 1, 2, 5), "note") |> ignore
      assert_eq(viewer.test_feedback_input_contribution().hover_line_number, -1)
    },
  )
}

///|
test "selection changes without editor focus never open the input" {
  with_feedback_test_viewer(
    (
      #|alpha
      #|beta
      #|gamma
    ),
    (viewer, service) => {
      service.set_feedback_enabled(test_model_uri(), true)
      viewer.set_selection(
        @core.Selection::from_positions(Position(1, 1), Position(1, 6)),
      )
      // The unattached harness has no DOM focus, so `_onSelectionChanged`'s
      // `hasTextFocus` gate holds the input closed (and no widget DOM is
      // ever created headlessly).
      assert_eq(viewer.test_feedback_input_contribution().visible, false)
      assert_true(viewer.test_feedback_input_contribution().widget is None)
    },
  )
}

///|
test "feedback content flush preserves central owners and refreshes model state" {
  let backings = RootTestServiceBackings::RootTestServiceBackings()
  let service = backings.agent_feedback
  let handle = service.agent_feedback_handle()
  let viewer = CodeEditorWidget::CodeEditorWidget(services=backings.services)
  let model = feedback_test_model(
    "/content-flush",
    (
      #|alpha
      #|beta
      #|gamma
    ),
  )
  let resource = model.uri
  service.set_feedback_enabled(resource, true)
  let item = handle.add_feedback(resource, Range(1, 1, 1, 6), "keep the guard")
  let comment = @agent_feedback.get_session_editor_comments([item])[0]
  viewer.set_model(Some(model))
  let input = viewer.test_feedback_input_contribution()
  let widgets = viewer.test_feedback_widget_contribution()
  let input_entry = viewer.contributions.instances["agentFeedback.editorInputContribution"]
  let widget_entry = viewer.contributions.instances["agentFeedback.editorWidgetContribution"]
  viewer.update_agent_feedback_hover_glyph(3)
  viewer.highlight_agent_feedback_range(comment)
  input.visible = true
  input.pinned_range = Some(Range(2, 1, 2, 5))
  input.anchor_position = Some(Position(2, 5))
  input.suppress_selection_change_once = true
  widgets.reply_drafts.set(comment.id, "draft survives rebuild")
  widgets.widget_id_pool = 17
  assert_eq(viewer.get_options().line_decorations_width, 28)
  assert_eq(input.hover_decoration_ids.length(), 1)
  assert_eq(widgets.highlight_decoration_ids.length(), 1)
  assert_eq(input_entry.listeners.length(), 9)
  assert_eq(widget_entry.listeners.length(), 5)

  viewer.set_value(
    (
      #|alpha changed
      #|beta
      #|gamma
    ),
  )

  assert_true(physical_equal(input, viewer.test_feedback_input_contribution()))
  assert_true(
    physical_equal(widgets, viewer.test_feedback_widget_contribution()),
  )
  assert_false(input.visible)
  assert_true(input.pinned_range is None)
  assert_true(input.anchor_position is None)
  assert_false(input.suppress_selection_change_once)
  assert_eq(input.hover_line_number, -1)
  assert_eq(input.hover_decoration_ids.length(), 0)
  assert_eq(widgets.highlight_decoration_ids.length(), 0)
  assert_eq(widgets.reply_drafts[comment.id], "draft survives rebuild")
  assert_eq(widgets.widget_id_pool, 17)
  assert_eq(widgets.widgets.length(), 0)
  assert_eq(input_entry.listeners.length(), 9)
  assert_eq(widget_entry.listeners.length(), 5)
  assert_eq(viewer.get_options().line_decorations_width, 28)

  viewer.dispose()
  model.dispose()
  backings.dispose()
}

///|
test "feedback model swap removal and reattach preserve only CodeEditorWidget-lifetime state" {
  let backings = RootTestServiceBackings::RootTestServiceBackings()
  let service = backings.agent_feedback
  let handle = service.agent_feedback_handle()
  let viewer = CodeEditorWidget::CodeEditorWidget(services=backings.services)
  let first = feedback_test_model(
    "/first",
    (
      #|alpha
      #|beta
      #|gamma
    ),
  )
  let second = feedback_test_model(
    "/second",
    (
      #|one
      #|two
      #|three
    ),
  )
  service.set_feedback_enabled(first.uri, true)
  let item = handle.add_feedback(
    first.uri,
    Range(1, 1, 1, 6),
    "first model note",
  )
  let comment = @agent_feedback.get_session_editor_comments([item])[0]
  viewer.set_model(Some(first))
  let input = viewer.test_feedback_input_contribution()
  let widgets = viewer.test_feedback_widget_contribution()
  viewer.update_agent_feedback_hover_glyph(3)
  viewer.highlight_agent_feedback_range(comment)
  input.visible = true
  input.pinned_range = Some(Range(2, 1, 2, 5))
  input.anchor_position = Some(Position(2, 5))
  input.suppress_selection_change_once = true
  widgets.reply_drafts.set(comment.id, "first model draft")
  widgets.widget_id_pool = 23
  assert_eq(viewer.get_options().line_decorations_width, 28)
  assert_eq(input.hover_decoration_ids.length(), 1)
  assert_eq(widgets.highlight_decoration_ids.length(), 1)

  viewer.set_model(Some(second))

  assert_true(physical_equal(input, viewer.test_feedback_input_contribution()))
  assert_true(
    physical_equal(widgets, viewer.test_feedback_widget_contribution()),
  )
  assert_false(input.visible)
  assert_true(input.pinned_range is None)
  assert_true(input.anchor_position is None)
  assert_false(input.suppress_selection_change_once)
  assert_eq(input.hover_line_number, -1)
  assert_eq(input.hover_decoration_ids.length(), 0)
  assert_eq(widgets.highlight_decoration_ids.length(), 0)
  assert_eq(widgets.widgets.length(), 0)
  // A headless CodeEditorWidget has no DOM View to rebuild. The contribution keeps the
  // reply-draft store and id pool until a later mounted rebuild can apply its
  // normal orphan-pruning policy.
  assert_eq(widgets.reply_drafts[comment.id], "first model draft")
  assert_eq(widgets.widget_id_pool, 23)
  assert_eq(viewer.get_options().line_decorations_width, 10)

  viewer.set_model(None)
  assert_true(physical_equal(input, viewer.test_feedback_input_contribution()))
  assert_true(
    physical_equal(widgets, viewer.test_feedback_widget_contribution()),
  )
  assert_eq(input.hover_decoration_ids.length(), 0)
  assert_eq(widgets.highlight_decoration_ids.length(), 0)
  assert_eq(widgets.widgets.length(), 0)
  assert_eq(widgets.reply_drafts[comment.id], "first model draft")
  assert_eq(widgets.widget_id_pool, 23)

  viewer.set_model(Some(first))
  assert_true(physical_equal(input, viewer.test_feedback_input_contribution()))
  assert_true(
    physical_equal(widgets, viewer.test_feedback_widget_contribution()),
  )
  assert_eq(viewer.get_options().line_decorations_width, 28)
  assert_eq(widgets.reply_drafts[comment.id], "first model draft")
  assert_eq(widgets.widget_id_pool, 23)

  viewer.dispose()
  first.dispose()
  second.dispose()
  backings.dispose()
}

///|
test "feedback disposal drains entries tears down model state and silences services" {
  let backings = RootTestServiceBackings::RootTestServiceBackings()
  let service = backings.agent_feedback
  let handle = service.agent_feedback_handle()
  let viewer = CodeEditorWidget::CodeEditorWidget(services=backings.services)
  let model = feedback_test_model(
    "/dispose",
    (
      #|alpha
      #|beta
      #|gamma
    ),
  )
  let resource = model.uri
  service.set_feedback_enabled(resource, true)
  let item = handle.add_feedback(resource, Range(1, 1, 1, 6), "dispose note")
  let comment = @agent_feedback.get_session_editor_comments([item])[0]
  viewer.set_model(Some(model))
  let input = viewer.test_feedback_input_contribution()
  let widgets = viewer.test_feedback_widget_contribution()
  let input_entry = viewer.contributions.instances["agentFeedback.editorInputContribution"]
  let widget_entry = viewer.contributions.instances["agentFeedback.editorWidgetContribution"]
  viewer.update_agent_feedback_hover_glyph(3)
  viewer.highlight_agent_feedback_range(comment)
  widgets.reply_drafts.set(comment.id, "retained reference draft")
  let mut input_service_deliveries = 0
  let mut widget_service_deliveries = 0
  input_entry.listeners.push(
    handle.on_did_change_feedback(_ => input_service_deliveries += 1),
  )
  widget_entry.listeners.push(
    handle.on_did_change_feedback(_ => widget_service_deliveries += 1),
  )
  assert_eq(input_entry.listeners.length(), 10)
  assert_eq(widget_entry.listeners.length(), 6)
  assert_eq(input.hover_decoration_ids.length(), 1)
  assert_eq(widgets.highlight_decoration_ids.length(), 1)

  viewer.dispose()
  viewer.dispose()

  assert_true(input_entry.lifecycle == ContributionDisposed)
  assert_true(widget_entry.lifecycle == ContributionDisposed)
  assert_eq(input_entry.listeners.length(), 0)
  assert_eq(widget_entry.listeners.length(), 0)
  assert_eq(input.hover_line_number, -1)
  assert_eq(input.hover_decoration_ids.length(), 0)
  assert_eq(widgets.highlight_decoration_ids.length(), 0)
  assert_eq(widgets.widgets.length(), 0)
  assert_true(viewer.agent_feedback_input_contribution() is None)
  assert_true(viewer.agent_feedback_widget_contribution() is None)
  assert_false(
    viewer.contributions.instances.contains(
      "agentFeedback.editorInputContribution",
    ),
  )
  assert_false(
    viewer.contributions.instances.contains(
      "agentFeedback.editorWidgetContribution",
    ),
  )

  service.set_feedback_enabled(resource, false)
  handle.add_feedback(resource, Range(2, 1, 2, 5), "after dispose") |> ignore
  assert_eq(input_service_deliveries, 0)
  assert_eq(widget_service_deliveries, 0)
  assert_eq(input_entry.listeners.length(), 0)
  assert_eq(widget_entry.listeners.length(), 0)
  assert_eq(input.hover_decoration_ids.length(), 0)
  assert_eq(widgets.highlight_decoration_ids.length(), 0)
  assert_eq(widgets.widgets.length(), 0)
  assert_eq(widgets.reply_drafts[comment.id], "retained reference draft")

  model.dispose()
  backings.dispose()
}
