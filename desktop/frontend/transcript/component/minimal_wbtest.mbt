///|
test "minimal user boundaries group recorded and streaming assistant content" {
  let input = Input(
    minimal=true,
    source=OpenSeek,
    focused=@interop.ChannelId::Local,
    active_session="messages-test",
    current_project=None,
    projects=[],
    can_choose_project=false,
    project_menu_open=false,
    project_query="",
    root=None,
    // Text-only turns use the same User variant with an empty attachment list.
    items=VisibleRow::history([
      {
        kind: User(text="First question", images=[]),
        ts: None,
        sequence: Some(1),
      },
      {
        kind: Assistant(
          reasoning=None,
          prose=Some("Inspecting files"),
          calls=[
            {
              call_id: "read",
              children: [],
              name: "read",
              arguments: None,
              outcome: Pending(output=None),
            },
          ],
          replay=false,
          finished=false,
        ),
        ts: None,
        sequence: Some(2),
      },
      {
        kind: User(text="Second question", images=[]),
        ts: None,
        sequence: Some(3),
      },
    ]),
    streaming_response=Some("Checking another file"),
    streaming_identity="live",
  )
  let blocks = input.minimal_blocks().to_array()
  assert_eq(blocks.length(), 4)
  assert_true(blocks[0].content is Item(item={ kind: User(..), .. }, ..))
  assert_true(
    blocks[1].content
    is Minimal(
      Messages(
        [{ content: Prose(..), .. }, { content: Activity(_), .. }],
        active_group=None
      )
    ),
  )
  assert_true(blocks[2].content is Item(item={ kind: User(..), .. }, ..))
  assert_true(
    blocks[3].content
    is Minimal(
      Messages([{ content: Prose(live=true, ..), .. }], active_group=None)
    ),
  )
  // Subsequent deltas replace the text inside the same keyed message group.
  let updated = {
      ..input,
      streaming_response: Some("Checking another file now"),
    }
    .minimal_blocks()
    .to_array()
  assert_eq(blocks[3].key.wire(), updated[3].key.wire())
  let active_input = {
    ..input,
    items: [input.items[0], input.items[1]],
    streaming_response: None,
  }
  assert_true(
    active_input.minimal_blocks().to_array()[1].content
    is Minimal(Messages(_, active_group=Some(_))),
  )
  // New streamed prose and explicit terminal events both retire the group.
  for
    retired in [
      { ..active_input, streaming_response: Some("Next step"), },
      {
        ..active_input,
        items: [
          ..active_input.items,
          {
            identity: "terminal",
            item: { kind: TurnEnd, ts: None, sequence: Some(3), },
          },
        ],
      },
    ] {
    assert_true(
      retired.minimal_blocks().to_array()[1].content
      is Minimal(Messages(_, active_group=None)),
    )
  }
}

///|
test "minimal mbtx retains its description across completion and failure" {
  let call : @transcript.ToolCall = {
    children: [],
    call_id: "script",
    name: "mbtx",
    arguments: Some("{\"description\":\"Check project details\"}"),
    outcome: Pending(output=None),
  }
  let pending = MinimalCall::from_tool(call)
  assert_eq(pending.caption, "Check project details")
  assert_true(pending.status is Pending)
  for failed in [false, true] {
    let completed = MinimalCall::from_tool({
      ..call,
      outcome: Done(
        content="output",
        is_error=failed,
        brief=Some(if failed { "mbtx (exit=1)" } else { "mbtx (exit=0)" }),
      ),
    })
    assert_eq(completed.caption, "Check project details")
    assert_false(completed.status is Pending)
    assert_eq(completed.status is Failed, failed)
  }
}

///|
test "minimal mbtx falls back safely without a usable description" {
  for
    arguments in [None, Some("{"), Some("{}"), Some("{\"description\":\" \"}")] {
    let call : @transcript.ToolCall = {
      children: [],
      call_id: "script",
      name: "mbtx",
      arguments,
      outcome: Done(
        content="output",
        is_error=false,
        brief=Some("mbtx (exit=0)"),
      ),
    }
    assert_eq(MinimalCall::from_tool(call).caption, "mbtx (exit=0)")
    assert_eq(
      MinimalCall::from_tool({ ..call, outcome: Pending(output=None), }).caption,
      "mbtx",
    )
  }
}

///|
test "minimal descriptions share the card payload boundary" {
  let prefix = "{\"description\":\"Check project details\",\"source\":\""
  let suffix = "\"}"
  let padding = MAX_CARD_PAYLOAD_CHARS - prefix.length() - suffix.length()
  for extra in [0, 1] {
    let arguments = prefix + "x".repeat(padding + extra) + suffix
    assert_eq(arguments.length(), MAX_CARD_PAYLOAD_CHARS + extra)
    for name in ["mbtx", "read"] {
      let call : @transcript.ToolCall = {
        children: [],
        call_id: name,
        name,
        arguments: Some(arguments),
        outcome: Pending(output=None),
      }
      assert_eq(
        MinimalCall::from_tool(call).caption,
        if extra == 0 {
          "Check project details"
        } else {
          name
        },
      )
      let completed = {
        ..call,
        outcome: Done(content="", is_error=false, brief=Some("Completed work")),
      }
      assert_eq(
        MinimalCall::from_tool(completed).caption,
        if name == "mbtx" && extra == 0 {
          "Check project details"
        } else {
          "Completed work"
        },
      )
    }
  }
}

///|
test "other minimal tools still prefer their result brief" {
  let call : @transcript.ToolCall = {
    children: [],
    call_id: "read",
    name: "read",
    arguments: Some("{\"description\":\"Read project files\"}"),
    outcome: Done(content="output", is_error=false, brief=Some("Read moon.mod")),
  }
  let completed = MinimalCall::from_tool(call)
  assert_eq(completed.caption, "Read moon.mod")
  assert_eq(
    MinimalContent::Activity([Call(completed)]).summary(),
    "Read moon.mod",
  )
}

///|
test "folded minimal summaries preview operations independent of their outcome" {
  let read : MinimalCall = {
    tool_name: "read",
    changes: None,
    category: Some("Read files"),
    caption: "Read project files",
    status: Pending,
  }
  let script : MinimalCall = {
    tool_name: "mbtx",
    changes: None,
    category: Some("Execute mbtx scripts"),
    caption: "Check project details",
    status: Pending,
  }
  assert_eq(
    MinimalContent::Activity([Call(read), Call(script)]).summary(),
    "Read project files · Check project details",
  )
  let settled = { ..script, status: Succeeded, }
  // A later result brief replaces the script description even without its
  // own description argument. This is still concrete work, not a category.
  for (name, brief) in [("edit", "Edited main.mbt"), ("plan", "Updated plan")] {
    let next = MinimalCall::from_tool({
      children: [],
      call_id: name,
      name,
      arguments: None,
      outcome: Done(content="", is_error=false, brief=Some(brief)),
    })
    assert_eq(
      MinimalContent::Activity([Call(settled), Call(next)]).summary(),
      "Check project details · \{brief}",
    )
  }
  assert_eq(
    MinimalContent::Activity([Call(read), Call(settled)]).summary(),
    "Read project files · Check project details",
  )
  assert_eq(
    MinimalContent::Activity([
      Call({ ..read, status: Succeeded, }),
      Call(settled),
    ]).summary(),
    "Read project files · Check project details",
  )
}

///|
test "completed turn summaries show the first three captions and track failure status" {
  let pending : MinimalCall = {
    tool_name: "read",
    changes: None,
    category: Some("Read files"),
    caption: "Read project files",
    status: Pending,
  }
  // A recorded snapshot is neither a pending call nor a successful outcome.
  let snapshot = ToolStatus::from_outcome(Snapshot(content="Recorded output"))
  assert_true(snapshot is Snapshot)
  let snapshot_counts = MinimalToolStatus::from_activities([
    Call({ ..pending, status: snapshot, }),
  ])
  assert_eq((snapshot_counts.failed, snapshot_counts.pending), (0, 0))
  let failed = { ..pending, status: Failed, }
  let group = MinimalContent::Activity([Call(failed), Call(pending)])
  assert_eq(group.summary(), "Read project files · Read project files")
  let status = MinimalToolStatus::from_activities(group.activities())
  assert_eq((status.failed, status.pending), (1, 1))
  assert_eq(group.summary(), "Read project files · Read project files")
  assert_eq(
    MinimalContent::Completed([{ identity: "work", content: group, }]).summary(),
    "Read project files · Read project files",
  )
  // Count operations in order, including repeated captions. Failures beyond
  // the three visible operations must still be tracked, though never displayed.
  for count in 0..<=4 {
    let calls : Array[MinimalActivity] = []
    for index in 0..<count {
      calls.push(
        Call({
          ..pending,
          caption: "Operation \{index + 1}",
          status: if index == 3 {
            Failed
          } else {
            Succeeded
          },
        }),
      )
    }
    let status = MinimalToolStatus::from_activities(calls)
    assert_eq(
      (status.failed, status.pending),
      (if count == 4 { 1 } else { 0 }, 0),
    )
    assert_eq(
      MinimalContent::Completed([
        { identity: "work", content: Activity(calls), },
      ]).summary(),
      match count {
        0 => "Work completed"
        1 => "Operation 1"
        2 => "Operation 1 · Operation 2"
        3 => "Operation 1 · Operation 2 · Operation 3"
        _ => "Operation 1 · Operation 2 · Operation 3 · …"
      },
    )
  }
}

///|
test "background notices do not count as failed tools or replace pending descriptions" {
  let notice : MinimalActivity = Notice(
    text="Background task failed",
    error=true,
  )
  assert_eq(MinimalContent::Activity([notice]).summary(), "View activity")
  let status = MinimalToolStatus::from_activities([notice])
  assert_eq((status.failed, status.pending), (0, 0))
  let call : MinimalCall = {
    tool_name: "job_wait",
    changes: None,
    category: None,
    caption: "Inspect the background task output",
    status: Pending,
  }
  assert_eq(
    MinimalContent::Activity([Call(call), notice]).summary(),
    "View activity",
  )
  assert_eq(
    MinimalContent::Activity([Call({ ..call, status: Succeeded, }), notice]).summary(),
    "View activity",
  )
}

///|
test "job coordination does not take up captions in a work summary" {
  let entries : Array[MinimalActivity] = []
  for name in ["read", "job_wait", "job_output", "job_stop", "mbtx"] {
    let call : @transcript.ToolCall = {
      children: [],
      call_id: name,
      name,
      arguments: None,
      outcome: Done(content="", is_error=false, brief=Some(name)),
    }
    entries.push(Call(MinimalCall::from_tool(call)))
  }
  entries.push(Notice(text="background job finished", error=false))
  assert_eq(
    MinimalContent::Completed([
      { identity: "work", content: Activity(entries), },
    ]).summary(),
    "read · mbtx",
  )
}

///|
test "a minimal shell caption never repeats the command line brief" {
  // Codex briefs a command execution with the command itself; that is an
  // argument, so the caption falls back to the tool name instead.
  let call : @transcript.ToolCall = {
    children: [],
    call_id: "cmd",
    name: "shell",
    arguments: None,
    outcome: Done(
      content="output",
      is_error=false,
      brief=Some("private command"),
    ),
  }
  assert_eq(MinimalCall::from_tool(call).caption, "shell")
}

///|
test "OpenSeek and Codex web search names share the search activity" {
  for name in ["web_search", "webSearch"] {
    let call : @transcript.ToolCall = {
      children: [],
      call_id: "search",
      name,
      arguments: None,
      outcome: Done(
        content="results",
        is_error=false,
        brief=Some("Search results"),
      ),
    }
    assert_eq(MinimalCall::from_tool(call).category, Some("Search the web"))
  }
}

///|
test "registered built-ins and normalized operations have deliberate categories" {
  // The OpenSeek registry, child submit tools, and Codex adapter are the
  // sources of these names. Foreign names remain foreign even when they end
  // in a built-in operation's name.
  let cases = [
    ("read", Some("Read files")),
    ("edit", Some("Edit files")),
    ("multi_edit", Some("Edit files")),
    ("write", Some("Write files")),
    ("remove", Some("Remove files")),
    ("mbtx", Some("Execute mbtx scripts")),
    ("shell", Some("Execute commands")),
    ("imageView", Some("View images")),
    ("imageGeneration", Some("Generate images")),
    ("enteredReviewMode", Some("Review code")),
    ("exitedReviewMode", Some("Review code")),
    ("spawn_agent", Some("Create subagents")),
    ("review", Some("Create subagents")),
    ("wait_agent", Some("Wait for subagents")),
    ("send_input", Some("Send messages to subagents")),
    ("send_message", Some("Send messages to subagents")),
    ("resume_agent", Some("Resume subagents")),
    ("followup_task", Some("Assign subagent tasks")),
    ("interrupt_agent", Some("Stop subagents")),
    ("close_agent", Some("Close subagents")),
    ("list_agents", Some("List subagents")),
    ("submit_result", Some("Submit results")),
    ("submit_answer", Some("Submit results")),
    ("submit_pattern_repair", Some("Submit results")),
    ("submit_review", Some("Submit reviews")),
    ("plan", Some("Update plan")),
    ("goal", Some("Update goal")),
    ("finish", None),
    ("job_wait", None),
    ("job_output", None),
    ("job_stop", None),
    ("sleep", None),
    ("mcp__example__web_search", Some("Other tool calls")),
    ("dynamic__example__edit", Some("Other tool calls")),
    ("unknown", Some("Other tool calls")),
  ]
  for (name, expected) in cases {
    let call : @transcript.ToolCall = {
      children: [],
      call_id: name,
      name,
      arguments: None,
      outcome: Pending(output=None),
    }
    assert_eq(MinimalCall::from_tool(call).category, expected)
  }
}

///|
/// Minimal mode's finish line mirrors detailed mode: a finished answer carries
/// the item's own durable commit instant, so the completion stamp appears
/// beside the copy action that same rule withholds from anything else. Prose
/// still inside the process, and the live preview, carry none.
test "minimal prose keeps the durable completion stamp only when finished" {
  let input = Input(
    minimal=true,
    source=OpenSeek,
    focused=@interop.ChannelId::Local,
    active_session="desktop-test",
    current_project=None,
    projects=[],
    can_choose_project=false,
    project_menu_open=false,
    project_query="",
    root=None,
    items=[
      {
        item: {
          kind: Answer("the answer"),
          ts: Some(1_700_000_000_000.0),
          sequence: Some(7),
        },
        identity: "s7",
      },
    ],
    streaming_response=None,
    streaming_identity="r1",
  )
  guard input.minimal_blocks().to_array()
    is [
      {
        content: Minimal(
          Messages([{ content: Prose(completed_at~, ..), .. }], ..)
        ),
        ..
      },
    ] else {
    fail("expected one finished minimal prose block")
  }
  assert_eq(completed_at, Some(1_700_000_000_000.0))
  // A preview that has not committed yet never claims a completion instant.
  let streaming = { ..input, items: [], streaming_response: Some("partial"), }
  guard streaming.minimal_blocks().to_array()
    is [
      {
        content: Minimal(
          Messages([{ content: Prose(completed_at~, live~, ..), .. }], ..)
        ),
        ..
      },
    ] else {
    fail("expected one live minimal prose block")
  }
  assert_eq(completed_at, None)
  assert_true(live)
}

///|
test "background minimal call remains pending after detaching" {
  let call : @transcript.ToolCall = {
    call_id: "start",
    name: "mbtx",
    arguments: Some("{\"description\":\"Run tests\"}"),
    outcome: Done(content="", is_error=false, brief=Some("mbtx → bg bg-1")),
    children: [],
  }
  assert_true(MinimalCall::from_tool(call).status is Pending)
}

///|
test "background status joins only matching metadata and completion expiry is pure" {
  let start : @transcript.ToolCall = {
    call_id: "start",
    name: "mbtx",
    arguments: Some("{}"),
    children: [],
    outcome: Done(content="", is_error=false, brief=Some("mbtx → bg bg-a")),
  }
  let jobs : BackgroundJobs = { statuses: Map([]), }
  jobs.collect(start)
  jobs.collect({
    ..start,
    call_id: "second",
    outcome: Done(content="", is_error=false, brief=Some("mbtx → bg bg-b")),
  })
  let output : @transcript.ToolCall = {
    call_id: "read",
    name: "job_output",
    arguments: Some("{\"job_id\":\"bg-a\"}"),
    children: [],
    outcome: Done(
      content="",
      is_error=false,
      brief=Some("job bg-a (running): Tests"),
    ),
  }
  jobs.read_output(output)
  assert_true(jobs.statuses.get("bg-a") is Some(Pending))
  jobs.read_output({
    ..output,
    outcome: Done(
      content="",
      is_error=false,
      brief=Some("job bg-b (exit=0): Wrong job"),
    ),
  })
  assert_true(jobs.statuses.get("bg-a") is Some(Pending))
  jobs.read_output({
    ..output,
    outcome: Done(
      content="logs\n<system>job=bg-a exit=0 truncated=true</system>",
      is_error=false,
      brief=None,
    ),
  })
  assert_true(jobs.statuses.get("bg-a") is Some(RecentlySucceeded))
  assert_true(jobs.statuses.get("bg-b") is Some(Pending))
  jobs.read_output(output)
  assert_true(jobs.statuses.get("bg-a") is Some(RecentlySucceeded))
  let failed_read = {
    ..output,
    outcome: Done(content="read failed", is_error=true, brief=None),
  }
  assert_false(jobs.absorbs(failed_read))
  // Capture diagnostics can fail while the process itself is still running.
  // Keep that read's error visible without marking its owner completed.
  let capture_error = {
    ..output,
    outcome: Done(
      content="capture failed",
      is_error=true,
      brief=Some("job bg-a (running): Tests"),
    ),
  }
  assert_false(jobs.absorbs(capture_error))
  assert_false(
    jobs.absorbs({ ..output, arguments: Some("{\"job_id\":\"unknown\"}"), }),
  )
  assert_true(
    BackgroundJobs::finished_notice(
      "background job bg-b finished (exit=1): Tests",
    )
    is Some(("bg-b", Failed)),
  )
  assert_true(
    BackgroundJobs::finished_notice(
      "background job bg-b finished (running): Tests",
    )
    is None,
  )
  let input = {
    ..base_input(),
    minimal: true,
    items: VisibleRow::history([
      {
        kind: Assistant(
          reasoning=None,
          prose=None,
          calls=[start],
          replay=false,
          finished=false,
        ),
        ts: None,
        sequence: Some(1),
      },
      {
        kind: Notice(
          label="runtime notice",
          brief=Some("background job bg-a finished (exit=0): Tests"),
          body=None,
          is_error=false,
        ),
        ts: None,
        sequence: Some(2),
      },
    ]),
  }
  let initial = pinned_model({ ..input, items: [], })
  let emit : @cmd.Emit[Msg] = @cmd.Emit(_ => @cmd.none)
  let (observed, _) = initial.update(input, ContentRendered, emit)
  let (again, _) = initial.update(input, ContentRendered, emit)
  assert_true(observed == again)
  assert_eq(initial.job_completions.entries.length(), 0)
  assert_eq(observed.job_completions.entries.length(), 1)
  let (duplicate, _) = observed.update(input, ContentRendered, emit)
  assert_true(duplicate == observed)
  let (expired, _) = observed.update(input, JobCompletionExpired("bg-a"), emit)
  let (expired_again, _) = observed.update(
    input,
    JobCompletionExpired("bg-a"),
    emit,
  )
  assert_true(expired == expired_again)
  assert_false(observed.job_completions.hidden("bg-a"))
  assert_true(expired.job_completions.hidden("bg-a"))
  assert_true(JobCompletions::history(input).hidden("bg-a"))
  let entries = input
    .minimal_blocks(completions=expired.job_completions)
    .to_array()
  guard entries is [{ content: Minimal(content), .. }] else {
    fail("expected one original row")
  }
  assert_true(
    content.activities()
    is [Call({ caption: "mbtx → bg bg-a", status: Succeeded, .. })],
  )
}

///|
test "successful job_stop settles its original background call without a notice" {
  let start : @transcript.ToolCall = {
    call_id: "start",
    name: "mbtx",
    arguments: Some("{\"description\":\"Check popover attributes\"}"),
    children: [],
    outcome: Done(
      content="",
      is_error=false,
      brief=Some("mbtx → bg bg-stopped"),
    ),
  }
  let stop : @transcript.ToolCall = {
    call_id: "stop",
    name: "job_stop",
    arguments: Some("{\"job_id\":\"bg-stopped\"}"),
    children: [],
    outcome: Done(
      content="stopped background job bg-stopped",
      is_error=false,
      brief=None,
    ),
  }
  let input = {
    ..base_input(),
    minimal: true,
    items: VisibleRow::history([
      {
        kind: Assistant(
          reasoning=None,
          prose=None,
          calls=[start],
          replay=false,
          finished=false,
        ),
        ts: None,
        sequence: Some(1),
      },
      {
        kind: Assistant(
          reasoning=None,
          prose=None,
          calls=[stop],
          replay=false,
          finished=false,
        ),
        ts: None,
        sequence: Some(2),
      },
    ]),
  }
  let jobs = BackgroundJobs::from_input(input)
  assert_false(jobs.statuses.get("bg-stopped") is Some(Pending))
  assert_true(jobs.absorbs(stop))
}

///|
test "job records settle original calls and reject ambiguous generations" {
  let start : @transcript.ToolCall = {
    call_id: "start",
    name: "mbtx",
    arguments: None,
    children: [],
    outcome: Done(content="", is_error=false, brief=Some("mbtx → bg bg-1")),
  }
  let view : @protocol.JobView = {
    job: {
      generation: "current",
      id: "bg-1",
      revision: 1,
      command: "test",
      description: None,
      cwd: None,
      state: Running,
      started_at_ms: 1,
      backgrounded_at_ms: 2,
      finished_at_ms: None,
      last_output_at_ms: None,
      output_file: None,
      output_persistent: false,
      output_bytes: 0,
      output_chars: 0,
      output_truncated: false,
      invalid_utf8: false,
      output_error: None,
      persistence_error: None,
      cleanup_error: None,
      data: None,
    },
    output_path: None,
    controllable: false,
    error: None,
  }
  let input = {
    ..base_input(),
    items: VisibleRow::history([
      {
        kind: Assistant(
          reasoning=None,
          prose=None,
          calls=[start],
          replay=false,
          finished=false,
        ),
        ts: None,
        sequence: Some(1),
      },
    ]),
  }
  for
    (state, expected) in [
      (view.job.state, Pending),
      (Stopping, Pending),
      (Exited(0), RecentlySucceeded),
      (Exited(2), Failed),
      (Stopped("user"), Stopped),
      (Stopped("output_limit"), Failed),
      (Stopped("time_limit"), Failed),
      (Stopped("capture_failed"), Failed),
      (Interrupted, Failed),
    ] {
    let jobs = BackgroundJobs::from_input({
      ..input,
      background_jobs: [{ ..view, job: { ..view.job, state, }, }],
    })
    assert_true(jobs.statuses.get("bg-1") == Some(expected))
  }
  let success = { ..view, job: { ..view.job, state: Exited(0), }, }
  let failed = BackgroundJobs::from_input({
    ..input,
    background_jobs: [
      {
        ..success,
        job: { ..success.job, cleanup_error: Some("cleanup failed"), },
      },
    ],
  })
  assert_true(failed.statuses.get("bg-1") is Some(Failed))
  let ambiguous = BackgroundJobs::from_input({
    ..input,
    background_jobs: [
      success,
      { ..view, job: { ..view.job, generation: "previous", }, },
    ],
  })
  assert_true(ambiguous.statuses.get("bg-1") is Some(Pending))
  assert_true(
    BackgroundJobs::from_input({
      ..input,
      items: [],
      background_jobs: [success],
    }).statuses.is_empty(),
  )
}
