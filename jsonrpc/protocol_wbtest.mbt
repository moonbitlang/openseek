///|
test "build_request carries jsonrpc, numeric id, method and params" {
  let params : Json = { "name": "list", "cursor": "abc" }
  let request = build_request(7, "tools/list", params)
  assert_true(
    request
    is {
      "jsonrpc": String("2.0"),
      "id": Number(7, ..),
      "method": String("tools/list"),
      "params": { "name": String("list"), "cursor": String("abc"), .. },
      ..
    },
  )
}

///|
test "build_notification omits the id" {
  let note = build_notification(
    "notifications/initialized",
    Json::empty_object(),
  )
  assert_true(note is { "method": String("notifications/initialized"), .. })
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
  let message : Json = { "jsonrpc": "2.0", "id": 3, "result": { "tools": [] } }
  match classify_incoming(message) {
    Reply(id, Ok(value)) => {
      assert_eq(id, 3)
      assert_true(value is { "tools": Array([]), .. })
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
test "parse_error defaults code and message when the peer omits them" {
  match
    classify_incoming({
      "jsonrpc": "2.0",
      "id": 8,
      "error": Json::empty_object(),
    }) {
    Reply(_, Err(Failed(code~, message~))) => {
      assert_eq(code, 0)
      assert_eq(message, "")
    }
    _ => fail("expected a failed Reply")
  }
}

///|
test "classify_incoming distinguishes peer requests from notifications" {
  let peer_request : Json = {
    "jsonrpc": "2.0",
    "id": 9,
    "method": "roots/list",
  }
  match classify_incoming(peer_request) {
    PeerRequest(id, method_) => {
      assert_true(id is Number(9, ..))
      assert_eq(method_, "roots/list")
    }
    _ => fail("expected a PeerRequest")
  }
  let notification : Json = {
    "jsonrpc": "2.0",
    "method": "notifications/tools/list_changed",
  }
  match classify_incoming(notification) {
    Notification(method_, _) =>
      assert_eq(method_, "notifications/tools/list_changed")
    _ => fail("expected a Notification")
  }
}

///|
test "classify_incoming prefers error over result when a reply has both" {
  match
    classify_incoming({
      "jsonrpc": "2.0",
      "id": 5,
      "result": Json::null(),
      "error": { "code": -1, "message": "boom" },
    }) {
    Reply(5, Err(Failed(code~, message~))) => {
      assert_eq(code, -1)
      assert_eq(message, "boom")
    }
    _ => fail("expected the error to win over the result")
  }
}

///|
test "classify_incoming ignores an explicit null error and returns the result" {
  match
    classify_incoming({
      "jsonrpc": "2.0",
      "id": 6,
      "result": { "ok": true },
      "error": Json::null(),
    }) {
    Reply(6, Ok(value)) => assert_true(value is { "ok": True, .. })
    _ => fail("expected the null error to be ignored and the result returned")
  }
}

///|
test "classify_incoming treats a present null id as a peer request" {
  // JSON-RPC 2.0: a notification omits `id`; a present `id: null` is a request
  // that must be answered (echoing the null id).
  match
    classify_incoming({ "jsonrpc": "2.0", "id": Json::null(), "method": "ping" }) {
    PeerRequest(id, method_) => {
      assert_true(id is Null)
      assert_eq(method_, "ping")
    }
    _ => fail("expected a present null id to be a peer request")
  }
}

///|
test "classify_incoming treats an id-less, method-less message as unknown" {
  match classify_incoming({ "jsonrpc": "2.0" }) {
    Unknown => ()
    _ => fail("expected Unknown")
  }
}

///|
test "a reply with neither result nor error is a successful empty result" {
  match classify_incoming({ "jsonrpc": "2.0", "id": 2 }) {
    Reply(id, Ok(value)) => {
      assert_eq(id, 2)
      assert_true(value is Null)
    }
    _ => fail("expected a successful empty Reply")
  }
}

///|
test "classify_incoming accepts an exact integer reply id" {
  match
    classify_incoming({
      "jsonrpc": "2.0",
      "id": Json::number(3.0),
      "result": Json::null(),
    }) {
    Reply(3, Ok(_)) => ()
    _ => fail("expected an exact integer id to route")
  }
}

///|
test "classify_incoming rejects a fractional reply id as unknown" {
  // 1.5 truncates to 1 under `to_int`; accepting it would misroute the reply to
  // pending request 1.
  match
    classify_incoming({
      "jsonrpc": "2.0",
      "id": Json::number(1.5),
      "result": Json::null(),
    }) {
    Unknown => ()
    _ => fail("expected a fractional id to be Unknown")
  }
}

///|
test "classify_incoming rejects an out-of-range reply id as unknown" {
  // Beyond Int range `to_int` saturates, so the id would not round-trip; drop it.
  match
    classify_incoming({
      "jsonrpc": "2.0",
      "id": Json::number(4294967297.0),
      "result": Json::null(),
    }) {
    Unknown => ()
    _ => fail("expected an out-of-range id to be Unknown")
  }
}
