///|
fn listener_address(url : String) -> @socket.Addr raise {
  let authority = url
    .split("://")
    .last()
    .unwrap_or("")
    .split("/")
    .next()
    .unwrap_or("")
  @socket.Addr::parse(authority.to_owned())
}

///|
/// Assert on the captured listener capability, never on its released ephemeral
/// port: another process can legitimately acquire that address after close.
async fn expect_closed_listener(operation : async () -> Unit) -> Unit {
  try @async.with_timeout(1000, operation) catch {
    @os_error.OSError(_, context~) =>
      assert_true(context.has_prefix("@socket.TcpServer::accept()"))
    error => raise error
  } noraise {
    _ => fail("a closed host listener accepted a connection")
  }
}

///|
async fn expect_closed_host(server : Server) -> Unit {
  expect_closed_listener(() => {
    let (connection, _) = server.console.server.accept()
    connection.close()
  })
  expect_closed_listener(() => server.tools.run())
}

///|
async test "invalid frontend startup releases API and host tool listeners" {
  let root = @fs.tmpdir(prefix="seekmoon-server-startup-")
  defer @fs.rmdir(root, recursive=true)
  let server = Server::bind(port=0, runtime_dir=Path(root))
  defer server.close()
  let api = listener_address(server.url())
  let tools = listener_address(server.tools.url())
  assert_true(api.port() != tools.port())
  assert_true(!server.token().is_empty())
  @fs.write_file(root + "/file", "not a directory")
  try server.run(root=root + "/file") catch {
    @backend_host.HostError(_) => ()
    error => raise error
  } noraise {
    _ => fail("a file was served as a frontend root")
  }
  expect_closed_host(server)
}

///|
async test "an unused shared host explicitly releases both listeners" {
  let server = Server::bind(port=0)
  server.close()
  server.close()
  expect_closed_host(server)
}

///|
test "shared host keeps the existing relay environment override contract" {
  assert_true(relay_environment({}) is None)
  assert_true(
    relay_environment({ "OPENSEEK_RELAY_URL": "wss://relay.example/v1/tunnel" })
    is None,
  )
  guard relay_environment({
      "OPENSEEK_RELAY_URL": "wss://relay.example/v1/tunnel",
      "OPENSEEK_DEVICE_TOKEN": "test",
    })
    is Some(config) else {
    fail("a complete override was ignored")
  }
  assert_eq(config.relay_url, "wss://relay.example/v1/tunnel")
  assert_eq(config.device_token, "test")
  assert_eq(config.device_name, "desktop")
  guard relay_environment({
      "OPENSEEK_RELAY_URL": "wss://relay.example/v1/tunnel",
      "OPENSEEK_DEVICE_TOKEN": "test",
      "OPENSEEK_DEVICE_NAME": "terminal host",
    })
    is Some(named) else {
    fail("a named override was ignored")
  }
  assert_eq(named.device_name, "terminal host")
}
