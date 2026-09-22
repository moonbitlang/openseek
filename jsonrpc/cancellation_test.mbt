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
        @async.TaskCancelled => ()
        error => raise error
      } noraise {
        _ => fail("writer should propagate cancellation")
      }
      assert_true(client.is_closed())
      assert_true(request.wait())
    })
  })
}
