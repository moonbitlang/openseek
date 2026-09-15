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

///|
async test "invalid review deadline is rejected before fleet workspaces are created" {
  @vfs.with_tmpdir(prefix="openseek-review-deadline-fleet-", root => {
    let source = "\{root}/project"
    @fs.mkdir(source, recursive=true)
    let parsed = @testkit.run_matches(
      argv=[
        "--review-deadline", "0", "--concurrency", "1", "--dir", source, "write",
        "MoonBit",
      ],
      env={ "DEEPSEEK": "test-key" },
    )
    let _ = run_task_command(parsed) catch {
      error => {
        assert_true(
          "\{error}".contains("--review-deadline must be a positive integer"),
        )
        assert_false(@fs.exists("\{root}/project_run_1"))
        return
      }
    }
    fail("invalid review deadline started a fleet run")
  })
}
