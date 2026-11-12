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
  let (response, reply) = @http.post_text(url, body.stringify(), headers={
    "Authorization": "Bearer \{token.unwrap_or(handed)}",
  })
  let reply = reply.text()
  if response.code == 200 {
    (response.code, Some(@json.parse(reply)))
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
/// Five catalog items of about 20,000 characters: three fit one reply.
fn large_items() -> Array[Json] {
  [
    for index in 0..<5 => {
      { "server": "s", "blob": "\{index}" + "x".repeat(20000) }
    }
  ]
}

///|
async test "the MCP host refuses requests it cannot answer" {
  @async.with_task_group(group => {
    let service = Service::start(group, [])
    // A call to a server that is not configured runs nothing.
    assert_true(
      reply(service, {
        "version": 1,
        "call": { "server": "s", "tool": "t", "arguments": {} },
      })
      is { "is_error": true, .. },
    )
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
    for
      list in [
        ({ "cursor": -1 } : Json),
        { "cursor": 1.5 },
        { "cursor": "2" },
        { "cursor": 1 },
        { "snapshot": "0" },
        { "snapshot": 3 },
        { "server": 1 },
      ] {
      assert_true(
        reply(service, { "version": 1, "list": list })
        is { "is_error": true, .. },
        msg=list.stringify(),
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
async test "the MCP host lists an empty catalog as one empty reply" {
  @async.with_task_group(group => {
    let service = Service::start(group, [])
    assert_eq(reply(service, { "version": 1, "list": {} }), {
      "version": 1,
      "content": "The MCP catalog is empty",
      "is_error": false,
      "data": { "items": [], "snapshot": 0 },
    })
  })
}

///|
test "a listing packs the catalog in replies" {
  let items = large_items()
  let snapshot = { id: 0, items, }
  let listed : Array[Json] = []
  let summaries : Array[Json] = []
  let mut cursor = 0
  for ;; {
    let reply = list_reply(snapshot, cursor)
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
      { "next_cursor": Number(next, ..), .. } => cursor = next.to_int()
      _ => break
    }
  }
  assert_eq(listed, items)
  assert_eq(summaries, [
    "MCP catalog items 1–3 of 5", "MCP catalog items 4–5 of 5",
  ])
  let past_end = Some(list_reply(snapshot, 5)) catch { _ => None }
  assert_true(past_end is None)
}

///|
test "a listing pages through the catalog it started from" {
  let snapshots : Snapshots = { kept: [], next: 0, }
  let started = large_items()
  let first = snapshots.take(started)
  guard list_reply(first, 0)
    is {
      "data": { "items": Array(page), "next_cursor": Number(cursor, ..), .. },
      ..
    } else {
    fail("expected a first page")
  }
  // A server comes first in the catalog now, shifting every later item; a
  // new listing starts from the catalog as it stands.
  let shifted : Array[Json] = [{ "server": "new" }, ..started]
  assert_eq(snapshots.take(shifted).items, shifted)
  // The first listing goes on from the catalog it started from.
  guard snapshots.find(first.id) is Some(same) else {
    fail("expected the first listing's snapshot")
  }
  guard list_reply(same, cursor.to_int())
    is { "data": { "items": Array(rest), .. } as data, .. } else {
    fail("expected the rest of the listing")
  }
  assert_eq([..page, ..rest], started)
  assert_true(!(data is { "next_cursor": _, .. }))
  // An unchanged catalog lists from the latest snapshot.
  assert_eq(snapshots.take(shifted).id, 1)
  // Once enough later catalogs have been listed, the first is gone.
  for index in 0..<MaxSnapshots {
    ignore(snapshots.take([{ "server": "\{index}" }]))
  }
  assert_true(snapshots.find(first.id) is None)
}

///|
async test "a call's reply saves its images and names their files" {
  let image = @protocol.Image::from_bytes(
    @fs.read_binary("deepseek/client/testdata/two-colors.png"),
  )
  let root = @fs.tmpdir(prefix="mcp-host-images")
  defer @fs.rmdir(root, recursive=true)
  let directory = "\{root}/mcp-images"
  guard @agent_tool.respond("took it", images=[image, image]) is Respond(output) else {
    fail("expected a respond action")
  }
  guard call_reply(output, image_directory=directory)
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
    assert_eq(@fs.read_binary(path), image.bytes)
  }
  // Without a directory the image is dropped, and the text says so.
  guard @agent_tool.respond("", images=[image]) is Respond(dropped) else {
    fail("expected a respond action")
  }
  assert_eq(call_reply(dropped), {
    "version": 1,
    "content": "[image image/png not saved: this session has no directory to save images in]",
    "is_error": false,
  })
}

///|
test "an oversized reply is replaced with an error" {
  let reply : Json = {
    "version": 1,
    "content": "x".repeat(MaxReplyChars),
    "is_error": false,
  }
  assert_true(
    deliverable(reply) is { "content": String(content), "is_error": true, .. } &&
    content.has_prefix("MCP tool executed, but its result exceeded"),
  )
  let small : Json = { "version": 1, "content": "ok", "is_error": false }
  assert_eq(deliverable(small), small)
}
