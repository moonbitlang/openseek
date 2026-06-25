// The LSP session driven against a fake server over a pipe pair: the server
// answers `initialize` and `textDocument/hover` requests and ignores the
// notifications (`initialized`, `didOpen`) the session sends along the way.

///|
async test "a session initializes, syncs a document, and returns a hover" {
  @async.with_task_group(group => {
    let (server_reads, client_writes) = @io.pipe()
    let (client_reads, server_writes) = @io.pipe()
    let client = @jsonrpc.Client::new(
      @lsp.StreamTransport::new(client_reads, client_writes),
    )
    let session = @lsp.Session::new(client)
    let server : &@jsonrpc.Transport = @lsp.StreamTransport::new(
      server_reads, server_writes,
    )
    group.spawn_bg(no_wait=true, allow_failure=true, () => {
      for ;; {
        guard server.recv() is Some(message) else { return }
        match message {
          { "id": id, "method": String("initialize"), .. } =>
            server.send({
              "jsonrpc": "2.0",
              "id": id,
              "result": { "capabilities": {} },
            })
          { "id": id, "method": String("textDocument/hover"), .. } =>
            server.send({
              "jsonrpc": "2.0",
              "id": id,
              "result": { "contents": { "kind": "markdown", "value": "Int" } },
            })
          // Notifications (initialized, didOpen) carry no id: nothing to answer.
          _ => ()
        }
      }
    })
    session.initialize(root_uri="file:///w")
    session.sync_document(
      uri="file:///w/a.mbt",
      language_id="moonbit",
      text="let x = 1",
    )
    let hover = session.hover(uri="file:///w/a.mbt", line=0, character=4)
    assert_true(
      hover is Some({ "contents": { "value": String("Int"), .. }, .. }),
    )
  })
}
