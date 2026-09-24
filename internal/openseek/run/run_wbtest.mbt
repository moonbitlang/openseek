///|
test "explicit --concurrency selects fleet mode even at 1" {
  // Any explicit --concurrency copies --dir; 1 is not an in-place special case.
  let explicit_one = @testkit.run_matches(
    argv=["--concurrency", "1", "task"],
    env=Map([]),
  )
  assert_true(fleet_mode(explicit_one, 1))
  // Only the flagless default runs in place.
  let default_run = @testkit.run_matches(argv=["task"], env=Map([]))
  assert_false(fleet_mode(default_run, 1))
  // N >= 2 is fleet mode regardless of how it was set.
  assert_true(fleet_mode(default_run, 2))
}
