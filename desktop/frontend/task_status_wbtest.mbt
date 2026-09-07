///|
test "Codex outcomes remain unread while the editor covers the transcript" {
  let dispatch = test_dispatch()
  let context : @codex.SidebarContext = {
    channel: Local,
    selected: true,
    registered_projects: ["/workspace"],
  }
  for
    outcome in [
      ("completed", @conversation.CompletedMark),
      ("failed", @conversation.FailedMark),
    ] {
    let (wire_status, expected) = outcome
    for layout in [(false, true), (true, false), (true, true)] {
      let (narrow, expanded) = layout
      let model = {
        ..test_model(),
        screen: Codex,
        window_focused: true,
        narrow,
        right_panel_open: true,
        right_panel_expanded: expanded,
        codex: @codex.State::from_thread_snapshot({
          "thread": {
            "id": "task-a",
            "cwd": "/workspace",
            "projectRoot": "/workspace",
            "status": { "type": "active" },
            "turns": [{ "id": "turn-a", "status": "inProgress", "items": [] }],
          },
        }),
      }
      let (_, completed) = update(
        dispatch,
        Codex(
          channel=Local,
          @codex.Msg::notification(
            "turn/completed",
            {
              "threadId": "task-a",
              "turn": { "id": "turn-a", "status": wire_status, "items": [] },
            },
            1,
          ),
        ),
        model,
      )
      let rows = completed.codex.project_conversations(context, "/workspace")
      assert_eq(rows[0].input.run_mark, expected)
      if !narrow || !expanded {
        let reveal = if expanded {
          ToggleRightPanelExpanded
        } else {
          ViewportResized(width=1280)
        }
        let (_, restored) = update(dispatch, reveal, completed)
        let rows = restored.codex.project_conversations(context, "/workspace")
        assert_true(rows[0].input.run_mark is @conversation.NoRunMark)
      }
      let (_, revealed) = update(dispatch, ToggleRightPanel, completed)
      let rows = revealed.codex.project_conversations(context, "/workspace")
      assert_true(rows[0].input.run_mark is @conversation.NoRunMark)
    }
  }
}

///|
test "Codex outcomes are read when the transcript remains visible beside the editor" {
  let model = {
    ..test_model(),
    screen: Codex,
    window_focused: true,
    narrow: false,
    right_panel_open: true,
    right_panel_expanded: false,
    codex: @codex.State::from_thread_snapshot({
      "thread": {
        "id": "task-a",
        "cwd": "/workspace",
        "projectRoot": "/workspace",
        "status": { "type": "active" },
        "turns": [{ "id": "turn-a", "status": "inProgress", "items": [] }],
      },
    }),
  }
  let (_, completed) = update(
    test_dispatch(),
    Codex(
      channel=Local,
      @codex.Msg::notification(
        "turn/completed",
        {
          "threadId": "task-a",
          "turn": { "id": "turn-a", "status": "completed", "items": [] },
        },
        1,
      ),
    ),
    model,
  )
  let rows = completed.codex.project_conversations(
    { channel: Local, selected: true, registered_projects: ["/workspace"], },
    "/workspace",
  )
  assert_true(rows[0].input.run_mark is @conversation.NoRunMark)
}

///|
test "OpenSeek outcomes remain unread while the editor covers the transcript" {
  let dispatch = test_dispatch()
  for layout in [(false, true), (true, false), (true, true)] {
    let (narrow, expanded) = layout
    let model = {
      ..running_model(),
      window_focused: true,
      narrow,
      right_panel_open: true,
      right_panel_expanded: expanded,
    }
    let (_, completed) = update_dev(
      dispatch,
      Finished(run_id="r7", status="finished", answer=Some("done")),
      model,
    )
    assert_true(
      session_component_input(completed, Local, "desktop-test", "Task A").run_mark
      is @conversation.CompletedMark,
    )
    let (_, revealed) = update(dispatch, ToggleRightPanel, completed)
    assert_true(
      session_component_input(revealed, Local, "desktop-test", "Task A").run_mark
      is @conversation.NoRunMark,
    )
  }
}
