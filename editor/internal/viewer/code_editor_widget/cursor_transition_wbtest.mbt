///|
fn cursor_transition_model(
  text : String,
  host_version~ : Int32 = 73,
) -> @model.TextModel {
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="cursor-transition",
      path="/model.mbt",
    ),
    "cursor-transition",
    "plaintext",
    host_version,
    "host-revision",
    text,
  )
}

///|
test "set_selections without a model is an event-free no-op" {
  let viewer = CodeEditorWidget::CodeEditorWidget()
  let mut positions = 0
  let mut selections = 0
  viewer.on_did_change_cursor_position(_ => positions += 1) |> ignore
  viewer.on_did_change_cursor_selection(_ => selections += 1) |> ignore
  viewer.set_selections([Selection(Position(1, 1), Position(1, 1))])
  assert_true(viewer.get_position() is None)
  assert_true(viewer.get_selection() is None)
  assert_eq(positions, 0)
  assert_eq(selections, 0)
  viewer.dispose()
}

///|
test "empty set_selections is an event-free no-op" {
  with_test_viewer("one", viewer => {
    let before = viewer.get_selection()
    let mut events = 0
    viewer.on_did_change_cursor_selection(_ => events += 1) |> ignore
    viewer.set_selections([])
    assert_true(viewer.get_selection() == before)
    assert_eq(events, 0)
  })
}

///|
test "cursor transition metadata uses internal model version for api keyboard and mouse" {
  let viewer = CodeEditorWidget::CodeEditorWidget()
  let model = cursor_transition_model("alpha\nbeta")
  viewer.set_model(Some(model))
  let selections : Array[@editor_api.CursorSelectionChangedEvent] = []
  viewer.on_did_change_cursor_selection(event => selections.push(event))
  |> ignore

  viewer.set_position(Position(1, 3))
  let api = selections[selections.length() - 1]
  assert_eq(api.model_version_id, 1)
  assert_eq(api.old_model_version_id, 1)
  assert_eq(api.source, "api")
  assert_true(api.reason == NotSet)
  guard api.old_selections is Some(old) else {
    fail("ordinary API transition must retain old selections")
  }
  assert_selection_eq(old[0], Selection(Position(1, 1), Position(1, 1)))

  viewer.dispatch_mouse(reference_mouse_data(Position(2, 2)))
  let mouse = selections[selections.length() - 1]
  assert_eq(mouse.model_version_id, 1)
  assert_eq(mouse.old_model_version_id, 1)
  assert_eq(mouse.source, "mouse")
  assert_true(mouse.reason == Explicit)

  viewer.run_cursor_move(Left, false) |> ignore
  let keyboard = selections[selections.length() - 1]
  assert_eq(keyboard.model_version_id, 1)
  assert_eq(keyboard.old_model_version_id, 1)
  assert_eq(keyboard.source, "keyboard")
  assert_true(keyboard.reason == Explicit)
  assert_eq(model.version, 73)
  viewer.dispose()
}

///|
test "cursor transition fires position before selection after view state commit" {
  with_test_viewer("alpha\nbeta", viewer => {
    let order : Array[String] = []
    let mut position_committed = false
    let mut selection_committed = false
    viewer.on_did_change_cursor_position(event => {
      order.push("position")
      position_committed = viewer.get_position().unwrap() == event.position &&
        viewer.test_cursor().model_state().position == event.position &&
        viewer.view_selection().unwrap().get_position() == event.position
    })
    |> ignore
    viewer.on_did_change_cursor_selection(event => {
      order.push("selection")
      selection_committed = viewer.get_selection().unwrap() == event.selection &&
        viewer.test_cursor().get_view_selection() == event.selection &&
        viewer.view_selection().unwrap() == event.selection &&
        viewer.selection_view_range() ==
        Some(
          Range(
            event.selection.start().line_number,
            event.selection.start().column,
            event.selection.end().line_number,
            event.selection.end().column,
          ),
        )
    })
    |> ignore
    viewer.set_selection(Selection(Position(1, 2), Position(2, 3)))
    assert_true(order == ["position", "selection"])
    assert_true(position_committed)
    assert_true(selection_committed)
  })
}

///|
test "exact cursor state is a render and public event no-op" {
  with_test_viewer("alpha", viewer => {
    let mut outgoing = 0
    let mut public_events = 0
    viewer.test_view_model().on_cursor_state_changed(_ => outgoing += 1)
    |> ignore
    viewer.on_did_change_cursor_position(_ => public_events += 1) |> ignore
    viewer.on_did_change_cursor_selection(_ => public_events += 1) |> ignore
    viewer.set_position(Position(1, 1))
    assert_eq(outgoing, 0)
    assert_eq(public_events, 0)
    assert_eq(viewer.cursor_delivery.queue.length(), 0)
  })
}

///|
test "ready empty Flush is consumed before CodeEditorWidget skips public cursor emission" {
  let viewer = CodeEditorWidget::CodeEditorWidget()
  let mut positions = 0
  let mut selections = 0
  viewer.on_did_change_cursor_position(_ => positions += 1) |> ignore
  viewer.on_did_change_cursor_selection(_ => selections += 1) |> ignore
  let event : @view_model.CursorStateChangedEvent = {
    kind: CursorStateChanged,
    old_selections: None,
    selections: [],
    old_model_version_id: 0,
    model_version_id: 17,
    source: "model",
    reason: ContentFlush,
    reached_max_cursor_count: false,
  }
  viewer.cursor_delivery.enqueue(event)
  assert_eq(viewer.cursor_delivery.content_barrier_depth, 1)
  viewer.cursor_delivery.mark_content_complete(17)
  assert_eq(viewer.cursor_delivery.completed_content_versions.length(), 1)
  assert_eq(viewer.cursor_delivery.content_barrier_depth, 0)

  viewer.drain_cursor_delivery_queue()

  assert_eq(positions, 0)
  assert_eq(selections, 0)
  assert_eq(viewer.cursor_delivery.queue.length(), 0)
  assert_eq(viewer.cursor_delivery.completed_content_versions.length(), 0)
  assert_eq(viewer.cursor_delivery.content_barrier_depth, 0)
  assert_false(viewer.cursor_delivery.is_draining)
  viewer.dispose()
}

///|
test "ContentFlush emits content then position then selection with model source and internal version" {
  let viewer = CodeEditorWidget::CodeEditorWidget()
  let model = cursor_transition_model("one\ntwo")
  viewer.set_model(Some(model))
  viewer.set_position(Position(2, 2))
  let order : Array[String] = []
  let selections : Array[@editor_api.CursorSelectionChangedEvent] = []
  let mut content_saw_origin = false
  let mut position_was_origin = false
  viewer.on_did_change_model_content(event => {
    order.push("content:\{event.version_id}")
    content_saw_origin = viewer.get_position().unwrap() == Position(1, 1)
  })
  |> ignore
  viewer.on_did_change_cursor_position(event => {
    order.push("position")
    position_was_origin = event.position == Position(1, 1) &&
      viewer.get_position().unwrap() == Position(1, 1) &&
      viewer.test_cursor().model_state().position == Position(1, 1) &&
      viewer.test_cursor().view_state().position == Position(1, 1) &&
      viewer.view_selection().unwrap().get_position() == Position(1, 1)
  })
  |> ignore
  viewer.on_did_change_cursor_selection(event => {
    order.push("selection")
    selections.push(event)
  })
  |> ignore
  viewer.set_value("new\nvalue")
  assert_true(order == ["content:2", "position", "selection"])
  assert_true(content_saw_origin)
  assert_true(position_was_origin)
  assert_eq(selections.length(), 1)
  let flush = selections[0]
  assert_eq(flush.model_version_id, 2)
  assert_eq(flush.old_model_version_id, 0)
  assert_true(flush.old_selections is None)
  assert_eq(flush.source, "model")
  assert_true(flush.reason == ContentFlush)
  assert_eq(model.version, 73)
  viewer.dispose()
}

///|
test "ContentFlush at origin still emits because the model generation changed" {
  with_test_viewer("one", viewer => {
    let mut content = 0
    let mut positions = 0
    let mut selections = 0
    viewer.on_did_change_model_content(_ => content += 1) |> ignore
    viewer.on_did_change_cursor_position(_ => positions += 1) |> ignore
    viewer.on_did_change_cursor_selection(_ => selections += 1) |> ignore
    viewer.set_value("two")
    assert_eq(content, 1)
    assert_eq(positions, 1)
    assert_eq(selections, 1)
  })
}

///|
test "cursor delivery FIFO keeps reentrant position and selection pairs adjacent" {
  with_test_viewer("abcdef", viewer => {
    let order : Array[String] = []
    let mut reentered = false
    viewer.on_did_change_cursor_position(event => {
      order.push("position:\{event.position.column}")
      if !reentered {
        reentered = true
        viewer.set_position(Position(1, 5))
      }
    })
    |> ignore
    viewer.on_did_change_cursor_selection(event => {
      order.push("selection:\{event.selection.get_position().column}")
    })
    |> ignore
    viewer.set_position(Position(1, 3))
    assert_true(
      order == ["position:3", "selection:3", "position:5", "selection:5"],
    )
  })
}

///|
test "model swap in a position listener keeps the old pair ahead of the new model pair" {
  let viewer = CodeEditorWidget::CodeEditorWidget()
  let first = test_model("abcdef")
  let second = test_model("uvwxyz")
  viewer.set_model(Some(first))
  let order : Array[String] = []
  let mut swapped = false
  let mut retained_drain_gate = false
  let mut queued_new_pair = false
  viewer.on_did_change_cursor_position(event => {
    order.push("position:\{event.position.column}")
    if !swapped {
      swapped = true
      viewer.set_model(Some(second))
      retained_drain_gate = viewer.cursor_delivery.is_draining
      viewer.set_position(Position(1, 5))
      queued_new_pair = viewer.cursor_delivery.is_draining &&
        viewer.cursor_delivery.queue.length() == 1
    }
  })
  |> ignore
  viewer.on_did_change_cursor_selection(event => {
    order.push("selection:\{event.selection.get_position().column}")
  })
  |> ignore

  viewer.set_position(Position(1, 3))

  assert_true(
    order == ["position:3", "selection:3", "position:5", "selection:5"],
  )
  assert_true(retained_drain_gate)
  assert_true(queued_new_pair)
  assert_true(viewer.get_model().unwrap().same(second))
  assert_false(viewer.cursor_delivery.is_draining)
  assert_eq(viewer.cursor_delivery.queue.length(), 0)
  assert_eq(viewer.cursor_delivery.content_barrier_depth, 0)
  assert_eq(viewer.cursor_delivery.completed_content_versions.length(), 0)
  viewer.dispose()
  first.dispose()
  second.dispose()
}

///|
test "selection-listener reentrancy queues the later cursor pair" {
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
  })
}

///|
test "selection listener set_value delivers ContentFlush without barrier deadlock" {
  with_test_viewer("abcdef", viewer => {
    let order : Array[String] = []
    let mut flushed = false
    viewer.on_did_change_model_content(_ => order.push("content")) |> ignore
    viewer.on_did_change_cursor_position(event => {
      order.push("position:\{event.position.column}")
    })
    |> ignore
    viewer.on_did_change_cursor_selection(event => {
      order.push("selection:\{event.selection.get_position().column}")
      if !flushed {
        flushed = true
        viewer.set_value("replacement")
      }
    })
    |> ignore
    viewer.set_position(Position(1, 3))
    assert_true(
      order ==
      ["position:3", "selection:3", "content", "position:1", "selection:1"],
    )
    assert_eq(viewer.cursor_delivery.content_barrier_depth, 0)
    assert_eq(viewer.cursor_delivery.queue.length(), 0)

    // A later transition proves the delivery spine did not remain wedged.
    viewer.set_position(Position(1, 4))
    assert_eq(order[order.length() - 2], "position:4")
    assert_eq(order[order.length() - 1], "selection:4")
  })
}

///|
test "nested content completion releases only its matching Flush version" {
  with_test_viewer("one", viewer => {
    let order : Array[String] = []
    let mut reentered = false
    viewer
    .test_view_model()
    .on_cursor_state_changed(event => {
      if event.reason == ContentFlush && !reentered {
        reentered = true
        viewer.set_value("three")
      }
    })
    |> ignore
    viewer.on_did_change_model_content(event => {
      order.push("content:\{event.version_id}")
    })
    |> ignore
    viewer.on_did_change_cursor_selection(event => {
      order.push("selection:\{event.model_version_id}")
    })
    |> ignore

    viewer.set_value("two")
    assert_true(
      order == ["content:3", "content:2", "selection:2", "selection:3"],
    )
    assert_eq(viewer.cursor_delivery.content_barrier_depth, 0)
    assert_eq(viewer.cursor_delivery.queue.length(), 0)
    assert_eq(viewer.cursor_delivery.completed_content_versions.length(), 0)
  })
}

///|
test "old-model content completion cannot release a same-version new-model Flush" {
  let viewer = CodeEditorWidget::CodeEditorWidget()
  let first = test_model("first")
  let second = test_model("second")
  viewer.set_model(Some(first))
  let order : Array[String] = []
  let mut swapped = false
  viewer.on_did_change_model_content(event => {
    order.push("content:\{event.version_id}")
    if !swapped {
      swapped = true
      viewer.set_model(Some(second))
    }
  })
  |> ignore
  viewer.on_did_change_cursor_selection(event => {
    order.push("selection:\{event.model_version_id}")
  })
  |> ignore

  viewer.set_value("first replacement")
  assert_true(order == ["content:2"])
  assert_eq(viewer.cursor_delivery.completed_content_versions.length(), 0)

  order.clear()
  viewer.set_value("second replacement")
  assert_true(order == ["content:2", "selection:2"])
  assert_eq(viewer.cursor_delivery.completed_content_versions.length(), 0)
  viewer.dispose()
  first.dispose()
  second.dispose()
}

///|
test "two cursor mutations in one listener retain both outgoing facts" {
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
        viewer.set_position(Position(1, 4))
        viewer.set_position(Position(1, 6))
      }
    })
    |> ignore
    viewer.set_position(Position(1, 2))
    assert_true(
      order ==
      [
        "position:2", "selection:2", "position:4", "selection:4", "position:6", "selection:6",
      ],
    )
  })
}

///|
test "reentrant ContentFlush retains every queued cursor fact" {
  with_test_viewer("one", viewer => {
    let order : Array[String] = []
    let versions : Array[Int32] = []
    let mut reentered = false
    viewer.on_did_change_model_content(event => {
      order.push("content:\{event.version_id}")
      if !reentered {
        reentered = true
        viewer.set_value("three")
      }
    })
    |> ignore
    viewer.on_did_change_cursor_position(_ => order.push("position")) |> ignore
    viewer.on_did_change_cursor_selection(event => {
      order.push("selection")
      versions.push(event.model_version_id)
    })
    |> ignore
    viewer.set_value("two")
    assert_true(
      order ==
      [
        "content:2", "content:3", "position", "selection", "position", "selection",
      ],
    )
    assert_true(versions == [2, 3])
    assert_eq(viewer.cursor_delivery.queue.length(), 0)
    assert_eq(viewer.cursor_delivery.content_barrier_depth, 0)
  })
}

///|
test "set_selections keeps primary and forwards public source reason with empty secondaries" {
  with_test_viewer("one\ntwo", viewer => {
    let positions : Array[@editor_api.CursorPositionChangedEvent] = []
    let selections : Array[@editor_api.CursorSelectionChangedEvent] = []
    viewer.on_did_change_cursor_position(event => positions.push(event))
    |> ignore
    viewer.on_did_change_cursor_selection(event => selections.push(event))
    |> ignore
    viewer.set_selections(
      [
        Selection(Position(2, 2), Position(2, 3)),
        Selection(Position(1, 1), Position(1, 2)),
      ],
      source="selection-api",
      reason=Undo,
    )
    assert_eq(positions.length(), 1)
    assert_eq(selections.length(), 1)
    assert_eq(positions[0].secondary_positions.length(), 0)
    assert_eq(selections[0].secondary_selections.length(), 0)
    assert_eq(positions[0].source, "selection-api")
    assert_true(positions[0].reason == Undo)
    assert_eq(selections[0].source, "selection-api")
    assert_true(selections[0].reason == Undo)
    assert_selection_eq(
      selections[0].selection,
      Selection(Position(2, 2), Position(2, 3)),
    )
  })
}

///|
test "public ContentFlush reason does not open a model-content delivery barrier" {
  with_test_viewer("one\ntwo", viewer => {
    let order : Array[String] = []
    viewer.on_did_change_cursor_position(_ => order.push("position")) |> ignore
    viewer.on_did_change_cursor_selection(_ => order.push("selection"))
    |> ignore
    viewer.set_selections(
      [Selection(Position(2, 1), Position(2, 2))],
      source="api-with-flush-reason",
      reason=ContentFlush,
    )
    assert_true(order == ["position", "selection"])
    assert_eq(viewer.cursor_delivery.content_barrier_depth, 0)
    assert_eq(viewer.cursor_delivery.queue.length(), 0)
  })
}

///|
test "empty transition source falls back to keyboard" {
  with_test_viewer("one", viewer => {
    let sources : Array[String] = []
    viewer
    .test_view_model()
    .on_cursor_state_changed(event => sources.push(event.source))
    |> ignore
    viewer
    .test_view_model()
    .set_model_cursor_state(
      SingleCursorState(Position(1, 2), Position(1, 2), Simple, Position(1, 2)),
      "",
      NotSet,
    )
    |> ignore
    assert_true(sources == ["keyboard"])
  })
}
