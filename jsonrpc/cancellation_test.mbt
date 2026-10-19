///|
struct BlockedTransport {
  sent : @async.Queue[Json]
  incoming : @async.Queue[Json]
  release_send : @async.Queue[Unit]
}

///|
impl @jsonrpc.Transport for BlockedTransport with fn send(self, message) {
  self.sent.put(message)
  self.release_send.get()
}

///|
impl @jsonrpc.Transport for BlockedTransport with fn recv(self) {
  Some(self.incoming.get()) catch {
    _ => None
  }
}

///|
impl @jsonrpc.Transport for BlockedTransport with fn close(self) {
  self.sent.close()
  self.incoming.close()
  self.release_send.close()
}

///|
async test "cancelling a blocked writer closes the client and settles its request" {
  @async.with_timeout(2000, () => {
    @async.with_task_group(group => {
      let transport : BlockedTransport = {
        sent: Queue(kind=Unbounded),
        incoming: Queue(kind=Unbounded),
        release_send: Queue(kind=Unbounded),
      }
      let client = @jsonrpc.Client(transport)
      group.spawn_bg(no_wait=true, () => client.run_message_pump())
      let writer = group.spawn(() => client.run_writer())
      let request = group.spawn(() => {
        try
          client.request(method_="blocked", params=Json::empty_object())
        catch {
          @jsonrpc.Closed => true
          error => raise error
        } noraise {
          _ => false
        }
      })
      ignore(transport.sent.get())
      writer.cancel()
      try writer.wait() catch {
        @async.WaitedTaskAlreadyCancelled => ()
        error => raise error
      } noraise {
        _ => fail("writer should propagate cancellation")
      }
      assert_true(client.is_closed())
      assert_true(request.wait())
    })
  })
}

///|
async test "request cancellation survives a full outbox and preserves the connection" {
  @async.with_timeout(2000, () => {
    @async.with_task_group(group => {
      let transport : BlockedTransport = {
        sent: Queue(kind=Unbounded),
        incoming: Queue(kind=Unbounded),
        release_send: Queue(kind=Unbounded),
      }
      let client = @jsonrpc.Client(transport)
      defer client.close()
      group.spawn_bg(no_wait=true, allow_failure=true, () => {
        client.run_message_pump()
      })
      group.spawn_bg(no_wait=true, allow_failure=true, () => client.run_writer())
      let request = group.spawn(no_wait=true, () => {
        client.request(method_="tools/call", params={}, cancel_on_exit=true)
      })
      let sent = transport.sent.get()
      guard sent is { "id": id, .. } else { fail("missing request ID") }
      // The writer is blocked after writing the request. Fill the whole bounded
      // outbox, then cancel without allowing it to make room for a notification.
      for _ in 0..<1024 {
        client.notify(method_="queued", params={})
      }
      request.cancel()
      try request.wait() catch {
        @async.WaitedTaskAlreadyCancelled => ()
        error => raise error
      } noraise {
        _ => fail("request must be cancelled")
      }
      transport.release_send.put(())
      let cancellation = transport.sent.get()
      assert_eq(cancellation, {
        "jsonrpc": "2.0",
        "method": "notifications/cancelled",
        "params": { "requestId": id },
      })
      transport.release_send.put(())
      assert_true(transport.sent.get() is { "method": "queued", .. })
      assert_true(!client.is_closed())
    })
  })
}

///|
async test "cancelling an unsent request never sends a cancellation before its ID" {
  @async.with_timeout(2000, () => {
    @async.with_task_group(group => {
      let transport : BlockedTransport = {
        sent: Queue(kind=Unbounded),
        incoming: Queue(kind=Unbounded),
        release_send: Queue(kind=Unbounded),
      }
      let client = @jsonrpc.Client(transport)
      defer client.close()
      group.spawn_bg(no_wait=true, allow_failure=true, () => {
        client.run_message_pump()
      })
      group.spawn_bg(no_wait=true, allow_failure=true, () => client.run_writer())
      client.notify(method_="block-writer", params={})
      ignore(transport.sent.get())
      let request = group.spawn(no_wait=true, () => {
        client.request(method_="must-not-run", params={}, cancel_on_exit=true)
      })
      @async.pause()
      request.cancel()
      try request.wait() catch {
        @async.WaitedTaskAlreadyCancelled => ()
        error => raise error
      } noraise {
        _ => fail("request must be cancelled")
      }
      client.notify(method_="after-cancel", params={})
      transport.release_send.put(())
      assert_true(transport.sent.get() is { "method": "after-cancel", .. })
    })
  })
}
