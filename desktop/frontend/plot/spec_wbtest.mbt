///|
test "chart data rejects invalid shapes and unsupported versions before drawing" {
  for
    source in [
      "{}", "[]", "{\"version\":2,\"series\":[{\"y\":[1]}]}", "{\"series\":[{\"y\":[]}]}",
      "{\"series\":[{\"x\":[1],\"y\":[1,2]}]}", "{\"series\":[{\"y\":[1],\"labels\":[\"a\",\"b\"]}]}",
      "{\"series\":[{\"kind\":\"javascript\",\"y\":[1]}]}", "{\"height\":0,\"series\":[{\"y\":[1]}]}",
      "{\"series\":[{\"y\":[null]}]}",
    ] {
    try {
      let _ : Spec = @json.from_json(@json.parse(source))
    } catch {
      _ => ()
    } noraise {
      _ => fail("Invalid chart accepted: " + source)
    }
  }
}

///|
test "every admitted chart kind renders and all-hidden series remains a valid chart" {
  for kind in ["line", "scatter", "bar", "barh", "hist", "pie", "area"] {
    let spec : Spec = @json.from_json({
      "title": "A < B & C",
      "grid": true,
      "series": [{ "kind": kind, "label": "Example", "y": [2, 5, 3] }],
    })
    let drawing = spec.drawing([])
    assert_true(drawing.svg().contains("A &lt; B &amp; C"), msg=kind)
    assert_true(spec.drawing([0]).svg().contains("<svg"), msg=kind)
    if kind == "line" || kind == "scatter" {
      assert_eq(drawing.points().length(), 3)
      assert_eq(drawing.points()[1].data_y, 5.0)
      assert_eq(spec.drawing([0]).points().length(), 0)
    }
  }
}

///|
test "a series toggle clears stale picking indices" {
  let selection : Selection = { hovered: None, selected: None, hidden: [], }
  let hidden = selection.update(@plot_dom.ToggleSeries("1"))
  assert_eq(hidden.hidden, [1])
  assert_true(hidden.hovered is None && hidden.selected is None)
  assert_eq(hidden.update(@plot_dom.ToggleSeries("1")).hidden, [])
}

///|
test "catalog resolves immutable IDs from structured data and rejects collisions" {
  let first = @artifact.Chart(id="chart_first", spec={
    "series": [{ "y": [2] }],
  })
  let second = @artifact.Chart(id="chart_second", spec={
    "series": [{ "y": [9] }],
  })
  let catalog = Catalog::from_tool_data([
    Some(first.attach(None)),
    Some(second.attach(None)),
  ])
  assert_eq(catalog.source(first.id), Some(first.spec.stringify()))
  assert_eq(catalog.source(second.id), Some(second.spec.stringify()))
  assert_eq(catalog.source("chart_missing"), None)
  assert_eq(Catalog::from_tool_data([]).source(first.id), None)
  let repeated = Catalog::from_tool_data([
    Some(first.attach(None)),
    Some(first.attach(None)),
  ])
  assert_eq(repeated.source(first.id), Some(first.spec.stringify()))
  let conflicting = @artifact.Chart(id=first.id, spec=second.spec)
  let collision = Catalog::from_tool_data([
    Some(first.attach(None)),
    Some(conflicting.attach(None)),
    Some(first.attach(None)),
  ])
  assert_eq(collision.source(first.id), None)
}
