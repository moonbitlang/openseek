// Ported from `vscode/src/vs/base/test/common/scrollable.test.ts` at
// checked-in source. Test names and six checkpoints
// are kept source-identical.

///|
fn simulate_smooth_scroll(from : Double, to : Double) -> Array[(Int32, Int32)] {
  let viewport_height = 800.0
  let line_height = 20.0
  let operation = @view_layout.SmoothScrollingOperation(
    { scroll_left: 0.0, scroll_top: from, width: 0.0, height: viewport_height, },
    { scroll_left: 0.0, scroll_top: to, width: 0.0, height: viewport_height, },
    -10.0,
    135.0,
  )
  let result : Array[(Int32, Int32)] = []
  for now in [0.0, 25.0, 50.0, 75.0, 100.0, 125.0] {
    let scroll_top = operation.tick_at(now).scroll_top
    result.push(
      (
        (scroll_top / line_height).floor().to_int(),
        ((scroll_top + viewport_height) / line_height).ceil().to_int(),
      ),
    )
  }
  result
}

///|
fn assert_smooth_trace(
  from : Double,
  to : Double,
  expected : Array[(Int32, Int32)],
) -> Unit raise {
  let actual = simulate_smooth_scroll(from, to)
  assert_eq(actual.length(), expected.length())
  for index, value in actual {
    assert_true(value == expected[index])
  }
}

///|
test "smooth scroll 25 lines (40 fit)" {
  assert_smooth_trace(0.0, 500.0, [
    (5, 46),
    (14, 55),
    (20, 61),
    (23, 64),
    (24, 65),
    (25, 65),
  ])
}

///|
test "smooth scroll 75 lines (40 fit)" {
  assert_smooth_trace(0.0, 1500.0, [
    (15, 56),
    (44, 85),
    (62, 103),
    (71, 112),
    (74, 115),
    (75, 115),
  ])
}

///|
test "smooth scroll 100 lines (40 fit)" {
  assert_smooth_trace(0.0, 2000.0, [
    (20, 61),
    (59, 100),
    (82, 123),
    (94, 135),
    (99, 140),
    (100, 140),
  ])
}

///|
test "smooth scroll 125 lines (40 fit)" {
  assert_smooth_trace(0.0, 2500.0, [
    (16, 57),
    (29, 70),
    (107, 148),
    (119, 160),
    (124, 165),
    (125, 165),
  ])
}

///|
test "smooth scroll 500 lines (40 fit)" {
  assert_smooth_trace(0.0, 10000.0, [
    (16, 57),
    (29, 70),
    (482, 523),
    (494, 535),
    (499, 540),
    (500, 540),
  ])
}

///|
struct TestAnimationFrame {
  callback : () -> Unit
  mut active : Bool
}

///|
fn run_test_animation_frame(frame : TestAnimationFrame) -> Unit {
  if frame.active {
    frame.active = false
    (frame.callback)()
  }
}

///|
test "scrollable smooth state tracks future, combines, revalidates and cancels" {
  let clock = [0.0]
  let frames : Array[TestAnimationFrame] = []
  let scheduler = fn(callback) {
    let frame : TestAnimationFrame = { callback, active: true, }
    frames.push(frame)
    @base_common.Disposable::from(() => frame.active = false)
  }
  let scrollable = @view_layout.Scrollable(
    force_integer_values=true,
    smooth_scroll_duration=125.0,
    schedule_at_next_animation_frame=scheduler,
    now=() => clock[0],
  )
  scrollable.set_dimensions({
    width: 100.0,
    scroll_width: 1000.0,
    height: 100.0,
    scroll_height: 1000.0,
  })
  |> ignore
  let changes : Array[@view_layout.ScrollChange] = []
  let listener = scrollable.on_scroll(change => changes.push(change))
  scrollable.set_position_smooth({
    scroll_left: Some(400.0),
    scroll_top: Some(900.0),
  })
  assert_true(scrollable.has_pending_scroll_animation())
  assert_true(
    scrollable.future_position() == { scroll_left: 400.0, scroll_top: 900.0, },
  )
  assert_eq(frames.length(), 1)
  // Same-target is an exact early return: it neither replaces nor schedules.
  scrollable.set_position_smooth({
    scroll_left: Some(400.0),
    scroll_top: Some(900.0),
  })
  assert_eq(frames.length(), 1)
  assert_true(frames[0].active)
  // A second axis-partial request combines with the outstanding target and
  // disposes the first scheduled frame.
  scrollable.set_position_smooth({ scroll_left: None, scroll_top: Some(700.0), })
  assert_true(
    scrollable.future_position() == { scroll_left: 400.0, scroll_top: 700.0, },
  )
  assert_false(frames[0].active)
  assert_true(frames[1].active)
  // Dimension changes clamp and rebuild the outstanding target curves.
  scrollable.set_scroll_dimensions(
    {
      width: None,
      scroll_width: Some(300.0),
      height: None,
      scroll_height: Some(400.0),
    },
    true,
  )
  |> ignore
  assert_true(
    scrollable.future_position() == { scroll_left: 200.0, scroll_top: 300.0, },
  )
  clock[0] = 25.0
  run_test_animation_frame(frames[1])
  assert_true(changes.last().unwrap().in_smooth_scrolling)
  assert_true(scrollable.position().scroll_top > 0.0)
  let scheduled_after_tick = frames.last().unwrap()
  scrollable.set_position_now({ scroll_left: None, scroll_top: Some(20.0), })
  |> ignore
  assert_false(scrollable.has_pending_scroll_animation())
  assert_false(scheduled_after_tick.active)
  assert_false(changes.last().unwrap().in_smooth_scrolling)
  run_test_animation_frame(scheduled_after_tick)
  assert_eq(scrollable.position().scroll_top, 20.0)
  listener.dispose()
  scrollable.dispose()
}

///|
test "reuse animation replaces the target on the original timeline" {
  let clock = [0.0]
  let frames : Array[TestAnimationFrame] = []
  let scheduler = fn(callback) {
    let frame : TestAnimationFrame = { callback, active: true, }
    frames.push(frame)
    @base_common.Disposable::from(() => frame.active = false)
  }
  let scrollable = @view_layout.Scrollable(
    force_integer_values=true,
    smooth_scroll_duration=125.0,
    schedule_at_next_animation_frame=scheduler,
    now=() => clock[0],
  )
  scrollable.set_dimensions({
    width: 100.0,
    scroll_width: 100.0,
    height: 1000.0,
    scroll_height: 2000.0,
  })
  |> ignore
  scrollable.set_position_smooth({ scroll_left: None, scroll_top: Some(500.0), })
  clock[0] = 30.0
  scrollable.set_position_smooth(
    { scroll_left: None, scroll_top: Some(600.0), },
    reuse_animation=true,
  )
  assert_false(frames[0].active)
  assert_true(frames[1].active)
  assert_eq(scrollable.future_position().scroll_top, 600.0)
  clock[0] = 40.0
  run_test_animation_frame(frames[1])
  // Reuse keeps the original -10/135 timeline: completion is 50/135 here.
  let inverse = 1.0 - 50.0 / 135.0
  let expected = (600.0 * (1.0 - inverse * inverse * inverse))
    .to_int()
    .to_double()
  assert_true((scrollable.position().scroll_top - expected).abs() < 0.000001)
  scrollable.dispose()
}

///|
test "scroll event listener cancellation stops animation rescheduling" {
  let clock = [0.0]
  let frames : Array[TestAnimationFrame] = []
  let scheduler = fn(callback) {
    let frame : TestAnimationFrame = { callback, active: true, }
    frames.push(frame)
    @base_common.Disposable::from(() => frame.active = false)
  }
  let scrollable = @view_layout.Scrollable(
    force_integer_values=true,
    smooth_scroll_duration=125.0,
    schedule_at_next_animation_frame=scheduler,
    now=() => clock[0],
  )
  scrollable.set_dimensions({
    width: 100.0,
    scroll_width: 100.0,
    height: 100.0,
    scroll_height: 1000.0,
  })
  |> ignore
  let listener = scrollable.on_scroll(change => {
    if change.in_smooth_scrolling {
      scrollable.set_position_now({ scroll_left: None, scroll_top: Some(10.0), })
      |> ignore
    }
  })
  scrollable.set_position_smooth({ scroll_left: None, scroll_top: Some(500.0), })
  clock[0] = 25.0
  run_test_animation_frame(frames[0])
  assert_false(scrollable.has_pending_scroll_animation())
  assert_eq(frames.length(), 1)
  assert_eq(scrollable.position().scroll_top, 10.0)
  listener.dispose()
  scrollable.dispose()
}

///|
test "smooth duration zero falls back to immediate without scheduling" {
  let scheduled = Ref(0)
  let scrollable = @view_layout.Scrollable(
    force_integer_values=true,
    smooth_scroll_duration=0.0,
    schedule_at_next_animation_frame=callback => {
      let _ = callback
      scheduled.val += 1
      @base_common.Disposable::from(() => ())
    },
  )
  scrollable.set_dimensions({
    width: 100.0,
    scroll_width: 100.0,
    height: 100.0,
    scroll_height: 1000.0,
  })
  |> ignore
  scrollable.set_position_smooth({ scroll_left: None, scroll_top: Some(500.0), })
  assert_eq(scrollable.position().scroll_top, 500.0)
  assert_eq(scheduled.val, 0)
  assert_false(scrollable.has_pending_scroll_animation())
  scrollable.dispose()
}

///|
test "view layout smooth option reconfigures the 125ms duration live" {
  let frames : Array[TestAnimationFrame] = []
  let scheduler = fn(callback) {
    let frame : TestAnimationFrame = { callback, active: true, }
    frames.push(frame)
    @base_common.Disposable::from(() => frame.active = false)
  }
  let layout = @view_layout.ViewLayout(
    line_height=20,
    line_count=100,
    smooth_scrolling=false,
    schedule_at_next_animation_frame=scheduler,
    now=() => 0.0,
  )
  layout.set_viewport_size(width=100.0, height=100.0) |> ignore
  layout.scroll_to_smooth(scroll_top=100.0)
  assert_eq(layout.position().scroll_top, 100.0)
  assert_eq(frames.length(), 0)
  layout.set_smooth_scrolling(true)
  layout.scroll_to_smooth(scroll_top=200.0)
  assert_true(layout.has_pending_scroll_animation())
  assert_eq(layout.future_position().scroll_top, 200.0)
  assert_eq(frames.length(), 1)
  layout.dispose()
  assert_false(frames[0].active)
}
