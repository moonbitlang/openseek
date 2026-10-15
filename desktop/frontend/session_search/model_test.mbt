///|
test "search transitions are pure and stale replies cannot reopen or replace results" {
  let emit : @cmd.Emit[@session_search.Msg] = @cmd.Emit(_ => @cmd.none)
  let initial = @session_search.Model()
  let (_, opened, _) = initial.update(emit, Open(Local))
  let (_, opened_again, _) = initial.update(emit, Open(Local))
  assert_true(opened == opened_again)
  assert_false(initial.is_open())
  assert_true(opened.is_open())
  let (_, typed, _) = opened.update(emit, Changed("query"))
  let (_, typed_again, _) = opened.update(emit, Changed("query"))
  assert_true(typed == typed_again)
  let (_, waiting, _) = typed.update(emit, Due(1))
  assert_true(waiting == typed)
  let (_, loading, _) = typed.update(emit, Due(2))
  let (_, loading_again, _) = typed.update(emit, Due(2))
  assert_true(loading == loading_again)
  let reply : @protocol.SessionSearchReply = {
    hits: [
      {
        session: "found",
        workspace: "/project",
        title: "Title",
        archived: false,
        updated_at_ms: None,
      },
    ],
    errors: [],
    has_more: false,
  }
  let (_, ready, _) = loading.update(emit, Loaded(2, Ok(reply)))
  let (_, ready_again, _) = loading.update(emit, Loaded(2, Ok(reply)))
  assert_true(ready == ready_again)
  let (_, moved, _) = ready.update(emit, Move(1))
  let (_, moved_again, _) = ready.update(emit, Move(1))
  assert_true(moved == moved_again)
  let (_, selected, selection) = ready.update(emit, Pick(0))
  assert_false(selected.is_open())
  assert_true(
    selection is Some({ channel: Local, hit: { session: "found", .. }, }),
  )
  let (_, changed, _) = loading.update(emit, Changed("new query"))
  let (_, stale, _) = changed.update(emit, Loaded(2, Ok(reply)))
  assert_true(stale == changed)
  let (_, closed, _) = loading.update(emit, Close)
  let (_, late, _) = closed.update(emit, Loaded(2, Ok(reply)))
  assert_true(late == closed)
  let (_, toggled, _) = ready.update(emit, ToggleArchived)
  let (_, toggled_again, _) = ready.update(emit, ToggleArchived)
  assert_true(toggled == toggled_again)
  let (_, cleared, _) = ready.update(emit, Changed("  "))
  let (_, ignored, selection) = cleared.update(emit, Pick(0))
  assert_true(cleared == ignored)
  assert_true(selection is None)
}
