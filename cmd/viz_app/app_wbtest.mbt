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
  {
    key,
    id,
    root_label,
    run_root: None,
    last_active: None,
    is_marker: true,
    first_prompt: "",
  }
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
    run_root: None,
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

///|
/// A literal `+` in an `s=` key is a space, while an escaped `%2B` stays a
/// plus; malformed escapes and invalid UTF-8 reject the key.
test "hash session keys decode plus signs and reject malformed escapes" {
  fn key(fragment : String) -> String? raise MalformedHashSessionKey {
    HashSessionKey::from_fragment(fragment).map(key => key.0)
  }

  assert_eq(key("x=1&s=a+b%2Bc%20%E4%B8%AD"), Some("a b+c 中"))
  assert_eq(key("x=1"), None)
  for malformed in ["s=%", "s=%zz", "s=%FF"] {
    try key(malformed) catch {
      MalformedHashSessionKey => ()
    } noraise {
      _ => fail("expected \{malformed} to be rejected")
    }
  }
}

///|
test "a duration reads in the unit its size deserves" {
  assert_eq(duration_label(0L), "0 ms")
  assert_eq(duration_label(999L), "999 ms")
  assert_eq(duration_label(1_000L), "1 s")
  assert_eq(duration_label(1_250L), "1.3 s")
  // A 20-minute run must not read as a seven-digit millisecond count.
  assert_eq(duration_label(1_234_567L), "20m 34s")
  // Longer runs climb units instead of printing thousands of minutes.
  assert_eq(duration_label(3_600_000L), "1h 0m")
  assert_eq(duration_label(95_040_000L), "1d 2h")
  assert_eq(duration_label(1_368_252_000L), "15d 20h")
}

///|
test "a token count is compressed to a readable unit" {
  assert_eq(token_label(0), "0")
  assert_eq(token_label(999), "999")
  assert_eq(token_label(86_200), "86.2k")
  assert_eq(token_label(116_038_924L), "116M")
}

///|
test "a bar position keeps one decimal and drops a trailing zero" {
  assert_eq(round1(0.0), "0")
  assert_eq(round1(12.34), "12.3")
  assert_eq(round1(99.96), "100")
  assert_eq(round1(0.35), "0.4")
}

///|
/// One waterfall row for a tree-shape test: only the identity and the nesting
/// matter here, so the timing fields are constant.
fn tree_row(
  id : String,
  parent : String?,
  depth : Int32,
) -> @trajectory.WaterfallRow {
  (
    {
      span: (
        {
          id,
          parent_id: parent,
          session_id: "run",
          title: "main",
          depth,
          kind: Turn,
          status: Succeeded,
          label: id,
          started_at_ms: 0L,
          ended_at_ms: Some(1L),
          job_id: (None : String?),
          job_ids: [],
          sequence: (None : Int32?),
          tag: None,
          metadata: (Map([]) : Map[String, @json.Json]),
        } : @trajectory.TrajectorySpan),
      left_percent: 0.0,
      width_percent: 1.0,
      duration_ms: 1L,
      open_right_edge: false,
    } : @trajectory.WaterfallRow)
}

///|
test "folding a span hides its descendants and nothing beside them" {
  let rows : Array[@trajectory.WaterfallRow] = [
    tree_row("run", None, 0),
    tree_row("t1", Some("run"), 1),
    tree_row("a", Some("t1"), 2),
    tree_row("b", Some("t1"), 2),
    tree_row("t2", Some("run"), 1),
    tree_row("c", Some("t2"), 2),
  ]
  let ids = (rows : Array[@trajectory.WaterfallRow]) => {
    [
      for row in rows => row.span.id
    ]
  }
  // Nothing folded: the tree as it arrives.
  assert_eq(ids(visible_rows(rows, [])), ["run", "t1", "a", "b", "t2", "c"])
  // One turn folded: its own steps go, its sibling turn stays.
  assert_eq(ids(visible_rows(rows, ["t1"])), ["run", "t1", "t2", "c"])
  // A step folded leaves its siblings.
  assert_eq(ids(visible_rows(rows, ["a"])), ["run", "t1", "a", "b", "t2", "c"])
  // The run folded leaves the run itself, so it can be unfolded again.
  assert_eq(ids(visible_rows(rows, ["run"])), ["run"])
  let children = span_children_map(rows)
  assert_true(children.get("t1") is Some(_))
  assert_false(children.get("a") is Some(_))
}

///|
test "a run's root is the session that spawned the rest" {
  assert_eq(run_root_of("run"), "run")
  assert_eq(run_root_of("run-sr-1"), "run")
  assert_eq(run_root_of("run-sr-1-sr-2"), "run")
  // Only a trailing ordinal makes a child: an id that merely contains `-sr-`
  // stays its own root, like `trajectory.parent_session_of` decides.
  assert_eq(run_root_of("my-sr-run"), "my-sr-run")
  assert_eq(run_root_of("run-sr-x"), "run-sr-x")
  assert_eq(run_root_of("run-sr-"), "run-sr-")
}

///|
/// A finished span of one kind, for the measurements that only read times.
fn timed_span(
  kind : @trajectory.SpanKind,
  start : Int64,
  end : Int64,
) -> @trajectory.TrajectorySpan {
  {
    id: "span-\{start}-\{end}",
    parent_id: None,
    session_id: "run",
    title: "main",
    depth: 2,
    kind,
    status: Succeeded,
    label: kind.tag(),
    started_at_ms: start,
    ended_at_ms: Some(end),
    job_id: None,
    job_ids: [],
    sequence: None,
    tag: None,
    metadata: Map([]),
  }
}

///|
test "waiting counts a stretch once, not once per pool and once per job" {
  // A `job_wait` happens inside the jobs it waits on, and two jobs can run at
  // the same time: the plain sums would read 1_800 ms where the reader waited
  // 700.
  let spans = [
    timed_span(BackgroundJob, 200L, 900L),
    timed_span(BackgroundJob, 200L, 600L),
    timed_span(JobWait, 200L, 900L),
  ]
  assert_eq(waiting_ms(spans), 700L)
  let none : Array[@trajectory.TrajectorySpan] = []
  assert_eq(waiting_ms(none), 0L)
}

///|
test "the time scale labels midnight with a date and other marks with a clock" {
  // 2021-11-01 00:00 in the viewer's local timezone.
  let midnight : @trajectory.AxisTick = {
    at_ms: 1_635_724_800_000L,
    axis_ms: 0L,
    is_day: true,
  }
  assert_eq(tick_label_from("2021-11-01 00:00", midnight, 21_600_000L), "Nov 1")
  let noon : @trajectory.AxisTick = {
    ..midnight,
    at_ms: midnight.at_ms + 43_200_000L,
    is_day: false,
  }
  assert_eq(tick_label_from("2021-11-01 12:00", noon, 3_600_000L), "12:00")
  // A run of seconds needs the seconds, or two marks carry the same label.
  let fifteen : @trajectory.AxisTick = { ..noon, at_ms: noon.at_ms + 15_000L, }
  assert_eq(tick_label_from("2021-11-01 12:00", fifteen, 15_000L), "12:00:15")
}

///|
test "a standalone export only offers the runs it baked" {
  let served = { ..init_model(), standalone: false, }
  assert_true(trajectory_available(served, "viz-1"))
  // A test page bakes nothing, so an export has no run to open and no server
  // to ask: the link must not appear.
  let exported = { ..init_model(), standalone: true, }
  assert_false(trajectory_available(exported, "viz-1"))
}

///|
/// The same row with its span marked failed, for the filter's tests.
fn failed_row(row : @trajectory.WaterfallRow) -> @trajectory.WaterfallRow {
  { ..row, span: { ..row.span, status: Failed, }, }
}

///|
test "the failures filter keeps the failed steps and the rows that place them" {
  let rows : Array[@trajectory.WaterfallRow] = [
    tree_row("run", None, 0),
    tree_row("t1", Some("run"), 1),
    failed_row(tree_row("boom", Some("t1"), 2)),
    tree_row("t2", Some("run"), 1),
    tree_row("llm", Some("t2"), 2),
  ]
  assert_eq(failure_rows(rows, rows).map(row => row.span.id), [
    "run", "t1", "boom",
  ])
  // The filter narrows what is shown; it does not unfold a subtree the reader
  // folded away.
  let folded = visible_rows(rows, ["t1"])
  assert_eq(failure_rows(rows, folded).map(row => row.span.id), ["run", "t1"])
  // A run with nothing failed keeps nothing, which is what the empty state says.
  let clean : Array[@trajectory.WaterfallRow] = [tree_row("run", None, 0)]
  assert_true(failure_rows(clean, clean).is_empty())
}

///|
test "duration and token labels promote before rounding past a unit boundary" {
  assert_eq(duration_label(59_950L), "1m 0s")
  assert_eq(token_label(999_960L), "1M")
}

///|
test "unfold_failed_ancestors reveals collapsed ancestors of failed steps" {
  let run_row = tree_row("run", None, 0)
  let t1 = tree_row("t1", Some("run"), 1)
  let boom = failed_row(tree_row("boom", Some("t1"), 2))
  let t2 = tree_row("t2", Some("run"), 1)
  let trace : @trajectory.Trajectory = {
    root_session_id: "run",
    t0_ms: 0L,
    t_end_ms: 100L,
    live: false,
    sessions: [],
    spans: [run_row.span, t1.span, boom.span, t2.span],
    stats: {
      wall_ms: 100L,
      llm_ms: 0L,
      tool_ms: 0L,
      wait_ms: 0L,
      job_ms: 0L,
      prompt_tokens: 0L,
      completion_tokens: 0L,
      critical_path_ms: 0L,
      critical_path: [],
      span_count: 4,
      turn_count: 2,
      session_count: 1,
    },
  }
  assert_eq(unfold_failed_ancestors(trace, ["t1", "t2"]), ["t2"])
}

///|
test "ToggleTrajectoryFailures unfolds collapsed ancestors of failures" {
  let run_row = tree_row("run", None, 0)
  let t1 = tree_row("t1", Some("run"), 1)
  let boom = failed_row(tree_row("boom", Some("t1"), 2))
  let t2 = tree_row("t2", Some("run"), 1)
  let trace : @trajectory.Trajectory = {
    root_session_id: "run",
    t0_ms: 0L,
    t_end_ms: 100L,
    live: false,
    sessions: [],
    spans: [run_row.span, t1.span, boom.span, t2.span],
    stats: {
      wall_ms: 100L,
      llm_ms: 0L,
      tool_ms: 0L,
      wait_ms: 0L,
      job_ms: 0L,
      prompt_tokens: 0L,
      completion_tokens: 0L,
      critical_path_ms: 0L,
      critical_path: [],
      span_count: 4,
      turn_count: 2,
      session_count: 1,
    },
  }
  let model = {
    ..init_model(),
    trajectory_root: Some("run"),
    trajectory: Some(trace),
    trajectory_collapsed: ["t1", "t2"],
  }
  let (_, next) = update(stub_emit(), ToggleTrajectoryFailures, model)
  assert_true(next.trajectory_failed_only)
  assert_eq(next.trajectory_collapsed, ["t2"])
  // WatchTick skips overlapping fetches while trajectory or job requests are in flight.
  let watching = {
    ..model,
    trajectory_pending: true,
    trajectory_job_open: ["run/job-7"],
    trajectory_job_pending: ["run/job-7"],
  }
  let (_, after_tick) = update(stub_emit(), WatchTick, watching)
  assert_true(after_tick.trajectory_pending)
  assert_eq(after_tick.trajectory_job_pending, ["run/job-7"])
}

///|
test "session_row_of parses run_root and find_job_focus_span disambiguates start_hint" {
  let raw = "[{\"key\":\"k1\",\"id\":\"worker-custom\",\"root\":\"s\",\"root_label\":\"ws\",\"run_root\":\"run-main\",\"is_marker\":true,\"first_prompt\":\"go\"}]"
  guard parse_session_rows(raw) is Some([row]) else {
    fail("expected single row")
  }
  assert_eq(row.run_root, Some("run-main"))
  let s1 : @trajectory.TrajectorySpan = {
    id: "run-main:span:1",
    parent_id: None,
    session_id: "run-main",
    title: "run",
    depth: 1,
    kind: BackgroundJob,
    status: Succeeded,
    label: "bg-1",
    started_at_ms: 1_000L,
    ended_at_ms: Some(2_000L),
    job_id: Some("bg-1"),
    job_ids: ["bg-1"],
    sequence: None,
    tag: None,
    metadata: Map([]),
  }
  let s2 : @trajectory.TrajectorySpan = {
    ..s1,
    id: "run-main:span:2",
    started_at_ms: 9_000L,
    ended_at_ms: Some(10_000L),
  }
  let trace : @trajectory.Trajectory = {
    root_session_id: "run-main",
    t0_ms: 1_000L,
    t_end_ms: 10_000L,
    live: false,
    sessions: [],
    spans: [s1, s2],
    stats: {
      wall_ms: 9_000L,
      llm_ms: 0L,
      tool_ms: 0L,
      wait_ms: 0L,
      job_ms: 0L,
      prompt_tokens: 0L,
      completion_tokens: 0L,
      critical_path_ms: 0L,
      critical_path: [],
      span_count: 2,
      turn_count: 0,
      session_count: 1,
    },
  }
  assert_eq(
    find_job_focus_span(trace, "bg-1", start_hint=8_950L).map(s => s.id),
    Some("run-main:span:2"),
  )
  assert_eq(
    job_start_hint(
      Some(trace),
      "run-main/bg-1",
      preferred_span_id="run-main:span:2",
    ),
    Some(9_000L),
  )
  // Oversized integer strings reject cleanly instead of overflowing Int64.
  assert_eq(parse_optional_int64(Some("99999999999999999999999")), None)
  // Re-opening the same active trajectory root preserves collapsed state.
  let open = {
    ..init_model(),
    trajectory_root: Some("run-main"),
    trajectory_collapsed: ["turn-1"],
  }
  let (_, kept) = open_trajectory_from_fragment(stub_emit(), open, "t=run-main").unwrap()
  assert_eq(kept.trajectory_collapsed, ["turn-1"])
}

///|
test "virtual_window bounds DOM rows above WaterfallVirtualThreshold" {
  assert_eq(virtual_window(80, 400, 600), (0, 80))
  let (start, end) = virtual_window(500, 3200, 640)
  // 3200 / 32 = 100, minus 16 overscan = 84; (3200+640)/32 + 1 + 16 = 137
  assert_eq((start, end), (84, 137))
  assert_eq(virtual_window(500, 0, 640), (0, 37))
  // Shrinking row count below old scroll_top clamps to the tail instead of start > end.
  let (clamped_start, clamped_end) = virtual_window(150, 5000, 560)
  assert_eq(clamped_end, 150)
  assert_true(clamped_start < clamped_end)
}

///|
test "auto_collapsed_turns folds early succeeded turns while keeping failures and latest turn open" {
  fn mk(
    id : String,
    parent_id : String?,
    kind : @trajectory.SpanKind,
    status : @trajectory.SpanStatus,
  ) -> @trajectory.TrajectorySpan {
    {
      id,
      parent_id,
      session_id: "run",
      title: "run",
      depth: 0,
      kind,
      status,
      label: id,
      started_at_ms: 0L,
      ended_at_ms: Some(100L),
      job_id: None,
      job_ids: [],
      sequence: None,
      tag: None,
      metadata: Map([]),
    }
  }
  let spans : Array[@trajectory.TrajectorySpan] = [
    mk("run", None, Run, Succeeded),
    mk("turn-1", Some("run"), Turn, Succeeded),
    mk("turn-2", Some("run"), Turn, Succeeded),
    mk("turn-2-err", Some("turn-2"), ToolExec, Failed),
    mk("turn-3", Some("run"), Turn, Succeeded),
  ]
  for i in 0..<205 {
    spans.push(mk("step-\{i}", Some("turn-1"), ToolExec, Succeeded))
  }
  let trace : @trajectory.Trajectory = {
    root_session_id: "run",
    t0_ms: 0L,
    t_end_ms: 1000L,
    live: false,
    sessions: [],
    spans,
    stats: {
      wall_ms: 1000L,
      llm_ms: 0L,
      tool_ms: 0L,
      wait_ms: 0L,
      job_ms: 0L,
      prompt_tokens: 0L,
      completion_tokens: 0L,
      critical_path_ms: 0L,
      critical_path: [],
      span_count: spans.length(),
      turn_count: 3,
      session_count: 1,
    },
  }
  assert_eq(auto_collapsed_turns(trace), ["turn-1"])
}
