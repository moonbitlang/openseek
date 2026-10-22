///|
fn tool(
  name : String,
  description : String,
  schema : Json,
  output? : Json,
) -> @tool_catalog.Tool {
  Tool(name~, description~, input_schema=schema, output_schema?=output)
}

///|
fn catalog() -> @tool_catalog.Catalog {
  Catalog([
    Source(
      name="calendar",
      instructions="Manage the user's calendar.\nTimes are UTC.",
      tools=[
        tool("list_events", "List events in a date range.", {
          "type": "object",
          "properties": {
            "start": { "type": "string", "description": "ISO date" },
          },
        }),
        tool("create_event", "Create an event.", {
          "type": "object",
          "properties": { "title": { "type": "string" } },
          "required": ["title"],
        }),
      ],
    ),
    Source(name="github", tools=[
      tool("list_issues", "List repository issues.", {
        "type": "object",
        "properties": { "repository": { "type": "string" } },
      }),
    ]),
    @tool_catalog.Source::unavailable(
      name="billing",
      error="connection refused\nretrying",
    ),
  ])
}

///|
/// The tools of a page's `data`, as `server/name`.
fn listed(page : @tool_catalog.Page) -> Array[String] raise {
  guard page.data is { "tools": Array(tools), .. } else {
    fail("page data without tools: \{page.data.stringify()}")
  }
  tools.map(tool => {
    guard tool is { "server": String(server), "name": String(name), .. } else {
      fail("tool record without server and name: \{tool.stringify()}")
    }
    "\{server}/\{name}"
  })
}

///|
fn search_one(
  catalog : @tool_catalog.Catalog,
  query : String,
) -> @tool_catalog.Page raise {
  catalog.search(query~)
}

///|
test "a query ranks tools across servers with their schemas" {
  let page = catalog().search(query="create calendar event")
  assert_eq(listed(page), ["calendar/create_event", "calendar/list_events"])
  let create = page.text.find("## calendar / create_event")
  let list = page.text.find("## calendar / list_events")
  guard (create, list) is (Some(create), Some(list)) else {
    fail("expected both calendar tools: \{page.text}")
  }
  assert_true(create < list)
  assert_true(page.text.contains("\"required\":[\"title\"]"))
  assert_true(page.text.contains("@mcp.call(server, tool, arguments)"))
  // Only a search that names a server shows its instructions.
  assert_false(page.text.contains("Manage the user's calendar"))
  assert_true(page.data is { "total": 2, .. })
  assert_false(page.data is { "next_offset": _, .. })
}

///|
test "a tool's record carries its raw schemas" {
  let page = @tool_catalog.Catalog([
    Source(name="tracker", tools=[
      tool(
        "count_open",
        "Count open issues.",
        { "type": "object", "properties": { "repo": { "type": "string" } } },
        output={
          "type": "object",
          "properties": { "backlog": { "type": "integer" } },
        },
      ),
    ]),
  ]).search()
  assert_true(
    page.data
    is {
      "tools": [
        {
          "server": "tracker",
          "name": "count_open",
          "description": "Count open issues.",
          "input_schema": { "properties": { "repo": _, .. }, .. },
          "output_schema": { "properties": { "backlog": _, .. }, .. },
          ..
        },
      ],
      "total": 1,
      ..
    },
  )
}

///|
test "argument names in a schema and server names are searchable" {
  assert_eq(listed(search_one(catalog(), "repository")), ["github/list_issues"])
  assert_eq(listed(search_one(catalog(), "github")), ["github/list_issues"])
}

///|
test "a server alone lists its tools in order up to the limit, after its instructions" {
  let all = catalog().search(server="calendar")
  assert_eq(listed(all), ["calendar/list_events", "calendar/create_event"])
  assert_true(
    all.text.has_prefix(
      "Instructions from `calendar`:\nManage the user's calendar.\nTimes are UTC.\n\n`calendar` offers 2 tools.",
    ),
  )
  assert_true(
    all.data
    is {
      "instructions": "Manage the user's calendar.\nTimes are UTC.",
      "total": 2,
      ..
    },
  )
  assert_false(all.text.contains("Showing"))
  let huge = catalog().search(server="calendar", limit=1_000_000)
  assert_eq(huge.text, all.text)
  let cut = catalog().search(server="calendar", limit=1)
  assert_eq(listed(cut), ["calendar/list_events"])
  assert_true(cut.text.contains("Showing 1–1 of 2. Pass `offset=1`"))
  assert_true(cut.data is { "next_offset": 1, "total": 2, .. })
}

///|
test "offset pages through the rest of a listing without the instructions" {
  let next = catalog().search(server="calendar", limit=1, offset=1)
  assert_eq(listed(next), ["calendar/create_event"])
  assert_true(next.text.contains("Showing 2–2 of 2."))
  assert_false(next.text.contains("Pass `offset"))
  assert_false(next.text.contains("Instructions from"))
  assert_false(next.data is { "instructions": _, .. })
  assert_false(next.data is { "next_offset": _, .. })
}

///|
test "a query within a server ignores other servers" {
  let page = catalog().search(query="list", server="github")
  assert_eq(listed(page), ["github/list_issues"])
  assert_false(page.text.contains("Instructions from"))
}

///|
test "no arguments list every tool and the servers that did not connect" {
  let page = catalog().search()
  assert_eq(listed(page), [
    "calendar/list_events", "calendar/create_event", "github/list_issues",
  ])
  assert_true(page.text.has_prefix("3 MCP tools across 2 servers."))
  assert_true(
    page.text.contains(
      "configured but unavailable:\n- `billing`: connection refused",
    ),
  )
  assert_false(page.text.contains("retrying"))
}

///|
test "an unavailable server is an ordinary page with its error" {
  let page = catalog().search(server="billing")
  assert_eq(page.text, "`billing` is unavailable: connection refused\nretrying")
  assert_eq(listed(page), [])
  assert_true(page.data is { "total": 0, .. })
}

///|
test "no match is an ordinary page without tools" {
  let page = search_one(catalog(), "weather forecast")
  assert_eq(listed(page), [])
  assert_true(page.text.contains("@mcp.search()"))
  let empty = @tool_catalog.Catalog([Source(name="empty", tools=[])]).search(
    server="empty",
  )
  assert_eq(empty.text, "`empty` offers no tools.")
  assert_eq(
    @tool_catalog.Catalog([]).search().text,
    "No MCP servers are configured.",
  )
}

///|
test "invalid arguments and unknown servers are errors" {
  let cases : Array[
    (String, () -> @tool_catalog.Page raise @tool_catalog.SearchError),
  ] = [
    ("limit 0", () => catalog().search(query="event", limit=0)),
    ("negative offset", () => catalog().search(query="event", offset=-1)),
    ("offset past the end", () => catalog().search(server="calendar", offset=2)),
    ("unknown server", () => catalog().search(server="jira")),
  ]
  for case in cases {
    let (label, run) = case
    let result = try run() |> Ok catch {
      error => Err(error)
    }
    assert_true(result is Err(SearchError(_)), msg=label)
  }
  let unknown = try catalog().search(server="jira") |> Ok catch {
    error => Err(error)
  }
  guard unknown is Err(SearchError(message)) else { fail("expected an error") }
  assert_true(message.contains("`calendar`, `github`, `billing`"))
  // Blank strings mean absent.
  assert_eq(listed(catalog().search(query="  ", server="")).length(), 3)
}

///|
test "a page holds only whole entries within the size caps" {
  // Eight tools whose schemas are each large but under the catalog's cap.
  let padding = "x".repeat(12000)
  let tools = []
  for index in 0..<8 {
    tools.push(
      tool("tool_\{index}", "Big tool \{index}.", {
        "type": "object",
        "properties": { "value": { "enum": [padding] } },
      }),
    )
  }
  let page = @tool_catalog.Catalog([Source(name="big", tools~)]).search(
    server="big",
  )
  assert_true(page.text.length() < 40000)
  let reply : Json = { "content": page.text, "data": page.data }
  assert_true(reply.stringify().length() < 64000)
  let shown = listed(page).length()
  assert_true(shown > 0 && shown < 8)
  assert_true(page.text.contains("of 8. Pass `offset=\{shown}`"))
  assert_true(page.data is { "next_offset": Number(_, ..), .. })
  // Every shown schema is complete, in the text and in the records.
  assert_eq(page.text.split(padding).to_array().length() - 1, shown)
  assert_eq(page.data.stringify().split(padding).to_array().length() - 1, shown)
}

///|
test "long instructions are cut and marked" {
  let page = @tool_catalog.Catalog([
    Source(name="wiki", instructions="y".repeat(5000), tools=[]),
  ]).search(server="wiki")
  assert_true(page.text.contains("… (cut at 4000 characters)"))
  assert_false(page.text.contains("y".repeat(4001)))
}

///|
test "arguments defined under $defs are searchable" {
  let catalog = @tool_catalog.Catalog([
    Source(name="ref", tools=[
      tool("open_request", "Open a request.", {
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
    ]),
  ])
  assert_eq(listed(search_one(catalog, "repository")), ["ref/open_request"])
}

///|
test "a declared result schema is shown and searchable" {
  let catalog = @tool_catalog.Catalog([
    Source(name="tracker", tools=[
      tool(
        "count_open_issues",
        "Count open issues.",
        { "type": "object", "properties": { "repo": { "type": "string" } } },
        output={
          "type": "object",
          "properties": { "backlog": { "type": "integer" } },
        },
      ),
      tool("close_issue", "Close an issue.", {
        "type": "object",
        "properties": { "id": { "type": "integer" } },
      }),
    ]),
  ])
  let listing = catalog.search(server="tracker")
  assert_true(
    listing.text.contains(
      "Result `data` schema: {\"type\":\"object\",\"properties\":{\"backlog\":{\"type\":\"integer\"}}}",
    ),
  )
  // Only the tool that declares one shows a result schema.
  assert_eq(listing.text.split("Result `data` schema").to_array().length(), 2)
  assert_eq(listed(search_one(catalog, "backlog")), [
    "tracker/count_open_issues",
  ])
}

///|
test "fields of a map's values are searchable" {
  let catalog = @tool_catalog.Catalog([
    Source(name="ci", tools=[
      tool("dispatch", "Start jobs.", {
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
    ]),
  ])
  assert_eq(listed(search_one(catalog, "repository")), ["ci/dispatch"])
}

///|
test "fields in tuple items and conditional branches are searchable" {
  let catalog = @tool_catalog.Catalog([
    Source(name="t", tools=[
      tool("pair", "A pair.", {
        "type": "array",
        "prefixItems": [
          {
            "type": "object",
            "properties": { "repository": { "type": "string" } },
          },
        ],
      }),
      tool("legacy", "Old tuple.", {
        "type": "array",
        "items": [
          { "type": "object", "properties": { "branch": { "type": "string" } } },
        ],
      }),
      tool("cond", "Conditional.", {
        "type": "object",
        "if": { "properties": { "kind": { "const": "a" } } },
        "then": { "properties": { "timezone": { "type": "string" } } },
      }),
      tool("deps", "Dependent.", {
        "type": "object",
        "dependencies": {
          "a": ["b"],
          "c": { "properties": { "workspace": { "type": "string" } } },
        },
      }),
      tool("blob", "Encoded.", {
        "type": "string",
        "contentSchema": { "properties": { "checksum": { "type": "string" } } },
      }),
      tool("plain", "Plain.", {
        "type": "object",
        "default": { "repository": "ignored" },
      }),
    ]),
  ])
  for
    pair in [
      ("repository", "t/pair"),
      ("branch", "t/legacy"),
      ("timezone", "t/cond"),
      ("workspace", "t/deps"),
      ("checksum", "t/blob"),
    ] {
    let (query, name) = pair
    // Instance values are not indexed, so `plain` never matches.
    assert_eq(listed(search_one(catalog, query)), [name], msg=query)
  }
}

///|
test "a long query is echoed short and leaves the page its room" {
  let page = search_one(catalog(), "calendar ".repeat(3500))
  assert_true(page.text.length() < 2000)
  assert_true(page.text.contains("## calendar / list_events"))
  assert_true(page.text.contains("@mcp.call(server, tool, arguments)"))
}

///|
test "a lone tool too large for the page leaves its schemas to the records" {
  // Input and output schemas near the catalog's cap: the JSON Schema text of
  // both, beside the records, would not fit one reply.
  let properties : Map[String, Json] = Map([])
  for index in 0..<45 {
    properties["p_\{index}_" + "x".repeat(300)] = { "type": "string" }
  }
  let schema : Json = {
    "type": "object",
    "properties": Json::object(properties),
  }
  let page = @tool_catalog.Catalog([
    Source(name="wide", tools=[
      tool("call", "A wide tool.", schema, output=schema),
    ]),
  ]).search(server="wide")
  assert_true(page.text.length() < 40000)
  let reply : Json = { "content": page.text, "data": page.data }
  assert_true(reply.stringify().length() < 64000)
  assert_eq(listed(page), ["wide/call"])
  assert_true(page.text.contains("too large to show here"))
  assert_true(page.data is { "tools": [{ "output_schema": _, .. }], .. })
}

///|
test "server-supplied parts are bounded" {
  let huge : Json = {
    "type": "object",
    "properties": { "x": { "enum": ["y".repeat(20000)] } },
  }
  let page = @tool_catalog.Catalog([
    Source(name="s", tools=[
      tool("big", "d".repeat(2000), huge, output=huge),
      tool("odd", "Odd.", [1, 2]),
    ]),
  ]).search(server="s")
  guard page.data is { "tools": [big, odd], .. } else {
    fail("unexpected records: \{page.data.stringify()}")
  }
  let open : Json = { "type": "object" }
  guard big is { "input_schema": big_input, "description": String(d), .. } else {
    fail("unexpected record: \{big.stringify()}")
  }
  assert_eq(big_input, open)
  assert_eq(d.char_length(), 1025)
  assert_false(big is { "output_schema": _, .. })
  assert_true(odd is { "input_schema": input, .. } && input == open)
}
