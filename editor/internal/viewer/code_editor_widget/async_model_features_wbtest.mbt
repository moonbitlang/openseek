///|
fn async_test_model(path : String, text : String) -> @model.TextModel {
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="async-model-features",
      path~,
    ),
    path,
    "moonbit",
    7,
    "shared-host-revision",
    text,
  )
}

///|
fn async_hover_anchor() -> @hover.HoverAnchor {
  HoverRangeAnchor(
    priority=0,
    range=Range(1, 1, 1, 1),
    initial_mouse_pos_x=None,
    initial_mouse_pos_y=None,
  )
}

///|
fn async_hover_mouse_target() -> @editor_browser.MouseTarget {
  MouseTargetContentText(
    element=None,
    mouse_column=1,
    position=Position(1, 1),
    range=Range(1, 1, 1, 1),
    detail={ might_be_foreign_element: false, injected_text: None, },
  )
}

///|
struct ManualHoverTimeout {
  due_ms : Int32
  callback : () -> Unit
  mut active : Bool
}

///|
struct ManualHoverScheduler {
  mut now_ms : Int32
  tasks : Array[ManualHoverTimeout]
}

///|
fn ManualHoverScheduler::ManualHoverScheduler() -> ManualHoverScheduler {
  { now_ms: 0, tasks: [], }
}

///|
fn ManualHoverScheduler::schedule(
  self : ManualHoverScheduler,
  callback : () -> Unit,
  delay_ms : Int32,
) -> @base_common.Disposable {
  let task : ManualHoverTimeout = {
    due_ms: self.now_ms + delay_ms,
    callback,
    active: true,
  }
  self.tasks.push(task)
  @base_common.Disposable::from(() => task.active = false)
}

///|
fn ManualHoverScheduler::next_due_index(
  self : ManualHoverScheduler,
  target_ms : Int32,
) -> Int32? {
  let (result, _) = for
    index, task in self.tasks
    result = (None : Int32?), earliest = target_ms + 1 {
    if task.active && task.due_ms <= target_ms && task.due_ms < earliest {
      continue Some(index), task.due_ms
    }
  } nobreak {
    (result, earliest)
  }
  result
}

///|
fn ManualHoverScheduler::advance_to(
  self : ManualHoverScheduler,
  target_ms : Int32,
) -> Unit {
  match self.next_due_index(target_ms) {
    Some(index) => {
      let task = self.tasks[index]
      self.now_ms = task.due_ms
      task.active = false
      (task.callback)()
      self.advance_to(target_ms)
    }
    None => self.now_ms = target_ms
  }
}

///|
fn ManualHoverScheduler::active_count(self : ManualHoverScheduler) -> Int32 {
  for task in self.tasks; count = 0 {
    if task.active {
      continue count + 1
    }
  } nobreak {
    count
  }
}

///|
fn arm_manual_hover(viewer : CodeEditorWidget) -> Unit {
  let hc = viewer.content_hover_controller().unwrap()
  let (effect, hover) = hc.hover.start_showing_or_update_hover(
    async_hover_anchor(),
    false,
  )
  hc.hover = hover
  viewer.apply_hover_effect(effect)
}

///|
/// Keeps exact state-machine evidence in this integration suite without
/// reopening `HoverOperation`'s private state as production API.
fn assert_hover_operation_state(
  operation : @hover.HoverOperation,
  expected : String,
) -> Unit raise {
  assert_true(Debug::to_repr(operation).to_string().contains(expected))
  // The loading variant contains the non-loading variant's full tag as a
  // prefix, so keep that timing assertion exact through the public query.
  if expected == "HoverOpWaitingForAsync" {
    assert_false(operation.shows_loading_message())
  }
}

///|
/// Isolated concrete language/log backings narrowed into the root capability
/// bundle. The bundle still owns its omitted marker and feedback defaults.
struct AsyncModelFeatureTestServices {
  services : CodeEditorServices
  languages : @languages.Languages
  log_service : @log.LogService
}

///|
fn AsyncModelFeatureTestServices::AsyncModelFeatureTestServices() -> AsyncModelFeatureTestServices {
  let log_service = @log.LogService()
  let languages = @languages.Languages()
  let services = CodeEditorServices(
    languages=languages.language_handle(log_service.log_handle()),
    log_service=log_service.log_handle(),
  )
  { services, languages, log_service, }
}

///|
fn AsyncModelFeatureTestServices::dispose(
  self : AsyncModelFeatureTestServices,
) -> Unit {
  // The concrete backings remain caller-owned and usable after CodeEditorWidget
  // teardown; only the omitted defaults inside the bundle need disposal.
  self.languages
  .language_handle(self.log_service.log_handle())
  .get_language_configuration("moonbit")
  |> ignore
  self.log_service.trace("viewer.async-test", "dispose retained backings")
  self.services.dispose()
}

///|
test "live hover timers follow 150 300 900ms and cancel stale generations" {
  let backings = AsyncModelFeatureTestServices::AsyncModelFeatureTestServices()
  let viewer = CodeEditorWidget(services=backings.services)
  let model = async_test_model("/hover-timers.mbt", "hover")
  let scheduler = ManualHoverScheduler::ManualHoverScheduler()
  viewer.set_hover_host_for_test(
    (callback, delay_ms) => scheduler.schedule(callback, delay_ms),
    _ => (),
  )
  viewer.set_model(Some(model))
  let hc = viewer.content_hover_controller().unwrap()

  // A superseded operation clears both host handles and invalidates all three
  // latest-options debouncers before a new generation is armed.
  arm_manual_hover(viewer)
  assert_hover_operation_state(hc.hover.operation, "HoverOpFirstWait")
  assert_eq(scheduler.active_count(), 2)
  viewer.dismiss_hover()
  assert_eq(scheduler.active_count(), 0)

  arm_manual_hover(viewer)
  assert_hover_operation_state(hc.hover.operation, "HoverOpFirstWait")
  scheduler.advance_to(149)
  assert_hover_operation_state(hc.hover.operation, "HoverOpFirstWait")
  scheduler.advance_to(150)
  assert_hover_operation_state(hc.hover.operation, "HoverOpSecondWait")
  // The async trigger arms the second half relative to logical 150ms.
  scheduler.advance_to(299)
  assert_hover_operation_state(hc.hover.operation, "HoverOpSecondWait")
  scheduler.advance_to(300)
  assert_hover_operation_state(hc.hover.operation, "HoverOpWaitingForAsync")
  scheduler.advance_to(899)
  assert_hover_operation_state(hc.hover.operation, "HoverOpWaitingForAsync")
  scheduler.advance_to(900)
  assert_true(hc.hover.operation.shows_loading_message())
  assert_eq(scheduler.active_count(), 0)

  viewer.dispose()
  backings.dispose()
}

///|
test "content and model invalidation clear a pending mouse-react handle" {
  let backings = AsyncModelFeatureTestServices::AsyncModelFeatureTestServices()
  let viewer = CodeEditorWidget(services=backings.services)
  let first = async_test_model("/hover-react-first.mbt", "hover")
  let replacement = async_test_model("/hover-react-second.mbt", "hover")
  let scheduler = ManualHoverScheduler::ManualHoverScheduler()
  viewer.set_hover_host_for_test(
    (callback, delay_ms) => scheduler.schedule(callback, delay_ms),
    _ => (),
  )
  viewer.set_model(Some(first))
  let hc = viewer.content_hover_controller().unwrap()

  hc.hover = shown_hover_controller()
  viewer.sync_content_hover_widget()
  viewer.on_editor_mouse_move(async_hover_mouse_target())
  assert_true(hc.hover_react_pending)
  assert_eq(scheduler.active_count(), 1)
  viewer.set_value("content changed")
  assert_false(hc.hover_react_pending)
  assert_eq(scheduler.active_count(), 0)

  hc.hover = shown_hover_controller()
  viewer.sync_content_hover_widget()
  viewer.on_editor_mouse_move(async_hover_mouse_target())
  assert_true(hc.hover_react_pending)
  assert_eq(scheduler.active_count(), 1)
  hc.hover_is_mouse_down = true
  hc.hover_mouse_posx = 42.0
  hc.hover_mouse_posy = 24.0
  hc.hover_last_modifiers = EventModifiers(true, true, true)
  viewer.set_model(Some(replacement))
  assert_false(hc.hover_react_pending)
  assert_eq(scheduler.active_count(), 0)
  assert_false(hc.hover_is_mouse_down)
  assert_eq(hc.hover_mouse_posx, 0.0)
  assert_eq(hc.hover_mouse_posy, 0.0)
  let reset_modifiers = Debug::to_repr(hc.hover_last_modifiers).to_string()
  assert_true(reset_modifiers.contains("ctrl: false"))
  assert_true(reset_modifiers.contains("meta: false"))
  assert_true(reset_modifiers.contains("alt: false"))

  viewer.dispose()
  backings.dispose()
}

///|
test "hover widget mouseleave hides when the editor DOM is missing" {
  let backings = AsyncModelFeatureTestServices::AsyncModelFeatureTestServices()
  let viewer = CodeEditorWidget(services=backings.services)
  viewer.set_model(Some(async_test_model("/hover-no-dom.mbt", "hover")))
  let hc = viewer.content_hover_controller().unwrap()
  hc.hover = shown_hover_controller()
  viewer.sync_content_hover_widget()
  assert_true(viewer.content_hover_visible())
  assert_true(viewer.current_code_view() is None)

  viewer.on_content_hover_widget_mouse_leave(0.0, 0.0)

  assert_true(hc.hover.view is None)
  assert_false(viewer.content_hover_visible())
  viewer.dispose()
  backings.dispose()
}

///|
test "programmatic hover forwards immediate mode source focus and mouse state" {
  let backings = AsyncModelFeatureTestServices::AsyncModelFeatureTestServices()
  let viewer = CodeEditorWidget(services=backings.services)
  viewer.set_model(Some(async_test_model("/programmatic-hover.mbt", "hover")))
  viewer.set_hover_host_for_test(
    (_callback, _delay_ms) => @base_common.Disposable::from(() => ()),
    _ => (),
  )
  let hc = viewer.content_hover_controller().unwrap()
  assert_false(hc.hover_is_mouse_down)
  assert_false(hc.hover_ignore_mouse_events)
  assert_true(
    @hover.should_show_hover(
      hc.hover_settings.enabled,
      @hover.hover_multi_cursor_modifier,
      @hover.EventModifiers::none(),
    ),
  )
  assert_true(hc.hover_settings.sticky)
  assert_eq(hc.hover_settings.hiding_delay, 300)
  viewer.start_showing_hover_at_range(
    Range(1, 1, 1, 2),
    HoverStartImmediate,
    HoverStartKeyboard,
    true,
  )
  match hc.hover.operation.options {
    Some(options) => {
      assert_true(options.source is HoverStartKeyboard)
      // `Debug` intentionally remains available for opaque state, so the
      // integration test can verify the private focus bit without reopening
      // it as a field-level API.
      assert_true(
        Debug::to_repr(options).to_string().contains("should_focus: true"),
      )
    }
    None => fail("expected forwarded hover options")
  }
  match hc.hover.anchor {
    Some(anchor) => assert_eq(anchor.priority(), 0)
    None => fail("expected the programmatic hover anchor")
  }
  assert_hover_operation_state(hc.hover.operation, "HoverOpWaitingForAsync")

  viewer.on_editor_mouse_down(0.0, 0.0)
  assert_true(hc.hover_is_mouse_down)
  viewer.on_editor_mouse_up()
  assert_false(hc.hover_is_mouse_down)
  hc.hover_ignore_mouse_events = true
  viewer.on_editor_mouse_down(0.0, 0.0)
  assert_false(hc.hover_is_mouse_down)
  viewer.on_editor_mouse_up()
  assert_false(hc.hover_is_mouse_down)

  viewer.dispose()
  backings.dispose()
}

///|
fn hover_scroll_change(
  left_changed : Bool,
  top_changed : Bool,
) -> @view_layout.ScrollChange {
  let before = @view_layout.ScrollState(
    force_integer_values=false,
    100.0,
    500.0,
    0.0,
    100.0,
    500.0,
    0.0,
  )
  let after = @view_layout.ScrollState(
    force_integer_values=false,
    100.0,
    500.0,
    if left_changed {
      1.0
    } else {
      0.0
    },
    100.0,
    500.0,
    if top_changed {
      1.0
    } else {
      0.0
    },
  )
  after.create_scroll_event(before, false)
}

///|
test "hover scroll handling covers neither top left both and ignored input" {
  let backings = AsyncModelFeatureTestServices::AsyncModelFeatureTestServices()
  let viewer = CodeEditorWidget(services=backings.services)
  viewer.set_model(Some(async_test_model("/hover-scroll.mbt", "hover")))
  let hc = viewer.content_hover_controller().unwrap()

  for
    case in [
      (false, false, false),
      (false, true, true),
      (true, false, true),
      (true, true, true),
    ] {
    let (left_changed, top_changed, should_hide) = case
    hc.hover = shown_hover_controller()
    viewer.on_editor_scroll_changed(
      hover_scroll_change(left_changed, top_changed),
    )
    assert_eq(hc.hover.view is None, should_hide)
  }

  hc.hover = shown_hover_controller()
  hc.hover_ignore_mouse_events = true
  viewer.on_editor_scroll_changed(hover_scroll_change(true, true))
  assert_true(hc.hover.view is Some(_))
  hc.hover_ignore_mouse_events = false

  viewer.dispose()
  backings.dispose()
}

///|
fn shown_hover_controller() -> @hover.HoverController {
  let model = async_test_model("/shown-hover-helper.mbt", "shown")
  defer model.dispose()
  let source = new_hover_cancellation_source()
  defer source.dispose()
  let (_, started) = @hover.HoverController::empty().start_showing_or_update_hover(
    async_hover_anchor(),
    false,
  )
  let token = started.operation.token
  let request = started.request_stamp(model, source.token())
  let (_, after_async_trigger) = started.op_trigger_async_request(
    request,
    Some(model),
    token,
  )
  let after_sync = after_async_trigger.op_trigger_sync_request(
    request,
    Some(model),
    token,
    [
      MarkdownHover(
        range=Range(1, 1, 1, 1),
        contents=[PlainText("shown")],
        ordinal=100,
      ),
    ],
  )
  after_sync.op_async_done_request(request, Some(model), token)
}

///|
test "invisible hover dismissal cancels work idempotently" {
  let backings = AsyncModelFeatureTestServices::AsyncModelFeatureTestServices()
  let viewer = CodeEditorWidget(services=backings.services)
  viewer.set_model(
    Some(async_test_model("/hover-invisible-dismiss.mbt", "hover")),
  )
  let hc = viewer.content_hover_controller().unwrap()
  let (_, pending) = hc.hover.start_showing_or_update_hover(
    async_hover_anchor(),
    false,
  )
  hc.hover = pending
  let request = new_hover_cancellation_source()
  hc.begin_request(request, pending.operation.token)
  let token_before = pending.operation.token
  viewer.hide_content_hover()

  assert_true(request.token().is_cancellation_requested())
  assert_true(hc.hover.operation.token > token_before)
  assert_hover_operation_state(hc.hover.operation, "HoverOpIdle")
  assert_true(hc.hover.view is None)

  // Cancellation remains unconditional even when the controller is already
  // invisible; only its absence of render/DOM input is idempotent.
  let first_clear_token = hc.hover.operation.token
  viewer.hide_content_hover()
  assert_true(hc.hover.operation.token > first_clear_token)

  viewer.dispose()
  backings.dispose()
}

///|
test "visible hover dismissal clears the shown view" {
  let backings = AsyncModelFeatureTestServices::AsyncModelFeatureTestServices()
  let viewer = CodeEditorWidget(services=backings.services)
  viewer.set_model(
    Some(async_test_model("/hover-visible-dismiss.mbt", "hover")),
  )
  let hc = viewer.content_hover_controller().unwrap()
  hc.hover = shown_hover_controller()
  let token_before = hc.hover.operation.token
  viewer.hide_content_hover()

  assert_true(hc.hover.operation.token > token_before)
  assert_true(hc.hover.view is None)

  viewer.dispose()
  backings.dispose()
}

///|
test "content invalidation cancels hover request but preserves shown view" {
  let backings = AsyncModelFeatureTestServices::AsyncModelFeatureTestServices()
  let viewer = CodeEditorWidget(services=backings.services)
  let model = async_test_model("/hover-content.mbt", "content")
  viewer.set_model(Some(model))
  let hc = viewer.content_hover_controller().unwrap()
  hc.hover = shown_hover_controller()
  let before = hc.hover
  let source = new_hover_cancellation_source()
  hc.begin_request(source, before.operation.token)

  viewer.set_value("changed")

  assert_true(source.token().is_cancellation_requested())
  assert_true(hc.hover.operation.token > before.operation.token)
  assert_true(hc.hover.view == before.view)
  assert_true(hc.hover.anchor is None)
  assert_true(hc.hover_decoration_ids.is_empty())
  assert_true(hc.hover_decoration_range is None)
  viewer.dispose()
  backings.dispose()
}

///|
test "content invalidation removes loading visibility and permits same-anchor restart" {
  let backings = AsyncModelFeatureTestServices::AsyncModelFeatureTestServices()
  let viewer = CodeEditorWidget(services=backings.services)
  let model = async_test_model("/hover-loading-content.mbt", "content")
  viewer.set_model(Some(model))
  let hc = viewer.content_hover_controller().unwrap()
  let anchor = async_hover_anchor()
  let (_, armed) = hc.hover.start_showing_or_update_hover(anchor, false)
  let token = armed.operation.token
  let source = new_hover_cancellation_source()
  defer source.dispose()
  let request = armed.request_stamp(model, source.token())
  let (_, second_wait) = armed.op_trigger_async_request(
    request,
    Some(model),
    token,
  )
  let waiting = second_wait.op_trigger_sync_request(
    request,
    Some(model),
    token,
    [],
  )
  hc.hover = waiting.op_trigger_loading_request(request, Some(model), token)
  assert_true(hc.hover.view is None)
  viewer.sync_content_hover_widget()
  assert_true(viewer.content_hover_visible())

  viewer.set_value("changed")

  assert_true(hc.hover.view is None)
  assert_false(viewer.content_hover_visible())
  let (effect, restarted) = hc.hover.start_showing_or_update_hover(
    anchor,
    false,
    live_widget_visible=viewer.content_hover_visible(),
  )
  assert_true(effect is HoverScheduleDelayed(_))
  // Scheduling the same anchor again is the behavioral proof that content
  // invalidation cleared the private current-result anchor.
  assert_true(restarted.anchor == Some(anchor))
  viewer.dispose()
  backings.dispose()
}

///|
test "hover request stamp rejects version identity generation and token drift" {
  let first = async_test_model("/hover-same.mbt", "first")
  let replacement = async_test_model("/hover-same.mbt", "replacement")
  let hover = shown_hover_controller()
  let source = @language.CancellationTokenSource()
  let request = hover.request_stamp(first, source.token())
  assert_true(request.is_current(Some(first), hover.operation.token))
  assert_false(request.is_current(Some(replacement), hover.operation.token))
  assert_false(request.is_current(Some(first), hover.operation.token + 1))
  first.set_value("changed")
  assert_false(request.is_current(Some(first), hover.operation.token))

  let fresh = hover.request_stamp(first, source.token())
  source.cancel()
  assert_false(fresh.is_current(Some(first), hover.operation.token))
}
