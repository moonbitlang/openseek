// Headless pointer/event matrix supplement. Real gestures and visible DOM
// selection live in the browser component suite; this file owns exact event
// payloads and reentrant callback state.

///|
fn assert_pointer_transition(
  viewer : CodeEditorWidget,
  events : Array[@editor_api.CursorSelectionChangedEvent],
  previous_length : Int32,
  old_selection : @core.Selection,
  source : String,
) -> Unit raise {
  assert_eq(events.length(), previous_length + 1)
  let event = events[events.length() - 1]
  guard event.old_selections is Some(old) else {
    fail("ordinary pointer transition must retain old selections")
  }
  assert_eq(old.length(), 1)
  assert_selection_eq(old[0], old_selection)
  assert_selection_eq(event.selection, viewer.get_selection().unwrap())
  assert_eq(event.source, source)
  assert_true(event.reason == Explicit)
}

///|
test "live pointer branches retain exact old selections after committed state" {
  with_test_viewer(
    (
      #|alpha beta
      #|second line
      #|third
      #|fourth
    ),
    viewer => {
      let events : Array[@editor_api.CursorSelectionChangedEvent] = []
      let mut position_callbacks_committed = true
      let mut selection_callbacks_committed = true
      viewer.on_did_change_cursor_position(event => {
        position_callbacks_committed = position_callbacks_committed &&
          viewer.get_position().unwrap() == event.position &&
          viewer.test_cursor().model_state().position == event.position
      })
      |> ignore
      viewer.on_did_change_cursor_selection(event => {
        selection_callbacks_committed = selection_callbacks_committed &&
          viewer.get_selection().unwrap() == event.selection &&
          viewer.test_cursor().get_model_selection() == event.selection
        events.push(event)
      })
      |> ignore

      let mut before = viewer.get_selection().unwrap()
      let mut count = events.length()
      viewer.dispatch_mouse(mouse_dispatch_data(Position(1, 3)))
      assert_pointer_transition(viewer, events, count, before, "mouse")

      before = viewer.get_selection().unwrap()
      count = events.length()
      viewer.dispatch_mouse(
        mouse_dispatch_data(Position(1, 8), mouse_down_count=2),
      )
      assert_pointer_transition(viewer, events, count, before, "mouse")

      before = viewer.get_selection().unwrap()
      count = events.length()
      viewer.dispatch_mouse(
        mouse_dispatch_data(
          Position(1, 2),
          in_selection_mode=true,
          mouse_down_count=2,
        ),
      )
      assert_pointer_transition(viewer, events, count, before, "mouse")

      before = viewer.get_selection().unwrap()
      count = events.length()
      viewer.dispatch_mouse(
        mouse_dispatch_data(Position(2, 3), mouse_down_count=3),
      )
      assert_pointer_transition(viewer, events, count, before, "mouse")

      before = viewer.get_selection().unwrap()
      count = events.length()
      viewer.dispatch_mouse(
        mouse_dispatch_data(
          Position(4, 3),
          in_selection_mode=true,
          mouse_down_count=3,
        ),
      )
      assert_pointer_transition(viewer, events, count, before, "mouse")

      before = viewer.get_selection().unwrap()
      count = events.length()
      viewer.dispatch_mouse(
        mouse_dispatch_data(Position(1, 2), started_on_line_numbers=true),
      )
      assert_pointer_transition(viewer, events, count, before, "mouse")

      before = viewer.get_selection().unwrap()
      count = events.length()
      viewer.dispatch_mouse(
        mouse_dispatch_data(
          Position(3, 2),
          started_on_line_numbers=true,
          in_selection_mode=true,
        ),
      )
      assert_pointer_transition(viewer, events, count, before, "mouse")

      before = viewer.get_selection().unwrap()
      count = events.length()
      viewer.dispatch_mouse(
        mouse_dispatch_data(Position(2, 2), mouse_down_count=4),
      )
      assert_pointer_transition(viewer, events, count, before, "keyboard")
      assert_true(position_callbacks_committed)
      assert_true(selection_callbacks_committed)
    },
  )
}

///|
test "ctrl and meta pointer modifiers retain ordinary and non-multi behavior" {
  with_test_viewer("alpha beta\nsecond line", viewer => {
    let events : Array[@view_model.CursorStateChangedEvent] = []
    viewer
    .test_view_model()
    .on_cursor_state_changed(event => events.push(event))
    |> ignore

    viewer.dispatch_mouse(
      mouse_dispatch_data(Position(1, 3), ctrl_key=true, reveal_type=None),
    )
    assert_cursor(viewer, Selection(Position(1, 3), Position(1, 3)))
    assert_last_cursor_transition(events, "mouse")
    viewer.dispatch_mouse(
      mouse_dispatch_data(Position(2, 4), meta_key=true, reveal_type=None),
    )
    assert_cursor(viewer, Selection(Position(2, 4), Position(2, 4)))
    assert_last_cursor_transition(events, "mouse")

    let before = viewer.test_cursor().get_primary_cursor_state()
    let event_count = events.length()
    viewer.dispatch_mouse(
      mouse_dispatch_data(
        Position(1, 6),
        alt_key=true,
        ctrl_key=true,
        reveal_type=None,
      ),
    )
    assert_true(viewer.test_cursor().get_primary_cursor_state() == before)
    assert_eq(events.length(), event_count)
    viewer.dispatch_mouse(
      mouse_dispatch_data(
        Position(1, 8),
        alt_key=true,
        meta_key=true,
        reveal_type=None,
      ),
    )
    assert_true(viewer.test_cursor().get_primary_cursor_state() == before)
    assert_eq(events.length(), event_count)
  })
}

///|
test "pointer converts a wrapped injected position across a hidden model line" {
  let options = CodeEditorOptions(soft_wrap=true)
  with_test_viewer(
    (
      #|abcdefghij
      #|hidden line wraps too
      #|abcdefghijklmnop
      #|tail
    ),
    viewer => {
      viewer.test_set_soft_wrap_column(6)
      let view_model = viewer.test_view_model()
      let converter = view_model.coordinates_converter()
      let target = @base_common.Position(3, 12)
      let unprojected = converter.model_position_to_view_position(target)

      assert_true(view_model.set_hidden_areas([Range(2, 1, 2, 1)]))
      let folded = converter.model_position_to_view_position(target)
      assert_true(folded.line_number < unprojected.line_number)

      install_cursor_test_injected_text(
        viewer,
        Position(3, 4),
        "very-long-injected-text",
      )
      assert_true(view_model.get_hidden_areas() == [Range(2, 1, 2, 1)])
      let projected = converter.model_position_to_view_position(target)
      assert_true(projected != folded)
      assert_true(
        converter.view_position_to_model_position(projected) == target,
      )

      viewer.dispatch_mouse(
        mouse_dispatch_data(projected, ctrl_key=true, reveal_type=None),
      )
      assert_cursor(viewer, Selection(target, target))
      assert_position(viewer.test_cursor().view_state().position, projected)
    },
    options~,
  )
}

///|
test "selection-listener reentrancy preserves adjacent cursor event pairs" {
  with_test_viewer("abcdef", viewer => {
    let order : Array[String] = []
    let mut reentered = false
    viewer.on_did_change_cursor_position(event => {
      order.push("position:\{event.position.column}")
    })
    |> ignore
    viewer.on_did_change_cursor_selection(event => {
      order.push("selection:\{event.selection.get_position().column}")
      if !reentered {
        reentered = true
        viewer.set_position(Position(1, 5))
      }
    })
    |> ignore
    viewer.set_position(Position(1, 3))
    assert_true(
      order == ["position:3", "selection:3", "position:5", "selection:5"],
    )
    assert_position(viewer.get_position().unwrap(), Position(1, 5))
  })
}
