///|
fn progress_lane(steps : Int32, activity : String) -> Lane {
  { id: "a", kind: "task", label: "investigate", steps, activity, run: None, }
}

///|
test "a lane with nothing readable yet still says it started" {
  let (steps, activity) = detail_cells(progress_lane(0, ""))
  assert_true(steps is None)
  assert_true(activity is Some("starting…"))
}

///|
test "readable progress replaces the placeholder" {
  let (steps, activity) = detail_cells(progress_lane(3, "reading files"))
  assert_true(steps is Some("step 3"))
  assert_true(activity is Some("reading files"))
}

///|
test "the host reads step count and activity independently" {
  // Either can arrive without the other, and the placeholder stands in only
  // when the lane has nothing at all to report.
  let (steps, activity) = detail_cells(progress_lane(3, ""))
  assert_true(steps is Some("step 3"))
  assert_true(activity is None)
  let (steps, activity) = detail_cells(progress_lane(0, "reading files"))
  assert_true(steps is None)
  assert_true(activity is Some("reading files"))
}
