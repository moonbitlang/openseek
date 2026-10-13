///|
test "a wheel burst cannot cross a page, even after reaching its edge" {
  let gesture = PageGesture::new()
  assert_false(gesture.wheel(0, false, true))
  assert_false(gesture.wheel(20, true, true))
  assert_false(gesture.wheel(80, true, true))
  assert_true(gesture.wheel(400, true, true))
  assert_false(gesture.wheel(420, true, true))
  assert_false(gesture.wheel(450, true, true))
  assert_false(gesture.wheel(800, false, true))
}

///|
test "direction changes and initial edge events arm without crossing" {
  let gesture = PageGesture::new()
  assert_false(gesture.wheel(0, true, false))
  assert_true(gesture.wheel(300, true, false))
  assert_false(gesture.wheel(600, true, true))
  assert_true(gesture.wheel(900, true, true))
}

///|
test "wheel overlap mounts one complete adjacent turn without changing page ticks" {
  let turns = TurnIndex::new(paged_input(53).items)
  let next = turns.page_rows(Some(1), overlap=Some(19))
  assert_eq((next.start, next.end), (38, 80))
  assert_eq((next.page.start, next.page.end), (20, 40))
  let previous = turns.page_rows(Some(0), overlap=Some(20))
  assert_eq((previous.start, previous.end), (0, 42))
  assert_eq((previous.page.start, previous.page.end), (0, 20))
}

///|
test "following newer pages discards a stale overlap instead of mounting old history" {
  let turns = TurnIndex::new(paged_input(100).items)
  let bounds = turns.page_rows(None, overlap=Some(19))
  assert_eq((bounds.start, bounds.end), (160, 200))
}

///|
test "wheel page updates are pure without a DOM and retain the measured boundary" {
  let input = paged_input(60)
  let model = { ..pinned_model(input), page: Some(1), pinned: false, }
  for
    (forward, key, expected_page, overlap) in [
      (true, @transcript_overview.Durable(79), 2, 39),
      (false, @transcript_overview.Durable(41), 0, 20),
    ] {
    let message = CrossPage(page=1, forward~, key~, offset=-250)
    // The headless runtime has no document; any DOM read in update throws.
    let first = model.step(input, message)
    let second = model.step(input, message)
    assert_true(first == second)
    assert_eq(first.page, Some(expected_page))
    assert_eq(first.overlap, Some(overlap))
    assert_false(first.pinned)
    assert_eq(model.page, Some(1))
    assert_eq(model.overlap, None)
    // Replaying a measurement after the mounted page moved cannot skip pages.
    assert_true(first.step(input, message) == first)
  }
}

///|
test "wheel page updates reject stale pages and replaced boundary turns" {
  let input = paged_input(60)
  let model = { ..pinned_model(input), page: Some(1), pinned: false, }
  for
    message in [
      CrossPage(page=0, forward=true, key=Durable(39), offset=10),
      CrossPage(page=1, forward=true, key=Durable(77), offset=10),
    ] {
    assert_true(model.step(input, message) == model)
    assert_true(model.step(input, message) == model)
  }
}
