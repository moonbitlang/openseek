///|
async test "deterministic harness exercises file, command, and control tools" {
  let report = @tool_harness.run_harness()
  assert_false(report.rows.is_empty())
  assert_true(report.all_passed())
  let markdown = report.markdown()
  assert_true(markdown.contains("# Tool Harness"))
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
