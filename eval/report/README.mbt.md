# Eval Report

`bobzhang/openseek/eval/report` provides the small report primitive shared by
local harnesses. It renders a title, summary metrics, dynamic overview columns,
per-row detail metrics, and optional log links to Markdown, HTML, and JSON.

It is intentionally simple: individual harnesses still own their domain result
types, then convert to `Report` at the output boundary.

## API Shape

- `Metric(name~, value~)`: a string metric used in summaries or rows.
- `ReportRow(index~, name~, success~, reason?, warnings?, metrics?, details?,
  log_path?)`: one case/tool row. `metrics` appear in the overview table;
  `details` appear in the per-row details section.
- `Report(title~, summary?, metric_columns?, rows?)`: the renderable report.
- `Report::markdown()`: Markdown table plus optional log section.
- `Report::html()`: standalone HTML overview plus per-row detail cards.
- `Report::to_json()`: JSON representation for automated inspection.
- `Report::write_files(out_dir)`: writes `report.md`, `report.json`, and
  `report.html`.
- `write_files(out_dir, markdown, json, html?)`: shared writer for harnesses
  that keep their own richer JSON schema but reuse the renderers.

## Example

```moonbit check
///|
test "render a tiny report" {
  let report = @report.Report(
    title="Tool Harness",
    summary=[Metric(name="passed", value="true")],
    metric_columns=["Mode"],
    rows=[
      ReportRow(
        index=1,
        name="read",
        success=true,
        metrics=[Metric(name="Mode", value="filesystem")],
        details=[Metric(name="Log", value="logs/read.log")],
      ),
    ],
  )
  let markdown = report.markdown()
  assert_true(markdown.contains("# Tool Harness"))
  assert_true(
    markdown.contains("| # | Case | Result | Mode | Reason | Warnings |"),
  )
  assert_true(markdown.contains("| 1 | `read` | pass | filesystem | ok |  |"))
  assert_true(markdown.contains("## Trial Details"))
  assert_true(markdown.contains("- Log: `logs/read.log`"))
}
```
