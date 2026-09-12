///|
fn dispatcher_selection(column : Int) -> @core.Selection {
  Selection(Position(1, column), Position(1, column))
}

///|
fn dispatcher_event(
  old_selections : Array[@core.Selection]?,
  column : Int,
  old_version : Int,
  new_version : Int,
  source? : String = "first",
  reason? : @editor_api.CursorChangeReason = Explicit,
  reached_max_cursor_count? : Bool = false,
) -> CursorStateChangedEvent {
  {
    kind: CursorStateChanged,
    old_selections,
    selections: [dispatcher_selection(column)],
    old_model_version_id: old_version,
    model_version_id: new_version,
    source,
    reason,
    reached_max_cursor_count,
  }
}

///|
fn dispatcher_model_tokens_event(
  from_line_number : Int,
  to_line_number : Int,
) -> @model.ModelTokensChangedEvent {
  {
    semantic_tokens_applied: false,
    ranges: [{ from_line_number, to_line_number, }],
  }
}

///|
test "cursor outgoing nullable selection equality covers null length and index mismatches" {
  let one = dispatcher_selection(1)
  let two = dispatcher_selection(2)
  let three = dispatcher_selection(3)
  assert_true(selections_are_equal(None, None))
  assert_false(selections_are_equal(None, Some([one])))
  assert_false(selections_are_equal(Some([one]), None))
  assert_false(selections_are_equal(Some([one]), Some([one, two])))
  assert_false(
    selections_are_equal(Some([one, two, three]), Some([two, two, three])),
  )
  assert_false(
    selections_are_equal(Some([one, two, three]), Some([one, one, three])),
  )
  assert_false(
    selections_are_equal(Some([one, two, three]), Some([one, two, two])),
  )
  assert_true(
    selections_are_equal(Some([one, two, three]), Some([one, two, three])),
  )
}

///|
test "cursor outgoing no-op requires equal selections and internal version" {
  let one = dispatcher_selection(1)
  assert_true(dispatcher_event(Some([one]), 1, 7, 7).is_no_op())
  assert_false(dispatcher_event(Some([one]), 1, 7, 8).is_no_op())
  assert_false(dispatcher_event(None, 1, 0, 1).is_no_op())
}

///|
test "cursor outgoing merge keeps earliest old state and latest new state" {
  let first = dispatcher_event(
    Some([dispatcher_selection(1)]),
    2,
    10,
    11,
    source="first",
  )
  let second = dispatcher_event(
    Some([dispatcher_selection(2)]),
    3,
    11,
    12,
    source="second",
    reason=Redo,
  )
  guard first.attempt_to_merge(CursorEvent(second)) is Some(merged) else {
    fail("same-kind cursor events must merge")
  }
  assert_true(merged.old_selections == first.old_selections)
  assert_true(merged.selections[0] == dispatcher_selection(3))
  assert_eq(merged.old_model_version_id, 10)
  assert_eq(merged.model_version_id, 12)
  assert_eq(merged.source, "second")
  assert_true(merged.reason == Redo)
  assert_true(merged.kind == CursorStateChanged)
  assert_false(merged.reached_max_cursor_count)
  assert_true(
    first.attempt_to_merge(ViewZonesEvent(ViewZonesChangedEvent())) is None,
  )
}

///|
test "ViewZones outgoing is live and merges only its own kind" {
  let zones = ViewZonesChangedEvent()
  assert_true(zones.kind == ViewZonesChanged)
  assert_false(zones.is_no_op())
  guard zones.attempt_to_merge(ViewZonesEvent(ViewZonesChangedEvent()))
    is Some(merged) else {
    fail("same-kind ViewZones events must merge")
  }
  assert_true(physical_equal(merged, zones))
  assert_true(
    zones.attempt_to_merge(CursorEvent(dispatcher_event(None, 1, 0, 1))) is None,
  )
}

///|
test "model-token outgoing retains identity and never no-ops or merges" {
  let model_event = dispatcher_model_tokens_event(2, 4)
  let outgoing = ModelTokensChangedOutgoingEvent(model_event)
  assert_true(outgoing.kind == ModelTokensChanged)
  assert_true(physical_equal(outgoing.event, model_event))
  assert_false(outgoing.is_no_op())
  assert_true(outgoing.attempt_to_merge(ModelTokensEvent(outgoing)) is None)
  assert_true(
    outgoing.attempt_to_merge(CursorEvent(dispatcher_event(None, 1, 0, 1)))
    is None,
  )
  assert_true(
    outgoing.attempt_to_merge(ViewZonesEvent(ViewZonesChangedEvent())) is None,
  )
}

///|
test "model-token outgoing typed listener receives every event in FIFO order" {
  let dispatcher = CursorEventDispatcher::CursorEventDispatcher()
  let delivered : Array[Int] = []
  dispatcher.on_model_tokens_changed(event => {
    delivered.push(event.event.ranges[0].from_line_number)
  })
  |> ignore
  dispatcher.add_outgoing_event(
    ModelTokensEvent(
      ModelTokensChangedOutgoingEvent(dispatcher_model_tokens_event(1, 1)),
    ),
  )
  dispatcher.add_outgoing_event(
    ModelTokensEvent(
      ModelTokensChangedOutgoingEvent(dispatcher_model_tokens_event(2, 2)),
    ),
  )
  assert_eq(dispatcher.outgoing_events.length(), 2)
  dispatcher.emit_outgoing_events()
  assert_true(delivered == [1, 2])
}

///|
test "empty model-token outgoing event remains observable" {
  let dispatcher = CursorEventDispatcher::CursorEventDispatcher()
  let mut delivered = 0
  let mut observed_range_count = -1
  dispatcher.on_model_tokens_changed(event => {
    observed_range_count = event.event.ranges.length()
    delivered += 1
  })
  |> ignore
  dispatcher.emit_model_tokens_changed(
    ModelTokensChangedOutgoingEvent({
      semantic_tokens_applied: false,
      ranges: [],
    }),
  )
  assert_eq(delivered, 1)
  assert_eq(observed_range_count, 0)
}

///|
test "model-token outgoing reentrant delivery preserves event identity order" {
  let dispatcher = CursorEventDispatcher::CursorEventDispatcher()
  let delivered : Array[String] = []
  let mut reentered = false
  dispatcher.on_model_tokens_changed(event => {
    let line = event.event.ranges[0].from_line_number
    delivered.push("enter:\{line}")
    if !reentered {
      reentered = true
      dispatcher.emit_model_tokens_changed(
        ModelTokensChangedOutgoingEvent(dispatcher_model_tokens_event(2, 2)),
      )
    }
    delivered.push("exit:\{line}")
  })
  |> ignore
  dispatcher.emit_model_tokens_changed(
    ModelTokensChangedOutgoingEvent(dispatcher_model_tokens_event(1, 1)),
  )
  assert_true(delivered == ["enter:1", "enter:2", "exit:2", "exit:1"])
}

///|
test "cursor outgoing merge ORs the reached-max source flag" {
  let first = dispatcher_event(Some([dispatcher_selection(1)]), 2, 1, 1)
  let second = dispatcher_event(
    Some([dispatcher_selection(2)]),
    3,
    1,
    1,
    reached_max_cursor_count=true,
  )
  guard first.attempt_to_merge(CursorEvent(second)) is Some(merged) else {
    fail("same-kind cursor events must merge")
  }
  assert_true(merged.reached_max_cursor_count)
}

///|
test "cursor outgoing queue merges into first same-kind slot and drops no-ops" {
  let dispatcher = CursorEventDispatcher::CursorEventDispatcher()
  let delivered : Array[String] = []
  dispatcher.on_event(event => {
    delivered.push(
      "\{event.source}:\{event.selections[0].get_position().column}",
    )
  })
  |> ignore
  let one = dispatcher_selection(1)
  dispatcher.add_outgoing_event(
    CursorEvent(dispatcher_event(Some([one]), 1, 1, 1)),
  )
  dispatcher.add_outgoing_event(ViewZonesEvent(ViewZonesChangedEvent()))
  dispatcher.add_outgoing_event(
    CursorEvent(dispatcher_event(Some([one]), 3, 1, 2, source="latest")),
  )
  dispatcher.emit_outgoing_events()
  assert_true(delivered == ["latest:3"])
}

///|
test "cursor outgoing different-kind slots retain FIFO position around merge" {
  let dispatcher = CursorEventDispatcher::CursorEventDispatcher()
  let one = dispatcher_selection(1)
  dispatcher.add_outgoing_event(ViewZonesEvent(ViewZonesChangedEvent()))
  dispatcher.add_outgoing_event(
    CursorEvent(dispatcher_event(Some([one]), 2, 1, 2, source="first")),
  )
  dispatcher.add_outgoing_event(ViewZonesEvent(ViewZonesChangedEvent()))
  dispatcher.add_outgoing_event(
    CursorEvent(
      dispatcher_event(
        Some([dispatcher_selection(2)]),
        3,
        2,
        3,
        source="latest",
        reason=Undo,
      ),
    ),
  )
  assert_eq(dispatcher.outgoing_events.length(), 2)
  assert_true(dispatcher.outgoing_events[0] is ViewZonesEvent(_))
  guard dispatcher.outgoing_events[1] is CursorEvent(merged) else {
    fail("the cursor event must retain its first same-kind FIFO slot")
  }
  assert_eq(merged.old_model_version_id, 1)
  assert_eq(merged.model_version_id, 3)
  assert_eq(merged.source, "latest")
  assert_true(merged.reason == Undo)
}

///|
test "heterogeneous queue delivers cursor and ViewZones facts in FIFO order" {
  let dispatcher = CursorEventDispatcher::CursorEventDispatcher()
  let delivered : Array[String] = []
  dispatcher.on_event(event => {
    delivered.push("cursor:\{event.selections[0].get_position().column}")
  })
  |> ignore
  dispatcher.on_view_zones_changed(_ => delivered.push("zones")) |> ignore
  dispatcher.add_outgoing_event(ViewZonesEvent(ViewZonesChangedEvent()))
  dispatcher.add_outgoing_event(CursorEvent(dispatcher_event(None, 3, 0, 1)))
  dispatcher.emit_outgoing_events()
  assert_true(delivered == ["zones", "cursor:3"])
}

///|
test "reentrant cross-kind fire uses the shared outgoing listener delivery" {
  let dispatcher = CursorEventDispatcher::CursorEventDispatcher()
  let delivered : Array[String] = []
  dispatcher.on_event(_event => {
    delivered.push("cursor:before")
    dispatcher.emit_view_zones_changed(ViewZonesChangedEvent())
    delivered.push("cursor:after")
  })
  |> ignore
  dispatcher.on_view_zones_changed(_ => delivered.push("zones")) |> ignore
  dispatcher.emit_outgoing_event(dispatcher_event(None, 2, 0, 1))
  assert_true(delivered == ["cursor:before", "zones", "cursor:after"])
}

///|
test "standalone no-op drains before a later live cursor event" {
  let dispatcher = CursorEventDispatcher::CursorEventDispatcher()
  let delivered : Array[Int] = []
  dispatcher.on_event(event => {
    delivered.push(event.selections[0].get_position().column)
  })
  |> ignore
  let one = dispatcher_selection(1)
  dispatcher.emit_outgoing_event(
    dispatcher_event(Some([one]), 1, 1, 1, source="no-op"),
  )
  assert_eq(dispatcher.outgoing_events.length(), 0)
  assert_eq(delivered.length(), 0)
  dispatcher.emit_outgoing_event(
    dispatcher_event(Some([one]), 2, 1, 2, source="live"),
  )
  assert_true(delivered == [2])
}

///|
test "cursor outgoing FIFO continues through reentrant delivery" {
  let dispatcher = CursorEventDispatcher::CursorEventDispatcher()
  let delivered : Array[Int] = []
  let mut reentered = false
  dispatcher.on_event(event => {
    delivered.push(event.selections[0].get_position().column)
    if !reentered {
      reentered = true
      dispatcher.emit_outgoing_event(
        dispatcher_event(
          Some([dispatcher_selection(2)]),
          4,
          1,
          1,
          source="reentrant",
        ),
      )
    }
  })
  |> ignore
  dispatcher.emit_outgoing_event(
    dispatcher_event(Some([dispatcher_selection(1)]), 2, 1, 1, source="outer"),
  )
  assert_true(delivered == [2, 4])
}

///|
test "single cursor listener receives a reentrant event recursively" {
  let dispatcher = CursorEventDispatcher::CursorEventDispatcher()
  let delivered : Array[String] = []
  let mut reentered = false
  dispatcher.on_event(event => {
    let column = event.selections[0].get_position().column
    delivered.push("enter:\{column}")
    if !reentered {
      reentered = true
      dispatcher.emit_outgoing_event(
        dispatcher_event(
          Some([dispatcher_selection(column)]),
          4,
          1,
          1,
          source="reentrant",
        ),
      )
    }
    delivered.push("exit:\{column}")
  })
  |> ignore
  dispatcher.emit_outgoing_event(
    dispatcher_event(Some([dispatcher_selection(1)]), 2, 1, 1),
  )
  assert_true(delivered == ["enter:2", "enter:4", "exit:4", "exit:2"])
}

///|
test "reentrant cursor event drains current listeners then nests before return" {
  let dispatcher = CursorEventDispatcher::CursorEventDispatcher()
  let delivered : Array[String] = []
  let mut reentered = false
  dispatcher.on_event(event => {
    let column = event.selections[0].get_position().column
    delivered.push("first:\{column}:before")
    if !reentered {
      reentered = true
      dispatcher.emit_outgoing_event(
        dispatcher_event(
          Some([dispatcher_selection(column)]),
          4,
          1,
          1,
          source="reentrant",
        ),
      )
    }
    delivered.push("first:\{column}:after")
  })
  |> ignore
  dispatcher.on_event(event => {
    delivered.push("second:\{event.selections[0].get_position().column}")
  })
  |> ignore
  dispatcher.emit_outgoing_event(
    dispatcher_event(Some([dispatcher_selection(1)]), 2, 1, 1),
  )
  assert_true(
    delivered ==
    [
      "first:2:before", "second:2", "first:4:before", "first:4:after", "second:4",
      "first:2:after",
    ],
  )
}

///|
test "reentrant cursor delivery retains array semantics after sibling disposal" {
  let dispatcher = CursorEventDispatcher::CursorEventDispatcher()
  let delivered : Array[String] = []
  let mut reentered = false
  let sibling = Ref(@base_common.Disposable::from(() => ()))
  dispatcher.on_event(event => {
    let column = event.selections[0].get_position().column
    delivered.push("first:\{column}:before")
    if !reentered {
      reentered = true
      sibling.val.dispose()
      dispatcher.emit_outgoing_event(
        dispatcher_event(
          Some([dispatcher_selection(column)]),
          4,
          1,
          1,
          source="reentrant",
        ),
      )
    }
    delivered.push("first:\{column}:after")
  })
  |> ignore
  sibling.val = dispatcher.on_event(event => {
    delivered.push("second:\{event.selections[0].get_position().column}")
  })
  dispatcher.emit_outgoing_event(
    dispatcher_event(Some([dispatcher_selection(1)]), 2, 1, 1),
  )
  assert_true(
    delivered ==
    ["first:2:before", "first:4:before", "first:4:after", "first:2:after"],
  )
}

///|
test "disposing the cursor dispatcher drops listeners pending facts and later emissions" {
  let dispatcher = CursorEventDispatcher::CursorEventDispatcher()
  let mut delivered = 0
  dispatcher.on_event(_ => delivered += 1) |> ignore
  let selection = dispatcher_selection(1)
  dispatcher.add_outgoing_event(
    CursorEvent(dispatcher_event(Some([selection]), 2, 1, 1)),
  )
  dispatcher.dispose()
  assert_eq(dispatcher.outgoing_events.length(), 0)
  dispatcher.emit_outgoing_event(dispatcher_event(Some([selection]), 3, 1, 1))
  assert_eq(delivered, 0)
  dispatcher.on_event(_ => delivered += 1) |> ignore
  dispatcher.emit_outgoing_event(dispatcher_event(Some([selection]), 4, 1, 1))
  assert_eq(delivered, 0)
}

///|
test "disposing a view model retires cursor outgoing subscriptions" {
  let view_model = cursor_reference_view_model()
  let mut delivered = 0
  view_model.on_cursor_state_changed(_ => delivered += 1) |> ignore
  view_model.dispose()
  view_model.move_cursor_to(Position(1, 2), false) |> ignore
  assert_eq(delivered, 0)
}

///|
test "ViewModel exposes and retires ViewZones outgoing subscriptions" {
  let view_model = cursor_reference_view_model()
  let mut delivered = 0
  let mut kind_was_view_zones = false
  view_model.on_view_zones_changed(event => {
    kind_was_view_zones = event.kind == ViewZonesChanged
    delivered += 1
  })
  |> ignore
  view_model.emit_view_zones_changed()
  assert_eq(delivered, 1)
  assert_true(kind_was_view_zones)
  view_model.dispose()
  view_model.emit_view_zones_changed()
  assert_eq(delivered, 1)
}
