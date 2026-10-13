///|
fn test_model(name : String) -> @model.TextModel {
  TextModel(
    try! @base_common.Uri::from(
      scheme="inmemory",
      authority="browser-testing",
      path="/\{name}.mbt",
    ),
    "\{name}.mbt",
    "moonbit",
    1,
    "revision-1",
    "one\ntwo",
  )
}

///|
test "observations are isolated by viewer id and disposable" {
  let first_model = test_model("first")
  defer first_model.dispose()
  let second_model = test_model("second")
  defer second_model.dispose()
  let first_registration = register_viewer("observations-first", set_hidden_areas=(
    _ranges,
    _source,
    _force,
  ) => ())
  defer first_registration.dispose()
  let second_registration = register_viewer("observations-second", set_hidden_areas=(
    _ranges,
    _source,
    _force,
  ) => ())
  defer second_registration.dispose()
  let build_models : Array[Int32] = []
  let build_counts : Array[Int32] = []
  let render_facts : Array[(Int32, Int32, Bool)] = []
  let hover_facts : Array[(Bool, String)] = []
  let first_build = on_did_build_view_model("observations-first", observation => {
    build_models.push(observation.model.identity())
    build_counts.push(observation.token_count)
  })
  let first_render = on_did_render_model("observations-first", observation => {
    render_facts.push(
      (observation.line_count, observation.rendered_lines, observation.fresh),
    )
  })
  let first_hover = on_did_resolve_hover("observations-first", observation => {
    hover_facts.push((observation.ok, observation.revision))
  })
  defer first_render.dispose()
  defer first_hover.dispose()
  publish_view_model_built("observations-second", {
    model: second_model,
    line_count: 2,
    token_count: 20,
    tokenize_ms: 1.0,
    build_ms: 2.0,
  })
  publish_view_model_built("observations-first", {
    model: first_model,
    line_count: 2,
    token_count: 7,
    tokenize_ms: 3.0,
    build_ms: 4.0,
  })
  publish_model_rendered("observations-first", {
    model: first_model,
    line_count: 2,
    rendered_lines: 2,
    patch_ms: 5.0,
    fresh: true,
  })
  publish_hover_resolved("observations-first", {
    ok: true,
    revision: "revision-1",
  })
  assert_true(build_models == [first_model.identity()])
  assert_true(build_counts == [7])
  assert_true(render_facts == [(2, 2, true)])
  assert_true(hover_facts == [(true, "revision-1")])
  first_build.dispose()
  first_build.dispose()
  publish_view_model_built("observations-first", {
    model: first_model,
    line_count: 2,
    token_count: 99,
    tokenize_ms: 0.0,
    build_ms: 0.0,
  })
  assert_true(build_counts == [7])
}
