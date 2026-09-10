///|
test "format output includes failures and captured text" {
  assert_eq(
    @moon_check.format_output(
      Some(255),
      (
        #|Error: Failed to calculate build plan
        #|
        #|Caused by:
        #|    0: Failed to resolve the module dependency graph
      ),
      false,
    ),
    (
      #|moon check:
      #|exit=255
      #|Error: Failed to calculate build plan
      #|
      #|Caused by:
      #|    0: Failed to resolve the module dependency graph
    ),
  )
}

///|
test "format output keeps successful and truncated metadata" {
  assert_eq(
    @moon_check.format_output(
      Some(0),
      "Finished. moon: ran 2 tasks, now up to date",
      false,
    ),
    (
      #|moon check:
      #|Finished. moon: ran 2 tasks, now up to date
    ),
  )
  assert_eq(
    @moon_check.format_output(None, "long output", true),
    (
      #|moon check:
      #|exit=cancelled
      #|output_limit_reached=true
      #|long output
    ),
  )
}

///|
#cfg(not(platform="windows"))
async test "nearest project dir prefers the closest module or workspace" {
  @vfs.with_tmpdir(prefix="openseek-moon-check-root-", dir => {
    let module_dir = "\{dir}/packages/demo"
    let source = "\{module_dir}/src"
    @fs.mkdir(source, recursive=true)
    @fs.write_file(
      "\{dir}/moon.work",
      "members = []\n",
      create_mode=CreateOrTruncate,
    )
    assert_true(
      @moon_check.nearest_project_dir(source) is Some(root) && root == dir,
    )
    @fs.write_file(
      "\{module_dir}/moon.mod",
      "name = \"example/demo\"\n",
      create_mode=CreateOrTruncate,
    )
    assert_true(
      @moon_check.nearest_project_dir(source) is Some(root) &&
      root == module_dir,
    )
  })
}
