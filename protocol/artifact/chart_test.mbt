///|
test "chart receipt is small and attachment preserves other tool metadata" {
  let chart = @artifact.Chart(id="chart_example", spec={
    "title": "Weekly [revenue]\ntrend",
    "series": [{ "y": [2, 5] }],
  })
  assert_eq(
    chart.embed(),
    "![Weekly \\[revenue\\] trend](artifact://chart_example)",
  )
  let receipt = @json.parse(chart.receipt())
  assert_true(
    receipt is { "artifact_id": "chart_example", "embed": String(_), .. },
  )
  assert_false(chart.receipt().contains("series"))
  let data = chart.attach(
    Some({ "ptc_calls": [], "image_output": { "retained": true } }),
  )
  assert_true(
    data is { "ptc_calls": [], "image_output": { "retained": true, .. }, .. },
  )
  assert_eq(@artifact.charts(Some(data)), [chart])
  let copy : @artifact.Chart = @json.from_json(chart.to_json())
  assert_eq(copy, chart)
}

///|
test "chart artifact decoder ignores unsupported and damaged entries" {
  let chart = @artifact.Chart(id="chart_valid", spec={
    "series": [{ "y": [2] }],
  })
  let data : Json = {
    "artifacts": [
      { "id": "chart_bad", "kind": "mathplotlib", "version": 2, "spec": {} },
      { "id": "chart_../bad", "kind": "mathplotlib", "version": 1, "spec": {} },
      { "id": "chart_null", "kind": "mathplotlib", "version": 1, "spec": null },
      chart.to_json(),
    ],
  }
  assert_eq(@artifact.charts(Some(data)), [chart])
  assert_eq(@artifact.charts(None), [])
}
