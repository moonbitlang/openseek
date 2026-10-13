///|
/// Phase 2 of `monaco-hover-logic-chain-port.md`: the Monaco `HoverOperation`
/// state machine ported into `HoverController`.
fn markdown_part(start : Int32, end : Int32, text : String) -> HoverPart {
  MarkdownHover(
    range=Range(1, start + 1, 1, end + 1),
    contents=[PlainText(text)],
    ordinal=100,
  )
}

///|
/// Test entry: arm a delayed operation for `[start, end)` as if no hover were
/// shown, the way `on_event` arms one for a fresh anchor (line 1).
fn HoverController::start_delayed(
  self : HoverController,
  start : Int32,
  end : Int32,
) -> (HoverEffect, HoverController) {
  self.start_showing_or_update_hover(
    HoverRangeAnchor(
      priority=0,
      range=Range(1, start + 1, 1, end + 1),
      initial_mouse_pos_x=None,
      initial_mouse_pos_y=None,
    ),
    false,
  )
}

///|
test "immediate start retains source focus and anchor inputs" {
  let anchor = HoverRangeAnchor(
    priority=7,
    range=Range(1, 3, 1, 5),
    initial_mouse_pos_x=None,
    initial_mouse_pos_y=None,
  )
  let (effect, started) = HoverController::empty().start_showing_or_update_hover(
    anchor,
    false,
    mode=HoverStartImmediate,
    source=HoverStartKeyboard,
    should_focus=true,
  )
  assert_true(effect is HoverRunAsyncAndSync(_))
  assert_true(started.anchor == Some(anchor))
  match started.operation.options {
    Some(options) => {
      assert_true(options.source is HoverStartKeyboard)
      assert_true(options.should_focus)
      assert_true(options.anchor == anchor)
    }
    None => fail("expected retained start options")
  }
}

///|
test "delayed start arms the operation and suppresses results before the delay" {
  let controller = HoverController::empty()
  let (effect, armed) = controller.start_delayed(3, 7)
  assert_true(effect is HoverScheduleDelayed(1))
  assert_true(armed.operation.state is HoverOpFirstWait)
  // The same anchor keeps the in-flight operation untouched.
  let (again, unchanged) = armed.start_delayed(3, 7)
  assert_true(again is HoverNoEffect)
  assert_eq(unchanged.operation.token, armed.operation.token)
  // A new anchor rotates the token, invalidating in-flight timers.
  let (rescheduled, moved) = armed.start_delayed(10, 14)
  assert_true(rescheduled is HoverScheduleDelayed(2))
  assert_eq(moved.operation.token, 2)

  // The async trigger advances to SecondWait; emission is still suppressed.
  let (proceed, second_wait) = moved.op_trigger_async(2)
  assert_true(proceed)
  assert_true(second_wait.operation.state is HoverOpSecondWait)
  let async_during_wait = second_wait.op_async_item(2, [
    markdown_part(10, 14, "x"),
  ])
  assert_true(async_during_wait.view is None)
  assert_eq(async_during_wait.operation.parts.length(), 1)
  assert_true(async_during_wait.op_async_item(2, []) == async_during_wait)
  // The async stream finishes while still in SecondWait: emission stays
  // suppressed, but the operation records that async is done.
  let async_finished = async_during_wait.op_async_done(2)
  assert_true(async_finished.view is None)

  // The sync trigger (full delay) emits the accumulated parts: now it is shown.
  let shown = async_finished.op_trigger_sync(2, [])
  assert_true(shown.view is Some(_))
  // Async already finished during SecondWait, so the sync trigger completes
  // straight to Idle (Monaco's `_asyncIterableDone ? Idle : WaitingForAsync`).
  assert_true(shown.is_complete())
}

///|
test "immediate path shows the hover synchronously without the schedulers" {
  // Monaco start(Immediate): invoke the async + sync triggers back to back,
  // skipping the waits. The view is shown right away.
  let (_, armed) = HoverController::empty().start_delayed(3, 7)
  let (proceed, second_wait) = armed.op_trigger_async(1)
  assert_true(proceed)
  let shown = second_wait.op_trigger_sync(1, [markdown_part(3, 7, "immediate")])
  assert_true(shown.view is Some(_))
}

///|
test "stale timers and async results are dropped by the token guard" {
  let (_, armed) = HoverController::empty().start_delayed(3, 7)
  // A newer anchor has rotated the token to 2.
  let (_, moved) = armed.start_delayed(10, 14)
  assert_eq(moved.operation.token, 2)
  // A stale async trigger (token 1) does not advance the operation.
  let (proceed, untouched) = moved.op_trigger_async(1)
  assert_false(proceed)
  assert_true(untouched.operation.state is HoverOpFirstWait)
  // A stale streamed result is ignored.
  let still_empty = moved.op_async_item(1, [markdown_part(10, 14, "stale")])
  assert_eq(still_empty.operation.parts.length(), 0)
}

///|
test "clearing rotates the token and drops the shown hover" {
  let (_, armed) = HoverController::empty().start_delayed(3, 7)
  let (_, second_wait) = armed.op_trigger_async(1)
  let shown = second_wait.op_trigger_sync(1, [markdown_part(3, 7, "fn main")])
  assert_true(shown.view is Some(_))
  let cleared = shown.cleared()
  assert_true(cleared.view is None)
  assert_true(cleared.anchor is None)
  // The token rotated so a late async result for token 1 is dropped.
  assert_eq(cleared.operation.token, shown.operation.token + 1)
  let late = cleared.op_async_item(1, [markdown_part(3, 7, "late")])
  assert_true(late.view is None)
}

///|
fn operation_options(
  start : Int32,
  source~ : HoverStartSource = HoverStartMouse,
) -> HoverOperationOptions {
  HoverOperationOptions(
    HoverRangeAnchor(
      priority=0,
      range=Range(1, start, 1, start),
      initial_mouse_pos_x=None,
      initial_mouse_pos_y=None,
    ),
    should_focus=source is HoverStartKeyboard,
    source~,
    insist_on_keeping_hover_visible=source is HoverStartClick,
  )
}

///|
test "typed operation start covers delayed and every immediate state branch" {
  let options = operation_options(3)
  let idle = HoverOperation::idle_at(7)
  let (delayed_effect, first_wait) = idle.start(HoverStartDelayed, options)
  assert_true(delayed_effect is HoverOperationScheduleDelayed(7))
  assert_true(first_wait.state is HoverOpFirstWait)
  assert_true(first_wait.options == Some(options))

  // Delayed start is Idle-only across every other typed state.
  for
    state in [
      HoverOpFirstWait,
      HoverOpSecondWait,
      HoverOpWaitingForAsync,
      HoverOpWaitingForAsyncShowingLoading,
    ] {
    let operation = { ..first_wait, state, }
    let (delayed_again, delayed_unchanged) = operation.start(
      HoverStartDelayed,
      operation_options(4),
    )
    assert_true(delayed_again is HoverOperationNoStart)
    assert_true(delayed_unchanged == operation)
  }

  // Immediate Idle runs async then sync; SecondWait runs only sync.
  let immediate_options = operation_options(5, source=HoverStartKeyboard)
  let (immediate_idle, idle_with_options) = idle.start(
    HoverStartImmediate,
    immediate_options,
  )
  assert_true(immediate_idle is HoverOperationRunAsyncAndSync(7))
  assert_true(idle_with_options.state is HoverOpSecondWait)
  assert_true(idle_with_options.options == Some(immediate_options))
  let second_wait = { ..first_wait, state: HoverOpSecondWait, }
  let (immediate_second, second_with_options) = second_wait.start(
    HoverStartImmediate,
    immediate_options,
  )
  assert_true(immediate_second is HoverOperationRunSync)
  assert_true(second_with_options.options == Some(immediate_options))

  // FirstWait and both post-sync waiting states are the complete typed no-op
  // matrix for immediate start.
  for
    state in [
      HoverOpFirstWait,
      HoverOpWaitingForAsync,
      HoverOpWaitingForAsyncShowingLoading,
    ] {
    let operation = { ..first_wait, state, }
    let (effect, unchanged) = operation.start(
      HoverStartImmediate,
      immediate_options,
    )
    assert_true(effect is HoverOperationNoStart)
    assert_true(unchanged == operation)
  }
}

///|
test "async item accumulation preserves arrival order around the sync result" {
  let async_a = markdown_part(3, 7, "async-a")
  let async_b = markdown_part(3, 7, "async-b")
  let sync = markdown_part(3, 7, "sync")

  // Two streamed items can arrive before the full-delay sync computation.
  let (_, before_armed) = HoverController::empty().start_delayed(3, 7)
  let before_token = before_armed.operation.token
  let (_, before_async) = before_armed.op_trigger_async(before_token)
  let before_one = before_async.op_async_item(before_token, [async_a])
  let before_two = before_one.op_async_item(before_token, [async_b])
  assert_true(before_two.view is None)
  assert_true(before_two.operation.parts == [async_a, async_b])
  let before_sync = before_two.op_trigger_sync(before_token, [sync])
  assert_true(before_sync.operation.parts == [async_a, async_b, sync])
  match before_sync.view {
    Some(view) => assert_true(view.parts == [async_a, async_b, sync])
    None => fail("expected pre-sync async items to be shown at full delay")
  }

  // When sync wins the race, later async items append after it in their own
  // arrival order. An empty local item is the typed no-data seam and is inert.
  let (_, after_armed) = HoverController::empty().start_delayed(3, 7)
  let after_token = after_armed.operation.token
  let (_, after_async) = after_armed.op_trigger_async(after_token)
  let after_sync = after_async.op_trigger_sync(after_token, [sync])
  assert_true(after_sync.op_async_item(after_token, []) == after_sync)
  let after_one = after_sync.op_async_item(after_token, [async_a])
  let after_two = after_one.op_async_item(after_token, [async_b])
  assert_true(after_two.operation.parts == [sync, async_a, async_b])
  match after_two.view {
    Some(view) => assert_true(view.parts == [sync, async_a, async_b])
    None => fail("expected post-sync async items to update the shown hover")
  }
  let completed = after_two.op_async_done(after_token)
  assert_true(completed.is_complete())
}

///|
test "pure debouncer retains latest options and rejects stale or canceled runs" {
  assert_eq(HoverDebouncer().default_delay_ms, 0)
  let initial = HoverDebouncer(default_delay_ms=25)
  assert_eq(initial.default_delay_ms, 25)
  let first_options = operation_options(3)
  let (first_generation, first) = initial.schedule(first_options)
  assert_eq(first_generation, 1)
  assert_eq(first.delay_ms, 25)
  let second_options = operation_options(5, source=HoverStartClick)
  let (second_generation, second) = first.schedule(second_options, delay_ms=90)
  assert_eq(second_generation, 2)
  assert_eq(second.delay_ms, 90)
  let (stale, still_scheduled) = second.take(first_generation)
  assert_true(stale is None)
  assert_true(still_scheduled.scheduled)
  let (latest, consumed) = still_scheduled.take(second_generation)
  assert_true(latest == Some(second_options))
  assert_false(consumed.scheduled)

  let (third_generation, third) = consumed.schedule(first_options)
  let canceled = third.cancel()
  assert_false(canceled.scheduled)
  assert_true(canceled.options == Some(first_options))
  let (after_cancel, _) = canceled.take(third_generation)
  assert_true(after_cancel is None)
}

///|
fn request_test_model(path : String, text : String) -> @model.TextModel {
  TextModel(
    try! @base_common.Uri::from(scheme="inmemory", authority="request", path~),
    path,
    "moonbit",
    1,
    "same-host-revision",
    text,
  )
}

///|
test "request stamp requires stable model identity, internal version, generation, and live token" {
  let current = request_test_model("/stamp.mbt", "one")
  let same_uri_version = request_test_model("/stamp.mbt", "one")
  let token = @language.CancellationToken()
  let stamp = HoverRequestStamp::HoverRequestStamp(current, 11, token)
  assert_true(stamp.is_current(Some(current), 11))
  assert_false(stamp.is_current(Some(same_uri_version), 11))
  assert_false(stamp.is_current(Some(current), 10))
  assert_false(stamp.is_current(Some(current), 12))
  assert_false(stamp.is_current(None, 11))

  current.set_value("two")
  assert_false(stamp.is_current(Some(current), 11))

  let equal_content = request_test_model("/equal.mbt", "same")
  let equal_stamp = HoverRequestStamp::HoverRequestStamp(
    equal_content, 12, token,
  )
  equal_content.set_value("same")
  assert_false(equal_stamp.is_current(Some(equal_content), 12))

  let disposed_model = request_test_model("/disposed.mbt", "live")
  let disposed_stamp = HoverRequestStamp::HoverRequestStamp(
    disposed_model, 13, token,
  )
  disposed_model.dispose()
  assert_false(disposed_stamp.is_current(Some(disposed_model), 13))

  let live = request_test_model("/cancel.mbt", "one")
  let canceled_token = @language.CancellationToken()
  let canceled = HoverRequestStamp::HoverRequestStamp(live, 12, canceled_token)
  canceled_token.cancel()
  assert_false(canceled.is_current(Some(live), 12))
}

///|
test "request-aware transitions reject cancellation and stale generations" {
  let model = request_test_model("/transition.mbt", "one")
  let (_, armed) = HoverController::empty().start_delayed(3, 7)
  let token = @language.CancellationToken()
  let request = armed.request_stamp(model, token)
  let (proceed, second_wait) = armed.op_trigger_async_request(
    request,
    Some(model),
    1,
  )
  assert_true(proceed)
  let waiting = second_wait.op_trigger_sync_request(request, Some(model), 1, [])
  assert_true(waiting.operation.state is HoverOpWaitingForAsync)

  let stale_generation = waiting.op_async_item_request(
    request,
    Some(model),
    2,
    [markdown_part(3, 7, "stale")],
  )
  assert_eq(stale_generation.operation.parts.length(), 0)
  token.cancel()
  let canceled = waiting.op_async_item_request(request, Some(model), 1, [
    markdown_part(3, 7, "canceled"),
  ])
  assert_eq(canceled.operation.parts.length(), 0)
}

///|
test "canceling pending work preserves a complete shown view and rotates generation" {
  let (_, armed) = HoverController::empty().start_delayed(3, 7)
  let (_, second_wait) = armed.op_trigger_async(1)
  let shown = second_wait
    .op_trigger_sync(1, [markdown_part(3, 7, "visible")])
    .op_async_done(1)
  assert_true(shown.view is Some(_))
  assert_true(shown.current_complete)
  let canceled = shown.cancel_operation_preserving_view()
  assert_true(canceled.view == shown.view)
  assert_true(canceled.current_anchor == shown.current_anchor)
  assert_eq(canceled.current_complete, shown.current_complete)
  assert_true(canceled.anchor is None)
  assert_true(canceled.operation.state is HoverOpIdle)
  assert_eq(canceled.operation.token, shown.operation.token + 1)
  assert_eq(canceled.operation.parts.length(), 0)
  assert_true(canceled.operation.options is None)
  let late = canceled.op_async_item(1, [markdown_part(3, 7, "late")])
  assert_true(late.view == shown.view)
}

///|
test "canceling an incomplete shown view clears it so the same anchor restarts" {
  let anchor : HoverAnchor = HoverRangeAnchor(
    priority=0,
    range=Range(1, 4, 1, 8),
    initial_mouse_pos_x=None,
    initial_mouse_pos_y=None,
  )
  let (_, armed) = HoverController::empty().start_showing_or_update_hover(
    anchor, false,
  )
  let token = armed.operation.token
  let (_, second_wait) = armed.op_trigger_async(token)
  let partial = second_wait.op_trigger_sync(token, [
    markdown_part(3, 7, "partial"),
  ])
  assert_true(partial.view is Some(_))
  assert_false(partial.current_complete)

  let canceled = partial.cancel_operation_preserving_view()
  assert_true(canceled.view is None)
  assert_true(canceled.current_anchor is None)
  assert_true(canceled.anchor is None)
  let (effect, restarted) = canceled.start_showing_or_update_hover(
    anchor, false,
  )
  assert_true(effect is HoverScheduleDelayed(_))
  assert_true(restarted.anchor == Some(anchor))
  assert_eq(restarted.operation.token, canceled.operation.token + 1)
}

///|
test "equal parts at a new anchor still replace current result identity" {
  let first_anchor : HoverAnchor = HoverRangeAnchor(
    priority=0,
    range=Range(1, 3, 1, 3),
    initial_mouse_pos_x=None,
    initial_mouse_pos_y=None,
  )
  let second_anchor : HoverAnchor = HoverRangeAnchor(
    priority=0,
    range=Range(1, 4, 1, 4),
    initial_mouse_pos_x=None,
    initial_mouse_pos_y=None,
  )
  let parts = [markdown_part(2, 6, "same")]
  let first = HoverController::empty().set_current_result(
    parts, true, first_anchor,
  )
  let second = first.set_current_result(parts, true, second_anchor)
  assert_true(second.current_anchor == Some(second_anchor))
  assert_false(second == first)
}

///|
test "equal-key hover parts retain arrival order on every target" {
  let first = markdown_part(2, 6, "first")
  let second = markdown_part(2, 6, "second")
  assert_true(sort_hover_parts_stably([first, second]) == [first, second])
  assert_true(sort_hover_parts_stably([second, first]) == [second, first])

  let anchor : HoverAnchor = HoverRangeAnchor(
    priority=0,
    range=Range(1, 3, 1, 7),
    initial_mouse_pos_x=None,
    initial_mouse_pos_y=None,
  )
  let shown = HoverController::empty().set_current_result(
    [second, first],
    true,
    anchor,
  )
  match shown.view {
    Some(view) => assert_true(view.parts == [second, first])
    None => fail("expected equal-key hover parts to remain visible")
  }
}
