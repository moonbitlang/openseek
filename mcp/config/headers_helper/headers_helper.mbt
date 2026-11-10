///|
/// Run a headers helper and decode its stdout as a flat map of HTTP headers.
/// Arguments are passed literally, without a shell, in `cwd` when supplied.
/// The helper inherits the environment and receives EOF on stdin. Stderr is
/// forwarded while it runs and included in nonzero-exit errors. The helper owns
/// authorization deadlines, token expiry, refresh and persistence; cancellation
/// of the caller still terminates the subprocess.
pub async fn run(
  helper : @config.HeadersHelperCommand,
  cwd? : String,
) -> Map[String, String] {
  let diagnostics = @buffer.Buffer()
  let stdout = @buffer.Buffer()
  let mut code = 0
  @async.with_task_group(group => {
    let process = @process.spawn(
      group,
      helper.command,
      helper.arguments,
      stdin=Empty,
      stdout=Collect,
      stderr=Collect,
      cwd?=cwd.map(value => value),
      no_console_window=true,
    )
    group.spawn_bg(() => {
      while process.stderr.read() is Some(chunk) {
        diagnostics.write_bytes(chunk)
        @stdio.stderr.write(chunk)
      }
    })
    stdout.write_bytes(process.stdout.read_all())
    code = process.wait()
  })
  guard code == 0 else {
    fail(
      "MCP headersHelper exited with status \{code}:\n\{@utf8.decode(diagnostics.to_bytes())}",
    )
  }
  decode_helper_headers(@utf8.decode(stdout.to_bytes()))
}

///|
fn decode_helper_headers(text : String) -> Map[String, String] raise {
  let value = @json.parse(text) catch {
    _ => fail("MCP headersHelper must output a JSON object of string headers")
  }
  guard value is Object(fields) else {
    fail("MCP headersHelper must output a JSON object of string headers")
  }
  let headers : Map[String, String] = Map([])
  for name, value in fields {
    guard value is String(value) else {
      fail("MCP headersHelper values must be strings")
    }
    headers[name] = value
  }
  headers
}
