// Pure decoder and rendering tests — no transport.

///|
/// Assert that `decode` raises `Protocol`. The three tests below differ only in
/// the call; the chain that turns the raise into a comparable string — and the
/// `_ => "other"` arm that keeps an unexpected error from reading as a pass —
/// was copied into each of them.
fn assert_protocol(decode : () -> Unit raise) -> Unit raise {
  let outcome = try {
    decode()
    "no error"
  } catch {
    Protocol(_) => "protocol"
    _ => "other"
  }
  assert_eq(outcome, "protocol")
}

///|
test "decode_tool reads all fields" {
  let tool = decode_tool({
    "name": "search",
    "description": "Search the web",
    "inputSchema": { "type": "object", "required": ["q"] },
    "outputSchema": {
      "type": "object",
      "properties": { "hits": { "type": "array" } },
    },
  })
  assert_eq(tool.name, "search")
  assert_eq(tool.description, "Search the web")
  assert_true(tool.input_schema is { "type": "object", .. })
  assert_true(
    tool.output_schema is Some({ "properties": { "hits": _, .. }, .. }),
  )
}

///|
test "decode_tool defaults a missing description and schema" {
  let tool = decode_tool({ "name": "bare" })
  assert_eq(tool.name, "bare")
  assert_eq(tool.description, "")
  assert_true(tool.input_schema is { "type": "object", .. })
  assert_true(tool.output_schema is None)
}

///|
test "decode_tool ignores an output schema that is not an object" {
  let tool = decode_tool({ "name": "odd", "outputSchema": "string" })
  assert_true(tool.output_schema is None)
}

///|
test "decode_tool raises Protocol when name is missing" {
  assert_protocol(() => decode_tool({ "description": "no name" }) |> ignore)
}

///|
test "decode_content_block reads each block kind" {
  assert_eq(decode_content_block({ "type": "text", "text": "hi" }), Text("hi"))
  assert_eq(
    decode_content_block({
      "type": "image",
      "data": "AAAA",
      "mimeType": "image/png",
    }),
    Image(mime_type="image/png", data="AAAA"),
  )
  // `data` and `mimeType` are required; without them the block is not an
  // image the client can forward.
  assert_eq(
    decode_content_block({ "type": "image", "data": "AAAA" }),
    Other(kind="image"),
  )
  assert_eq(
    decode_content_block({
      "type": "resource",
      "resource": { "uri": "file:///a", "text": "body" },
    }),
    Resource(uri="file:///a", text=Some("body")),
  )
  assert_eq(
    decode_content_block({
      "type": "resource",
      "resource": { "uri": "file:///a" },
    }),
    Resource(uri="file:///a", text=None),
  )
  assert_eq(decode_content_block({ "type": "audio" }), Other(kind="audio"))
}

///|
test "decode_content_block raises Protocol without a type" {
  assert_protocol(() => decode_content_block({ "text": "orphan" }) |> ignore)
}

///|
test "decode_call_result defaults content and isError" {
  let empty = decode_call_result(Json::empty_object())
  assert_eq(empty.content.length(), 0)
  assert_false(empty.is_error)
  let flagged = decode_call_result({ "content": [], "isError": true })
  assert_true(flagged.is_error)
}

///|
test "decode_initialize_result reads identity and defaults" {
  let full = decode_initialize_result({
    "protocolVersion": "2025-06-18",
    "serverInfo": { "name": "srv", "version": "2.0" },
    "instructions": "be nice",
  })
  assert_eq(full.protocol_version, "2025-06-18")
  assert_eq(full.server_name, Some("srv"))
  assert_eq(full.server_version, Some("2.0"))
  assert_eq(full.instructions, Some("be nice"))
  let minimal = decode_initialize_result({ "protocolVersion": "2025-06-18" })
  assert_eq(minimal.server_name, None)
  assert_eq(minimal.server_version, None)
  assert_eq(minimal.instructions, None)
}

///|
test "decode_initialize_result raises without a protocol version" {
  assert_protocol(() => {
    decode_initialize_result({ "serverInfo": { "name": "srv" } }) |> ignore
  })
}

///|
test "render_text joins text and placeholders" {
  let result : CallToolResult = {
    content: [
      Text("see"),
      Image(mime_type="image/png", data="AAAA"),
      Resource(uri="file:///x", text=Some("body")),
      Resource(uri="file:///y", text=None),
      Other(kind="audio"),
    ],
    structured_content: None,
    is_error: false,
  }
  assert_eq(
    result.render_text(),
    "see\n[image image/png not attached: expected PNG, JPEG, GIF, or WebP image bytes]\n[resource file:///x]\nbody\n[resource: file:///y]\n[unsupported content: audio]",
  )
}

///|
test "render attaches readable images and notes rejected ones in place" {
  // Canonical base64 of the eight-byte PNG signature and of `<svg/>`.
  let png = "iVBORw0KGgo="
  let svg = "PHN2Zy8+"
  let result : CallToolResult = {
    content: [
      Image(mime_type="image/png", data=png),
      Text("between"),
      Image(mime_type="image/svg+xml", data=svg),
      Image(mime_type="image/jpeg", data=png),
      Image(mime_type="image/gif", data="R0lGODlh"),
    ],
    structured_content: None,
    is_error: false,
  }
  let rendered = result.render()
  assert_eq(rendered.images, [
    @protocol.Image::from_base64(media_type="image/png", png),
    @protocol.Image::from_bytes(b"GIF89a"),
  ])
  assert_eq(
    rendered.text,
    (
      #|between
      #|[image image/svg+xml not attached: expected PNG, JPEG, GIF, or WebP image bytes]
      #|[image image/jpeg not attached: image declares image/jpeg but bytes identify image/png]
    ),
  )
}

///|
test "render_text is empty for empty content" {
  let result : CallToolResult = {
    content: [],
    structured_content: None,
    is_error: false,
  }
  assert_eq(result.render_text(), "")
}

///|
test "decode_call_result keeps structuredContent" {
  let result = decode_call_result({
    "content": [],
    "structuredContent": { "value": 42 },
  })
  assert_eq(result.structured_content, Some({ "value": 42 }))
}

///|
test "render_text renders structuredContent when content is empty" {
  let result : CallToolResult = {
    content: [],
    structured_content: Some({ "value": 42 }),
    is_error: false,
  }
  assert_eq(result.render_text(), "{\"value\":42}")
}

///|
test "render_text does not duplicate structuredContent already in content" {
  let serialized = ({ "value": 42 } : Json).stringify()
  let result : CallToolResult = {
    content: [Text(serialized)],
    structured_content: Some({ "value": 42 }),
    is_error: false,
  }
  assert_eq(result.render_text(), serialized)
}

///|
test "render_text appends structuredContent distinct from a status message" {
  let result : CallToolResult = {
    content: [Text("done")],
    structured_content: Some({ "value": 42 }),
    is_error: false,
  }
  assert_eq(result.render_text(), "done\n{\"value\":42}")
}
