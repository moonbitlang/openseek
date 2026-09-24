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
    let _ = @run.run_task_command(parsed) catch {
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
