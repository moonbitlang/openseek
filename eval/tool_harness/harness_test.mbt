///|
async test "deterministic harness exercises every tool" {
  let report = @tool_harness.run_harness()
  assert_eq(report.rows.length(), 7)
  assert_eq(report.successes(), 7)
  assert_true(report.all_passed())
  let markdown = report.markdown()
  assert_true(markdown.contains("# Tool Harness"))
  assert_false(markdown.contains("`check_daemon`"))
  assert_false(markdown.contains("`moon_ide`"))
  assert_false(markdown.contains("`moon_check`"))
  assert_false(markdown.contains("`moon_cmd`"))
  assert_true(markdown.contains("| 4 | `multi_edit` | pass"))
  assert_true(markdown.contains("| 6 | `plan` | pass"))
  assert_true(markdown.contains("| 7 | `finish` | pass"))
}

///|
async test "harness report can be written for inspection" {
  @vfs.with_tmpdir(prefix="openseek-tool-harness-report-", root => {
    let report = @tool_harness.run_harness()
    report.write_files(root)
    let markdown = @fs.read_file("\{root}/report.md").text()
    let json = @fs.read_file("\{root}/report.json").text()
    assert_true(
      markdown.contains(
        "| # | Case | Result | Mode | Action | Reason | Warnings |",
      ),
    )
    assert_true(json.contains("\"title\":\"Tool Harness\""))
  })
}
