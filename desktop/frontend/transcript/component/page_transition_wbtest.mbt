///|
/// Drive state messages without executing their browser effects.
fn Model::step(self : Model, input : Input, msg : Msg) -> Model {
  self.update(input, msg, @cmd.Emit(_ => @cmd.none)).0
}

///|
test "page buttons move the navigation before replacing mounted content" {
  let input = paged_input(60)
  let moving = pinned_model(input).step(input, Overview(PreviousPage))
  assert_eq(moving.page, None)
  assert_eq(moving.navigation_page(TurnIndex::new(input.items)).index, 1)
  assert_false(moving.pinned)
  let rendering = moving.step(input, MountPage(moving.navigation_generation))
  assert_eq(rendering.page, Some(1))
  assert_true(rendering.navigation is Some(_))
  let ready = rendering.step(input, PageReady(moving.navigation_generation))
  assert_eq(ready.page, Some(1))
  assert_true(ready.navigation is None)
}

///|
test "rapid navigation keeps the last requested page and ignores stale completions" {
  let input = paged_input(60)
  let first = pinned_model(input).step(input, Overview(PreviousPage))
  let last = first.step(input, Overview(PreviousPage))
  assert_eq(last.navigation_page(TurnIndex::new(input.items)).index, 0)
  for
    msg in [
      MountPage(first.navigation_generation),
      PageReady(first.navigation_generation),
    ] {
    assert_true(last.step(input, msg) == last)
  }
  let cancelled = last.step(input, JumpToLatest)
  assert_true(
    cancelled.step(input, MountPage(last.navigation_generation)) == cancelled,
  )
  assert_true(cancelled.navigation is None)
}

///|
test "layout and scroll reports cannot overwrite a pending navigation target" {
  let input = paged_input(60)
  let moving = pinned_model(input).step(input, Overview(PreviousPage))
  for
    message in [
      Msg::Pinned(true),
      ContentRendered,
      Overview(ActiveChanged(None)),
      CrossPage(true),
    ] {
    assert_true(moving.step(input, message) == moving)
  }
}

///|
test "cross-page tick clicks share the loading path and retain the exact requested turn" {
  let input = paged_input(60)
  let first = pinned_model(input).step(
    input,
    Overview(Clicked(@transcript_overview.Durable(7))),
  )
  assert_eq(first.page, None)
  assert_true(
    first.navigation is Some({ page: 0, anchor: Some(Durable(7)), .. }),
  )
  // Changing the anchor within a pending page must also cancel the old request.
  let last = first.step(
    input,
    Overview(Clicked(@transcript_overview.Durable(17))),
  )
  assert_true(
    last.navigation is Some({ page: 0, anchor: Some(Durable(17)), .. }),
  )
  assert_true(last.step(input, MountPage(first.navigation_generation)) == last)
  let mounted = last.step(input, MountPage(last.navigation_generation))
  assert_eq(mounted.page, Some(0))
  assert_eq(mounted.overview.active, Some(@transcript_overview.Durable(17)))
}

///|
test "ticks in the mounted page do not show a loading screen" {
  let input = paged_input(60)
  let next = pinned_model(input).step(
    input,
    Overview(Clicked(@transcript_overview.Durable(87))),
  )
  assert_true(next.navigation is None)
  assert_eq(next.overview.active, Some(@transcript_overview.Durable(87)))
}
