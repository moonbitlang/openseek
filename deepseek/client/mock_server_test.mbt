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
