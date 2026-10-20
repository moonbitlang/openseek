///|
fn mcp_tool(
  name : String,
  description : String,
  schema : Json,
  output? : Json,
) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name~,
    description~,
    schema=JsonSchema(schema),
    output_schema?=output.map(output => JsonSchema(output)),
    program_callable=true,
    execute=Sync(_ => @agent_tool.respond("unused")),
  )
}

///|
fn sources() -> Array[@tool_search.Source] {
  [
    Source(
      name="calendar",
      instructions="Manage the user's calendar.\nSecond line is not shown.",
      tools=[
        mcp_tool("mcp__calendar__list_events", "List events in a date range.", {
          "type": "object",
          "properties": {
            "start": { "type": "string", "description": "ISO date" },
          },
        }),
        mcp_tool("mcp__calendar__create_event", "Create an event.", {
          "type": "object",
          "properties": { "title": { "type": "string" } },
          "required": ["title"],
        }),
      ],
    ),
    Source(name="github", tools=[
      mcp_tool("mcp__github__list_issues", "List repository issues.", {
        "type": "object",
        "properties": { "repository": { "type": "string" } },
      }),
    ]),
  ]
}

///|
fn search(arguments : Json) -> @agent_tool.ToolOutput raise {
  guard @tool_search.definition(sources()).execute is Sync(run) else {
    fail("tool_search should run synchronously")
  }
  guard run(arguments) is Respond(output) else {
    fail("tool_search should respond")
  }
  output
}

///|
test "the description names each server with its tool count and first instruction line" {
  let description = @tool_search.definition(sources()).description
  assert_true(description.contains("@openseek_tools.call(name, arguments)"))
  assert_true(
    description.contains("- calendar (2 tools): Manage the user's calendar."),
  )
  assert_false(description.contains("Second line"))
  assert_true(description.contains("- github (1 tool)"))
  assert_false(description.contains("- github (1 tool):"))
}

///|
test "a query ranks tools across servers with their schemas" {
  let output = search({ "query": "create calendar event" })
  assert_false(output.is_error)
  let create = output.content.find("## mcp__calendar__create_event")
  let list = output.content.find("## mcp__calendar__list_events")
  guard (create, list) is (Some(create), Some(list)) else {
    fail("expected both calendar tools: \{output.content}")
  }
  assert_true(create < list)
  assert_false(output.content.contains("mcp__github__list_issues"))
  assert_true(output.content.contains("\"required\":[\"title\"]"))
}

///|
test "argument names in a schema are searchable" {
  let output = search({ "query": "repository" })
  assert_true(output.content.contains("## mcp__github__list_issues"))
  assert_false(output.content.contains("## mcp__calendar"))
}

///|
test "a server alone lists its tools in order up to the limit" {
  let all = search({ "server": "calendar" })
  assert_false(all.is_error)
  assert_true(all.content.has_prefix("`calendar` offers 2 tools."))
  assert_false(all.content.contains("Showing"))
  let huge = search({ "server": "calendar", "limit": 1.0e12 })
  assert_eq(huge.content, all.content)
  let cut = search({ "server": "calendar", "limit": 1 })
  assert_true(cut.content.contains("Showing 1–1 of 2. Pass `offset: 1`"))
  assert_true(cut.content.contains("## mcp__calendar__list_events"))
  assert_false(cut.content.contains("## mcp__calendar__create_event"))
}

///|
test "a query within a server ignores other servers" {
  let output = search({ "query": "list", "server": "github" })
  assert_true(output.content.contains("## mcp__github__list_issues"))
  assert_false(output.content.contains("## mcp__calendar__list_events"))
}

///|
test "no match is an ordinary result that names the servers" {
  let output = search({ "query": "weather forecast" })
  assert_false(output.is_error)
  assert_true(output.content.contains("`calendar`, `github`"))
}

///|
test "bad arguments and unknown servers are errors" {
  let cases : Array[Json] = [
    { "query": "  " },
    {},
    { "query": 3 },
    { "query": "event", "limit": 0 },
    { "query": "event", "limit": 1.5 },
    { "query": "event", "offset": -1 },
    { "server": "calendar", "offset": 2 },
    { "server": "jira" },
  ]
  for arguments in cases {
    let output = search(arguments)
    assert_true(output.is_error, msg="\{arguments.stringify()}")
  }
  let unknown = search({ "server": "jira" })
  assert_true(unknown.content.contains("`calendar`, `github`"))
}

///|
test "offset pages through the rest of a listing" {
  let next = search({ "server": "calendar", "limit": 1, "offset": 1 })
  assert_false(next.is_error)
  assert_true(next.content.contains("## mcp__calendar__create_event"))
  assert_false(next.content.contains("## mcp__calendar__list_events"))
  assert_true(next.content.contains("Showing 2–2 of 2."))
  assert_false(next.content.contains("Pass `offset"))
}

///|
test "a page holds only whole entries within the size cap" {
  // Eight tools whose schemas are each large but under the bridge's cap.
  let padding = "x".repeat(12000)
  let tools = []
  for index in 0..<8 {
    tools.push(
      mcp_tool("mcp__big__tool_\{index}", "Big tool \{index}.", {
        "type": "object",
        // An enum this long is shown as the schema itself, which is large.
        "properties": { "value": { "enum": [padding] } },
      }),
    )
  }
  guard @tool_search.definition([Source(name="big", tools~)]).execute
    is Sync(run) else {
    fail("tool_search should run synchronously")
  }
  guard run({ "server": "big" }) is Respond(output) else {
    fail("tool_search should respond")
  }
  assert_true(output.content.length() < 60000)
  assert_true(output.content.contains("## mcp__big__tool_0"))
  assert_false(output.content.contains("## mcp__big__tool_7"))
  assert_true(output.content.contains("of 8. Pass `offset: "))
  // Every shown schema is complete.
  let shown = output.content.split("Arguments schema: ").to_array().length() - 1
  assert_eq(output.content.split(padding).to_array().length() - 1, shown)
}

///|
test "arguments defined under $defs are searchable" {
  let tools = [
    mcp_tool("mcp__ref__open_request", "Open a request.", {
      "type": "object",
      "properties": { "request": { "$ref": "#/$defs/Request" } },
      "$defs": {
        "Request": {
          "type": "object",
          "properties": {
            "repository": { "type": "string", "description": "Target repo" },
          },
        },
      },
    }),
  ]
  guard @tool_search.definition([Source(name="ref", tools~)]).execute
    is Sync(run) else {
    fail("tool_search should run synchronously")
  }
  guard run({ "query": "repository" }) is Respond(output) else {
    fail("tool_search should respond")
  }
  assert_true(output.content.contains("## mcp__ref__open_request"))
}

///|
test "a declared result schema is shown and searchable" {
  let tools = [
    mcp_tool(
      "mcp__tracker__count_open_issues",
      "Count open issues.",
      { "type": "object", "properties": { "repo": { "type": "string" } } },
      output={
        "type": "object",
        "properties": { "backlog": { "type": "integer" } },
      },
    ),
    mcp_tool("mcp__tracker__close_issue", "Close an issue.", {
      "type": "object",
      "properties": { "id": { "type": "integer" } },
    }),
  ]
  guard @tool_search.definition([Source(name="tracker", tools~)]).execute
    is Sync(run) else {
    fail("tool_search should run synchronously")
  }
  guard run({ "server": "tracker" }) is Respond(listing) else {
    fail("tool_search should respond")
  }
  assert_true(
    listing.content.contains(
      "Result `data` schema: {\"type\":\"object\",\"properties\":{\"backlog\":{\"type\":\"integer\"}}}",
    ),
  )
  // Only the tool that declares one shows a result schema.
  assert_eq(
    listing.content.split("Result `data` schema").to_array().length(),
    2,
  )
  guard run({ "query": "backlog" }) is Respond(found) else {
    fail("tool_search should respond")
  }
  assert_true(found.content.contains("## mcp__tracker__count_open_issues"))
  assert_false(found.content.contains("## mcp__tracker__close_issue"))
}

///|
test "a known server without tools is an ordinary empty result" {
  guard @tool_search.definition([Source(name="empty", tools=[])]).execute
    is Sync(run) else {
    fail("tool_search should run synchronously")
  }
  guard run({ "server": "empty" }) is Respond(output) else {
    fail("tool_search should respond")
  }
  assert_false(output.is_error)
  assert_eq(output.content, "`empty` offers no tools.")
}

///|
test "fields of a map's values are searchable" {
  let tools = [
    mcp_tool("mcp__ci__dispatch", "Start jobs.", {
      "type": "object",
      "properties": {
        "jobs": {
          "type": "object",
          "additionalProperties": {
            "type": "object",
            "properties": { "repository": { "type": "string" } },
          },
        },
      },
    }),
  ]
  guard @tool_search.definition([Source(name="ci", tools~)]).execute
    is Sync(run) else {
    fail("tool_search should run synchronously")
  }
  guard run({ "query": "repository" }) is Respond(output) else {
    fail("tool_search should respond")
  }
  assert_true(output.content.contains("## mcp__ci__dispatch"))
}
