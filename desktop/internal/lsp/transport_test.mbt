// End-to-end through the public API: a real `@jsonrpc.Client` driving a
// `StreamTransport` over a pipe pair, answered by a fake server that runs a
// `StreamTransport` of its own on the other ends — so both sides exercise the
// Content-Length framing.

///|
async test "a jsonrpc client over a stream transport completes a framed request" {
  @async.with_task_group(group => {
    // client -> server and server -> client byte pipes.
    let (server_reads, client_writes) = @io.pipe()
    let (client_reads, server_writes) = @io.pipe()
    let client = @jsonrpc.Client::new(
      @lsp.StreamTransport::new(client_reads, client_writes),
    )
    let server : &@jsonrpc.Transport = @lsp.StreamTransport::new(
      server_reads, server_writes,
    )
    // Fake server: read one request and answer it, echoing the id.
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      guard server.recv() is Some(request) else { return }
      let id = match request {
        { "id": id, .. } => id
        _ => Json::null()
      }
      server.send({ "jsonrpc": "2.0", "id": id, "result": { "ok": true } })
    })
    let result = client.request(method_="ping", params={})
    assert_true(result is { "ok": True, .. })
  })
}
