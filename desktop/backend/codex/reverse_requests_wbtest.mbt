///|
priv struct ApprovalTransport {
  incoming : @async.Queue[Json]
  outgoing : @async.Queue[Json]
}

///|
impl @jsonrpc.Transport for ApprovalTransport with fn send(self, message) {
  self.outgoing.put(message)
}

///|
impl @jsonrpc.Transport for ApprovalTransport with fn recv(self) {
  Some(self.incoming.get()) catch {
    _ => None
  }
}

///|
impl @jsonrpc.Transport for ApprovalTransport with fn close(self) {
  self.incoming.close()
  self.outgoing.close()
}

///|
async test "Codex approval tokens fence reused ids and arbitrate simultaneous replies" {
  @async.with_timeout(5000, () => {
    @async.with_task_group(group => {
      let transport : ApprovalTransport = {
        incoming: Queue(kind=Blocking(4)),
        outgoing: Queue(kind=Blocking(4)),
      }
      let rpc = @jsonrpc.Client(transport)
      defer rpc.close()
      let connection : Connection = { rpc, }
      let received : @async.Queue[@jsonrpc.PeerRequest] = Queue(
        kind=Blocking(4),
      )
      rpc.set_request_handler(request => received.try_put(request))
      group.spawn_bg(no_wait=true, allow_failure=true, () => {
        rpc.run_message_pump()
      })
      group.spawn_bg(no_wait=true, allow_failure=true, () => rpc.run_writer())
      transport.incoming.put({
        "jsonrpc": "2.0",
        "id": 7,
        "method": "item/commandExecution/requestApproval",
        "params": { "threadId": "thread-1" },
      })
      let request = received.get()
      let key = request.id().stringify()
      let registry = ReverseRequestRegistry()
      let old_token = registry.insert(key, request)
      guard registry.snapshot()
        is {
          "data": [{ "response_token": String(snapshot_token), .. }],
          "generation": Number(1, ..),
          ..
        } else {
        fail("snapshot must contain the live request")
      }
      assert_eq(snapshot_token, old_token)
      registry.reset()
      let token = registry.insert(key, request)
      assert_true(token != old_token)
      let stale : @async.Queue[Result[Json, CodexError]] = Queue(
        kind=Blocking(1),
      )
      connection.dispatch_input(
        group,
        registry,
        Respond(request.id(), old_token, { "decision": "accept" }, stale),
      )
      assert_true(stale.get() is Err(_))
      assert_eq(registry.generation, 3)
      let first : @async.Queue[Result[Json, CodexError]] = Queue(
        kind=Blocking(1),
      )
      let second : @async.Queue[Result[Json, CodexError]] = Queue(
        kind=Blocking(1),
      )
      connection.dispatch_input(
        group,
        registry,
        Respond(request.id(), token, { "decision": "decline" }, first),
      )
      connection.dispatch_input(
        group,
        registry,
        Respond(request.id(), token, { "decision": "accept" }, second),
      )
      assert_true(second.get() is Err(_))
      assert_true(first.get() is Ok(_))
      assert_true(
        transport.outgoing.get()
        is { "id": Number(7, ..), "result": { "decision": "decline", .. }, .. },
      )
      assert_true(transport.outgoing.try_get() is None)
      assert_true(
        registry.snapshot() is { "data": [], "generation": Number(4, ..), .. },
      )
      // A new host actor may restart its generation counter and reuse the RPC id.
      // Its randomly minted reply identity must still reject the old window.
      let restarted = ReverseRequestRegistry()
      let fresh_token = restarted.insert(key, request)
      assert_true(fresh_token != token && fresh_token != old_token)
      assert_true(restarted.take(key, token) is None)
      assert_true(restarted.take(key, fresh_token) is Some(_))
    })
  })
}
