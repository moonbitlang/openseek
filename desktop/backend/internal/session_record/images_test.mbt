///|
let pixel = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=="

///|
fn image_record(sequence : Int32, kind : String, padding : String) -> String {
  let json : Json = {
    "sequence": sequence,
    "ts": 0,
    "item": {
      "kind": kind,
      "payload": {
        "tool_call_id": "image",
        "tool_name": "read_image",
        "is_error": false,
        "content": [
          { "type": "text", "text": padding },
          { "type": "image", "media_type": "image/png", "data": pixel },
        ],
      },
    },
  }
  json.stringify()
}

///|
fn image_reference(
  doc : @protocol.SessionDocument,
) -> @protocol.SessionImageRef raise {
  guard doc.events is Some([event, ..]) else { fail("missing event") }
  let content = match event.item {
    User(user) => user.content
    ToolResult(result) => result.content
    _ => fail("expected image content")
  }
  guard content.0 is [Text(_), ImageRef(image)] else {
    fail("expected lightweight image reference")
  }
  image
}

///|
async test "snapshots and follower events defer images without changing durable content" {
  for kind in ["user", "tool_result"] {
    let (root, path) = record_fixture("images")
    // Unicode and a multi-chunk event exercise byte rather than UTF-16 offsets.
    let padding = "图".repeat(50000)
    let original = header_line("images") + image_record(1, kind, padding)
    write_record(path, original)
    let tail = @session_record.Tail(root, "images")
    let events = tail.poll()
    assert_eq(events.length(), 1)
    let image = image_reference(tail.document())
    assert_eq(image.sequence, 1)
    assert_eq(image.part, 1)
    assert_false(tail.document().to_json().stringify().contains(pixel))
    let reply = @session_record.read_image(image)
    assert_eq(reply.data_url, "data:image/png;base64," + pixel)
    // Finishing a previously unterminated record and appending preserves refs.
    append_record(path, "\n" + event_line(2, "next"))
    assert_eq(tail.poll().length(), 1)
    assert_eq(@session_record.read_image(image).data_url, reply.data_url)
    assert_eq(
      @session_record.read_text(root, "images"),
      original + "\n" + event_line(2, "next"),
    )
    let loaded = @session_record.read_document(root, "images")
    assert_eq(
      @session_record.read_image(image_reference(loaded)).data_url,
      reply.data_url,
    )
  }
}

///|
async test "image references reject replaced records, bad parts and deferred invalid images" {
  let (root, path) = record_fixture("images")
  write_record(
    path,
    header_line("images") + image_record(1, "user", "text") + "\n",
  )
  let image = image_reference(@session_record.read_document(root, "images"))
  let wrong_part = try {
    ignore(@session_record.read_image({ ..image, part: 0, }))
    false
  } catch {
    _ => true
  }
  assert_true(wrong_part)
  let wrong_sequence = try {
    ignore(@session_record.read_image({ ..image, sequence: 2, }))
    false
  } catch {
    _ => true
  }
  assert_true(wrong_sequence)
  write_record(path, header_line("images") + event_line(1, "replacement"))
  let replaced = try {
    ignore(@session_record.read_image(image))
    false
  } catch {
    _ => true
  }
  assert_true(replaced)
  let invalid = image_record(1, "user", "text").replace(
    old=pixel,
    new="invalid base64",
  )
  write_record(path, header_line("images") + invalid + "\n")
  let image = image_reference(@session_record.read_document(root, "images"))
  let rejected = try {
    ignore(@session_record.read_image(image))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
async test "archived records produce readable references and reject on-disk references" {
  let (root, path) = record_fixture("images")
  write_record(
    path,
    header_line("images") + image_record(1, "user", "archived") + "\n",
  )
  let live = image_reference(@session_record.read_document(root, "images"))
  let archived = @pathx.Path(root.to_string() + "-archived").resolve()
  @fs.rename(root.to_string(), archived.to_string())
  let image = image_reference(@session_record.read_document(archived, "images"))
  assert_false(image.record == live.record)
  assert_eq(
    @session_record.read_image(image).data_url,
    "data:image/png;base64," + pixel,
  )
  let moved = try {
    ignore(@session_record.read_image(live))
    false
  } catch {
    _ => true
  }
  assert_true(moved)
  // A raw record cannot supply another record's reference to the UI.
  let injected : Json = {
    "sequence": 1,
    "item": {
      "kind": "user",
      "payload": {
        "content": [{ "type": "image_ref", "image": image.to_json() }],
      },
    },
  }
  write_record(
    @session_record.record_path(archived, "images"),
    header_line("images") + injected.stringify() + "\n",
  )
  let refused = try {
    ignore(@session_record.read_document(archived, "images"))
    false
  } catch {
    _ => true
  }
  assert_true(refused)
}
