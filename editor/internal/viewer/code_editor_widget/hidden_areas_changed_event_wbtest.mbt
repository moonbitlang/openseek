///|
let hidden_event_source =
  #|one
  #|two
  #|three
  #|four
  #|five
  #|six
  #|seven
  #|eight

///|
test "headless hidden-area event is changed-only" {
  with_test_viewer(hidden_event_source, viewer => {
    let mut delivered = 0
    viewer.on_did_change_hidden_areas(() => delivered += 1) |> ignore

    viewer.set_hidden_areas([])
    assert_eq(delivered, 0)
    viewer.set_hidden_areas([Range(2, 1, 3, 1)])
    assert_eq(delivered, 1)
    viewer.set_hidden_areas([Range(2, 1, 3, 1)])
    viewer.set_hidden_areas([Range(2, 1, 3, 1)], force_update=true)
    assert_eq(delivered, 1)
    viewer.set_hidden_areas([])
    assert_eq(delivered, 2)
  })

  with_test_viewer(hidden_event_source, viewer => {
    let mut delivered = 0
    viewer.on_did_change_hidden_areas(() => delivered += 1) |> ignore
    viewer.set_hidden_areas([Range(1, 1, 8, 1)])
    assert_eq(viewer.test_view_model().line_count(), 8)
    assert_eq(delivered, 1)
  })
}

///|
test "hidden-area event is a no-op without a model" {
  let viewer = CodeEditorWidget::CodeEditorWidget()
  defer viewer.dispose()
  let mut delivered = 0
  viewer.on_did_change_hidden_areas(() => delivered += 1) |> ignore
  viewer.set_hidden_areas([Range(1, 1, 2, 1)])
  assert_eq(delivered, 0)
}

///|
test "hidden-area event follows only the current model across a swap" {
  let first = test_model(hidden_event_source)
  defer first.dispose()
  let second = test_model(hidden_event_source)
  defer second.dispose()
  let viewer = CodeEditorWidget::CodeEditorWidget()
  defer viewer.dispose()
  let delivered_values : Array[String] = []
  viewer.on_did_change_hidden_areas(() => {
    delivered_values.push(viewer.get_value())
  })
  |> ignore

  viewer.set_model(Some(first))
  let first_view_model = viewer.test_view_model()
  viewer.set_hidden_areas([Range(2, 1, 2, 1)])
  assert_true(delivered_values == [hidden_event_source])

  viewer.set_model(Some(second))
  // The detached ViewModel can still be used as a white-box object, but its
  // dispatcher and model-scoped root relay have both been retired.
  first_view_model.set_hidden_areas([Range(4, 1, 4, 1)]) |> ignore
  assert_eq(delivered_values.length(), 1)
  viewer.set_hidden_areas([Range(3, 1, 3, 1)])
  assert_true(delivered_values == [hidden_event_source, hidden_event_source])
}

///|
test "viewer disposal retires hidden-area public and model-scoped delivery" {
  let model = test_model(hidden_event_source)
  defer model.dispose()
  let viewer = CodeEditorWidget::CodeEditorWidget()
  viewer.set_model(Some(model))
  let view_model = viewer.test_view_model()
  let mut delivered = 0
  viewer.on_did_change_hidden_areas(() => delivered += 1) |> ignore
  viewer.set_hidden_areas([Range(2, 1, 2, 1)])
  assert_eq(delivered, 1)

  viewer.dispose()
  view_model.set_hidden_areas([Range(4, 1, 4, 1)]) |> ignore
  viewer.set_hidden_areas([Range(5, 1, 5, 1)])
  viewer.on_did_change_hidden_areas(() => delivered += 1) |> ignore
  assert_eq(delivered, 1)
}

///|
test "public hidden-area event supports synchronous reentrant changes" {
  with_test_viewer(hidden_event_source, viewer => {
    let order : Array[String] = []
    let mut calls = 0
    viewer.on_did_change_hidden_areas(() => {
      calls += 1
      let call = calls
      order.push("enter:\{call}")
      if call == 1 {
        viewer.set_hidden_areas([Range(4, 1, 4, 1)])
      }
      order.push("exit:\{call}")
    })
    |> ignore

    viewer.set_hidden_areas([Range(2, 1, 2, 1)])
    assert_true(order == ["enter:1", "enter:2", "exit:2", "exit:1"])
    assert_true(
      viewer.test_view_model().get_hidden_areas() == [Range(4, 1, 4, 1)],
    )
  })
}

///|
test "public hidden-area event follows cursor layout and recovery scroll" {
  with_test_viewer(hidden_event_source, viewer => {
    viewer.set_position(Position(4, 2))
    let view_model = viewer.test_view_model()
    let layout = view_model.view_layout
    layout.set_viewport_size(width=400.0, height=18.0) |> ignore
    let old_top = layout.get_vertical_offset_for_line_number(4) + 7.0
    layout.scroll_to(scroll_top=old_top) |> ignore

    let order : Array[String] = []
    let scroll_subscription = layout.on_did_scroll(_change => {
      order.push("scroll")
    })
    defer scroll_subscription.dispose()
    let mut committed_before_public = false
    let mut public_cursor_events = 0
    viewer.on_did_change_cursor_position(_ => public_cursor_events += 1)
    |> ignore
    viewer.on_did_change_cursor_selection(_ => public_cursor_events += 1)
    |> ignore
    viewer.on_did_change_hidden_areas(() => {
      order.push("hidden")
      committed_before_public = view_model.cursor.model_state().position ==
        Position(4, 2) &&
        view_model.cursor.view_state().position == Position(2, 2) &&
        view_model.line_count() == 6 &&
        layout.line_count() == 6 &&
        layout.get_current_scroll_top() ==
        layout.get_vertical_offset_for_line_number(2) + 7.0
    })
    |> ignore

    viewer.set_hidden_areas([Range(2, 1, 3, 1)])
    assert_true(order == ["scroll", "scroll", "hidden"])
    assert_true(committed_before_public)
    // Mapping-only cursor reprojection is committed before the hidden event,
    // but does not fabricate a public model-coordinate cursor transition.
    assert_eq(public_cursor_events, 0)
  })
}
