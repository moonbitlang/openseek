///|
fn tool(
  name : String,
  description : String,
  schema : Json,
  output? : Json,
) -> @catalog.Tool {
  Tool(name~, description~, input_schema=schema, output_schema?=output)
}

///|
fn catalog() -> @catalog.Catalog {
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
    @catalog.Source::unavailable(
      name="billing",
      error="connection refused\nretrying",
    ),
  ])
}

///|
/// The tools of a page's records, as `server/name`.
fn listed(page : @catalog.Page) -> Array[String] {
  page.tools.map(entry => "\{entry.server}/\{entry.tool.name}")
}

///|
fn search_one(
  catalog : @catalog.Catalog,
  query : String,
) -> @catalog.Page raise {
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
  // Schemas are shown as JSON Schema text, and the page closes with the call
  // form rather than a call per tool.
  assert_true(
    page.text.contains(
      "Arguments schema: {\"type\":\"object\",\"properties\":{\"title\":{\"type\":\"string\"}},\"required\":[\"title\"]}",
    ),
  )
  assert_true(page.text.contains("@mcp.call(server, tool, arguments)"))
  assert_false(page.text.contains("@mcp.call(\"calendar\""))
  // Only a search that names a server shows its instructions.
  assert_false(page.text.contains("Manage the user's calendar"))
  assert_eq(page.total, 2)
  assert_true(page.next_offset is None)
  assert_true(page.instructions is None)
}

///|
test "a tool's record carries its raw schemas" {
  let page = @catalog.Catalog([
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
  guard page.tools is [{ server: "tracker", tool, }] else {
    fail("expected one tracker tool: \{listed(page).join(", ")}")
  }
  assert_eq(tool.name, "count_open")
  assert_eq(tool.description, "Count open issues.")
  assert_true(tool.input_schema is { "properties": { "repo": _, .. }, .. })
  assert_true(
    tool.output_schema is Some({ "properties": { "backlog": _, .. }, .. }),
  )
  assert_eq(page.total, 1)
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
  assert_eq(
    all.instructions,
    Some("Manage the user's calendar.\nTimes are UTC."),
  )
  assert_eq(all.total, 2)
  assert_false(all.text.contains("Showing"))
  let huge = catalog().search(server="calendar", limit=1_000_000)
  assert_eq(huge.text, all.text)
  let cut = catalog().search(server="calendar", limit=1)
  assert_eq(listed(cut), ["calendar/list_events"])
  assert_true(cut.text.contains("Showing 1–1 of 2. Pass `offset=1`"))
  assert_eq(cut.next_offset, Some(1))
  assert_eq(cut.total, 2)
}

///|
test "offset pages through the rest of a listing without the instructions" {
  let next = catalog().search(server="calendar", limit=1, offset=1)
  assert_eq(listed(next), ["calendar/create_event"])
  assert_true(next.text.contains("Showing 2–2 of 2."))
  assert_false(next.text.contains("Pass `offset"))
  assert_false(next.text.contains("Instructions from"))
  assert_true(next.instructions is None)
  assert_true(next.next_offset is None)
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
  assert_eq(page.total, 0)
}

///|
test "no match is an ordinary page without tools" {
  let page = search_one(catalog(), "weather forecast")
  assert_eq(listed(page), [])
  assert_true(page.text.contains("@mcp.search()"))
  let empty = @catalog.Catalog([Source(name="empty", tools=[])]).search(
    server="empty",
  )
  assert_eq(empty.text, "`empty` offers no tools.")
  assert_eq(
    @catalog.Catalog([]).search().text,
    "No MCP servers are configured.",
  )
}

///|
test "invalid arguments and unknown servers are errors" {
  let cases : Array[(String, () -> @catalog.Page raise @catalog.SearchError)] = [
    ("limit 0", () => catalog().search(query="event", limit=0)),
    ("negative offset", () => catalog().search(query="event", offset=-1)),
    ("offset past the end", () => catalog().search(server="calendar", offset=2)),
    ("offset past no match", () => catalog().search(query="zzz", offset=1)),
    ("offset past no servers", () => @catalog.Catalog([]).search(offset=1)),
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
test "entries past the room for their shapes are brief, within the text cap" {
  // Eight tools whose schemas are each large: a few fit one page whole.
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
  let page = @catalog.Catalog([Source(name="big", tools~)]).search(server="big")
  assert_true(page.text.length() < 40000)
  assert_eq(listed(page).length(), 8)
  assert_true(page.next_offset is None)
  // A schema is shown whole or not at all; the rest leave theirs to the records.
  let whole = page.text.split(padding).to_array().length() - 1
  let brief = page.text.split("do not fit this page").to_array().length() - 1
  assert_true(whole > 0 && whole < 8)
  assert_eq(whole + brief, 8)
}

///|
test "arguments defined under $defs are searchable" {
  let catalog = @catalog.Catalog([
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
  let catalog = @catalog.Catalog([
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
  let catalog = @catalog.Catalog([
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
  let catalog = @catalog.Catalog([
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
  // Input and output schemas whose JSON Schema text together does not fit one
  // page.
  let properties : Map[String, Json] = Map([])
  for index in 0..<135 {
    properties["p_\{index}_" + "x".repeat(300)] = { "type": "string" }
  }
  let schema : Json = {
    "type": "object",
    "properties": Json::object(properties),
  }
  let page = @catalog.Catalog([
    Source(name="wide", tools=[
      tool("call", "A wide tool.", schema, output=schema),
    ]),
  ]).search(server="wide")
  assert_true(page.text.length() < 40000)
  assert_eq(listed(page), ["wide/call"])
  assert_true(page.text.contains("do not fit this page"))
  assert_true(page.tools is [{ tool: { output_schema: Some(_), .. }, .. }])
}
