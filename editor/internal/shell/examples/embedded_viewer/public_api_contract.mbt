// Compile-only contract for the independent Viewer, MarkdownViewer, and
// DiffEditor facades. The imports and inferred browser-owned values below keep
// the public embedding boundary checked by the real MoonBit package.

///|
fn contract_disposable() -> @base_common.Disposable {
  @base_common.Disposable::from(() => ())
}

///|
fn contract_feedback_handle() -> @agent_feedback_api.AgentFeedbackHandle {
  AgentFeedbackHandle(
    on_did_change_feedback=_ => contract_disposable(),
    on_did_change_navigation=_ => contract_disposable(),
    is_feedback_enabled=_ => false,
    get_feedback=_ => [],
    get_navigation_bearing=(_, item_ids) => {
      active_idx: -1,
      total_count: item_ids.length(),
    },
    add_feedback=(resource, range, text, kind, state, selected_text) => {
      id: "external-contract-feedback",
      text,
      resource,
      range,
      selected_text,
      kind: kind.unwrap_or(UserReview),
      replies: [],
      state: state.unwrap_or(Created),
    },
    mark_feedback_submitted=_ => (),
    remove_feedback=(_, _) => (),
    accept_feedback=(_, _) => (),
    set_navigation_anchor=(_, _) => (),
    update_feedback=(_, _, _) => (),
    add_reply=(_, _, _) => (),
  )
}

///|
fn contract_quick_diff_handle() -> @quick_diff_api.QuickDiffHandle {
  QuickDiffHandle(get_original_content=_ => None, on_did_change_original=_ => {
    contract_disposable()
  })
}

///|
fn require_contract_element(_element : @rdom.Element) -> Unit {
  ()
}

///|
fn require_contract_optional_element(_element : @rdom.Element?) -> Unit {
  ()
}

///|
fn require_contract_cursor_position_event(
  _event : @editor_api.CursorPositionChangedEvent,
) -> Unit {
  ()
}

///|
fn require_contract_cursor_selection_event(
  _event : @editor_api.CursorSelectionChangedEvent,
) -> Unit {
  ()
}

///|
fn require_contract_model_event(_event : @editor_api.ModelChangedEvent) -> Unit {
  ()
}

///|
fn require_contract_scroll_event(_event : @editor_api.ScrollEvent) -> Unit {
  ()
}

///|
fn require_contract_scrolled_position(
  _position : @editor_api.ScrolledVisiblePosition?,
) -> Unit {
  ()
}

///|
/// This function is referenced but never called by `main`. Moon still checks
/// every external-facing signature while the example keeps its normal runtime
/// behavior and generated executable interface.
fn compile_external_viewer_api_contract(
  host : @rdom.Element,
  model : @model.TextModel,
) -> Unit {
  let log_service = @log.LogService()
  let languages = @languages.Languages()
  let markers = @markers.MarkerService()
  let marker_decorations = @markers.MarkerDecorationsService(
    markers.marker_service_handle(),
  )
  let services = @viewer.ViewerServices(
    languages=languages.language_handle(log_service.log_handle()),
    markers=Decorations(marker_decorations.marker_decorations_handle()),
    agent_feedback=contract_feedback_handle(),
    quick_diff=contract_quick_diff_handle(),
    log_service=log_service.log_handle(),
  )
  let options = @viewer.ViewerOptions::default()
    .with_placeholder("Loading external model...")
    .with_theme("light")
    .with_render_whitespace(All)
    .with_render_control_characters(false)
    .with_render_line_highlight(Gutter)
    .with_render_line_highlight_only_when_focus(true)
    .with_render_validation_decorations(Off)
    .with_tab_size(4)
    .with_soft_wrap(true)
    .with_line_numbers_min_chars(3)
    .with_line_decorations_width(12)
    .with_line_height(22.0)
  options.soft_wrap() |> ignore
  options.line_height() |> ignore
  let viewer = @viewer.Viewer::create(host, services~, options~)
  require_contract_element(viewer.get_container_dom_node())
  require_contract_optional_element(viewer.get_dom_node())
  let cursor_position_subscription = viewer.on_did_change_cursor_position(
    require_contract_cursor_position_event,
  )
  let cursor_selection_subscription = viewer.on_did_change_cursor_selection(
    require_contract_cursor_selection_event,
  )
  let model_subscription = viewer.on_did_change_model(
    require_contract_model_event,
  )
  let scroll_subscription = viewer.on_did_scroll_change(
    require_contract_scroll_event,
  )
  viewer.set_model(Some(model))
  viewer.handle_initialized()
  viewer.get_scrolled_visible_position({ line_number: 1, column: 1, })
  |> require_contract_scrolled_position

  // Browser-owned types remain inferred: this external host imports neither
  // viewer/browser nor any implementation/testing/contribution package.
  let overlay_node = @rdom.document().create_element("div")
  let overlay = @viewer.overlay_widget(
    "external-contract-overlay", overlay_node,
  )
  viewer.add_overlay_widget(overlay)
  let zone_node = @rdom.document().create_element("div")
  viewer.change_view_zones(accessor => {
    let id = accessor.add_zone(
      @viewer.view_zone(
        1,
        zone_node,
        height_in_px=18.0,
        suppress_mouse_down=true,
      ),
    )
    accessor.layout_zone(id)
    accessor.remove_zone(id)
  })
  viewer.remove_overlay_widget(overlay)
  viewer.set_model(None)
  cursor_position_subscription.dispose()
  cursor_selection_subscription.dispose()
  model_subscription.dispose()
  scroll_subscription.dispose()
  viewer.dispose()
  require_contract_element(viewer.get_container_dom_node())
  require_contract_optional_element(viewer.get_dom_node())

  // Rich Markdown is a separate explicit surface, never a Viewer presentation
  // union. The model carries its resource semantics at the host boundary.
  let markdown_host = @rdom.document().create_element("div")
  let markdown_options = @viewer.MarkdownViewerOptions::default()
    .with_placeholder("Loading external Markdown model...")
    .with_theme("light")
    .with_show_unused(false)
  let markdown_viewer = @viewer.MarkdownViewer::create(
    markdown_host,
    services~,
    options=markdown_options,
  )
  let markdown_model = @viewer.MarkdownViewerModel(model, MoonBitMarkdown)
  let markdown_model_subscription = markdown_viewer.on_did_change_model(
    require_contract_model_event,
  )
  let markdown_content_subscription = markdown_viewer.on_did_change_model_content(_ => {
      ()
    },
  )
  let markdown_scroll_subscription = markdown_viewer.on_did_scroll_change(() => {
    ()
  })
  let markdown_dispose_subscription = markdown_viewer.on_did_dispose(() => ())
  markdown_viewer.set_model(Some(markdown_model)) |> ignore
  // Exact same model + resource kind is a no-op and must not retire the active
  // caller-owned model.
  markdown_viewer.set_model(Some(markdown_model)) |> ignore
  markdown_viewer.get_model() |> ignore
  markdown_viewer.get_options() |> ignore
  markdown_viewer.update_options(markdown_options)
  let markdown_view_state = markdown_viewer.save_view_state()
  markdown_viewer.restore_view_state(markdown_view_state)
  markdown_viewer.reveal_range_in_center(Range(1, 1, 1, 1))
  markdown_viewer.toggle_section_at(0) |> ignore
  markdown_viewer.collapsed_sections() |> ignore
  markdown_viewer.get_id() |> ignore
  markdown_viewer.get_content_height() |> ignore
  markdown_viewer.get_content_width() |> ignore
  require_contract_element(markdown_viewer.get_container_dom_node())
  require_contract_optional_element(markdown_viewer.get_dom_node())
  markdown_viewer.handle_initialized()
  markdown_viewer.layout()
  markdown_viewer.focus()
  markdown_viewer.has_text_focus() |> ignore
  markdown_viewer.set_model(None) |> ignore
  markdown_model_subscription.dispose()
  markdown_content_subscription.dispose()
  markdown_scroll_subscription.dispose()
  markdown_dispose_subscription.dispose()
  markdown_viewer.dispose()

  // DiffEditor owns two internal code-editor kernels and one shared diff
  // ViewModel. Algorithm selection remains a host/provider concern.
  let diff_host = @rdom.document().create_element("div")
  let diff_options = @viewer.DiffEditorOptions(
    editor_options=options,
    layout=SideBySide,
  )
  let diff_editor = @viewer.DiffEditor::create(
    diff_host,
    services~,
    options=diff_options,
  )
  let diff_subscription = diff_editor.on_did_update_diff(() => ())
  let diff_content_height_subscription = diff_editor.on_did_change_content_height(_height => {
      ()
    },
  )
  let diff_model = @viewer.DiffEditorModel(model, model)
  diff_editor.set_model(Some(diff_model)) |> ignore
  diff_editor.reveal_first_diff()
  // Exact same pair returns None; callers therefore never dispose active
  // models while handling a no-op replacement.
  diff_editor.set_model(Some(diff_model)) |> ignore
  diff_editor.get_model() |> ignore
  diff_editor.get_diff() |> ignore
  diff_editor.is_diff_up_to_date() |> ignore
  diff_editor.get_layout() |> ignore
  diff_editor.reveal_next_change() |> ignore
  diff_editor.reveal_previous_change() |> ignore
  diff_editor.update_options(diff_options.with_layout(Inline))
  diff_editor.focus()
  diff_editor.layout()
  // A real clear returns the already-detached pair to its caller. This
  // compile-only contract intentionally leaves the borrowed model alive.
  diff_editor.set_model(None) |> ignore
  diff_subscription.dispose()
  diff_content_height_subscription.dispose()
  diff_editor.dispose()

  // Explicit bundles and concrete backings remain caller-owned.
  services.dispose()
  marker_decorations.dispose()
  markers.dispose()
  log_service.flush()
}
