///|
/// Bind a localhost mock server for one test, or report the skip and return
/// None where the sandbox forbids TCP binds.
async fn bind_test_server(skip_message : String) -> @http.Server? {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0")) catch {
    error if "\{error}".contains("Operation not permitted") => {
      println(skip_message)
      return None
    }
    error => raise error
  }
  Some(server)
}

///|
/// Serve `/chat/completions` on a localhost mock for one test, returning its
/// URL: `handle` runs per request with the request, its body read out as text,
/// and the connection to answer on. Reports the skip and returns None where the
/// sandbox forbids TCP binds.
async fn serve_chat_completions(
  group : @async.TaskGroup[Unit],
  skip_message : String,
  max_connections~ : Int,
  handle : async (@http.Request, String, @http.ServerConnection) -> Unit,
) -> String? {
  guard bind_test_server(skip_message) is Some(server) else { return None }
  group.spawn_bg(no_wait=true) <| () => {
    server.run_forever(
      (request, body, conn) => handle(request, body.read_all().text(), conn),
      max_connections~,
    )
  }
  Some("http://127.0.0.1:\{server.addr.port()}/chat/completions")
}
