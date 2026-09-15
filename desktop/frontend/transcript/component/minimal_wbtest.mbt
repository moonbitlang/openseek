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
  assert_true(pending.pending)
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
    assert_false(completed.pending)
    assert_eq(completed.failed, failed)
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
  assert_eq(MinimalCall::from_tool(call).caption, "Read moon.mod")
}

///|
test "active minimal summaries show the newest pending operation until all settle" {
  let read : MinimalCall = {
    changes: None,
    category: Some("Read files"),
    caption: "Read project files",
    pending: true,
    failed: false,
  }
  let script : MinimalCall = {
    changes: None,
    category: Some("Execute mbtx scripts"),
    caption: "Check project details",
    pending: true,
    failed: false,
  }
  assert_eq(
    MinimalContent::Activity([Call(read), Call(script)]).summary(),
    script.caption,
  )
  let settled = { ..script, pending: false, }
  assert_eq(
    MinimalContent::Activity([Call(read), Call(settled)]).summary(),
    read.caption,
  )
  assert_eq(
    MinimalContent::Activity([Call({ ..read, pending: false, }), Call(settled)]).summary(),
    "Read files · Execute mbtx scripts",
  )
}

///|
test "completed turn summaries retain activity categories and failure counts" {
  let pending : MinimalCall = {
    changes: None,
    category: Some("Read files"),
    caption: "Read project files",
    pending: true,
    failed: false,
  }
  let failed = { ..pending, pending: false, failed: true, }
  let group = MinimalContent::Activity([Call(failed), Call(pending)])
  assert_eq(group.summary(), pending.caption)
  assert_eq(
    MinimalContent::Completed([{ identity: "work", content: group, }]).summary(),
    "Read files · 1 tool call failed",
  )
}

///|
test "background notices do not count as failed tools or replace pending descriptions" {
  let notice : MinimalActivity = Notice(
    text="Background task failed",
    error=true,
  )
  assert_eq(MinimalContent::Activity([notice]).summary(), "View activity")
  let call : MinimalCall = {
    changes: None,
    category: None,
    caption: "Inspect the background task output",
    pending: true,
    failed: false,
  }
  assert_eq(
    MinimalContent::Activity([Call(call), notice]).summary(),
    call.caption,
  )
  assert_eq(
    MinimalContent::Activity([Call({ ..call, pending: false, }), notice]).summary(),
    "View activity",
  )
}

///|
test "job coordination does not add categories to a work summary" {
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
    MinimalContent::Activity(entries).summary(),
    "Read files · Execute mbtx scripts",
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
