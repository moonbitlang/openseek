///|
test "parse_load reads a found envelope with header" {
  let text =
    #|{"found":true,"events":"{\"sequence\":1,\"ts\":0,\"item\":{\"kind\":\"user\",\"payload\":{\"content\":\"hi\"}}}\n","header":{"version":1,"system_prompt":"SYS"}}
  match parse_load(text) {
    Loaded(parsed, system_prompt, header_present) => {
      inspect(parsed.events.length(), content="1")
      inspect(system_prompt, content="SYS")
      inspect(header_present, content="true")
    }
    _ => fail("expected Loaded")
  }
}

///|
test "parse_load treats a null header as events-only" {
  let text =
    #|{"found":true,"events":"","header":null}
  match parse_load(text) {
    Loaded(_, system_prompt, header_present) => {
      inspect(system_prompt, content="")
      inspect(header_present, content="false")
    }
    _ => fail("expected Loaded")
  }
}

///|
test "parse_load distinguishes not-found from malformed" {
  guard parse_load("{\"found\":false}") is NotFound else {
    fail("expected NotFound")
  }
  guard parse_load("not json") is Malformed else { fail("expected Malformed") }
  guard parse_load("{\"events\":\"x\"}") is Malformed else {
    fail("expected Malformed when found is missing")
  }
}

///|
test "parse_session_rows reads the listing, skipping malformed rows" {
  let text =
    #|[{"key":"0|a","id":"a","root_label":"app/.openseek","last_active":1,"first_prompt":"hello"},{"first_prompt":"no id"},{"id":"b","root":"lib/.openseek","first_prompt":""}]
  guard parse_session_rows(text) is Some(rows) else { fail("expected Some") }
  inspect(rows.length(), content="2")
  inspect(rows[0].key, content="0|a")
  inspect(rows[0].id, content="a")
  inspect(rows[0].root_label, content="app/.openseek")
  inspect(rows[0].first_prompt, content="hello")
  inspect(rows[1].key, content="b")
  inspect(rows[1].id, content="b")
  inspect(rows[1].root_label, content="lib/.openseek")
}

///|
test "parse_session_rows distinguishes empty list from a non-array body" {
  guard parse_session_rows("[]") is Some(empty) else {
    fail("expected Some([])")
  }
  inspect(empty.length(), content="0")
  guard parse_session_rows("oops 500") is None else {
    fail("expected None for a non-JSON body")
  }
  guard parse_session_rows("{\"error\":\"x\"}") is None else {
    fail("expected None for a non-array body")
  }
}

///|
test "session_url percent-encodes the id" {
  inspect(session_url("0|a b/c"), content="/api/sessions/0%7Ca%20b%2Fc")
}

///|
test "sidebar_roots preserves listing order without duplicates" {
  let rows = [
    { key: "0|a", id: "a", root_label: "app/.openseek", first_prompt: "" },
    { key: "0|b", id: "b", root_label: "app/.openseek", first_prompt: "" },
    { key: "1|c", id: "c", root_label: "lib/.openseek", first_prompt: "" },
  ]
  @debug.debug_inspect(
    sidebar_roots(rows),
    content=(
      #|["app/.openseek", "lib/.openseek"]
    ),
  )
}

///|
test "collapsed root helpers toggle and prune stale roots" {
  let rows = [
    { key: "0|a", id: "a", root_label: "app/.openseek", first_prompt: "" },
    { key: "1|b", id: "b", root_label: "lib/.openseek", first_prompt: "" },
  ]
  let collapsed = toggle_collapsed_root([], "app/.openseek")
  @debug.debug_inspect(collapsed, content="[\"app/.openseek\"]")
  let expanded = toggle_collapsed_root(collapsed, "app/.openseek")
  @debug.debug_inspect(expanded, content="[]")
  @debug.debug_inspect(
    prune_collapsed_roots(["app/.openseek", "stale/.openseek"], rows),
    content="[\"app/.openseek\"]",
  )
}

///|
test "app class tracks sidebar visibility" {
  let visible = { ..init_model(), sidebar_visible: true }
  let hidden = { ..init_model(), sidebar_visible: false }
  inspect(app_class(visible), content="app")
  inspect(app_class(hidden), content="app sidebar-hidden")
}

///|
test "theme values map to the data-theme attribute" {
  inspect(Theme::value(Light), content="light")
  inspect(Theme::value(Dark), content="dark")
  inspect(Theme::value(System), content="system")
}

///|
test "visualizer defaults to model view" {
  assert_true(init_model().view_mode == ModelView)
}
