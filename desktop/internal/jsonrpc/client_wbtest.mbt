// Round-trip tests over an in-memory message transport (two queues), so the
// client is exercised with no framing and no process.

///|
/// A `Transport` backed by two queues: `inbound` carries peer->client messages
/// the client reads, `outbound` collects client->peer messages the fake peer
/// reads. Closing `inbound` ends the stream.
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
/// Build a success reply echoing a request's id, tagging the result with the
/// request's method so a test can tell replies apart regardless of order.
fn reply_for(request : Json) -> Json {
  let id = match request {
    { "id": id, .. } => id
    _ => Json::null()
  }
  let method_ = match request {
    { "method": String(method_), .. } => method_
    _ => ""
  }
  { "jsonrpc": "2.0", "id": id, "result": { "method": method_ } }
}

///|
async test "concurrent requests each get their own reply even when answered out of order" {
  @async.with_task_group(group => {
    let inbound : @async.Queue[Json] = Queue(kind=Unbounded)
    let outbound : @async.Queue[Json] = Queue(kind=Unbounded)
    let client = Client::new(FakeTransport::{ inbound, outbound })
    // Fake peer: take both requests, then answer them in reverse arrival order.
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      let first_seen = outbound.get()
      let second_seen = outbound.get()
      inbound.put(reply_for(second_seen))
      inbound.put(reply_for(first_seen))
    })
    let first = group.spawn(() => client.request(method_="first", params={}))
    let second = group.spawn(() => client.request(method_="second", params={}))
    assert_true(first.wait() is { "method": String("first"), .. })
    assert_true(second.wait() is { "method": String("second"), .. })
  })
}

///|
async test "a request fails with Closed when the transport ends without a reply" {
  @async.with_task_group(group => {
    let inbound : @async.Queue[Json] = Queue(kind=Unbounded)
    let outbound : @async.Queue[Json] = Queue(kind=Unbounded)
    let client = Client::new(FakeTransport::{ inbound, outbound })
    // The peer consumes the request but ends the stream without answering.
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      outbound.get() |> ignore
      inbound.close()
    })
    let outcome = try {
      client.request(method_="ping", params={}) |> ignore
      "no error raised"
    } catch {
      Closed => "closed"
      error if @async.is_being_cancelled() => raise error
      _ => "other error"
    }
    assert_eq(outcome, "closed")
  })
}
