// Exact-label subset of
// vscode/src/vs/editor/test/browser/controller/cursor.test.ts
// in the checked-in source.
//
// This root-owned split covers public API/event/flush and pointer-command
// seams. Movement-only labels live in
// viewer/common/view_model/cursor_reference_wbtest.mbt.
//
// SKIPPED exact upstream label:
// `Double-click on punctuation should select the character, not adjacent space`
// — the `//` token-boundary assertion requires the separately deferred
// token-aware cursorWordOperations.ts owner (CMC-033/D6).

///|
fn cursor_reference_text() -> String {
  "    \tMy First Line\t \r\n\tMy Second Line\n    Third Line🐶\n\r\n1"
}

///|
fn reference_mouse_data(
  position : @base_common.Position,
  in_selection_mode~ : Bool = false,
  mouse_down_count~ : Int32 = 1,
  started_on_line_numbers~ : Bool = false,
  reveal_type~ : @controller.NavigationCommandRevealType = Minimal,
) -> @controller.MouseDispatchData {
  {
    position,
    mouse_column: position.column,
    reveal_type,
    mouse_down_count,
    in_selection_mode,
    started_on_line_numbers,
    alt_key: false,
    ctrl_key: false,
    meta_key: false,
    shift_key: in_selection_mode,
    middle_button: false,
    left_button: true,
    on_injected_text: false,
  }
}

///|
test "select all" {
  with_test_viewer(cursor_reference_text(), viewer => {
    viewer.run_select_all_core_command() |> ignore
    assert_cursor(viewer, Selection(Position(1, 1), Position(5, 2)))
    let state = viewer.test_cursor().model_state()
    assert_position(state.selection_start_start, Position(1, 1))
    assert_position(state.selection_start_end, Position(1, 1))
    assert_true(state.selection_start_kind == Simple)
    assert_eq(state.selection_start_leftover_visible_columns, 0)
    assert_position(state.position, Position(5, 2))
    assert_eq(state.leftover_visible_columns, 0)
  })
}

///|
test "no move doesn't trigger event" {
  with_test_viewer(cursor_reference_text(), viewer => {
    let mut events = 0
    viewer.test_view_model().on_cursor_state_changed(_ => events += 1) |> ignore
    viewer
    .test_view_model()
    .move_cursor_to(Position(1, 1), false, source="mouse", reason=Explicit)
    |> ignore
    assert_eq(events, 0)
  })
}

///|
test "move eventing" {
  with_test_viewer(cursor_reference_text(), viewer => {
    let events : Array[@view_model.CursorStateChangedEvent] = []
    viewer
    .test_view_model()
    .on_cursor_state_changed(event => events.push(event))
    |> ignore
    viewer
    .test_view_model()
    .move_cursor_to(Position(1, 2), false, source="mouse", reason=Explicit)
    |> ignore
    assert_eq(events.length(), 1)
    assert_selection_eq(
      events[0].selections[0],
      Selection(Position(1, 2), Position(1, 2)),
    )
  })
}

///|
test "move in selection mode eventing" {
  with_test_viewer(cursor_reference_text(), viewer => {
    let events : Array[@view_model.CursorStateChangedEvent] = []
    viewer
    .test_view_model()
    .on_cursor_state_changed(event => events.push(event))
    |> ignore
    viewer
    .test_view_model()
    .move_cursor_to(Position(1, 2), true, source="mouse", reason=Explicit)
    |> ignore
    assert_eq(events.length(), 1)
    assert_selection_eq(
      events[0].selections[0],
      Selection(Position(1, 1), Position(1, 2)),
    )
  })
}

///|
test "setSelection / setPosition with source" {
  with_test_viewer("Just text", viewer => {
    let sources : Array[String] = []
    viewer.on_did_change_cursor_position(event => sources.push(event.source))
    |> ignore
    viewer.set_selection(
      Selection(Position(1, 2), Position(1, 3)),
      source="navigation",
    )
    assert_eq(sources[sources.length() - 1], "navigation")
    viewer.set_position(Position(1, 2), source="navigation")
    assert_eq(sources[sources.length() - 1], "navigation")
  })
}

///|
test "issue #33788: Wrong cursor position when double click to select a word" {
  with_test_viewer("Just some text", viewer => {
    viewer.dispatch_mouse(
      reference_mouse_data(Position(1, 8), mouse_down_count=2),
    )
    assert_cursor(viewer, Selection(Position(1, 6), Position(1, 10)))
    viewer.dispatch_mouse(
      reference_mouse_data(
        Position(1, 8),
        in_selection_mode=true,
        mouse_down_count=2,
      ),
    )
    assert_cursor(viewer, Selection(Position(1, 6), Position(1, 10)))
  })
}

///|
test "issue #12887: Double-click highlighting separating white space" {
  with_test_viewer("abc def", viewer => {
    viewer.dispatch_mouse(
      reference_mouse_data(Position(1, 5), mouse_down_count=2),
    )
    assert_cursor(viewer, Selection(Position(1, 5), Position(1, 8)))
  })
}

///|
/// Adaptation note: the upstream case first switches the model to CRLF via
/// `setEOL`, then calls `setValue`. This readonly TextModel deliberately has
/// no `setEOL` mutation lane, so the exact-label port retains the scoped
/// `setValue`/ContentFlush cursor-reset assertion and omits only that
/// unavailable setup step.
test "issue #23983: Calling model.setValue() resets cursor position" {
  with_test_viewer("first line\nsecond line", viewer => {
    viewer.set_selection(Selection(Position(2, 2), Position(2, 2)))
    viewer.set_value(
      (
        #|different first line
        #|different second line
        #|new third line
      ),
    )
    assert_cursor(viewer, Selection(Position(1, 1), Position(1, 1)))
  })
}

///|
test "issue #7100: Mouse word selection is strange when non-word character is at the end of line" {
  with_test_viewer(
    (
      #|before.a
      #|before
      #|hello:
      #|there:
      #|this is strange:
      #|here
      #|it
      #|is
    ),
    viewer => {
      viewer.dispatch_mouse(
        reference_mouse_data(Position(3, 7), mouse_down_count=2),
      )
      assert_cursor(viewer, Selection(Position(3, 7), Position(3, 7)))
      viewer.dispatch_mouse(
        reference_mouse_data(
          Position(4, 7),
          in_selection_mode=true,
          mouse_down_count=2,
        ),
      )
      assert_cursor(viewer, Selection(Position(3, 7), Position(4, 7)))
    },
  )
}

///|
test "issue #112039: shift-continuing a double/triple-click and drag selection does not remember its starting mode" {
  with_test_viewer(
    (
      #|just some text
      #|and another line
      #|and another one
    ),
    viewer => {
      viewer.dispatch_mouse(
        reference_mouse_data(Position(2, 6), mouse_down_count=2),
      )
      viewer.dispatch_mouse(
        reference_mouse_data(Position(1, 8), in_selection_mode=true),
      )
      assert_cursor(viewer, Selection(Position(2, 12), Position(1, 6)))
    },
  )
}

///|
test "issue #158236: Shift click selection does not work on line number indicator" {
  with_test_viewer(
    (
      #|just some text
      #|and another line
      #|and another one
    ),
    viewer => {
      viewer.dispatch_mouse(reference_mouse_data(Position(3, 5)))
      viewer.dispatch_mouse(
        reference_mouse_data(
          Position(2, 1),
          in_selection_mode=true,
          started_on_line_numbers=true,
        ),
      )
      assert_cursor(viewer, Selection(Position(3, 5), Position(2, 1)))
    },
  )
}
