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
test "sidebar_groups clusters by container, in listing order, no duplicates" {
  let rows = [
    // Two sibling run workspaces share the /tmp/ab container.
    {
      key: "0|a",
      id: "run",
      root_label: "/tmp/ab/A-1/.openseek",
      first_prompt: "",
    },
    {
      key: "1|b",
      id: "run",
      root_label: "/tmp/ab/B-1/.openseek",
      first_prompt: "",
    },
    // A workspace directly under cwd groups by itself; a bare store by cwd.
    { key: "2|c", id: "c", root_label: "app/.openseek", first_prompt: "" },
    { key: "3|d", id: "d", root_label: ".openseek", first_prompt: "" },
  ]
  @debug.debug_inspect(
    sidebar_groups(rows),
    content=(
      #|["/tmp/ab", "app", ""]
    ),
  )
}

///|
test "session grouping derives container, row label, and heading" {
  // A nested run workspace: grouped by container, labelled by workspace name.
  inspect(session_group("/tmp/ab/A-1/.openseek"), content="/tmp/ab")
  inspect(session_row_label("/tmp/ab/A-1/.openseek", "run"), content="A-1")
  inspect(group_display("/tmp/ab"), content="/tmp/ab")
  // A workspace directly under cwd: grouped by the workspace, labelled by id.
  inspect(session_group("app/.openseek"), content="app")
  inspect(session_row_label("app/.openseek", "c"), content="c")
  // A bare cwd store: the current-directory group, labelled by id.
  inspect(session_group(".openseek"), content="")
  inspect(session_row_label(".openseek", "cli-1"), content="cli-1")
  inspect(group_display(""), content="current directory")
  // A leading "./" is stripped from the heading.
  inspect(group_display("./.repos"), content=".repos")
  inspect(session_group("./.repos/toml_run_1/.openseek"), content="./.repos")
  inspect(
    session_row_label("./.repos/toml_run_1/.openseek", "run"),
    content="toml_run_1",
  )
}

///|
test "collapsed group helpers toggle and prune stale groups" {
  let rows = [
    { key: "0|a", id: "a", root_label: "app/.openseek", first_prompt: "" },
    { key: "1|b", id: "b", root_label: "lib/.openseek", first_prompt: "" },
  ]
  let collapsed = toggle_collapsed_root([], "app")
  @debug.debug_inspect(collapsed, content="[\"app\"]")
  let expanded = toggle_collapsed_root(collapsed, "app")
  @debug.debug_inspect(expanded, content="[]")
  @debug.debug_inspect(
    prune_collapsed_roots(["app", "stale"], rows),
    content="[\"app\"]",
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
