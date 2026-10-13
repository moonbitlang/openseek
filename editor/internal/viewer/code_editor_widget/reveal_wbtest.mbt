// Phase 2 behavior tests for the `CodeEditorWidget::reveal*` surface, on the headless
// `with_test_viewer` harness (no DOM): an unattached viewer owns a full model +
// ViewModel but no `CodeBrowserData`, so reveals drive model→view conversion
// and vertical scroll math without retaining browser-only requests. Pure
// request construction/cancellation is pinned here; real arm/flush behavior
// lives in the browser suite (Phase 3).

///|
fn reveal_test_scroll_change(
  scroll_top : Double,
  top_changed : Bool,
  left_changed~ : Bool = false,
) -> @view_layout.ScrollChange {
  {
    position: { scroll_left: 0.0, scroll_top, },
    delta_left: 0.0,
    delta_top: 0.0,
    left_changed,
    top_changed,
    dimensions_changed: false,
    in_smooth_scrolling: false,
    old_width: 0.0,
    old_scroll_width: 0.0,
    old_scroll_left: 0.0,
    width: 0.0,
    scroll_width: 0.0,
    scroll_left: 0.0,
    old_height: 0.0,
    old_scroll_height: 0.0,
    old_scroll_top: scroll_top,
    height: 0.0,
    scroll_height: 0.0,
    scroll_top,
    width_changed: false,
    scroll_width_changed: false,
    scroll_left_changed: false,
    height_changed: false,
    scroll_height_changed: false,
    scroll_top_changed: top_changed,
  }
}

///|
/// `reveal_line` scrolls a line below the viewport into view, keeping the +1
/// bottom pad clear of the horizontal scrollbar (Monaco's `Simple`).
test "reveal_line brings a line below the viewport into view" {
  with_test_viewer(long_document(200), viewer => {
    viewer.test_set_viewport(width=800.0, height=180.0)
    viewer.reveal_line(50)
    // box_start=(50-1)*18=882, box_end=882+18+18=918; viewport 0..180; the box
    // sits below, so scroll to box_end-180=738.
    assert_eq(viewer.test_view_model().view_layout.position().scroll_top, 738.0)
  })
}

///|
/// Revealing a line already inside the viewport is a no-op.
test "reveal_line leaves an already-visible line untouched" {
  with_test_viewer(long_document(200), viewer => {
    viewer.test_set_viewport(width=800.0, height=180.0)
    viewer.reveal_line(5)
    assert_eq(viewer.test_view_model().view_layout.position().scroll_top, 0.0)
  })
}

///|
/// `reveal_line_in_center` centers the line in the viewport (Monaco's `Center`).
test "reveal_line_in_center centers the target line" {
  with_test_viewer(long_document(200), viewer => {
    viewer.test_set_viewport(width=800.0, height=180.0)
    viewer.reveal_line_in_center(50)
    // box_middle=((49*18)+(49*18+18))/2=891, minus half the viewport (90) = 801.
    assert_eq(viewer.test_view_model().view_layout.position().scroll_top, 801.0)
  })
}

///|
/// A multi-line `reveal_range` resets `scroll_left` to 0 (Monaco's "two or more
/// lines → scroll to base") while still moving vertically to the range.
test "reveal_range over multiple lines resets horizontal scroll" {
  with_test_viewer(long_document(200), viewer => {
    viewer.test_set_viewport(width=800.0, height=180.0)
    viewer.test_view_model().view_layout.set_content_width(2000.0) |> ignore
    viewer.set_scroll_position(scroll_top=0.0, scroll_left=500.0)
    assert_eq(
      viewer.test_view_model().view_layout.position().scroll_left,
      500.0,
    )
    let range = @base_common.Range(50, 1, 52, 1)
    viewer.reveal_range(range)
    let position = viewer.test_view_model().view_layout.position()
    // Vertical: box_start=49*18=882, box_end=51*18+18+18=954; below viewport →
    // scroll to 954-180=774.
    assert_eq(position.scroll_top, 774.0)
    // Horizontal: multi-line range collapses scroll_left to 0.
    assert_eq(position.scroll_left, 0.0)
  })
}

///|
/// A single-line `reveal_range` cannot measure horizontal geometry headlessly,
/// so it changes only the semantic vertical layout and retains no browser data.
test "headless single-line reveal retains no browser request" {
  with_test_viewer(long_document(200), viewer => {
    viewer.test_set_viewport(width=800.0, height=180.0)
    viewer.test_view_model().view_layout.set_content_width(2000.0) |> ignore
    viewer.set_scroll_position(scroll_top=0.0, scroll_left=500.0)
    let range = @base_common.Range(50, 3, 50, 8)
    viewer.reveal_range(range)
    guard viewer.model_slot.current is Some(model_data) else {
      fail("headless model data missing")
    }
    assert_true(model_data.browser is None)
    // No synchronous horizontal movement.
    assert_eq(
      viewer.test_view_model().view_layout.position().scroll_left,
      500.0,
    )
  })
}

///|
test "source-shaped revealRange forwards source and pure request facts" {
  with_test_viewer(long_document(200), viewer => {
    viewer.test_set_viewport(width=800.0, height=180.0)
    viewer.test_view_model().view_layout.set_content_width(2000.0) |> ignore
    viewer.send_reveal_range(
      Range(50, 3, 50, 8),
      Simple,
      reveal_horizontal=true,
      source="mouse",
      minimal_reveal=true,
      scroll_type=Immediate,
    )
    // Minimal omits the ordinary Simple bottom line: 900 - 180 = 720.
    assert_eq(viewer.test_view_model().view_layout.position().scroll_top, 720.0)
    guard horizontal_reveal_request_for_range(
        Range(50, 3, 50, 8),
        true,
        0.0,
        720.0,
        Immediate,
      )
      is Some(request) else {
      fail("expected a single-line horizontal reveal request")
    }
    assert_true(request.minimal_reveal)
    assert_true(request.scroll_type == Immediate)
  })
}

///|
test "vertical reveal resets an in-flight horizontal animation target" {
  let layout = @view_layout.ViewLayout(
    line_height=18,
    line_count=200,
    smooth_scrolling=true,
    schedule_at_next_animation_frame=_ => {
      @base_common.Disposable::from(() => ())
    },
    now=() => 0.0,
  )
  layout.set_viewport_size(width=800.0, height=180.0) |> ignore
  layout.set_content_width(2000.0) |> ignore
  layout.scroll_to_smooth(scroll_top=0.0, scroll_left=500.0)
  assert_eq(layout.position().scroll_left, 0.0)
  assert_eq(layout.future_position().scroll_left, 500.0)
  let target = layout.validate_scroll_position({
    scroll_left: None,
    scroll_top: Some(738.0),
  })
  apply_cursor_reveal_scroll_position(layout, target, true)
  assert_eq(layout.future_position().scroll_left, 0.0)
  layout.dispose()
}

///|
/// A vertical scroll that stays inside the reveal's `[start, stop]` band keeps
/// the deferred request; one that leaves the band cancels it (Monaco's
/// `onScrollChanged`).
test "vertical scroll inside the band keeps, outside cancels, the deferral" {
  let request : HorizontalRevealRangeRequest = {
    minimal_reveal: false,
    view_line_number: 50,
    start_column: 3,
    end_column: 8,
    start_scroll_top: 0.0,
    stop_scroll_top: 738.0,
    scroll_type: Immediate,
  }
  assert_false(
    request.should_cancel_on_scroll(reveal_test_scroll_change(100.0, true)),
  )
  assert_true(
    request.should_cancel_on_scroll(reveal_test_scroll_change(2000.0, true)),
  )
}

///|
test "horizontal reveal cancellation gates top changes and keeps reversed-band endpoints" {
  let request : HorizontalRevealRangeRequest = {
    minimal_reveal: false,
    view_line_number: 1,
    start_column: 1,
    end_column: 1,
    start_scroll_top: 100.0,
    stop_scroll_top: 0.0,
    scroll_type: Immediate,
  }
  assert_false(
    request.should_cancel_on_scroll(reveal_test_scroll_change(-1.0, false)),
  )
  assert_false(
    request.should_cancel_on_scroll(reveal_test_scroll_change(100.0, true)),
  )
  assert_false(
    request.should_cancel_on_scroll(reveal_test_scroll_change(0.0, true)),
  )
  assert_true(
    request.should_cancel_on_scroll(reveal_test_scroll_change(-1.0, true)),
  )
}

///|
/// A horizontal scroll by anyone else cancels the deferred reveal.
test "horizontal scroll cancels a pending horizontal reveal" {
  let request : HorizontalRevealRangeRequest = {
    minimal_reveal: false,
    view_line_number: 50,
    start_column: 3,
    end_column: 8,
    start_scroll_top: 0.0,
    stop_scroll_top: 738.0,
    scroll_type: Immediate,
  }
  assert_true(
    request.should_cancel_on_scroll(
      reveal_test_scroll_change(738.0, false, left_changed=true),
    ),
  )
}
