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
