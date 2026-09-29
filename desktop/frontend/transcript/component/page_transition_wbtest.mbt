///|
test "page buttons move the navigation before replacing mounted content" {
  let input = paged_input(60)
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let initial = pinned_model(input)
  let (moving, _) = initial.update(input, Overview(PreviousPage), emit)
  assert_eq(moving.page, None)
  assert_eq(moving.navigation_page(TurnIndex::new(input.items)).index, 1)
  assert_true(moving.navigation is Some({ rendering: false, .. }))
  assert_false(moving.pinned)
  let (rendering, _) = moving.update(
    input,
    MountPage(moving.navigation_generation),
    emit,
  )
  assert_eq(rendering.page, Some(1))
  assert_true(rendering.navigation is Some({ rendering: true, .. }))
  let (ready, _) = rendering.update(
    input,
    PageReady(moving.navigation_generation),
    emit,
  )
  assert_eq(ready.page, Some(1))
  assert_true(ready.navigation is None)
}

///|
test "rapid navigation keeps the last requested page and ignores stale completions" {
  let input = paged_input(60)
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (first, _) = pinned_model(input).update(
    input,
    Overview(PreviousPage),
    emit,
  )
  let (last, _) = first.update(input, Overview(PreviousPage), emit)
  assert_eq(last.navigation_page(TurnIndex::new(input.items)).index, 0)
  let (stale, _) = last.update(
    input,
    MountPage(first.navigation_generation),
    emit,
  )
  assert_true(stale == last)
  let (stale, _) = last.update(
    input,
    PageReady(first.navigation_generation),
    emit,
  )
  assert_true(stale == last)
  let (cancelled, _) = last.update(input, JumpToLatest, emit)
  let (stale, _) = cancelled.update(
    input,
    MountPage(last.navigation_generation),
    emit,
  )
  assert_true(stale == cancelled)
  assert_true(stale.navigation is None)
}

///|
test "layout and scroll reports cannot overwrite a pending navigation target" {
  let input = paged_input(60)
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (moving, _) = pinned_model(input).update(
    input,
    Overview(PreviousPage),
    emit,
  )
  for
    message in [
      Msg::Pinned(true),
      ContentRendered,
      Overview(ActiveChanged(None)),
      CrossPage(true),
    ] {
    let (next, _) = moving.update(input, message, emit)
    assert_true(next == moving)
  }
}

///|
test "cross-page tick clicks share the loading path and retain the exact requested turn" {
  let input = paged_input(60)
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (first, _) = pinned_model(input).update(
    input,
    Overview(Clicked(@transcript_overview.Durable(7))),
    emit,
  )
  assert_eq(first.page, None)
  assert_true(
    first.navigation
    is Some({ page: 0, anchor: Some(Durable(7)), rendering: false, .. }),
  )
  // A second tick in the same pending page must supersede the first anchor.
  let (last, _) = first.update(
    input,
    Overview(Clicked(@transcript_overview.Durable(17))),
    emit,
  )
  assert_true(
    last.navigation is Some({ page: 0, anchor: Some(Durable(17)), .. }),
  )
  let (stale, _) = last.update(
    input,
    MountPage(first.navigation_generation),
    emit,
  )
  assert_true(stale == last)
  let (mounted, _) = last.update(
    input,
    MountPage(last.navigation_generation),
    emit,
  )
  assert_eq(mounted.page, Some(0))
  assert_eq(mounted.overview.active, Some(@transcript_overview.Durable(17)))
}

///|
test "ticks in the mounted page do not show a loading screen" {
  let input = paged_input(60)
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (next, _) = pinned_model(input).update(
    input,
    Overview(Clicked(@transcript_overview.Durable(87))),
    emit,
  )
  assert_true(next.navigation is None)
  assert_eq(next.overview.active, Some(@transcript_overview.Durable(87)))
}
