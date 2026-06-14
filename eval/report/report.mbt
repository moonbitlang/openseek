///|
/// One named measurement, already rendered to display text — the shared cell
/// format for report summaries and per-row metric columns.
pub struct Metric {
  name : String
  value : String
}

///|
/// Build a metric. `value` is display text: format numbers before
/// constructing so the report layer never guesses precision.
pub fn Metric::Metric(name~ : String, value~ : String) -> Metric {
  { name, value }
}

///|
/// One trial's row in an eval report: which case (`name`) and repetition
/// (`index`), whether it passed, the failure `reason` ("ok" when it passed),
/// non-fatal `warnings`, its `metrics` cells, and the path of its full
/// transcript log when one was kept.
pub struct ReportRow {
  index : Int
  name : String
  success : Bool
  reason : String
  warnings : String
  metrics : Array[Metric]
  details : Array[Metric]
  log_path : String
}

///|
/// Build a report row; everything beyond identity and the verdict is
/// optional. `reason` defaults to "ok" so passing rows read uniformly.
pub fn ReportRow::ReportRow(
  index~ : Int,
  name~ : String,
  success~ : Bool,
  reason? : String = "ok",
  warnings? : String = "",
  metrics? : Array[Metric] = [],
  details? : Array[Metric] = [],
  log_path? : String = "",
) -> ReportRow {
  { index, name, success, reason, warnings, metrics, details, log_path }
}

///|
/// A complete eval run's results: a `title`, run-level `summary` metrics, the
/// ordered `metric_columns` every row renders under, and one `ReportRow` per
/// trial. Renders to markdown for humans and JSON for tooling.
pub struct Report {
  title : String
  summary : Array[Metric]
  metric_columns : Array[String]
  rows : Array[ReportRow]
}

///|
/// Build a report. `metric_columns` names and orders the per-row metric
/// cells; rows supply values for those names via their `metrics`.
pub fn Report::Report(
  title~ : String,
  summary? : Array[Metric] = [],
  metric_columns? : Array[String] = [],
  rows? : Array[ReportRow] = [],
) -> Report {
  { title, summary, metric_columns, rows }
}

///|
/// How many rows passed.
pub fn Report::successes(self : Report) -> Int {
  let mut count = 0
  for row in self.rows {
    if row.success {
      count += 1
    }
  }
  count
}

///|
/// Whether every row passed — the run's exit-status verdict. Vacuously true
/// for a report with no rows.
pub fn Report::all_passed(self : Report) -> Bool {
  self.successes() == self.rows.length()
}

///|
/// Render the report as a human-facing markdown document: title, summary
/// bullets, the trial table, and a log-paths section when any row kept one.
pub fn Report::markdown(self : Report) -> String {
  let lines : Array[String] = ["# \{self.title}", ""]
  for metric in self.summary {
    lines.push("- \{metric.name}: `\{metric.value}`")
  }
  if self.summary.length() > 0 {
    lines.push("")
  }
  lines.push(table_header(self.metric_columns))
  lines.push(table_divider(self.metric_columns))
  for row in self.rows {
    lines.push(row.markdown_row(self.metric_columns))
  }
  let detail_lines = detail_section_lines(self.rows)
  if detail_lines.length() > 0 {
    lines.push("")
    lines.push("## Trial Details")
    lines.push("")
    for line in detail_lines {
      lines.push(line)
    }
  }
  let log_lines = log_section_lines(self.rows)
  if log_lines.length() > 0 {
    lines.push("")
    lines.push("## Logs")
    lines.push("")
    for line in log_lines {
      lines.push(line)
    }
  }
  lines.join("\n") + "\n"
}

///|
/// Render the report as JSON for tooling (diffing runs, dashboards), with
/// the success count precomputed alongside the raw rows.
pub fn Report::to_json(self : Report) -> Json {
  {
    "title": self.title,
    "summary": ([ for metric in self.summary => metric.to_json() ] : Json),
    "metric_columns": self.metric_columns,
    "successes": self.successes(),
    "rows": ([ for row in self.rows => row.to_json() ] : Json),
  }
}

///|
/// Render the report as a standalone HTML document for browser inspection.
pub fn Report::html(self : Report) -> String {
  let out = StringBuilder::new()
  out.write_string("<!doctype html>\n<html><head><meta charset=\"utf-8\">")
  out.write_string(
    "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
  )
  out.write_string("<title>")
  out.write_string(escape_html(self.title))
  out.write_string("</title>")
  out.write_string(
    "<style>:root{color-scheme:light;--bg:#f7f9fb;--panel:#fff;--text:#1f2328;--muted:#59636e;--line:#d0d7de;--line-soft:#eaeef2;--good:#116329;--bad:#cf222e;--accent:#0969da;--warn:#9a6700}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font-family:Inter,ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,\"Segoe UI\",sans-serif;font-size:14px;line-height:1.45}main{max-width:1440px;margin:0 auto;padding:28px 24px 44px}h1{margin:0 0 16px;font-size:28px;line-height:1.15}h2{margin:28px 0 12px;font-size:18px}.summary{display:flex;flex-wrap:wrap;align-items:flex-start;gap:10px;margin:12px 0 20px}.metric,.trial-card{background:var(--panel);border:1px solid var(--line);border-radius:8px}.metric{padding:9px 10px;min-width:140px;max-width:420px}.summary>.metric{flex:1 1 150px}.summary>.metric:last-child{flex-basis:320px}.metric-name{color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.04em}.metric code,.detail-list code,td code,.logs code{background:#f6f8fa;border:1px solid var(--line-soft);border-radius:5px;padding:1px 5px;white-space:pre-wrap;overflow-wrap:anywhere}.table-wrap{overflow-x:auto;background:var(--panel);border:1px solid var(--line);border-radius:8px}table{border-collapse:separate;border-spacing:0;width:100%;font-size:13px}th,td{border-bottom:1px solid var(--line-soft);padding:8px 10px;text-align:left;vertical-align:top}th{background:#f6f8fa;color:#3f4852;font-weight:650;white-space:nowrap}tbody tr:last-child td{border-bottom:0}.pass{color:var(--good);font-weight:700}.fail{color:var(--bad);font-weight:700}.reason-cell,.warning-cell{max-width:360px;overflow-wrap:anywhere}.trial-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(360px,1fr));gap:12px}.trial-card{padding:14px}.trial-card header{display:flex;gap:10px;align-items:center;justify-content:space-between;margin-bottom:10px}.trial-card h3{margin:0;font-size:16px}.badge{border-radius:999px;padding:2px 9px;font-size:12px;font-weight:700}.badge.pass{background:#dafbe1}.badge.fail{background:#ffebe9}.detail-list{display:grid;grid-template-columns:minmax(120px,180px) 1fr;gap:6px 12px;margin:0}.detail-list dt{color:var(--muted);font-weight:650}.detail-list dd{margin:0;min-width:0}.detail-list dd.long{white-space:pre-wrap;overflow-wrap:anywhere}.detail-list dd.long code{display:block;max-height:180px;overflow:auto}.logs{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:12px 16px}.logs ul{margin:8px 0 0;padding-left:20px}@media(max-width:720px){main{padding:20px 14px}.summary>.metric{flex-basis:100%;max-width:none}.trial-grid{grid-template-columns:1fr}.detail-list{grid-template-columns:1fr}.detail-list dt{margin-top:6px}}</style>",
  )
  out.write_string("</head><body><main>")
  out.write_string("<h1>")
  out.write_string(escape_html(self.title))
  out.write_string("</h1>")
  if self.summary.length() > 0 {
    out.write_string("<div class=\"summary\">")
    for metric in self.summary {
      out.write_string("<div class=\"metric\"><div class=\"metric-name\">")
      out.write_string(escape_html(metric.name))
      out.write_string("</div><code>")
      out.write_string(escape_html(metric.value))
      out.write_string("</code></div>")
    }
    out.write_string("</div>")
  }
  out.write_string("<div class=\"table-wrap\"><table><thead><tr>")
  let columns : Array[String] = ["#", "Case", "Result"]
  for column in self.metric_columns {
    columns.push(column)
  }
  columns.push("Reason")
  columns.push("Warnings")
  for column in columns {
    out.write_string("<th>")
    out.write_string(escape_html(column))
    out.write_string("</th>")
  }
  out.write_string("</tr></thead><tbody>")
  for row in self.rows {
    out.write_string("<tr><td>")
    out.write_string(row.index.to_string())
    out.write_string("</td><td><code>")
    out.write_string(escape_html(row.name))
    out.write_string("</code></td><td class=\"")
    out.write_string(if row.success { "pass" } else { "fail" })
    out.write_string("\">")
    out.write_string(if row.success { "pass" } else { "fail" })
    out.write_string("</td>")
    for column in self.metric_columns {
      out.write_string("<td>")
      out.write_string(escape_html(row.metric_value(column)))
      out.write_string("</td>")
    }
    out.write_string("<td class=\"reason-cell\">")
    out.write_string(escape_html(short_cell(row.reason)))
    out.write_string("</td><td class=\"warning-cell\">")
    out.write_string(escape_html(short_cell(row.warnings)))
    out.write_string("</td></tr>")
  }
  out.write_string("</tbody></table></div>")
  if has_detail_section(self.rows) {
    out.write_string(
      "<section><h2>Trial Details</h2><div class=\"trial-grid\">",
    )
    for row in self.rows {
      if row.has_details() {
        out.write_string("<article class=\"trial-card\"><header><h3><code>")
        out.write_string(escape_html(row.name))
        out.write_string("</code></h3><span class=\"badge ")
        out.write_string(if row.success { "pass" } else { "fail" })
        out.write_string("\">")
        out.write_string(if row.success { "pass" } else { "fail" })
        out.write_string("</span></header><dl class=\"detail-list\">")
        write_html_detail(out, "Reason", row.reason, long=true)
        if row.warnings != "" {
          write_html_detail(out, "Warnings", row.warnings, long=true)
        }
        for detail in row.details {
          write_html_detail(
            out,
            detail.name,
            detail.value,
            long=detail.value.length() > 80,
          )
        }
        out.write_string("</dl></article>")
      }
    }
    out.write_string("</div></section>")
  }
  let log_lines = log_section_lines(self.rows)
  if log_lines.length() > 0 {
    out.write_string("<section class=\"logs\"><h2>Logs</h2><ul>")
    for row in self.rows {
      if row.log_path != "" {
        out.write_string("<li><code>")
        out.write_string(escape_html(row.name))
        out.write_string("</code> trial ")
        out.write_string(row.index.to_string())
        out.write_string(": <code>")
        out.write_string(escape_html(row.log_path))
        out.write_string("</code></li>")
      }
    }
    out.write_string("</ul></section>")
  }
  out.write_string("</main></body></html>\n")
  out.to_string()
}

///|
/// Write both renderings of this report under `out_dir` — the standard
/// artifact layout eval runners leave behind.
pub async fn Report::write_files(self : Report, out_dir : String) -> Unit {
  write_files(out_dir, self.markdown(), self.to_json(), html=self.html())
}

///|
/// Write already-rendered report artifacts under `out_dir`, creating it as
/// needed. `html` is optional for older runners that only render markdown and
/// JSON.
pub async fn write_files(
  out_dir : String,
  markdown : String,
  json : Json,
  html? : String = "",
) -> Unit {
  let _ = @fs.mkdir(out_dir, recursive=true) catch { _ => () }
  @fs.write_file(
    out_dir + "/report.json",
    json.stringify(),
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(out_dir + "/report.md", markdown, create_mode=CreateOrTruncate)
  if html != "" {
    @fs.write_file(out_dir + "/report.html", html, create_mode=CreateOrTruncate)
  }
}

///|
fn Metric::to_json(self : Metric) -> Json {
  { "name": self.name, "value": self.value }
}

///|
fn ReportRow::to_json(self : ReportRow) -> Json {
  {
    "index": self.index,
    "name": self.name,
    "success": self.success,
    "reason": self.reason,
    "warnings": self.warnings,
    "metrics": ([ for metric in self.metrics => metric.to_json() ] : Json),
    "details": ([ for metric in self.details => metric.to_json() ] : Json),
    "log_path": self.log_path,
  }
}

///|
fn table_header(metric_columns : Array[String]) -> String {
  let cells : Array[String] = ["#", "Case", "Result"]
  for column in metric_columns {
    cells.push(column)
  }
  cells.push("Reason")
  cells.push("Warnings")
  "| " + cells.join(" | ") + " |"
}

///|
fn table_divider(metric_columns : Array[String]) -> String {
  let cells : Array[String] = ["---", "---", "---"]
  for _ in metric_columns {
    cells.push("---")
  }
  cells.push("---")
  cells.push("---")
  "| " + cells.join(" | ") + " |"
}

///|
fn ReportRow::markdown_row(
  self : ReportRow,
  metric_columns : Array[String],
) -> String {
  let cells : Array[String] = [
    self.index.to_string(),
    "`\{escape_table_cell(self.name)}`",
    if self.success {
      "pass"
    } else {
      "fail"
    },
  ]
  for column in metric_columns {
    cells.push(escape_table_cell(self.metric_value(column)))
  }
  cells.push(escape_table_cell(short_cell(self.reason)))
  cells.push(escape_table_cell(short_cell(self.warnings)))
  "| " + cells.join(" | ") + " |"
}

///|
fn ReportRow::metric_value(self : ReportRow, column : String) -> String {
  for metric in self.metrics {
    if metric.name == column {
      return metric.value
    }
  }
  ""
}

///|
fn log_section_lines(rows : Array[ReportRow]) -> Array[String] {
  let lines : Array[String] = []
  for row in rows {
    if row.log_path != "" {
      lines.push("- `\{row.name}` trial \{row.index}: `\{row.log_path}`")
    }
  }
  lines
}

///|
fn detail_section_lines(rows : Array[ReportRow]) -> Array[String] {
  let lines : Array[String] = []
  for row in rows {
    if row.has_details() {
      if lines.length() > 0 {
        lines.push("")
      }
      lines.push("### `\{row.name}`")
      lines.push("")
      lines.push("- result: `\{if row.success { "pass" } else { "fail" }}`")
      lines.push("- reason: \{markdown_text(row.reason)}")
      if row.warnings != "" {
        lines.push("- warnings: \{markdown_text(row.warnings)}")
      }
      for detail in row.details {
        lines.push("- \{detail.name}: `\{escape_backticks(detail.value)}`")
      }
    }
  }
  lines
}

///|
fn has_detail_section(rows : Array[ReportRow]) -> Bool {
  for row in rows {
    if row.has_details() {
      return true
    }
  }
  false
}

///|
fn ReportRow::has_details(self : ReportRow) -> Bool {
  self.details.length() > 0 || self.reason != "ok" || self.warnings != ""
}

///|
fn write_html_detail(
  out : StringBuilder,
  name : String,
  value : String,
  long~ : Bool,
) -> Unit {
  out.write_string("<dt>")
  out.write_string(escape_html(name))
  out.write_string("</dt><dd")
  if long {
    out.write_string(" class=\"long\"")
  }
  out.write_string("><code>")
  out.write_string(escape_html(value))
  out.write_string("</code></dd>")
}

///|
fn short_cell(text : String) -> String {
  let squashed = text
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\n", new=" ")
    .trim()
    .to_owned()
  if squashed.length() <= 96 {
    squashed
  } else {
    squashed.sub(start=0, end=96).to_owned() + "..."
  }
}

///|
fn markdown_text(text : String) -> String {
  "`\{escape_backticks(short_cell(text))}`"
}

///|
fn escape_backticks(text : String) -> String {
  text.replace_all(old="`", new="\\`")
}

///|
/// Make free text safe inside a markdown table cell: escape `|` and flatten
/// newlines to spaces. Failure reasons quote arbitrary model and tool
/// output, which would otherwise break the table layout.
pub fn escape_table_cell(text : String) -> String {
  text
  |> String::replace_all(old="|", new="\\|")
  |> String::replace_all(old="\n", new=" ")
}

///|
fn escape_html(text : String) -> String {
  text
  |> String::replace_all(old="&", new="&amp;")
  |> String::replace_all(old="<", new="&lt;")
  |> String::replace_all(old=">", new="&gt;")
  |> String::replace_all(old="\"", new="&quot;")
}
