///|
test "parse_load reads a found envelope with header" {
  let text =
    #|{"found":true,"events":"{\"sequence\":1,\"ts\":0,\"item\":{\"kind\":\"user\",\"payload\":{\"content\":\"hi\"}}}\n","events_bytes":77,"header":{"version":1,"system_prompt":"SYS"}}
  match parse_load(text) {
    Loaded(parsed, system_prompt, header_present, log_bytes) => {
      inspect(parsed.events.length(), content="1")
      inspect(system_prompt, content="SYS")
      inspect(header_present, content="true")
      inspect(log_bytes, content="77")
    }
    _ => fail("expected Loaded")
  }
}

///|
test "parse_load treats a null header as events-only" {
  let text =
    #|{"found":true,"events":"","header":null}
  match parse_load(text) {
    Loaded(_, system_prompt, header_present, log_bytes) => {
      inspect(system_prompt, content="")
      inspect(header_present, content="false")
      inspect(log_bytes, content="0")
    }
    _ => fail("expected Loaded")
  }
}

///|
fn parsed_log(session : @agent_session.Session) -> @session_log.ParsedLog {
  {
    events: [
      for event in session.events() => event
    ],
    errors: [],
    partial_tail: false,
  }
}

///|
test "session metadata counts steps and total runtime" {
  let text =
    #|{"found":true,"events":"{\"sequence\":1,\"ts\":100000,\"item\":{\"kind\":\"user\",\"payload\":{\"content\":\"hi\"}}}\n{\"sequence\":2,\"ts\":101500,\"item\":{\"kind\":\"assistant\",\"payload\":{\"content\":\"\",\"tool_calls\":[]}}}\n{\"sequence\":3,\"ts\":170300,\"item\":{\"kind\":\"terminal\",\"payload\":{\"kind\":\"finished\",\"message\":\"done\"}}}\n","events_bytes":307,"header":null}
  match parse_load(text) {
    Loaded(parsed, _, _, log_bytes) => {
      inspect(format_log_size(log_bytes), content="307 B")
      inspect(agent_step_count(parsed), content="1")
      inspect(runtime_label(parsed), content="70.3s")
      inspect(end_time_label(parsed), content="1970-01-01 00:02 UTC")
    }
    _ => fail("expected Loaded")
  }
}

///|
test "session metadata counts terminal final answers as steps" {
  let parsed = parsed_log(
    @agent_session.Session(SessionId("terminal-step"), system_prompt="")
    .append(User(UserMessage("hi")))
    .append(Terminal(Finished("done"))),
  )
  inspect(agent_step_count(parsed), content="1")
}

///|
test "session metadata does not double count finish tool terminals" {
  let parsed = parsed_log(
    @agent_session.Session(SessionId("finish-step"), system_prompt="")
    .append(User(UserMessage("hi")))
    .append(Assistant(AssistantMessage("")))
    .append(
      Tool(
        ToolResult(
          tool_call_id="finish_1",
          tool_name="finish",
          content="finished: done",
        ),
      ),
    )
    .append(Terminal(Finished("done"))),
  )
  inspect(agent_step_count(parsed), content="1")
}

///|
test "absolute time labels format UTC timestamps" {
  inspect(absolute_time_label(0L), content="1970-01-01 00:00 UTC")
  inspect(last_active_label(Some(0L)), content="1970-01-01 00:00 UTC")
  inspect(last_active_label(None), content="")
}

///|
test "log size formats larger byte counts" {
  inspect(format_log_size(554702L), content="541.7 KiB")
  inspect(format_log_size(2097152L), content="2.0 MiB")
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
  debug_inspect(rows[0].last_active, content="Some(1)")
  inspect(rows[1].key, content="b")
  inspect(rows[1].id, content="b")
  inspect(rows[1].root_label, content="lib/.openseek")
  debug_inspect(rows[1].last_active, content="None")
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
    marker_row("0|a", "run", "/tmp/ab/A-1/.openseek"),
    marker_row("1|b", "run", "/tmp/ab/B-1/.openseek"),
    // Default-scan "./" workspaces stay separate (not merged under ".").
    marker_row("2|c", "c", "./app/.openseek"),
    marker_row("3|d", "d", "./lib/.openseek"),
    marker_row("4|e", "e", "./.openseek"),
  ]
  @debug.debug_inspect(
    sidebar_groups(rows),
    content=(
      #|["/tmp/ab", "app", "lib", ""]
    ),
  )
}

///|
fn marker_row(key : String, id : String, root_label : String) -> SessionRow {
  { key, id, root_label, last_active: None, is_marker: true, first_prompt: "" }
}

///|
test "session grouping derives container, row label, and heading" {
  // A nested run workspace (marker store): grouped by container, labelled by
  // workspace name.
  inspect(session_group("/tmp/ab/A-1/.openseek", true), content="/tmp/ab")
  inspect(
    session_row_label("/tmp/ab/A-1/.openseek", "run", true),
    content="A-1",
  )
  inspect(group_display("/tmp/ab"), content="/tmp/ab")
  // A workspace directly under cwd groups by itself, labelled by id — and the
  // default-scan "./" prefix normalizes to the same key as the bare form.
  inspect(session_group("./app/.openseek", true), content="app")
  inspect(session_group("app/.openseek", true), content="app")
  inspect(session_row_label("./app/.openseek", "c", true), content="c")
  // A bare cwd store: the current-directory group, labelled by id.
  inspect(session_group("./.openseek", true), content="")
  inspect(session_group(".openseek", true), content="")
  inspect(session_row_label(".openseek", "cli-1", true), content="cli-1")
  inspect(group_display(""), content="current directory")
  // Nested "./"-prefixed roots cluster by their normalized container.
  inspect(
    session_group("./.repos/toml_run_1/.openseek", true),
    content=".repos",
  )
  inspect(
    session_row_label("./.repos/toml_run_1/.openseek", "run", true),
    content="toml_run_1",
  )
  // A direct store (is_marker=false) is its own group, labelled by id — even a
  // hidden one is NOT stripped, so unrelated direct stores never merge.
  inspect(
    session_group("/tmp/openseek-sessions", false),
    content="/tmp/openseek-sessions",
  )
  inspect(
    session_row_label("/tmp/openseek-sessions", "cli-1", false),
    content="cli-1",
  )
  inspect(
    session_group("/tmp/.my-sessions", false),
    content="/tmp/.my-sessions",
  )
  // A non-hidden marker (e.g. --session-root-name sessions) still groups by
  // container when the server flags it as a marker.
  inspect(session_group("runs/A-1/sessions", true), content="runs")
  inspect(session_row_label("runs/A-1/sessions", "x", true), content="A-1")
}

///|
test "sidebar_groups keeps unrelated direct stores separate" {
  let rows = [
    {
      key: "0|a",
      id: "a",
      root_label: "/srv/store-a",
      last_active: None,
      is_marker: false,
      first_prompt: "",
    },
    {
      key: "1|b",
      id: "b",
      root_label: "/srv/store-b",
      last_active: None,
      is_marker: false,
      first_prompt: "",
    },
  ]
  @debug.debug_inspect(
    sidebar_groups(rows),
    content=(
      #|["/srv/store-a", "/srv/store-b"]
    ),
  )
}

///|
test "collapsed group helpers toggle and prune stale groups" {
  let rows = [
    marker_row("0|a", "a", "app/.openseek"),
    marker_row("1|b", "b", "lib/.openseek"),
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
