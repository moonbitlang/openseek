// Root command/input integration for the approved cursor parity child. Pure
// state, handled, and reveal facts stay headless; real KeyboardEvent default
// prevention remains in the browser layer owned by the parent task.

///|
fn dispatch_navigation_key(
  viewer : CodeEditorWidget,
  key : String,
  shift~ : Bool = false,
) -> Bool {
  viewer.handle_editor_key_down(key, alt=false, ctrl_cmd=false, shift~)
}

///|
fn mouse_dispatch_data(
  position : @base_common.Position,
  started_on_line_numbers~ : Bool = false,
  in_selection_mode~ : Bool = false,
  mouse_down_count~ : Int32 = 1,
  alt_key~ : Bool = false,
  ctrl_key~ : Bool = false,
  meta_key~ : Bool = false,
  shift_key~ : Bool = false,
  middle_button~ : Bool = false,
  on_injected_text~ : Bool = false,
  reveal_type~ : @controller.NavigationCommandRevealType = Minimal,
) -> @controller.MouseDispatchData {
  {
    position,
    mouse_column: position.column,
    reveal_type,
    started_on_line_numbers,
    in_selection_mode,
    mouse_down_count,
    alt_key,
    ctrl_key,
    meta_key,
    shift_key,
    left_button: !middle_button,
    middle_button,
    on_injected_text,
  }
}

///|
fn assert_last_cursor_transition(
  events : Array[@view_model.CursorStateChangedEvent],
  source : String,
) -> Unit raise {
  assert_true(events.length() > 0)
  let event = events[events.length() - 1]
  assert_eq(event.source, source)
  assert_true(event.reason == Explicit)
}

///|
fn reset_cursor_mouse_reveal(viewer : CodeEditorWidget) -> Unit {
  viewer.set_scroll_position(scroll_top=0.0, scroll_left=0.0)
  match viewer.current_code_browser_data() {
    Some(browser) => browser.clear_horizontal_reveal()
    None => ()
  }
}

///|
test "registered cursor keys move and extend the primary selection" {
  with_test_viewer(
    (
      #|  abc
      #|xy
      #|last
    ),
    viewer => {
      viewer.set_position(Position(2, 1))
      assert_true(dispatch_navigation_key(viewer, "ArrowLeft"))
      assert_position(viewer.get_position().unwrap(), Position(1, 6))

      viewer.set_position(Position(1, 6))
      assert_true(dispatch_navigation_key(viewer, "ArrowRight"))
      assert_position(viewer.get_position().unwrap(), Position(2, 1))

      viewer.set_position(Position(2, 2))
      assert_true(dispatch_navigation_key(viewer, "ArrowUp"))
      assert_position(viewer.get_position().unwrap(), Position(1, 2))
      viewer.set_position(Position(2, 2))
      assert_true(dispatch_navigation_key(viewer, "ArrowDown"))
      assert_position(viewer.get_position().unwrap(), Position(3, 2))

      viewer.set_position(Position(1, 5))
      assert_true(dispatch_navigation_key(viewer, "Home"))
      assert_position(viewer.get_position().unwrap(), Position(1, 3))
      viewer.set_position(Position(1, 5))
      assert_true(dispatch_navigation_key(viewer, "End"))
      assert_position(viewer.get_position().unwrap(), Position(1, 6))

      viewer.set_position(Position(1, 2))
      assert_true(dispatch_navigation_key(viewer, "ArrowRight", shift=true))
      assert_selection_eq(
        viewer.get_selection().unwrap(),
        Selection(Position(1, 2), Position(1, 3)),
      )
      viewer.set_position(Position(2, 2))
      assert_true(dispatch_navigation_key(viewer, "ArrowLeft", shift=true))
      assert_selection_eq(
        viewer.get_selection().unwrap(),
        Selection(Position(2, 2), Position(2, 1)),
      )
      viewer.set_position(Position(2, 2))
      assert_true(dispatch_navigation_key(viewer, "ArrowUp", shift=true))
      assert_selection_eq(
        viewer.get_selection().unwrap(),
        Selection(Position(2, 2), Position(1, 2)),
      )
      viewer.set_position(Position(2, 2))
      assert_true(dispatch_navigation_key(viewer, "ArrowDown", shift=true))
      assert_selection_eq(
        viewer.get_selection().unwrap(),
        Selection(Position(2, 2), Position(3, 2)),
      )
      viewer.set_position(Position(1, 5))
      assert_true(dispatch_navigation_key(viewer, "Home", shift=true))
      assert_selection_eq(
        viewer.get_selection().unwrap(),
        Selection(Position(1, 5), Position(1, 3)),
      )
      viewer.set_position(Position(1, 5))
      assert_true(dispatch_navigation_key(viewer, "End", shift=true))
      assert_selection_eq(
        viewer.get_selection().unwrap(),
        Selection(Position(1, 5), Position(1, 6)),
      )
    },
  )
}

///|
test "page commands use configured fallback for marker omitted and exact zero" {
  with_test_viewer(long_document(30), viewer => {
    // floor(180 / 18) - 2 = 8 source page lines.
    viewer.test_set_viewport(width=800.0, height=180.0)
    viewer.set_position(Position(10, 1))
    assert_true(dispatch_navigation_key(viewer, "PageUp"))
    assert_position(viewer.get_position().unwrap(), Position(2, 1))

    viewer.set_position(Position(10, 1))
    assert_true(dispatch_navigation_key(viewer, "PageDown"))
    assert_position(viewer.get_position().unwrap(), Position(18, 1))

    viewer.set_position(Position(10, 1))
    viewer.run_cursor_page(Down, false, page_size=0) |> ignore
    assert_position(viewer.get_position().unwrap(), Position(18, 1))

    viewer.set_position(Position(10, 1))
    viewer.run_cursor_page(Down, false, page_size=-1) |> ignore
    assert_position(viewer.get_position().unwrap(), Position(18, 1))

    viewer.set_position(Position(10, 1))
    viewer.run_cursor_page(Down, false, page_size=3) |> ignore
    assert_position(viewer.get_position().unwrap(), Position(13, 1))

    viewer.set_position(Position(10, 1))
    assert_true(dispatch_navigation_key(viewer, "PageUp", shift=true))
    assert_selection_eq(
      viewer.get_selection().unwrap(),
      Selection(Position(10, 1), Position(2, 1)),
    )

    viewer.set_position(Position(10, 1))
    assert_true(dispatch_navigation_key(viewer, "PageDown", shift=true))
    assert_selection_eq(
      viewer.get_selection().unwrap(),
      Selection(Position(10, 1), Position(18, 1)),
    )
  })
}

///|
test "cursor command wins at a hard boundary and reveals its result" {
  with_test_viewer(long_document(8), viewer => {
    viewer.test_set_viewport(width=800.0, height=18.0)
    viewer.set_position(Position(1, 1))
    assert_true(dispatch_navigation_key(viewer, "ArrowLeft"))
    assert_position(viewer.get_position().unwrap(), Position(1, 1))

    assert_true(dispatch_navigation_key(viewer, "ArrowDown"))
    assert_position(viewer.get_position().unwrap(), Position(2, 1))
    assert_true(
      viewer.test_view_model().view_layout.position().scroll_top > 0.0,
    )
  })
}

///|
test "cursor key precondition and exact chords fall through when unmatched" {
  let viewer = CodeEditorWidget::CodeEditorWidget()
  assert_false(dispatch_navigation_key(viewer, "ArrowLeft"))
  viewer.set_model(Some(test_model("abc")))
  assert_false(
    viewer.handle_editor_key_down(
      "ArrowLeft",
      alt=true,
      ctrl_cmd=false,
      shift=false,
    ),
  )
  assert_false(
    viewer.handle_editor_key_down(
      "ArrowLeft",
      alt=false,
      ctrl_cmd=true,
      shift=false,
    ),
  )
  assert_false(dispatch_navigation_key(viewer, "F1"))
  viewer.dispose()
}

///|
test "live single-cursor mouse branches use the shared transition spine" {
  with_test_viewer(
    (
      #|alpha beta!
      #|second line
      #|third
    ),
    viewer => {
      let events : Array[@view_model.CursorStateChangedEvent] = []
      viewer
      .test_view_model()
      .on_cursor_state_changed(event => events.push(event))
      |> ignore

      // Ordinary click and drag.
      viewer.dispatch_mouse(mouse_dispatch_data(Position(1, 3)))
      assert_cursor(viewer, Selection(Position(1, 3), Position(1, 3)))
      assert_last_cursor_transition(events, "mouse")
      viewer.dispatch_mouse(
        mouse_dispatch_data(Position(1, 6), in_selection_mode=true),
      )
      assert_cursor(viewer, Selection(Position(1, 3), Position(1, 6)))
      assert_last_cursor_transition(events, "mouse")

      // Double click and its word-granularity drag continuation.
      viewer.dispatch_mouse(
        mouse_dispatch_data(Position(1, 8), mouse_down_count=2),
      )
      assert_cursor(viewer, Selection(Position(1, 7), Position(1, 11)))
      assert_last_cursor_transition(events, "mouse")
      viewer.dispatch_mouse(
        mouse_dispatch_data(
          Position(1, 2),
          in_selection_mode=true,
          mouse_down_count=2,
        ),
      )
      assert_cursor(viewer, Selection(Position(1, 11), Position(1, 1)))
      assert_last_cursor_transition(events, "mouse")

      // Triple click and its whole-line drag continuation.
      viewer.dispatch_mouse(
        mouse_dispatch_data(Position(2, 4), mouse_down_count=3),
      )
      assert_cursor(viewer, Selection(Position(2, 1), Position(3, 1)))
      assert_last_cursor_transition(events, "mouse")
      viewer.dispatch_mouse(
        mouse_dispatch_data(
          Position(1, 4),
          in_selection_mode=true,
          mouse_down_count=3,
        ),
      )
      assert_cursor(viewer, Selection(Position(3, 1), Position(1, 1)))
      assert_last_cursor_transition(events, "mouse")

      // Gutter click/drag takes the same live whole-line paths.
      viewer.dispatch_mouse(
        mouse_dispatch_data(Position(1, 4), started_on_line_numbers=true),
      )
      assert_cursor(viewer, Selection(Position(1, 1), Position(2, 1)))
      assert_last_cursor_transition(events, "mouse")
      viewer.dispatch_mouse(
        mouse_dispatch_data(
          Position(2, 3),
          started_on_line_numbers=true,
          in_selection_mode=true,
        ),
      )
      assert_cursor(viewer, Selection(Position(1, 1), Position(3, 1)))
      assert_last_cursor_transition(events, "mouse")

      // Four or more clicks route SelectAll through its source-shaped keyboard
      // command body even though the caller is pointer dispatch.
      viewer.dispatch_mouse(
        mouse_dispatch_data(Position(2, 2), mouse_down_count=4),
      )
      assert_cursor(viewer, Selection(Position(1, 1), Position(3, 6)))
      assert_last_cursor_transition(events, "keyboard")
      viewer.dispatch_mouse(
        mouse_dispatch_data(Position(2, 2), mouse_down_count=5),
      )
      // Repeating SelectAll is an exact-state no-op.
      assert_eq(events.length(), 9)

      // `_validateViewColumn` clamps a below-minimum pointer column before the
      // ordinary MoveTo adapter commits its view state.
      viewer.dispatch_mouse(mouse_dispatch_data(Position(1, 0)))
      assert_cursor(viewer, Selection(Position(1, 1), Position(1, 1)))
      assert_position(
        viewer.test_cursor().get_view_selection().get_position(),
        Position(1, 1),
      )
      assert_last_cursor_transition(events, "mouse")
    },
  )
}

///|
test "deferred mouse branches remain exact no-ops" {
  with_test_viewer("alpha beta\nsecond", viewer => {
    viewer.set_position(Position(1, 4))
    let events : Array[@view_model.CursorStateChangedEvent] = []
    viewer
    .test_view_model()
    .on_cursor_state_changed(event => events.push(event))
    |> ignore
    let deferred = [
      mouse_dispatch_data(Position(2, 2), middle_button=true),
      mouse_dispatch_data(
        Position(2, 2),
        started_on_line_numbers=true,
        alt_key=true,
      ),
      mouse_dispatch_data(Position(2, 2), mouse_down_count=3, alt_key=true),
      mouse_dispatch_data(
        Position(2, 2),
        mouse_down_count=2,
        on_injected_text=true,
      ),
      mouse_dispatch_data(Position(2, 2), mouse_down_count=2, alt_key=true),
      mouse_dispatch_data(Position(2, 2), alt_key=true),
      mouse_dispatch_data(
        Position(2, 2),
        in_selection_mode=true,
        alt_key=true,
        shift_key=true,
      ),
    ]
    for data in deferred {
      viewer.dispatch_mouse(data)
      assert_cursor(viewer, Selection(Position(1, 4), Position(1, 4)))
      assert_eq(events.length(), 0)
    }
  })
}

///|
test "mouse navigation reveal types preserve command-specific gates" {
  with_test_viewer(long_document(40), viewer => {
    viewer.test_set_viewport(width=800.0, height=180.0)

    // Pointer commands reveal after either Regular or Minimal passes the
    // command's None gate. Line 10 ends exactly at the viewport edge and stays
    // at scrollTop 0; keyboard reveal below retains the extra bottom line.
    viewer.dispatch_mouse(
      mouse_dispatch_data(Position(10, 1), reveal_type=Regular),
    )
    assert_eq(viewer.test_view_model().view_layout.position().scroll_top, 0.0)
    reset_cursor_mouse_reveal(viewer)
    viewer.set_position(Position(9, 1))
    assert_true(dispatch_navigation_key(viewer, "ArrowDown"))
    assert_eq(viewer.test_view_model().view_layout.position().scroll_top, 18.0)
    reset_cursor_mouse_reveal(viewer)

    // MoveTo reveals only after a changed state, and None suppresses both
    // vertical and horizontal reveal.
    viewer.dispatch_mouse(
      mouse_dispatch_data(Position(30, 1), reveal_type=None),
    )
    assert_eq(viewer.test_view_model().view_layout.position().scroll_top, 0.0)
    viewer.dispatch_mouse(
      mouse_dispatch_data(Position(31, 1), reveal_type=Regular),
    )
    assert_true(
      viewer.test_view_model().view_layout.position().scroll_top > 0.0,
    )
    reset_cursor_mouse_reveal(viewer)
    viewer.dispatch_mouse(
      mouse_dispatch_data(Position(31, 1), reveal_type=Minimal),
    )
    assert_eq(viewer.test_view_model().view_layout.position().scroll_top, 0.0)

    // Word commands reveal even when replaying an identical selection; their
    // reveal includes the horizontal axis. None remains an exact no-op.
    viewer.dispatch_mouse(
      mouse_dispatch_data(
        Position(30, 3),
        mouse_down_count=2,
        reveal_type=Minimal,
      ),
    )
    reset_cursor_mouse_reveal(viewer)
    viewer.dispatch_mouse(
      mouse_dispatch_data(
        Position(30, 3),
        mouse_down_count=2,
        reveal_type=Minimal,
      ),
    )
    assert_true(
      viewer.test_view_model().view_layout.position().scroll_top > 0.0,
    )
    reset_cursor_mouse_reveal(viewer)
    viewer.dispatch_mouse(
      mouse_dispatch_data(Position(30, 3), mouse_down_count=2, reveal_type=None),
    )
    assert_eq(viewer.test_view_model().view_layout.position().scroll_top, 0.0)

    // Line commands also reveal after an identical selection, but vertically
    // only. SelectAll intentionally performs no reveal at all.
    viewer.dispatch_mouse(
      mouse_dispatch_data(
        Position(30, 3),
        mouse_down_count=3,
        reveal_type=Minimal,
      ),
    )
    reset_cursor_mouse_reveal(viewer)
    viewer.dispatch_mouse(
      mouse_dispatch_data(
        Position(30, 3),
        mouse_down_count=3,
        reveal_type=Regular,
      ),
    )
    assert_true(
      viewer.test_view_model().view_layout.position().scroll_top > 0.0,
    )
    reset_cursor_mouse_reveal(viewer)
    viewer.dispatch_mouse(
      mouse_dispatch_data(Position(30, 3), mouse_down_count=3, reveal_type=None),
    )
    assert_eq(viewer.test_view_model().view_layout.position().scroll_top, 0.0)
    viewer.dispatch_mouse(
      mouse_dispatch_data(
        Position(30, 3),
        mouse_down_count=4,
        reveal_type=Minimal,
      ),
    )
    assert_eq(viewer.test_view_model().view_layout.position().scroll_top, 0.0)
  })
}

///|
test "cursor Smooth reveal downgrades an exact one-line vertical delta" {
  assert_false(cursor_reveal_should_smooth(Smooth, 0.0, 18))
  assert_false(cursor_reveal_should_smooth(Smooth, 18.0, 18))
  assert_true(cursor_reveal_should_smooth(Smooth, 18.1, 18))
  assert_false(cursor_reveal_should_smooth(Immediate, 180.0, 18))
}

///|
test "line drag keeps wrapped injected-text view position authoritative" {
  let options = CodeEditorOptions(soft_wrap=true)
  with_test_viewer(
    (
      #|a
      #|abcdef
      #|last
    ),
    viewer => {
      viewer.test_set_soft_wrap_column(5)
      install_cursor_test_injected_text(viewer, Position(2, 4), "X")
      let view_model = viewer.test_view_model()
      let converter = view_model.coordinates_converter()
      let target_view = converter.model_position_to_view_position(
        Position(2, 2),
      )
      let next_view = @base_common.Position(target_view.line_number + 1, 1)
      assert_eq(
        converter.view_position_to_model_position(next_view).line_number,
        2,
      )

      // Establish a whole-line anchor on model line 1, then drag forward on
      // model line 2. The Line algorithm advances one *view* line; the old
      // model-space reconstruction jumped to model line 3 instead.
      viewer.dispatch_mouse(
        mouse_dispatch_data(
          Position(1, 1),
          mouse_down_count=3,
          reveal_type=None,
        ),
      )
      viewer.dispatch_mouse(
        mouse_dispatch_data(
          target_view,
          in_selection_mode=true,
          mouse_down_count=3,
          reveal_type=None,
        ),
      )
      let forward = viewer.test_cursor().get_primary_cursor_state()
      assert_position(forward.view_state.position, next_view)
      assert_eq(forward.model_state.position.line_number, 2)

      // Re-entering the anchor line exercises the equal branch and restores
      // the anchor range's far model edge.
      viewer.dispatch_mouse(
        mouse_dispatch_data(
          Position(1, 1),
          in_selection_mode=true,
          mouse_down_count=3,
          reveal_type=None,
        ),
      )
      let equal = viewer.test_cursor().get_primary_cursor_state()
      assert_position(equal.model_state.position, Position(2, 1))
      assert_true(equal.model_state.selection_start_kind == Line)
    },
    options~,
  )
}

///|
test "dollar punctuation keeps its one-unit word anchor through continuation" {
  with_test_viewer("foo $ bar", viewer => {
    viewer.dispatch_mouse(
      mouse_dispatch_data(Position(1, 5), mouse_down_count=2, reveal_type=None),
    )
    assert_cursor(viewer, Selection(Position(1, 5), Position(1, 6)))
    let anchor = viewer.test_cursor().model_state()
    assert_position(anchor.selection_start_start, Position(1, 5))
    assert_position(anchor.selection_start_end, Position(1, 6))
    assert_true(anchor.selection_start_kind == Word)

    // A later Shift-style pointer continuation (single-click count) dispatches
    // through the stored Word anchor and starts at the punctuation's near edge.
    viewer.dispatch_mouse(
      mouse_dispatch_data(
        Position(1, 8),
        in_selection_mode=true,
        reveal_type=None,
      ),
    )
    assert_cursor(viewer, Selection(Position(1, 5), Position(1, 10)))

    // Backward continuation uses the punctuation anchor's far edge, keeping
    // the entire one-code-unit separator inside the selection.
    viewer.dispatch_mouse(
      mouse_dispatch_data(
        Position(1, 2),
        in_selection_mode=true,
        reveal_type=None,
      ),
    )
    assert_cursor(viewer, Selection(Position(1, 6), Position(1, 1)))
  })
}

///|
test "shift gutter forward from Simple uses line continuation" {
  with_test_viewer(
    (
      #|one
      #|two
      #|three
    ),
    viewer => {
      viewer.set_position(Position(1, 2))
      assert_true(
        viewer.test_cursor().model_state().selection_start_kind == Simple,
      )
      viewer.dispatch_mouse(
        mouse_dispatch_data(
          Position(2, 2),
          started_on_line_numbers=true,
          in_selection_mode=true,
          reveal_type=None,
        ),
      )
      let state = viewer.test_cursor().get_primary_cursor_state()
      assert_position(state.view_state.position, Position(3, 1))
      assert_position(state.model_state.position, Position(3, 1))
      assert_true(state.model_state.selection_start_kind == Simple)
      assert_cursor(viewer, Selection(Position(1, 2), Position(3, 1)))
    },
  )
}

///|
fn install_cursor_test_injected_text(
  viewer : CodeEditorWidget,
  position : @base_common.Position,
  content : String,
) -> Unit {
  let model = viewer.get_model().unwrap()
  model.delta_decorations([], [
    {
      range: @base_common.Range::from_positions(position, position),
      options: ModelDecorationOptions(
        "",
        description="cursor injected-text fixture",
        show_if_collapsed=true,
        after=InjectedTextOptions(content),
      ),
    },
  ])
  |> ignore
}
