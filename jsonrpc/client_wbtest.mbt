// Round-trip tests over in-memory transports (queues), so the client is
// exercised with no framing and no process. Every test that issues a request
// spawns both standing tasks — `run_message_pump` (reader) and `run_writer`
// (writer) — the client requires.

///|
/// A `Transport` backed by two queues: `inbound` carries peer->client messages
/// the client reads, `outbound` collects client->peer messages the fake peer
/// reads. `close` closes both, ending the stream and unblocking a parked reader.
struct FakeTransport {
  inbound : @async.Queue[Json]
  outbound : @async.Queue[Json]
}

///|
impl Transport for FakeTransport with fn send(self, message) {
  self.outbound.put(message)
}

///|
impl Transport for FakeTransport with fn recv(self) {
  Some(self.inbound.get()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => None
  }
}

///|
impl Transport for FakeTransport with fn close(self) {
  self.inbound.close()
  self.outbound.close()
}

///|
fn new_transport() -> FakeTransport {
  { inbound: Queue(kind=Unbounded), outbound: Queue(kind=Unbounded) }
}

///|
/// A `Transport` whose `send` always fails and whose `recv` blocks until closed,
/// to exercise the close-on-send path and reader wake-up.
struct SendFailTransport {
  inbound : @async.Queue[Json]
}

///|
impl Transport for SendFailTransport with fn send(self, _message) {
  ignore(self.inbound)
  fail("send failed")
}

///|
impl Transport for SendFailTransport with fn recv(self) {
  Some(self.inbound.get()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => None
  }
}

///|
impl Transport for SendFailTransport with fn close(self) {
  self.inbound.close()
}

///|
/// Spawn the two standing tasks the client needs: reader and writer.
fn[X] spawn_client(group : @async.TaskGroup[X], client : Client) -> Unit {
  group.spawn_bg(no_wait=true, allow_failure=true, () => {
    client.run_message_pump()
  })
  group.spawn_bg(no_wait=true, allow_failure=true, () => client.run_writer())
}

///|
/// The raw id of a request, or `Null` if it somehow has none.
fn id_of(request : Json) -> Json {
  match request {
    { "id": id, .. } => id
    _ => Json::null()
  }
}

///|
/// Build a success reply echoing a request's id, tagging the result with the
/// request's method so a test can tell replies apart regardless of order.
fn reply_for(request : Json) -> Json {
  let method_ = match request {
    { "method": String(method_), .. } => method_
    _ => ""
  }
  { "jsonrpc": "2.0", "id": id_of(request), "result": { "method": method_ } }
}

///|
/// Build a JSON-RPC error reply echoing a request's id.
fn error_for(request : Json, code : Int, message : String) -> Json {
  {
    "jsonrpc": "2.0",
    "id": id_of(request),
    "error": { "code": Json::number(code.to_double()), "message": message },
  }
}

///|
async test "concurrent requests each get their own reply even when answered out of order" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let client = Client::new(transport)
    spawn_client(group, client)
    // Fake peer: take both requests, then answer them in reverse arrival order.
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      let first_seen = transport.outbound.get()
      let second_seen = transport.outbound.get()
      transport.inbound.put(reply_for(second_seen))
      transport.inbound.put(reply_for(first_seen))
    })
    let first = group.spawn(() => {
      client.request(method_="first", params=Json::empty_object())
    })
    let second = group.spawn(() => {
      client.request(method_="second", params=Json::empty_object())
    })
    assert_true(first.wait() is { "method": String("first"), .. })
    assert_true(second.wait() is { "method": String("second"), .. })
  })
}

///|
/// Regression guard: with several requests outstanding and only one answered,
/// the answered request's reply must come back promptly (no read-lock starving).
async test "a delivered reply never waits behind other outstanding requests" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let client = Client::new(transport)
    spawn_client(group, client)
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      client.request(method_="first", params=Json::null()) |> ignore
    })
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      client.request(method_="second", params=Json::null()) |> ignore
    })
    let third = group.spawn(() => {
      client.request(method_="third", params=Json::null())
    })
    let mut third_request = Json::null()
    for _ in 0..<3 {
      let sent = transport.outbound.get()
      if sent is { "method": String("third"), .. } {
        third_request = sent
      }
    }
    transport.inbound.put(reply_for(third_request))
    assert_true(third.wait() is { "method": String("third"), .. })
  })
}

///|
async test "a request raises Failed on a JSON-RPC error reply" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let client = Client::new(transport)
    spawn_client(group, client)
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      transport.inbound.put(error_for(transport.outbound.get(), -32601, "nope"))
    })
    let outcome = try {
      client.request(method_="tools/call", params=Json::empty_object())
      |> ignore
      "no error raised"
    } catch {
      Failed(code~, message~) => "failed \{code} \{message}"
      error if @async.is_being_cancelled() => raise error
      _ => "other error"
    }
    assert_eq(outcome, "failed -32601 nope")
  })
}

///|
/// A malformed peer that puts both `result` and `error` in one reply: the error
/// must win so a failure is never masked as success.
async test "a reply with both result and error surfaces the error" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let client = Client::new(transport)
    spawn_client(group, client)
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      let request = transport.outbound.get()
      transport.inbound.put({
        "jsonrpc": "2.0",
        "id": id_of(request),
        "result": { "ignored": true },
        "error": { "code": -32000, "message": "both" },
      })
    })
    let outcome = try {
      client.request(method_="x", params=Json::empty_object()) |> ignore
      "no error raised"
    } catch {
      Failed(code~, message~) => "failed \{code} \{message}"
      error if @async.is_being_cancelled() => raise error
      _ => "other error"
    }
    assert_eq(outcome, "failed -32000 both")
  })
}

///|
/// A reply carrying `error: null` next to a result is a success, not a failure.
async test "a reply with a null error alongside a result succeeds" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let client = Client::new(transport)
    spawn_client(group, client)
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      let request = transport.outbound.get()
      transport.inbound.put({
        "jsonrpc": "2.0",
        "id": id_of(request),
        "result": { "value": 7 },
        "error": Json::null(),
      })
    })
    let result = client.request(method_="probe", params=Json::empty_object())
    assert_true(result is { "value": Number(7, ..), .. })
  })
}

///|
/// A non-conformant peer batching two replies in one array must not wedge the
/// correlated requests.
async test "a batched array reply routes each element" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let client = Client::new(transport)
    spawn_client(group, client)
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      let first = transport.outbound.get()
      let second = transport.outbound.get()
      transport.inbound.put([reply_for(first), reply_for(second)])
    })
    let a = group.spawn(() => {
      client.request(method_="a", params=Json::empty_object())
    })
    let b = group.spawn(() => {
      client.request(method_="b", params=Json::empty_object())
    })
    assert_true(a.wait() is { "method": String("a"), .. })
    assert_true(b.wait() is { "method": String("b"), .. })
  })
}

///|
async test "peer notifications reach the installed handler" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let client = Client::new(transport)
    let seen : Ref[String] = { val: "" }
    client.set_notification_handler((method_, _params) => seen.val = method_)
    spawn_client(group, client)
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      let request = transport.outbound.get()
      transport.inbound.put({
        "jsonrpc": "2.0",
        "method": "notifications/message",
        "params": Json::empty_object(),
      })
      transport.inbound.put(reply_for(request))
    })
    client.request(method_="ping", params=Json::empty_object()) |> ignore
    assert_eq(seen.val, "notifications/message")
  })
}

///|
/// A stray reply for an id we never issued is dropped, and the client stays
/// usable for the real request.
async test "a reply for an unknown id is dropped and the client stays usable" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let client = Client::new(transport)
    spawn_client(group, client)
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      let request = transport.outbound.get()
      transport.inbound.put({
        "jsonrpc": "2.0",
        "id": 9999,
        "result": Json::empty_object(),
      })
      transport.inbound.put(reply_for(request))
    })
    let result = client.request(method_="real", params=Json::empty_object())
    assert_true(result is { "method": String("real"), .. })
  })
}

///|
/// A peer `ping` request is answered with an empty success (this client serves
/// no other method).
async test "a peer ping is answered with an empty success" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let client = Client::new(transport)
    spawn_client(group, client)
    transport.inbound.put({ "jsonrpc": "2.0", "id": 42, "method": "ping" })
    let reply = transport.outbound.get()
    assert_true(reply is { "id": Number(42, ..), "result": _, .. })
    assert_true(!(reply is { "error": _, .. }))
  })
}

///|
async test "a request fails with Closed when the transport ends without a reply" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let client = Client::new(transport)
    spawn_client(group, client)
    // The peer consumes the request but ends the stream without answering.
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      transport.outbound.get() |> ignore
      transport.inbound.close()
    })
    let outcome = try {
      client.request(method_="ping", params=Json::empty_object()) |> ignore
      "no error raised"
    } catch {
      Closed => "closed"
      error if @async.is_being_cancelled() => raise error
      _ => "other error"
    }
    assert_eq(outcome, "closed")
    assert_true(client.is_closed())
  })
}

///|
/// A failed send closes the client and unblocks the parked reader, so both
/// standing tasks return and the in-flight request fails with `Closed`.
async test "a failed send closes the client and stops both tasks" {
  @async.with_task_group(group => {
    let client = Client::new(SendFailTransport::{
      inbound: Queue(kind=Unbounded),
    })
    let pump = group.spawn(() => client.run_message_pump())
    let writer = group.spawn(() => client.run_writer())
    let outcome = try {
      client.request(method_="ping", params=Json::empty_object()) |> ignore
      "no error raised"
    } catch {
      Closed => "closed"
      error if @async.is_being_cancelled() => raise error
      _ => "other error"
    }
    assert_eq(outcome, "closed")
    assert_true(client.is_closed())
    pump.wait()
    writer.wait()
  })
}

///|
/// Regression guard: cancelling the reader must close the client (not leave a
/// zombie whose `is_closed` lies) and fail every in-flight request with `Closed`.
async test "cancelling the reader closes the client and fails in-flight requests" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let client = Client::new(transport)
    // Reader with nothing to read (peer never answers); writer drains sends.
    let pump = group.spawn(() => client.run_message_pump())
    group.spawn_bg(no_wait=true, allow_failure=true, () => client.run_writer())
    let request = group.spawn(() => {
      try {
        client.request(method_="ping", params=Json::empty_object()) |> ignore
        "returned"
      } catch {
        Closed => "closed"
        error if @async.is_being_cancelled() => raise error
        _ => "other error"
      }
    })
    pump.cancel()
    assert_eq(request.wait(), "closed")
    assert_true(client.is_closed())
  })
}

///|
async test "a request after close raises Closed and notify is a no-op" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let client = Client::new(transport)
    client.close()
    assert_true(client.is_closed())
    let outcome = try {
      client.request(method_="ping", params=Json::empty_object()) |> ignore
      "returned"
    } catch {
      Closed => "closed"
      error if @async.is_being_cancelled() => raise error
      _ => "other error"
    }
    assert_eq(outcome, "closed")
    // notify after close must not raise.
    client.notify(
      method_="notifications/initialized",
      params=Json::empty_object(),
    )
    ignore(group)
  })
}

///|
async test "notify enqueues an id-less message the writer sends" {
  @async.with_task_group(group => {
    let transport = new_transport()
    let client = Client::new(transport)
    spawn_client(group, client)
    client.notify(
      method_="notifications/initialized",
      params=Json::empty_object(),
    )
    let sent = transport.outbound.get()
    assert_true(sent is { "method": String("notifications/initialized"), .. })
    assert_true(!(sent is { "id": _, .. }))
  })
}
