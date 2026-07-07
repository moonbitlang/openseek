///|
test "build_request carries jsonrpc, numeric id, method and params" {
  let params : Json = { "textDocument": { "uri": "openseek:///a.mbt" } }
  let request = build_request(7, "textDocument/hover", params)
  assert_true(
    request
    is {
      "jsonrpc": String("2.0"),
      "id": Number(7, ..),
      "method": String("textDocument/hover"),
      "params": {
        "textDocument": { "uri": String("openseek:///a.mbt"), .. },
        ..
      },
      ..
    },
  )
}

///|
test "build_notification omits the id" {
  let note = build_notification("initialized", {})
  assert_true(note is { "method": String("initialized"), .. })
  assert_true(!(note is { "id": _, .. }))
}

///|
test "build_error_reply answers a peer request with a method-not-found error" {
  let reply = build_error_reply(Json::number(5))
  assert_true(
    reply
    is {
      "id": Number(5, ..),
      "error": {
        "code": Number(-32601, ..),
        "message": String("Method not found"),
        ..
      },
      ..
    },
  )
  // An error reply, not a misleading empty success.
  assert_true(!(reply is { "result": _, .. }))
}

///|
test "classify_incoming routes a successful reply by id" {
  let message : Json = {
    "jsonrpc": "2.0",
    "id": 3,
    "result": { "contents": "Int" },
  }
  match classify_incoming(message) {
    Reply(id, Ok(value)) => {
      assert_eq(id, 3)
      assert_true(value is { "contents": String("Int"), .. })
    }
    _ => fail("expected a successful Reply")
  }
}

///|
test "classify_incoming parses an error reply into a typed failure" {
  let message : Json = {
    "jsonrpc": "2.0",
    "id": 4,
    "error": { "code": -32601, "message": "method not found" },
  }
  match classify_incoming(message) {
    Reply(id, Err(Failed(code~, message~))) => {
      assert_eq(id, 4)
      assert_eq(code, -32601)
      assert_eq(message, "method not found")
    }
    _ => fail("expected a failed Reply")
  }
}

///|
test "classify_incoming distinguishes peer requests from notifications" {
  let peer_request : Json = {
    "jsonrpc": "2.0",
    "id": 9,
    "method": "window/workDoneProgress/create",
  }
  match classify_incoming(peer_request) {
    PeerRequest(id) => assert_true(id is Number(9, ..))
    _ => fail("expected a PeerRequest")
  }
  let notification : Json = {
    "jsonrpc": "2.0",
    "method": "textDocument/publishDiagnostics",
  }
  match classify_incoming(notification) {
    Notification(_, _) => ()
    _ => fail("expected a Notification")
  }
}

///|
test "classify_incoming treats an id-less, method-less message as unknown" {
  match classify_incoming({ "jsonrpc": "2.0" }) {
    Unknown => ()
    _ => fail("expected Unknown")
  }
}
