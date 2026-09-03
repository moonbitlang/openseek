// Contribution/command registry checks (deviations-closeout Track D): the
// registered features instantiate per `CodeEditorWidget` through the registry and
// dispose with it; the keybinding table gates on live preconditions.

///|
test "contributions instantiate centrally in the reviewed order and expose every typed variant" {
  let viewer = CodeEditorWidget::CodeEditorWidget(
    contributions=CodeEditorContributionDescriptors::standalone(),
  )
  let expected = [
    "agentFeedback.editorInputContribution",
    "agentFeedback.editorWidgetContribution",
    @folding_browser.FOLDING_CONTROLLER_ID,
    markdown_comment_contribution_id,
    "editor.contrib.contentHover",
    "quickDiff.decorator",
    context_menu_contribution_id,
    definition_contribution_id,
    references_contribution_id,
    code_lens_contribution_id,
  ]
  let actual : Array[String] = []
  for id, entry in viewer.contributions.instances {
    actual.push(id)
    match (id, entry.instance) {
      ("agentFeedback.editorInputContribution", AgentFeedbackInput(_)) => ()
      ("agentFeedback.editorWidgetContribution", AgentFeedbackWidget(_)) => ()
      (@folding_browser.FOLDING_CONTROLLER_ID, Folding(_)) => ()
      ("editor.contrib.markdownComments", MarkdownComments(_)) => ()
      ("editor.contrib.contentHover", ContentHover(_)) => ()
      ("quickDiff.decorator", QuickDiff(_)) => ()
      ("editor.contrib.contextmenu", ContextMenu(_)) => ()
      ("editor.contrib.definition", Definition(_)) => ()
      ("editor.contrib.referencesController", References(_)) => ()
      ("css.editor.codeLens", CodeLens(_)) => ()
      _ => fail("contribution id and concrete variant diverged: \{id}")
    }
  }
  assert_eq(actual, expected)
  for id in expected {
    guard viewer.contributions.lookup(id) is Some(_) else {
      fail("missing known contribution: \{id}")
    }
  }
  assert_true(viewer.contributions.lookup("editor.contrib.unknown") is None)
  assert_true(viewer.agent_feedback_input_contribution() is Some(_))
  assert_true(viewer.agent_feedback_widget_contribution() is Some(_))
  assert_true(viewer.folding_controller() is Some(_))
  assert_true(viewer.markdown_comment_contribution() is Some(_))
  assert_true(viewer.content_hover_controller() is Some(_))
  assert_true(viewer.quick_diff_contribution() is Some(_))
  assert_true(viewer.context_menu_contribution() is Some(_))
  assert_true(viewer.definition_contribution() is Some(_))
  assert_true(viewer.references_contribution() is Some(_))
  assert_true(viewer.code_lens_contribution() is Some(_))
  let mut code_lens_after_first_render = false
  for description in editor_registry().contributions {
    if description.id == code_lens_contribution_id {
      code_lens_after_first_render = description.instantiation
        is AfterFirstRender
    }
  }
  assert_true(code_lens_after_first_render)

  // Every typed accessor validates both its fixed id and the enum variant.
  // Temporarily put a valid but mismatched payload under quick diff's id.
  let quick_diff_entry = viewer.contributions.instances["quickDiff.decorator"]
  let hover = viewer.content_hover_contribution().unwrap()
  viewer.contributions.instances["quickDiff.decorator"] = EditorContributionEntry(
    ContentHover(hover),
  )
  assert_true(viewer.quick_diff_contribution() is None)
  viewer.contributions.instances["quickDiff.decorator"] = quick_diff_entry

  viewer.dispose()
  for id in expected {
    assert_false(viewer.contributions.instances.contains(id))
  }
}

///|
test "diff pane descriptors keep markdown comments and navigation but exclude folding and nested diff" {
  let viewer = CodeEditorWidget::CodeEditorWidget(
    contributions=CodeEditorContributionDescriptors::diff_pane(),
  )
  let expected = [
    "agentFeedback.editorInputContribution", "agentFeedback.editorWidgetContribution",
    markdown_comment_contribution_id, "editor.contrib.contentHover", context_menu_contribution_id,
    definition_contribution_id, references_contribution_id,
  ]
  let actual : Array[String] = []
  for id, _ in viewer.contributions.instances {
    actual.push(id)
  }
  assert_eq(actual, expected)
  assert_true(viewer.agent_feedback_input_contribution() is Some(_))
  assert_true(viewer.agent_feedback_widget_contribution() is Some(_))
  assert_true(viewer.folding_controller() is None)
  assert_true(viewer.content_hover_controller() is Some(_))
  assert_true(viewer.context_menu_contribution() is Some(_))
  assert_true(viewer.definition_contribution() is Some(_))
  assert_true(viewer.references_contribution() is Some(_))
  assert_true(viewer.markdown_comment_contribution() is Some(_))
  assert_true(viewer.quick_diff_contribution() is None)
  assert_true(viewer.code_lens_contribution() is None)

  viewer.dispose()
  viewer.dispose()
  assert_eq(viewer.contributions.instances.length(), 0)
}

///|
test "peek preview descriptors cannot recursively create references markdown or quick diff" {
  let viewer = CodeEditorWidget::CodeEditorWidget(
    contributions=CodeEditorContributionDescriptors::peek_preview(),
  )
  let expected = [
    "editor.contrib.contentHover", context_menu_contribution_id, definition_contribution_id,
  ]
  let actual : Array[String] = []
  for id, _ in viewer.contributions.instances {
    actual.push(id)
  }
  assert_eq(actual, expected)
  assert_true(viewer.content_hover_controller() is Some(_))
  assert_true(viewer.context_menu_contribution() is Some(_))
  assert_true(viewer.definition_contribution() is Some(_))
  assert_true(viewer.references_contribution() is None)
  assert_true(viewer.markdown_comment_contribution() is None)
  assert_true(viewer.quick_diff_contribution() is None)
  assert_true(viewer.folding_controller() is None)
  assert_true(viewer.agent_feedback_input_contribution() is None)
  assert_true(viewer.agent_feedback_widget_contribution() is None)
  assert_true(viewer.code_lens_contribution() is None)
  assert_false(viewer.references_peek_available())

  viewer.dispose()
  viewer.dispose()
  assert_eq(viewer.contributions.instances.length(), 0)
}

///|
test "duplicate contribution ids are first-wins before later side effects" {
  let first_constructed = Ref(0)
  let first_initialized = Ref(0)
  let first_disposed = Ref(0)
  let second_constructed = Ref(0)
  let second_initialized = Ref(0)
  let second_disposed = Ref(0)
  let registry : EditorContributionRegistry = {
    contributions: [],
    commands: Map([]),
    keybindings: [],
  }
  registry.register_editor_contribution(
    "test.duplicate",
    QuickDiff,
    Eager,
    viewer => {
      first_constructed.val += 1
      let state = QuickDiffContributionState(
        viewer.create_decorations_collection(),
      )
      state.listeners.push(
        @base_common.Disposable::from(() => first_disposed.val += 1),
      )
      QuickDiff(state)
    },
    _viewer => {
      first_initialized.val += 1
      []
    },
  )
  registry.register_editor_contribution(
    "test.duplicate",
    QuickDiff,
    Eager,
    viewer => {
      second_constructed.val += 1
      let state = QuickDiffContributionState(
        viewer.create_decorations_collection(),
      )
      state.listeners.push(
        @base_common.Disposable::from(() => second_disposed.val += 1),
      )
      QuickDiff(state)
    },
    _viewer => {
      second_initialized.val += 1
      []
    },
  )
  assert_eq(registry.contributions.length(), 1)
  let viewer = CodeEditorWidget::CodeEditorWidget()
  registry.instantiate_enabled(
    viewer,
    CodeEditorContributionDescriptors::standalone(),
  )
  // Re-initializing through another registry pass is also first-wins against
  // the already-installed CodeEditorWidget row.
  registry.instantiate_enabled(
    viewer,
    CodeEditorContributionDescriptors::standalone(),
  )
  assert_eq(first_constructed.val, 1)
  assert_eq(first_initialized.val, 1)
  assert_eq(second_constructed.val, 0)
  assert_eq(second_initialized.val, 0)
  guard viewer.contributions.instances.get("test.duplicate") is Some(entry) else {
    fail("first duplicate row was not installed")
  }
  entry.dispose(viewer)
  entry.dispose(viewer)
  assert_eq(first_disposed.val, 1)
  assert_eq(second_disposed.val, 0)
  viewer.dispose()
  viewer.dispose()
  assert_eq(first_disposed.val, 1)
  assert_eq(second_disposed.val, 0)
  assert_false(viewer.contributions.instances.contains("test.duplicate"))
}

///|
test "direct entry disposal retires typed lookup without removing the row early" {
  let viewer = CodeEditorWidget::CodeEditorWidget()
  guard viewer.contributions.instances.get("editor.contrib.contentHover")
    is Some(hover) else {
    fail("missing hover contribution entry")
  }
  hover.dispose(viewer)
  assert_true(viewer.content_hover_controller() is None)
  assert_true(
    viewer.contributions.instances.contains("editor.contrib.contentHover"),
  )
  assert_true(
    viewer.contributions.instances["editor.contrib.contentHover"].lifecycle ==
    ContributionDisposed,
  )
  hover.dispose(viewer)
  viewer.dispose()
}

///|
test "viewer disposes all ten real rows once in order while the map stays installed" {
  let viewer = CodeEditorWidget::CodeEditorWidget()
  let expected_ids = [
    "agentFeedback.editorInputContribution",
    "agentFeedback.editorWidgetContribution",
    @folding_browser.FOLDING_CONTROLLER_ID,
    "editor.contrib.markdownComments",
    "editor.contrib.contentHover",
    "quickDiff.decorator",
    context_menu_contribution_id,
    definition_contribution_id,
    references_contribution_id,
    code_lens_contribution_id,
  ]
  let order : Array[String] = []
  let map_stayed_installed = Ref(true)
  let typed_row_stayed_available = Ref(true)
  let wrapper_stayed_live = Ref(true)
  let track = label => {
    @base_common.Disposable::from(() => {
      order.push(label)
      if viewer.contributions.lifecycle != ContributionsLive {
        wrapper_stayed_live.val = false
      }
      if viewer.contributions.instances.length() != expected_ids.length() {
        map_stayed_installed.val = false
      }
      for id in expected_ids {
        if !viewer.contributions.instances.contains(id) {
          map_stayed_installed.val = false
        }
      }
      let available = match label {
        "input" => viewer.agent_feedback_input_contribution() is Some(_)
        "widget" => viewer.agent_feedback_widget_contribution() is Some(_)
        "folding" => viewer.folding_controller() is Some(_)
        "markdown" => viewer.markdown_comment_contribution() is Some(_)
        "hover" => viewer.content_hover_controller() is Some(_)
        "quickDiff" => viewer.quick_diff_contribution() is Some(_)
        "contextMenu" => viewer.context_menu_contribution() is Some(_)
        "definition" => viewer.definition_contribution() is Some(_)
        "references" => viewer.references_contribution() is Some(_)
        "codeLens" => viewer.code_lens_contribution() is Some(_)
        _ => false
      }
      if !available {
        typed_row_stayed_available.val = false
      }
    })
  }
  viewer.contributions.instances["agentFeedback.editorInputContribution"].listeners.push(
    track("input"),
  )
  viewer.contributions.instances["agentFeedback.editorWidgetContribution"].listeners.push(
    track("widget"),
  )
  viewer.contributions.instances[@folding_browser.FOLDING_CONTROLLER_ID].listeners.push(
    track("folding"),
  )
  viewer.markdown_comment_contribution().unwrap().listeners.push(
    track("markdown"),
  )
  viewer.content_hover_controller().unwrap().install_react_timer(track("hover"))
  viewer.quick_diff_contribution().unwrap().listeners.push(track("quickDiff"))
  viewer.contributions.instances[context_menu_contribution_id].listeners.push(
    track("contextMenu"),
  )
  viewer.contributions.instances[definition_contribution_id].listeners.push(
    track("definition"),
  )
  viewer.contributions.instances[references_contribution_id].listeners.push(
    track("references"),
  )
  viewer.contributions.instances[code_lens_contribution_id].listeners.push(
    track("codeLens"),
  )
  viewer.dispose()
  viewer.dispose()
  assert_eq(order, [
    "input", "widget", "folding", "markdown", "hover", "quickDiff", "contextMenu",
    "definition", "references", "codeLens",
  ])
  assert_true(map_stayed_installed.val)
  assert_true(typed_row_stayed_available.val)
  assert_true(wrapper_stayed_live.val)
  assert_true(viewer.contributions.lifecycle == ContributionsDisposed)
  assert_eq(viewer.contributions.instances.length(), 0)
}

///|
test "contribution wrapper retires lookup between behavior and retained-resource phases" {
  let viewer = CodeEditorWidget::CodeEditorWidget()
  let hover_state = viewer.content_hover_contribution().unwrap()
  viewer.contributions.dispose_behavior(viewer)
  assert_true(viewer.contributions.lifecycle == ContributionsDisposing)
  assert_eq(viewer.contributions.instances.length(), 10)
  assert_true(viewer.content_hover_contribution() is None)
  assert_true(
    viewer.contributions.lookup("editor.contrib.contentHover") is None,
  )
  // The retained state is still present in the sole map until the later root
  // hover-resource slot completes.
  guard viewer.contributions.instances.get("editor.contrib.contentHover")
    is Some(entry) else {
    fail("hover entry cleared before retained-resource phase")
  }
  guard entry.instance is ContentHover(stored) else {
    fail("hover entry variant changed during disposal")
  }
  assert_true(physical_equal(hover_state, stored))
  viewer.contributions.dispose_retained_browser_resources()
  assert_true(viewer.contributions.lifecycle == ContributionsDisposed)
  assert_eq(viewer.contributions.instances.length(), 0)
  viewer.dispose()
}

///|
test "two viewers isolate mutable contribution state and disposal owners" {
  let first = CodeEditorWidget::CodeEditorWidget()
  let second = CodeEditorWidget::CodeEditorWidget()
  let first_input = first.agent_feedback_input_contribution().unwrap()
  let second_input = second.agent_feedback_input_contribution().unwrap()
  let first_widgets = first.agent_feedback_widget_contribution().unwrap()
  let second_widgets = second.agent_feedback_widget_contribution().unwrap()
  let first_folding = first.folding_controller().unwrap()
  let second_folding = second.folding_controller().unwrap()
  let first_markdown = first.markdown_comment_contribution().unwrap()
  let second_markdown = second.markdown_comment_contribution().unwrap()
  let first_hover = first.content_hover_controller().unwrap()
  let second_hover = second.content_hover_controller().unwrap()
  let first_quick_diff = first.quick_diff_contribution().unwrap()
  let second_quick_diff = second.quick_diff_contribution().unwrap()
  let first_context_menu = first.context_menu_contribution().unwrap()
  let second_context_menu = second.context_menu_contribution().unwrap()
  let first_definition = first.definition_contribution().unwrap()
  let second_definition = second.definition_contribution().unwrap()
  let first_references = first.references_contribution().unwrap()
  let second_references = second.references_contribution().unwrap()
  let first_code_lens = first.code_lens_contribution().unwrap()
  let second_code_lens = second.code_lens_contribution().unwrap()
  assert_false(physical_equal(first_input, second_input))
  assert_false(physical_equal(first_widgets, second_widgets))
  assert_false(physical_equal(first_folding, second_folding))
  assert_false(physical_equal(first_markdown, second_markdown))
  assert_false(physical_equal(first_hover, second_hover))
  assert_false(physical_equal(first_quick_diff, second_quick_diff))
  assert_false(physical_equal(first_context_menu, second_context_menu))
  assert_false(physical_equal(first_definition, second_definition))
  assert_false(physical_equal(first_references, second_references))
  assert_false(physical_equal(first_code_lens, second_code_lens))

  // Give every concrete controller/state a CodeEditorWidget-specific mutable witness.
  // These values deliberately differ so an accidental shared carrier or
  // cross-CodeEditorWidget lookup is observable before either CodeEditorWidget is disposed.
  first_input.visible = true
  first_input.hover_line_number = 11
  second_input.visible = false
  second_input.hover_line_number = 22
  first_widgets.widget_id_pool = 101
  first_widgets.reply_drafts["first"] = "first draft"
  second_widgets.widget_id_pool = 202
  second_widgets.reply_drafts["second"] = "second draft"
  first_markdown.generation = 101
  second_markdown.generation = 202
  first_hover.hover_keep_open = true
  first_hover.hover_notified_token = 11
  second_hover.hover_ignore_mouse_events = true
  second_hover.hover_notified_token = 22
  first_code_lens.widget_id_pool = 101
  second_code_lens.widget_id_pool = 202

  let first_disposals : Array[String] = []
  let second_disposals : Array[String] = []
  first.contributions.instances["agentFeedback.editorInputContribution"].listeners.push(
    @base_common.Disposable::from(() => first_disposals.push("input")),
  )
  second.contributions.instances["agentFeedback.editorInputContribution"].listeners.push(
    @base_common.Disposable::from(() => second_disposals.push("input")),
  )
  first.contributions.instances["agentFeedback.editorWidgetContribution"].listeners.push(
    @base_common.Disposable::from(() => first_disposals.push("widget")),
  )
  second.contributions.instances["agentFeedback.editorWidgetContribution"].listeners.push(
    @base_common.Disposable::from(() => second_disposals.push("widget")),
  )
  first_folding.local_to_dispose.push(
    @base_common.Disposable::from(() => first_disposals.push("folding")),
  )
  second_folding.local_to_dispose.push(
    @base_common.Disposable::from(() => second_disposals.push("folding")),
  )
  first_markdown.listeners.push(
    @base_common.Disposable::from(() => first_disposals.push("markdown")),
  )
  second_markdown.listeners.push(
    @base_common.Disposable::from(() => second_disposals.push("markdown")),
  )
  first_hover.install_react_timer(
    @base_common.Disposable::from(() => first_disposals.push("hover")),
  )
  second_hover.install_react_timer(
    @base_common.Disposable::from(() => second_disposals.push("hover")),
  )
  first_quick_diff.listeners.push(
    @base_common.Disposable::from(() => first_disposals.push("quickDiff")),
  )
  second_quick_diff.listeners.push(
    @base_common.Disposable::from(() => second_disposals.push("quickDiff")),
  )
  first.contributions.instances[context_menu_contribution_id].listeners.push(
    @base_common.Disposable::from(() => first_disposals.push("contextMenu")),
  )
  second.contributions.instances[context_menu_contribution_id].listeners.push(
    @base_common.Disposable::from(() => second_disposals.push("contextMenu")),
  )
  first.contributions.instances[definition_contribution_id].listeners.push(
    @base_common.Disposable::from(() => first_disposals.push("definition")),
  )
  second.contributions.instances[definition_contribution_id].listeners.push(
    @base_common.Disposable::from(() => second_disposals.push("definition")),
  )
  first.contributions.instances[references_contribution_id].listeners.push(
    @base_common.Disposable::from(() => first_disposals.push("references")),
  )
  second.contributions.instances[references_contribution_id].listeners.push(
    @base_common.Disposable::from(() => second_disposals.push("references")),
  )
  first.contributions.instances[code_lens_contribution_id].listeners.push(
    @base_common.Disposable::from(() => first_disposals.push("codeLens")),
  )
  second.contributions.instances[code_lens_contribution_id].listeners.push(
    @base_common.Disposable::from(() => second_disposals.push("codeLens")),
  )
  let second_folding_listener_count = second_folding.local_to_dispose.length()
  let second_markdown_listener_count = second_markdown.listeners.length()
  let second_quick_diff_listener_count = second_quick_diff.listeners.length()

  assert_eq(first_input.hover_line_number, 11)
  assert_eq(second_input.hover_line_number, 22)
  assert_eq(first_widgets.widget_id_pool, 101)
  assert_eq(second_widgets.widget_id_pool, 202)
  assert_eq(first_widgets.reply_drafts.get("second"), None)
  assert_eq(second_widgets.reply_drafts.get("first"), None)
  assert_eq(first_markdown.generation, 101)
  assert_eq(second_markdown.generation, 202)
  assert_true(first_hover.hover_keep_open)
  assert_false(second_hover.hover_keep_open)
  assert_false(first_hover.hover_ignore_mouse_events)
  assert_true(second_hover.hover_ignore_mouse_events)
  assert_eq(first_code_lens.widget_id_pool, 101)
  assert_eq(second_code_lens.widget_id_pool, 202)

  first.dispose()

  // First's cleanup drains only First-owned stores. Second keeps the exact
  // same typed instances, mutable sentinels, and pending disposal handles.
  assert_eq(first_disposals, [
    "input", "widget", "folding", "markdown", "hover", "quickDiff", "contextMenu",
    "definition", "references", "codeLens",
  ])
  assert_eq(second_disposals, [])
  // Markdown teardown advances only First's stale-callback generation.
  assert_eq(first_markdown.generation, 102)
  assert_true(first.agent_feedback_input_contribution() is None)
  assert_true(first.agent_feedback_widget_contribution() is None)
  assert_true(first.folding_controller() is None)
  assert_true(first.markdown_comment_contribution() is None)
  assert_true(first.content_hover_controller() is None)
  assert_true(first.quick_diff_contribution() is None)
  assert_true(first.context_menu_contribution() is None)
  assert_true(first.definition_contribution() is None)
  assert_true(first.references_contribution() is None)
  assert_true(first.code_lens_contribution() is None)
  assert_true(
    physical_equal(
      second_input,
      second.agent_feedback_input_contribution().unwrap(),
    ),
  )
  assert_true(
    physical_equal(
      second_widgets,
      second.agent_feedback_widget_contribution().unwrap(),
    ),
  )
  assert_true(
    physical_equal(second_folding, second.folding_controller().unwrap()),
  )
  assert_true(
    physical_equal(
      second_markdown,
      second.markdown_comment_contribution().unwrap(),
    ),
  )
  assert_true(
    physical_equal(second_hover, second.content_hover_controller().unwrap()),
  )
  assert_true(
    physical_equal(second_quick_diff, second.quick_diff_contribution().unwrap()),
  )
  assert_true(
    physical_equal(
      second_context_menu,
      second.context_menu_contribution().unwrap(),
    ),
  )
  assert_true(
    physical_equal(second_definition, second.definition_contribution().unwrap()),
  )
  assert_true(
    physical_equal(second_references, second.references_contribution().unwrap()),
  )
  assert_true(
    physical_equal(second_code_lens, second.code_lens_contribution().unwrap()),
  )
  assert_false(second_input.visible)
  assert_eq(second_input.hover_line_number, 22)
  assert_eq(second_widgets.widget_id_pool, 202)
  assert_eq(second_widgets.reply_drafts.get("second"), Some("second draft"))
  assert_eq(
    second_folding.local_to_dispose.length(),
    second_folding_listener_count,
  )
  assert_eq(second_markdown.generation, 202)
  assert_eq(second_markdown.listeners.length(), second_markdown_listener_count)
  assert_eq(second_hover.hover_notified_token, 22)
  assert_eq(
    second_quick_diff.listeners.length(),
    second_quick_diff_listener_count,
  )

  // Mutating Second after First's teardown cannot reach the retained First
  // controller objects either.
  second_input.hover_line_number = 23
  second_widgets.widget_id_pool = 203
  second_widgets.reply_drafts["second"] = "updated second draft"
  second_markdown.generation = 203
  second_hover.hover_notified_token = 23
  second_code_lens.widget_id_pool = 203
  assert_eq(first_input.hover_line_number, 11)
  assert_eq(first_widgets.widget_id_pool, 101)
  assert_eq(first_widgets.reply_drafts.get("first"), Some("first draft"))
  assert_eq(first_markdown.generation, 102)
  assert_eq(first_hover.hover_notified_token, 11)
  assert_eq(first_code_lens.widget_id_pool, 101)

  second.dispose()
  assert_eq(second_disposals, [
    "input", "widget", "folding", "markdown", "hover", "quickDiff", "contextMenu",
    "definition", "references", "codeLens",
  ])
  assert_eq(first_disposals, [
    "input", "widget", "folding", "markdown", "hover", "quickDiff", "contextMenu",
    "definition", "references", "codeLens",
  ])
}

///|
test "model removal and reattach preserve central contribution identities" {
  let viewer = CodeEditorWidget::CodeEditorWidget()
  let input = viewer.agent_feedback_input_contribution().unwrap()
  let widgets = viewer.agent_feedback_widget_contribution().unwrap()
  let folding = viewer.folding_controller().unwrap()
  let markdown = viewer.markdown_comment_contribution().unwrap()
  let hover = viewer.content_hover_controller().unwrap()
  let quick_diff = viewer.quick_diff_contribution().unwrap()
  let context_menu = viewer.context_menu_contribution().unwrap()
  let definition = viewer.definition_contribution().unwrap()
  let references = viewer.references_contribution().unwrap()
  let code_lens = viewer.code_lens_contribution().unwrap()
  let markdown_listener_disposed = Ref(false)
  markdown.listeners.push(
    @base_common.Disposable::from(() => markdown_listener_disposed.val = true),
  )
  let markdown_listener_count = markdown.listeners.length()
  let model = test_model("alpha\nbeta")
  viewer.set_model(Some(model))
  viewer.set_model(Some(model))
  viewer.set_model(None)
  viewer.set_model(Some(model))
  assert_true(
    physical_equal(input, viewer.agent_feedback_input_contribution().unwrap()),
  )
  assert_true(
    physical_equal(
      widgets,
      viewer.agent_feedback_widget_contribution().unwrap(),
    ),
  )
  assert_true(physical_equal(folding, viewer.folding_controller().unwrap()))
  assert_true(
    physical_equal(markdown, viewer.markdown_comment_contribution().unwrap()),
  )
  assert_eq(markdown.listeners.length(), markdown_listener_count)
  assert_false(markdown_listener_disposed.val)
  assert_true(physical_equal(hover, viewer.content_hover_controller().unwrap()))
  assert_true(
    physical_equal(quick_diff, viewer.quick_diff_contribution().unwrap()),
  )
  assert_true(
    physical_equal(context_menu, viewer.context_menu_contribution().unwrap()),
  )
  assert_true(
    physical_equal(definition, viewer.definition_contribution().unwrap()),
  )
  assert_true(
    physical_equal(references, viewer.references_contribution().unwrap()),
  )
  assert_true(
    physical_equal(code_lens, viewer.code_lens_contribution().unwrap()),
  )
  viewer.dispose()
  assert_true(markdown_listener_disposed.val)
  model.dispose()
}

///|
test "keybinding dispatch honors preconditions" {
  let viewer = CodeEditorWidget::CodeEditorWidget()
  // `editor.action.hideHover` is bound to Escape but gated on
  // `hoverVisible`; with no hover the key falls through unhandled.
  assert_false(
    editor_registry().dispatch_keybinding(
      viewer,
      "Escape",
      alt=false,
      ctrl_cmd=false,
      shift=false,
    ),
  )
  // The hover scroll cluster is gated on `hoverFocused`; without a widget
  // the chord resolves to no command.
  assert_false(
    editor_registry().dispatch_keybinding(
      viewer,
      "ArrowUp",
      alt=false,
      ctrl_cmd=false,
      shift=false,
    ),
  )
  viewer.dispose()
}

///|
test "keybinding rules match chords exactly" {
  // `pageUpHover`'s secondary is Alt+ArrowUp; an Alt+CtrlCmd+ArrowUp chord
  // matches no rule (Monaco's resolver would equally find it unbound).
  let registry = editor_registry()
  let mut alt_arrow_rules = 0
  let mut alt_ctrl_arrow_rules = 0
  for rule in registry.keybindings {
    if rule.key == "ArrowUp" && rule.alt && !rule.ctrl_cmd {
      alt_arrow_rules += 1
    }
    if rule.key == "ArrowUp" && rule.alt && rule.ctrl_cmd {
      alt_ctrl_arrow_rules += 1
    }
  }
  assert_eq(alt_arrow_rules, 1)
  assert_eq(alt_ctrl_arrow_rules, 0)
}

///|
test "cursor navigation registers exactly 16 primary rules after contributions" {
  let expected : Map[String, (String, Bool)] = {
    "cursorLeft": ("ArrowLeft", false),
    "cursorLeftSelect": ("ArrowLeft", true),
    "cursorRight": ("ArrowRight", false),
    "cursorRightSelect": ("ArrowRight", true),
    "cursorUp": ("ArrowUp", false),
    "cursorUpSelect": ("ArrowUp", true),
    "cursorPageUp": ("PageUp", false),
    "cursorPageUpSelect": ("PageUp", true),
    "cursorDown": ("ArrowDown", false),
    "cursorDownSelect": ("ArrowDown", true),
    "cursorPageDown": ("PageDown", false),
    "cursorPageDownSelect": ("PageDown", true),
    "cursorHome": ("Home", false),
    "cursorHomeSelect": ("Home", true),
    "cursorEnd": ("End", false),
    "cursorEndSelect": ("End", true),
  }
  let hover_ids : Map[String, Unit] = {
    "editor.action.scrollUpHover": (),
    "editor.action.scrollDownHover": (),
    "editor.action.scrollLeftHover": (),
    "editor.action.scrollRightHover": (),
    "editor.action.pageUpHover": (),
    "editor.action.pageDownHover": (),
    "editor.action.goToTopHover": (),
    "editor.action.goToBottomHover": (),
  }
  let registry = editor_registry()
  let mut cursor_rules = 0
  let mut first_cursor_rule = registry.keybindings.length()
  let mut last_hover_rule = -1
  for i, rule in registry.keybindings {
    match expected.get(rule.command_id) {
      Some((key, shift)) => {
        cursor_rules += 1
        first_cursor_rule = first_cursor_rule.min(i)
        assert_eq(rule.key, key)
        assert_eq(rule.shift, shift)
        assert_false(rule.alt)
        assert_false(rule.ctrl_cmd)
      }
      None => ()
    }
    if hover_ids.contains(rule.command_id) {
      last_hover_rule = i
    }
  }
  assert_eq(cursor_rules, 16)
  assert_true(last_hover_rule >= 0)
  assert_true(first_cursor_rule > last_hover_rule)
}

///|
test "Go to References registers the exact Shift F12 chord" {
  let rules = editor_registry().keybindings.filter(rule => {
    rule.command_id == "editor.action.goToReferences"
  })
  assert_eq(rules.length(), 1)
  assert_eq(rules[0].key, "F12")
  assert_false(rules[0].alt)
  assert_false(rules[0].ctrl_cmd)
  assert_true(rules[0].shift)
}

///|
test "definition context menu suppresses unavailable actions" {
  let services = definition_navigation_services([])
  defer services.dispose()
  let viewer = CodeEditorWidget::CodeEditorWidget(services~)
  defer viewer.dispose()
  let model = definition_navigation_test_model(
    "file:///headless-context-menu.mbt",
  )
  defer model.dispose()
  viewer.set_model(Some(model))

  // A provider makes Go to Definition available, but a headless CodeEditorWidget cannot
  // own Peek UI, so only the available top-level action remains.
  let headless_entries = editor_registry().resolve_editor_menu(
    viewer,
    EditorContext,
  )
  assert_eq(headless_entries.length(), 1)
  guard headless_entries[0]
    is ContextMenuAction(id="editor.action.revealDefinition", ..) else {
    fail("expected only the available Go to Definition action")
  }

  let unavailable = CodeEditorWidget::CodeEditorWidget()
  defer unavailable.dispose()
  let unavailable_model = definition_navigation_test_model(
    "file:///no-provider-context-menu.mbt",
  )
  defer unavailable_model.dispose()
  unavailable.set_model(Some(unavailable_model))
  assert_eq(
    editor_registry().resolve_editor_menu(unavailable, EditorContext).length(),
    0,
  )
}

///|
test "menu resolution orders groups and inserts separators only between visible groups" {
  let registry : EditorContributionRegistry = {
    contributions: [],
    commands: Map([]),
    keybindings: [],
  }
  registry.register_editor_command(
    "test.second",
    _viewer => true,
    _viewer => (),
    [],
    title="Second",
    menu_placements=[
      { menu_id: EditorContext, group: "02_navigation", order: 2.0, },
    ],
  )
  registry.register_editor_command(
    "test.first",
    _viewer => true,
    _viewer => (),
    [],
    title="First",
    menu_placements=[
      { menu_id: EditorContext, group: "01_primary", order: 9.0, },
    ],
  )
  registry.register_editor_command(
    "test.hidden",
    _viewer => false,
    _viewer => (),
    [],
    title="Hidden",
    menu_placements=[
      { menu_id: EditorContext, group: "00_hidden", order: 1.0, },
    ],
  )
  let viewer = CodeEditorWidget::CodeEditorWidget()
  defer viewer.dispose()
  let entries = registry.resolve_editor_menu(viewer, EditorContext)
  assert_eq(entries.length(), 3)
  guard entries[0] is ContextMenuAction(id="test.first", ..) else {
    fail("expected the first nonempty group first")
  }
  assert_true(entries[1] is ContextMenuSeparator)
  guard entries[2] is ContextMenuAction(id="test.second", ..) else {
    fail("expected the second nonempty group after one separator")
  }
}
