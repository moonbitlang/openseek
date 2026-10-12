///| The ViewModel flush branch of the `set_value` port (plan
/// `monaco-set-value-api-port.md`, Tracks B/C): a `TextModel::set_value`
/// reaches every registered view model through the model's two-loop
/// dispatch, reprojects the lines, flushes the layout (scroll clamps
/// instead of resetting), resets the cursor to the origin, and resets
/// hidden areas — while the injected-text reproject keeps them.

///|
test "flush reprojects the view lines to the new content (no wrap)" {
  let model = plain_text_model("one\ntwo")
  let view_model = @view_model.ViewModel(model)
  assert_eq(view_model.line_count(), 2)
  model.set_value(
    (
      #|a
      #|b
      #|c
      #|d
    ),
  )
  assert_eq(view_model.line_count(), 4)
  assert_eq(view_model.get_line_content(3), "c")
}

///|
test "flush reprojects wrapped lines against the new content" {
  let model = plain_text_model("aaaa bbbb cccc")
  let view_model = @view_model.ViewModel::with_options(
    model,
    @view_model.ViewModelOptions::soft_wrap(5),
  )
  assert_true(view_model.line_count() > 1)
  model.set_value("dd")
  assert_eq(view_model.line_count(), 1)
  assert_eq(view_model.get_line_content(1), "dd")
}

///|
test "public content listeners observe already-updated view models (two-loop order)" {
  let model = plain_text_model("one\ntwo")
  let vm1 = @view_model.ViewModel(model)
  let vm2 = @view_model.ViewModel(model)
  let observed : Array[Int32] = []
  let _sub = model.on_did_change_content(e => {
    observed.push(vm1.line_count())
    observed.push(vm2.line_count())
    observed.push(e.version_id)
  })
  model.set_value(
    (
      #|a
      #|b
      #|c
    ),
  )
  assert_true(observed == [3, 3, 2])
}

///|
test "headless flush suppresses full-reset token notification" {
  let model = plain_text_model("old")
  let view_model = @view_model.ViewModel(model)
  let mut token_events = 0
  let _sub = model.on_did_change_tokens(_event => token_events += 1)

  model.set_value(
    (
      #|a
      #|b
      #|c
      #|d
    ),
  )

  // `reset_tokenization(false)` suppresses the full reset event. With no
  // attached visible ranges there is no bounded refresh event either.
  assert_eq(token_events, 0)
  // The normal content first-loop still rebuilds the projection.
  assert_true(
    view_model
    .coordinates_converter()
    .model_position_to_view_position(Position(4, 2)) ==
    Position(4, 2),
  )
}

///|
test "flush resets the cursor to the origin (cursor.ts ContentFlush branch)" {
  let model = plain_text_model(
    (
      #|one
      #|two
      #|three
    ),
  )
  let view_model = @view_model.ViewModel(model)
  view_model.set_cursor_state(
    Some(
      @cursor.CursorState::from_model_selection(
        Selection(Position(3, 4), Position(3, 4)),
      ),
    ),
    "test",
    Explicit,
  )
  |> ignore
  assert_true(
    view_model.cursor.get_view_selection().get_position() == Position(3, 4),
  )
  model.set_value("a\nb")
  let selection = view_model.cursor.get_view_selection()
  assert_true(selection.is_empty())
  assert_true(selection.get_position() == Position(1, 1))
}

///|
test "flush clamps the scroll position instead of resetting it" {
  let long_lines = StringBuilder()
  for index in 0..<40 {
    if index > 0 {
      long_lines.write_char('\n')
    }
    long_lines <+ "line_\{index}"
  }
  let model = plain_text_model(long_lines.to_string())
  let view_model = @view_model.ViewModel(model)
  let layout = view_model.view_layout
  layout.set_viewport_size(width=400.0, height=100.0) |> ignore
  layout.scroll_to(scroll_top=100000.0, scroll_left=0.0) |> ignore
  assert_true(layout.get_current_scroll_top() > 0.0)
  model.set_value(
    (
      #|a
      #|b
      #|c
      #|d
      #|e
      #|f
      #|g
      #|h
      #|i
      #|j
    ),
  )
  assert_eq(layout.line_count(), 10)
  // clamped to the shrunken extent — not reset to the origin (the reset is
  // `set_model`'s behavior)
  assert_true(layout.get_current_scroll_top() > 0.0)
  assert_eq(layout.get_current_scroll_top(), layout.get_scroll_height() - 100.0)
}

///|
test "flush resets hidden areas; the injected-text reproject keeps them" {
  let model = plain_text_model(
    (
      #|a
      #|b
      #|c
      #|d
      #|e
    ),
  )
  let view_model = @view_model.ViewModel(model)
  let lines = view_model.lines()
  assert_true(lines.set_hidden_areas([Range(2, 1, 3, 1)]))
  assert_eq(view_model.line_count(), 3)
  // the injected-text form (whole reproject) keeps folded regions
  view_model.on_did_change_content_or_injected_text()
  assert_eq(view_model.line_count(), 3)
  // a flush replaces the document: `onModelFlushed` resets hidden areas
  model.set_value(
    (
      #|a
      #|b
      #|c
      #|d
      #|e
    ),
  )
  assert_eq(view_model.line_count(), 5)
  assert_eq(lines.get_hidden_areas().length(), 0)
}

///|
test "converter round-trips against the post-flush projections" {
  let model = plain_text_model("one\ntwo")
  let view_model = @view_model.ViewModel(model)
  model.set_value(
    (
      #|alpha
      #|bravo
      #|charlie
    ),
  )
  let converter = view_model.coordinates_converter()
  let position = @base_common.Position(3, 4)
  assert_true(converter.model_position_to_view_position(position) == position)
  assert_true(converter.view_position_to_model_position(position) == position)
}

///|
test "dispose unregisters the view model from the model's dispatch set" {
  let model = plain_text_model("one")
  let view_model = @view_model.ViewModel(model)
  model.set_value("a\nb")
  assert_eq(view_model.line_count(), 2)
  view_model.dispose()
  model.set_value(
    (
      #|a
      #|b
      #|c
    ),
  )
  // no longer registered: the stale projection stays at the old count
  assert_eq(view_model.line_count(), 2)
}
