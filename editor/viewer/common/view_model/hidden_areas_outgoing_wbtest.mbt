///|
fn hidden_outgoing_fixture() -> (@model.TextModel, ViewModel) {
  let model = cursor_reference_model(
    (
      #|one
      #|two
      #|three
      #|four
      #|five
      #|six
      #|seven
      #|eight
    ),
  )
  (model, ViewModel(model))
}

///|
test "hidden-area outgoing fires after mapping cursor layout and recovery" {
  let (model, view_model) = hidden_outgoing_fixture()
  defer model.dispose()
  defer view_model.dispose()
  let layout = view_model.view_layout
  layout.set_viewport_size(width=400.0, height=18.0) |> ignore
  view_model.move_cursor_to_model_position(Position(4, 2), false) |> ignore
  let old_top = layout.get_vertical_offset_for_line_number(4) + 7.0
  layout.scroll_to(scroll_top=old_top) |> ignore

  let order : Array[String] = []
  let scroll_subscription = layout.on_did_scroll(_change => order.push("scroll"))
  defer scroll_subscription.dispose()
  let mut state_was_committed = false
  let outgoing_subscription = view_model.on_hidden_areas_changed(event => {
    order.push("outgoing")
    state_was_committed = event.kind == HiddenAreasChanged &&
      view_model.line_count() == 6 &&
      layout.line_count() == 6 &&
      view_model.cursor.model_state().position == Position(4, 2) &&
      view_model.cursor.view_state().position == Position(2, 2) &&
      layout.get_current_scroll_top() ==
      layout.get_vertical_offset_for_line_number(2) + 7.0
  })
  defer outgoing_subscription.dispose()

  assert_true(
    view_model.set_hidden_areas([Range(2, 1, 3, 1)], on_line_mapping_changed=reproject_cursor => {
      order.push("mapping")
      reproject_cursor()
      order.push("cursor")
    }),
  )
  assert_true(order == ["mapping", "cursor", "scroll", "scroll", "outgoing"])
  assert_true(state_was_committed)
}

///|
test "hidden outgoing skips forced-same but reports all-hidden fallback" {
  let (model, view_model) = hidden_outgoing_fixture()
  defer model.dispose()
  defer view_model.dispose()
  let mut delivered = 0
  view_model.on_hidden_areas_changed(_ => delivered += 1) |> ignore

  assert_true(view_model.set_hidden_areas([Range(2, 1, 3, 1)]))
  assert_eq(delivered, 1)
  assert_false(view_model.set_hidden_areas([Range(2, 1, 3, 1)]))
  assert_false(
    view_model.set_hidden_areas([Range(2, 1, 3, 1)], force_update=true),
  )
  assert_eq(delivered, 1)

  let (all_hidden_model, all_hidden) = hidden_outgoing_fixture()
  defer all_hidden_model.dispose()
  defer all_hidden.dispose()
  let mut all_hidden_delivered = 0
  all_hidden.on_hidden_areas_changed(_ => all_hidden_delivered += 1) |> ignore
  all_hidden.set_hidden_areas([Range(1, 1, 8, 1)]) |> ignore
  assert_eq(all_hidden.line_count(), 8)
  assert_eq(all_hidden.get_hidden_areas().length(), 0)
  // The projected-line recursion reveals everything, but still reports the
  // attempted mapping as changed, so the source emits exactly one fact.
  assert_eq(all_hidden_delivered, 1)
}

///|
test "hidden dispatcher merges same-kind facts into their first queue slot" {
  let first = HiddenAreasChangedOutgoingEvent()
  let second = HiddenAreasChangedOutgoingEvent()
  assert_true(first.kind == HiddenAreasChanged)
  assert_false(first.is_no_op())
  guard first.attempt_to_merge(HiddenAreasEvent(second)) is Some(merged) else {
    fail("same-kind hidden-area facts must merge")
  }
  assert_true(physical_equal(merged, first))
  assert_true(
    first.attempt_to_merge(ViewZonesEvent(ViewZonesChangedEvent())) is None,
  )

  let dispatcher = CursorEventDispatcher::CursorEventDispatcher()
  defer dispatcher.dispose()
  let mut delivered = 0
  dispatcher.on_hidden_areas_changed(_ => delivered += 1) |> ignore
  dispatcher.add_outgoing_event(HiddenAreasEvent(first))
  dispatcher.add_outgoing_event(HiddenAreasEvent(second))
  assert_eq(dispatcher.outgoing_events.length(), 1)
  guard dispatcher.outgoing_events[0] is HiddenAreasEvent(retained) else {
    fail("the hidden-area fact must retain its first same-kind queue slot")
  }
  assert_true(physical_equal(retained, first))
  dispatcher.emit_outgoing_events()
  assert_eq(delivered, 1)
}

///|
test "hidden dispatcher reentrancy finishes siblings before nested delivery" {
  let dispatcher = CursorEventDispatcher::CursorEventDispatcher()
  defer dispatcher.dispose()
  let order : Array[String] = []
  let mut first_calls = 0
  let mut second_calls = 0
  dispatcher.on_hidden_areas_changed(_event => {
    first_calls += 1
    let call = first_calls
    order.push("first:\{call}:before")
    if call == 1 {
      dispatcher.emit_hidden_areas_changed(HiddenAreasChangedOutgoingEvent())
    }
    order.push("first:\{call}:after")
  })
  |> ignore
  dispatcher.on_hidden_areas_changed(_event => {
    second_calls += 1
    order.push("second:\{second_calls}")
  })
  |> ignore

  dispatcher.emit_hidden_areas_changed(HiddenAreasChangedOutgoingEvent())
  assert_true(
    order ==
    [
      "first:1:before", "second:1", "first:2:before", "first:2:after", "second:2",
      "first:1:after",
    ],
  )
}
