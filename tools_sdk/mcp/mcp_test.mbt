///|
/// Async tests in this package run concurrently, and every one of them sets
/// the process-wide OPENSEEK_MCP; each holds this lock while it does.
let environment : @async.Mutex = @async.Mutex()

///|
/// How many hosts `with_host` has started. Each gets its own token, so no host
/// shares a capability, and with it a cached catalog, with an earlier one that
/// happened to get the same port.
let hosts : Ref[Int32] = Ref(0)

///|
/// Runs `body` with OPENSEEK_MCP pointing at a loopback host that answers each
/// request with `reply(input)` as `(status, envelope)`, and returns the request
/// bodies the host received. Restores the process environment on success,
/// assertion failure, or cancellation.
async fn with_host(
  reply : (Json) -> (Int32, Json),
  body : async () -> Unit,
) -> Array[Json] {
  environment.acquire()
  defer environment.release()
  let previous = @env.get_env_var("OPENSEEK_MCP")
  defer (match previous {
    Some(value) => @env.set_env_var("OPENSEEK_MCP", value)
    None => @env.unset_env_var("OPENSEEK_MCP")
  })
  hosts.val += 1
  let token = "mcp-test-\{hosts.val}"
  let received : Array[Json] = []
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      defer server.close()
      let worker = group.spawn(no_wait=true, () => {
        server.run_forever((req, conn) => {
          defer conn.close()
          assert_true(req.meth is Post)
          assert_eq(req.headers.get("Content-Type"), Some("application/json"))
          assert_eq(req.path, "/call")
          assert_eq(req.headers.get("Authorization"), Some("Bearer \{token}"))
          let input = @json.parse(conn.text.read_all())
          received.push(input)
          let (status, envelope) = reply(input)
          conn.send_response(status, if status == 200 { "OK" } else { "Error" })
          conn.text.write_json(envelope)
          conn.end_response()
        })
      })
      defer {
        worker.cancel()
        @async.protect_from_cancel(() => worker.wait() catch { _ => () })
      }
      @env.set_env_var(
        "OPENSEEK_MCP",
        (
          {
            "version": 1,
            "url": "http://127.0.0.1:\{server.addr.port()}/call",
            "token": token,
          } : Json).stringify(),
      )
      body()
    })
  })
  received
}

///|
fn ok(content : String, data? : Json) -> (Int32, Json) {
  let envelope : Map[String, Json] = Map([
    ("version", 1),
    ("content", Json(content)),
    ("is_error", false),
  ])
  if data is Some(data) {
    envelope["data"] = data
  }
  (200, Json::object(envelope))
}

///|
fn refused(content : String) -> (Int32, Json) {
  (200, { "version": 1, "content": content, "is_error": true })
}

///|
async test "MCP calls send the server, tool, and arguments unchanged" {
  let arguments : Json = {
    "repo": "moonbitlang/openseek",
    "labels": ["bug", "mcp"],
    "nested": { "page": 2, "done": false, "cursor": null },
  }
  let results = []
  let received = with_host(input => ok("issue list", data=input), () => {
    results.push(@mcp.call("github", "search_issues", arguments))
    results.push(@mcp.call("files", "remove", {}))
  })
  let expected : Array[Json] = [
    {
      "version": 1,
      "call": {
        "server": "github",
        "tool": "search_issues",
        "arguments": arguments,
      },
    },
    {
      "version": 1,
      "call": { "server": "files", "tool": "remove", "arguments": {} },
    },
  ]
  // Exact equality catches rewritten arguments or SDK-injected fields.
  assert_eq(received, expected)
  for i, result in results {
    assert_eq(result.content, "issue list")
    assert_false(result.is_error)
    assert_eq(result.data, Some(expected[i]))
    assert_eq(result.images, [])
  }
}

///|
async test "MCP calls return the files the host saved images in" {
  let mut result = None
  ignore(
    with_host(
      _ => {
        (
          200,
          {
            "version": 1,
            "content": "took it",
            "is_error": false,
            "images": ["/scratch/mcp-images/a.png"],
          },
        )
      },
      () => result = Some(@mcp.call("browser", "screenshot", {})),
    ),
  )
  guard result is Some(result) else { fail("no result") }
  assert_eq(result.images, ["/scratch/mcp-images/a.png"])
}

///|
async test "MCP tool failures are results, transport failures raise" {
  let mut result = None
  ignore(
    with_host(_ => refused("rate limited"), () => {
      result = Some(@mcp.call("github", "search_issues", {}))
    }),
  )
  guard result is Some(result) else { fail("no result") }
  assert_true(result.is_error)
  assert_eq(result.content, "rate limited")
  assert_true(result.data is None)
  let mut failed = false
  let received = with_host(_ => (503, "Unavailable"), () => {
    failed = try {
      ignore(@mcp.call("github", "create_issue", { "title": "t" }))
      false
    } catch {
      @mcp.TransportError(_) => true
      error => raise error
    }
  })
  assert_true(failed)
  // Never retried: a lost response does not prove the call did not run.
  assert_eq(received.length(), 1)
}

///|
/// A host whose catalog is `pages`, one `list` reply each. Cursors count
/// items, as the host's do.
fn catalog_host(pages : Array[Array[Json]]) -> (Json) -> (Int32, Json) {
  fn(input) {
    let cursor = match input {
      { "list": { "cursor": Number(cursor, ..), .. }, .. } => cursor.to_int()
      { "list": _, .. } => 0
      _ => return refused("not a list request")
    }
    let mut start = 0
    for index, page in pages {
      if start == cursor {
        let data : Map[String, Json] = { "items": Json::array(page) }
        if index + 1 < pages.length() {
          data["next_cursor"] = Json(start + page.length())
        }
        return ok("MCP catalog items", data=Json::object(data))
      }
      start += page.length()
    }
    refused("MCP host list cursor \{cursor} is past the catalog")
  }
}

///|
fn server_item(name : String, instructions? : String, error? : String) -> Json {
  let fields : Map[String, Json] = { "server": Json(name) }
  if instructions is Some(text) {
    fields["instructions"] = Json(text)
  }
  if error is Some(text) {
    fields["error"] = Json(text)
  }
  Json::object(fields)
}

///|
fn tool_item(server : String, name : String, output_schema? : Json) -> Json {
  let tool : Map[String, Json] = {
    "name": Json(name),
    "description": Json("Does \{name}."),
    "input_schema": {
      "type": "object",
      "properties": { "q": { "type": "string" } },
      "required": ["q"],
    },
  }
  if output_schema is Some(schema) {
    tool["output_schema"] = schema
  }
  { "server": Json(server), "tool": Json::object(tool) }
}

///|
/// A catalog over three replies: `github` with instructions and two tools,
/// `calendar` with one, and an unavailable `billing`.
let paged : Array[Array[Json]] = [
  [
    server_item("github", instructions="Prefer search_issues."),
    tool_item("github", "search_issues", output_schema={
      "type": "object",
      "properties": { "items": { "type": "array" } },
    }),
  ],
  [tool_item("github", "create_issue"), server_item("calendar")],
  [
    tool_item("calendar", "list_events"),
    server_item("billing", error="connection refused"),
  ],
]

///|
async test "the first search downloads every page of the catalog" {
  let pages = []
  let received = with_host(catalog_host(paged), () => pages.push(@mcp.search()))
  assert_eq(received, [
    { "version": 1, "list": {} },
    { "version": 1, "list": { "cursor": 2 } },
    { "version": 1, "list": { "cursor": 4 } },
  ])
  let page = pages[0]
  assert_eq(page.tools.map(tool => "\{tool.server}/\{tool.name}"), [
    "github/search_issues", "github/create_issue", "calendar/list_events",
  ])
  assert_eq(page.total, 3)
  assert_true(page.next_offset is None)
  assert_true(page.instructions is None)
  assert_eq("\{page}", page.text)
  assert_true(page.text.has_prefix("3 MCP tools across 2 servers."))
  assert_true(
    page.text.contains(
      "configured but unavailable:\n- `billing`: connection refused",
    ),
  )
  let tool = page.tools[0]
  assert_eq(tool.description, "Does search_issues.")
  assert_true(
    tool.input_schema
    is { "properties": { "q": { "type": "string", .. }, .. }, .. },
  )
  assert_true(
    tool.output_schema is Some({ "properties": { "items": _, .. }, .. }),
  )
  assert_true(page.tools[1].output_schema is None)
}

///|
async test "later searches reuse the downloaded catalog" {
  let pages = []
  let received = with_host(catalog_host(paged), () => {
    pages.push(@mcp.search(server="github", limit=1))
    pages.push(@mcp.search(query="events"))
    pages.push(@mcp.search(server="github", offset=1))
  })
  // One download, three requests for its three replies, for all three searches.
  assert_eq(received.length(), 3)
  assert_eq(pages[0].instructions, Some("Prefer search_issues."))
  assert_true(pages[0].text.has_prefix("Instructions from `github`:"))
  assert_eq(pages[0].next_offset, Some(1))
  assert_eq(pages[1].tools.map(tool => tool.name), ["list_events"])
  assert_eq(pages[2].tools.map(tool => tool.name), ["create_issue"])
  assert_true(pages[2].instructions is None)
}

///|
async test "an empty catalog and an unavailable server are ordinary pages" {
  let pages = []
  ignore(with_host(catalog_host([[]]), () => pages.push(@mcp.search())))
  assert_eq(pages[0].text, "No MCP servers are configured.")
  inspect(pages[0], content="No MCP servers are configured.")
  assert_true(pages[0].tools.is_empty())
  assert_eq(pages[0].total, 0)
  ignore(
    with_host(catalog_host(paged), () => {
      pages.push(@mcp.search(server="billing"))
    }),
  )
  assert_eq(pages[1].text, "`billing` is unavailable: connection refused")
  inspect(pages[1], content="`billing` is unavailable: connection refused")
  assert_true(pages[1].tools.is_empty())
}

///|
/// Runs `search` against `reply` and returns the `SearchError` it raised.
async fn search_error(
  reply : (Json) -> (Int32, Json),
  search : async () -> Unit,
) -> String {
  let mut message = None
  ignore(
    with_host(reply, () => {
      try search() catch {
        @mcp.SearchError(reason) => message = Some(reason)
        error => raise error
      } noraise {
        _ => ()
      }
    }),
  )
  guard message is Some(message) else { fail("search did not raise") }
  message
}

///|
async test "searches the catalog refuses raise SearchError" {
  assert_eq(
    search_error(catalog_host(paged), () => ignore(@mcp.search(server="nope"))),
    "no MCP server `nope`; servers: `github`, `calendar`, `billing`",
  )
  assert_eq(
    search_error(catalog_host(paged), () => ignore(@mcp.search(limit=0))),
    "`limit` must be a positive integer",
  )
}

///|
async test "every download failure is a SearchError" {
  // A listing the host refuses, with its reason.
  assert_eq(
    search_error(_ => refused("listing refused"), () => ignore(@mcp.search())),
    "listing refused",
  )
  // Transport failure.
  ignore(search_error(_ => (503, "Unavailable"), () => ignore(@mcp.search())))
  // A successful envelope without items, and a tool before its server.
  assert_eq(
    search_error(_ => ok("no items"), () => ignore(@mcp.search())),
    "Invalid MCP catalog from the MCP host",
  )
  assert_eq(
    search_error(catalog_host([[tool_item("s", "t")]]), () => {
      ignore(@mcp.search())
    }),
    "Invalid MCP catalog from the MCP host",
  )
}

///|
async test "a failed download is not kept" {
  let attempts = Ref(0)
  let pages = []
  let received = with_host(
    input => {
      attempts.val += 1
      if attempts.val == 1 {
        (503, "Unavailable")
      } else {
        catalog_host(paged)(input)
      }
    },
    () => {
      let failed = try {
        ignore(@mcp.search())
        false
      } catch {
        @mcp.SearchError(_) => true
      }
      assert_true(failed)
      pages.push(@mcp.search())
    },
  )
  assert_eq(received.length(), 4)
  assert_eq(pages[0].total, 3)
}

///|
async test "without an MCP host, a call raises and a search is a SearchError" {
  environment.acquire()
  defer environment.release()
  let previous = @env.get_env_var("OPENSEEK_MCP")
  defer (match previous {
    Some(value) => @env.set_env_var("OPENSEEK_MCP", value)
    None => @env.unset_env_var("OPENSEEK_MCP")
  })
  // What an older host and a run without MCP servers both hand a script.
  @env.unset_env_var("OPENSEEK_MCP")
  let missing = "No MCP host: this run has no MCP servers configured."
  // Each error shows its reason, which is what a script that lets it escape
  // prints.
  let raised = try {
    ignore(@mcp.call("github", "search_issues", {}))
    None
  } catch {
    @mcp.TransportError(message) as error => Some((message, "\{error}"))
    error => raise error
  }
  assert_eq(raised, Some((missing, "TransportError: \{missing}")))
  let searched = try {
    ignore(@mcp.search())
    None
  } catch {
    @mcp.SearchError(message) as error => Some((message, "\{error}"))
  }
  assert_eq(searched, Some((missing, "SearchError: \{missing}")))
}
