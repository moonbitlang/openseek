///|
test "markdown renders summary metrics and dynamic columns" {
  let report = @report.Report(
    title="Tool Harness",
    summary=[
      Metric(name="result", value="2/2"),
      Metric(name="passed", value="true"),
    ],
    metric_columns=["Mode", "Steps"],
    rows=[
      ReportRow(
        index=1,
        name="read",
        success=true,
        metrics=[
          Metric(name="Mode", value="filesystem"),
          Metric(name="Steps", value="1"),
        ],
        details=[Metric(name="Log", value="logs/read.log")],
      ),
      ReportRow(
        index=2,
        name="shell",
        success=false,
        reason="exit 1",
        warnings="contains | pipe\nand newline",
        metrics=[Metric(name="Mode", value="process")],
      ),
    ],
  )
  let text = report.markdown()
  assert_true(text.contains("# Tool Harness"))
  assert_true(text.contains("- result: `2/2`"))
  assert_true(
    text.contains("| # | Case | Result | Mode | Steps | Reason | Warnings |"),
  )
  assert_true(text.contains("## Trial Details"))
  assert_true(text.contains("- Log: `logs/read.log`"))
  assert_true(text.contains("contains \\| pipe and newline"))
  assert_eq(report.successes(), 1)
  assert_false(report.all_passed())
}

///|
async test "report writes markdown json and html files" {
  let root = @fs.tmpdir(prefix="openseek-eval-report")
  let report = @report.Report(title="Tiny Report", rows=[
    ReportRow(index=1, name="finish", success=true),
  ])
  report.write_files(root)
  let markdown = @fs.read_file(root + "/report.md").text()
  let json = @fs.read_file(root + "/report.json").text()
  let html = @fs.read_file(root + "/report.html").text()
  assert_true(markdown.contains("# Tiny Report"))
  assert_true(json.contains("\"title\":\"Tiny Report\""))
  assert_true(html.contains("<title>Tiny Report</title>"))
  assert_true(html.contains("table-wrap"))
  @fs.rmdir(root, recursive=true)
}
