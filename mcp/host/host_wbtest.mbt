///|
/// One request on its own connection, as the SDK sends it.
async fn send_body(
  service : Service,
  body : Json,
  token? : String,
) -> (Int32, Json?) {
  guard @json.parse(service.env()["OPENSEEK_MCP"])
    is { "url": String(url), "token": String(handed), .. } else {
    fail("missing MCP host handoff")
  }
  let (response, reply) = @http.post(url, body, headers={
    "Authorization": "Bearer \{token.unwrap_or(handed)}",
  })
  if response.code == 200 {
    (response.code, Some(reply.json()))
  } else {
    (response.code, None)
  }
}

///|
/// The reply to `body`, which must be admitted.
async fn reply(service : Service, body : Json) -> Json {
  guard send_body(service, body) is (200, Some(json)) else {
    fail("expected an admitted request")
  }
  json
}

///|
/// A result that echoes what a call asked for, with `data`.
fn echo(
  server : String,
  tool : String,
  arguments : Json,
) -> @agent_tool.ToolAction {
  @agent_tool.respond("\{server}/\{tool} \{arguments.stringify()}", data={
    "ok": true,
  })
}

///|
async test "the MCP host routes calls and refuses other requests" {
  @async.with_task_group(group => {
    let service = Service::start(
      group,
      call=(server, tool, arguments) => echo(server, tool, arguments),
      items=() => [],
    )
    let call = reply(service, {
      "version": 1,
      "call": { "server": "s", "tool": "t", "arguments": { "x": 1 } },
    })
    assert_eq(call, {
      "version": 1,
      "content": "s/t {\"x\":1}",
      "is_error": false,
      "data": { "ok": true },
    })
    // A call needs its arguments, and an unknown shape executes nothing.
    for
      body in [
        ({ "version": 1, "call": { "server": "s", "tool": "t" } } : Json),
        { "version": 1, "name": "t", "arguments": {} },
        { "version": 1, "list": 0 },
      ] {
      assert_eq(
        reply(service, body),
        {
          "version": 1,
          "content": "MCP host requires version=1 and a list or a call (server, tool, arguments)",
          "is_error": true,
        },
        msg=body.stringify(),
      )
    }
    // Another token is refused before anything is read.
    assert_true(
      send_body(service, { "version": 1, "list": {} }, token="other")
      is (403, None),
    )
  })
}

///|
async test "the MCP host lists the catalog in replies it packs" {
  @async.with_task_group(group => {
    // Five items of about 20,000 characters: three fit one reply.
    let items : Array[Json] = [
      for index in 0..<5 => {
        { "server": "s", "blob": "\{index}" + "x".repeat(20000) }
      }
    ]
    let service = Service::start(
      group,
      call=(server, tool, arguments) => echo(server, tool, arguments),
      items=() => items,
    )
    let listed : Array[Json] = []
    let summaries : Array[Json] = []
    let mut cursor : Json = null
    for ;; {
      let reply = reply(service, { "version": 1, "list": { "cursor": cursor } })
      guard reply
        is {
          "content": summary,
          "is_error": false,
          "data": { "items": Array(page), .. } as data,
          ..
        } else {
        fail("expected a listing: \{reply.stringify()}")
      }
      assert_true(reply.stringify().length() <= MaxReplyChars)
      listed.append(page)
      summaries.push(summary)
      match data {
        { "next_cursor": next, .. } => cursor = next
        _ => break
      }
    }
    assert_eq(listed, items)
    assert_eq(summaries, [
      "MCP catalog items 1–3 of 5", "MCP catalog items 4–5 of 5",
    ])
    assert_true(
      reply(service, { "version": 1, "list": { "cursor": 5 } })
      is { "is_error": true, .. },
    )
    for bad in [({ "cursor": -1 } : Json), { "cursor": 1.5 }, { "cursor": "2" }] {
      assert_eq(
        reply(service, { "version": 1, "list": bad }),
        {
          "version": 1,
          "content": "MCP host list requires a non-negative integer cursor",
          "is_error": true,
        },
        msg=bad.stringify(),
      )
    }
  })
}

///|
async test "the MCP host lists an empty catalog as one empty reply" {
  @async.with_task_group(group => {
    let service = Service::start(
      group,
      call=(server, tool, arguments) => echo(server, tool, arguments),
      items=() => [],
    )
    assert_eq(reply(service, { "version": 1, "list": {} }), {
      "version": 1,
      "content": "The MCP catalog is empty",
      "is_error": false,
      "data": { "items": [] },
    })
  })
}

///|
async test "the MCP host saves a result's images and names their files" {
  let image = @protocol.Image::from_bytes(
    @fs.read_file("deepseek/client/testdata/two-colors.png").binary(),
  )
  let call : Json = {
    "version": 1,
    "call": { "server": "s", "tool": "shot", "arguments": {} },
  }
  @async.with_task_group(group => {
    let root = @fs.tmpdir(prefix="mcp-host-images")
    defer @fs.rmdir(root, recursive=true)
    let directory = "\{root}/mcp-images"
    let service = Service::start(
      group,
      call=(_, _, _) => @agent_tool.respond("took it", images=[image, image]),
      items=() => [],
      image_directory=directory,
    )
    guard reply(service, call)
      is {
        "content": String(content),
        "is_error": false,
        "images": [String(first), String(second)],
        ..
      } else {
      fail("expected two saved images")
    }
    assert_true(first != second)
    assert_eq(
      content,
      (
        $|took it
        $|[image image/png saved to \{first}; show it to the model with read_image]
        $|[image image/png saved to \{second}; show it to the model with read_image]
      ),
    )
    for path in [first, second] {
      assert_true(
        path.has_prefix("\{directory}/mcp-image-") && path.has_suffix(".png"),
      )
      assert_eq(@fs.read_file(path).binary(), image.bytes)
    }
  })
  // Without a directory the image is dropped, and the text says so.
  @async.with_task_group(group => {
    let service = Service::start(
      group,
      call=(_, _, _) => @agent_tool.respond("", images=[image]),
      items=() => [],
    )
    assert_eq(reply(service, call), {
      "version": 1,
      "content": "[image image/png not saved: this session has no directory to save images in]",
      "is_error": false,
    })
  })
}

///|
async test "the MCP host replaces an oversized result with an error" {
  @async.with_task_group(group => {
    let service = Service::start(
      group,
      call=(_, _, _) => @agent_tool.respond("x".repeat(MaxReplyChars)),
      items=() => [],
    )
    assert_true(
      reply(service, {
        "version": 1,
        "call": { "server": "s", "tool": "t", "arguments": {} },
      })
      is { "content": String(content), "is_error": true, .. } &&
      content.has_prefix("MCP tool executed, but its result exceeded"),
    )
  })
}

///|
async test "a call is cancelled when its script closes the connection" {
  @async.with_task_group(group => {
    let ended = Ref(false)
    let finished = Ref(false)
    let service = Service::start(
      group,
      call=(_, _, _) => {
        defer {
          ended.val = true
        }
        @async.sleep(60000)
        finished.val = true
        @agent_tool.respond("too late")
      },
      items=() => [],
    )
    // The script stops while its call runs, which closes the connection.
    let stopped = try {
      ignore(
        @async.with_timeout(200, () => {
          reply(service, {
            "version": 1,
            "call": { "server": "s", "tool": "t", "arguments": {} },
          })
        }),
      )
      false
    } catch {
      @async.TimeoutError => true
      error => raise error
    }
    assert_true(stopped)
    @async.with_timeout(5000, () => {
      while !ended.val {
        @async.sleep(10)
      }
    })
    assert_false(finished.val)
  })
}
