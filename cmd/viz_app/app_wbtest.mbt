///|
fn parsed_log(session : @agent_session.Session) -> @session_log.ParsedLog {
  {
    header: None,
    events: [
      for event in session.events() => event
    ],
    errors: [],
    partial_tail: false,
  }
}

///|
test "session metadata counts durable assistant responses" {
  let parsed = parsed_log(
    @agent_session.Session(SessionId("review-on-finish"), system_prompt="")
    .append(User(UserMessage(Content([Text("hi")]))))
    .append(Assistant(AssistantMessage("")))
    .append(
      Tool(
        ToolResult(tool_call_id="finish_1", tool_name="submit_report", content=[
          Text("finished: done"),
        ]),
      ),
    )
    .append(Runtime(RuntimeNotice("[review] goal-met audit: clean")))
    .append(Runtime(RuntimeNotice(@agent_session.GoalClearedNotice)))
    .append(Terminal(Finished("done"))),
  )
  inspect(agent_step_count(parsed), content="1")
  let continued = parsed_log(
    @agent_session.Session(SessionId("runtime-continuation"), system_prompt="")
    .append(User(UserMessage(Content([Text("hi")]))))
    .append(Assistant(AssistantMessage("")))
    .append(
      Tool(
        ToolResult(tool_call_id="finish_1", tool_name="submit_report", content=[
          Text("finished: first answer"),
        ]),
      ),
    )
    .append(Runtime(RuntimeNotice("background job completed")))
    .append(Assistant(AssistantMessage("second answer")))
    .append(Terminal(Finished("second answer"))),
  )
  inspect(agent_step_count(continued), content="2")
}

///|
test "session metadata does not double count finish tool terminals" {
  let parsed = parsed_log(
    @agent_session.Session(SessionId("finish-step"), system_prompt="")
    .append(User(UserMessage(Content([Text("hi")]))))
    .append(Assistant(AssistantMessage("")))
    .append(
      Tool(
        ToolResult(tool_call_id="finish_1", tool_name="finish", content=[
          Text("finished: done"),
        ]),
      ),
    )
    .append(Terminal(Finished("done"))),
  )
  inspect(agent_step_count(parsed), content="1")
}

///|
test "session metadata ignores checkpoint replay assistants" {
  let parsed = parsed_log(
    @agent_session.Session(SessionId("checkpoint-replay"), system_prompt="")
    .append(User(UserMessage(Content([Text("go")]))))
    .append(Assistant(AssistantMessage("first")))
    .append(
      Summary(
        SessionSummary(content="checkpoint", from_sequence=1, to_sequence=2),
      ),
    )
    .append(Assistant(AssistantMessage("first", is_replay=true)))
    .append(User(UserMessage(Content([Text("continue")]))))
    .append(Assistant(AssistantMessage("second")))
    .append(Terminal(Finished("second"))),
  )
  inspect(agent_step_count(parsed), content="2")
}

///|
fn marker_row(key : String, id : String, root_label : String) -> SessionRow {
  { key, id, root_label, last_active: None, is_marker: true, first_prompt: "", }
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
fn direct_row(key : String, id : String, root_label : String) -> SessionRow {
  {
    key,
    id,
    root_label,
    last_active: None,
    is_marker: false,
    first_prompt: "",
  }
}

///|
test "sidebar_groups keeps unrelated direct stores separate" {
  let rows = [
    direct_row("0|a", "a", "/srv/store-a"),
    direct_row("1|b", "b", "/srv/store-b"),
  ]
  @debug.debug_inspect(
    sidebar_groups(rows),
    content=(
      #|["/srv/store-a", "/srv/store-b"]
    ),
  )
}

///|
/// A non-empty standalone export with an untouched pane auto-opens its first
/// row. Live server lists, empty exports, an existing selection, or a dropped
/// file all keep the explicit click.
test "standalone exports auto-open their first session" {
  let row = direct_row("k1", "s1", "")
  let other = { ..row, key: "k2", id: "s2", }
  assert_true(should_auto_open(true, [row], selected=None, dropped=None))
  assert_true(should_auto_open(true, [row, other], selected=None, dropped=None))
  assert_false(should_auto_open(false, [row], selected=None, dropped=None))
  assert_false(should_auto_open(true, [], selected=None, dropped=None))
  assert_false(should_auto_open(true, [row], selected=Some("k1"), dropped=None))
  assert_false(
    should_auto_open(true, [row], selected=None, dropped=Some("f.jsonl")),
  )
}

///|
/// A no-op `Emit` for `update` tests that ignore the emitted commands.
fn stub_emit() -> @cmd.Emit[Msg] {
  Emit(_ => @cmd.none)
}

///|
test "a late session list does not clobber the dropped-file status" {
  let emit = stub_emit()
  let dropped = apply_dropped_file(
    init_model(),
    "run.jsonl",
    10L,
    (
      #|{"sequence":1,"ts":0,"item":{"kind":"user","payload":{"content":"hi"}}}
      #|
    ),
  )
  let before = dropped.status
  let (_, listed) = update(emit, SessionsFetched(Ok("[]")), dropped)
  inspect(listed.status == before, content="true")
  inspect(listed.sessions.length(), content="0")
  // Without an active dropped file the list outcome still updates the status.
  let (_, plain) = update(emit, SessionsFetched(Ok("[]")), init_model())
  inspect(plain.status, content="0 session(s)")
}

///|
test "error and escalated filters are mutually exclusive" {
  let emit = stub_emit()
  let errors = { ..init_model(), errors_only: true, }
  let (_, escalated) = update(emit, ToggleEscalatedOnly, errors)
  assert_true(escalated.escalated_only)
  assert_false(escalated.errors_only)
  let (_, errors_again) = update(emit, ToggleErrorsOnly, escalated)
  assert_true(errors_again.errors_only)
  assert_false(errors_again.escalated_only)
  // The build-error filter joins the same exclusivity group in both
  // directions: switching it on clears the others, and vice versa.
  let (_, build) = update(emit, ToggleBuildErrorsOnly, errors_again)
  assert_true(build.build_errors_only)
  assert_false(build.errors_only)
  assert_false(build.escalated_only)
  let (_, back) = update(emit, ToggleErrorsOnly, build)
  assert_true(back.errors_only)
  assert_false(back.build_errors_only)
}

///|
test "selecting a session invalidates an in-flight dropped-file read" {
  let emit = stub_emit()
  let model = { ..init_model(), drop_ticket: 5, }
  let (_, selected) = update(emit, Select("0|remote"), model)
  inspect(selected.drop_ticket, content="6")
  debug_inspect(selected.selected, content="Some(\"0|remote\")")
  // The read the old drop issued now carries a stale ticket.
  let (_, unchanged) = update(
    emit,
    DroppedFileRead(5, "old.jsonl", 1L, Ok("")),
    selected,
  )
  debug_inspect(unchanged.dropped, content="None")
  debug_inspect(unchanged.selected, content="Some(\"0|remote\")")
}

///|
test "stale dropped-file reads are discarded" {
  let emit = stub_emit()
  let model = { ..init_model(), drop_ticket: 2, }
  // A read issued before the user moved on carries an old ticket: ignored.
  let (_, unchanged) = update(
    emit,
    DroppedFileRead(1, "old.jsonl", 1L, Ok("")),
    model,
  )
  debug_inspect(unchanged.dropped, content="None")
  // The read matching the current ticket applies.
  let (_, applied) = update(
    emit,
    DroppedFileRead(2, "new.jsonl", 1L, Ok("")),
    model,
  )
  debug_inspect(applied.dropped, content="Some(\"new.jsonl\")")
}

///|
/// An `s=` session key parsed from the URL hash is honored by the first
/// session listing — in the live viewer and exports alike — and consumed
/// whether or not it matches, so a stale key cannot re-fire on refreshes of
/// the list.
test "the hash session key restores the selection on the first listing" {
  let emit = stub_emit()
  let listing =
    #|[{"key":"k1","id":"s1"},{"key":"k2","id":"s2"}]
  let pending = { ..init_model(), pending_restore_key: Some("k2"), }
  let (_, restored) = update(emit, SessionsFetched(Ok(listing)), pending)
  debug_inspect(restored.selected, content="Some(\"k2\")")
  debug_inspect(restored.pending_restore_key, content="None")
  // An unknown key is consumed without selecting anything.
  let stale = { ..init_model(), pending_restore_key: Some("gone"), }
  let (_, ignored) = update(emit, SessionsFetched(Ok(listing)), stale)
  debug_inspect(ignored.selected, content="None")
  debug_inspect(ignored.pending_restore_key, content="None")
  // An existing selection is never yanked by a late restore key.
  let busy = {
    ..init_model(),
    pending_restore_key: Some("k2"),
    selected: Some("k1"),
  }
  let (_, kept) = update(emit, SessionsFetched(Ok(listing)), busy)
  debug_inspect(kept.selected, content="Some(\"k1\")")
}
