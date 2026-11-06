///|
let command : @argparse.Command = Command(
  "http-file-server",
  about="Serve a directory read-only on 127.0.0.1. Prints the bound URL; stop the process to close it.",
  positionals=[
    PositionArg("directory", default_values=["."], about="Directory to serve."),
  ],
  options=[
    OptionArg("port", long="port", default_values=["0"], about="TCP port; 0 asks the OS for a free port."),
  ],
)

///|
async fn run() -> Unit {
  let args = command.parse()
  let port = @string.parse_int(args.values["port"][0])
  guard port >= 0 && port <= 65535 else {
    @stdio.stderr.write("http-file-server: Port must be between 0 and 65535\n")
    @env.exit(1)
    return
  }
  let directory = @http_file_server.Directory(args.values["directory"][0])
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:\{port}"))
  defer server.close()
  let authority = "127.0.0.1:\{server.addr.port()}"
  @stdio.stdout.write("http://\{authority}/\n")
  server.run_forever((request, _, conn) => {
    defer conn.close()
    guard request.headers.get("host") == Some(authority) else {
      conn.send_response(403, "Forbidden", extra_headers={ "Content-Length": "0" })
      conn.end_response()
      return
    }
    directory.serve(request, conn, index=true) catch {
      error => {
        @stdio.stderr.write("http-file-server: \{error}\n")
        conn.send_response(500, "Internal Server Error", extra_headers={ "Content-Length": "0" })
        conn.end_response()
      }
    }
  })
}

///|
async fn main {
  run() catch {
    error => {
      @stdio.stderr.write("http-file-server: \{error}\n")
      @env.exit(1)
    }
  }
}
