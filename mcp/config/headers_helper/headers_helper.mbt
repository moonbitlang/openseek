///|
/// Run a headers helper and decode its stdout as a flat map of HTTP headers.
/// Arguments are passed literally, without a shell, in `cwd` when supplied.
/// The helper inherits the environment and receives EOF on stdin. Stderr is
/// forwarded while it runs and included in nonzero-exit errors. The helper owns
/// authorization deadlines, token expiry, refresh and persistence; cancellation
/// of the caller still terminates the subprocess.
pub async fn run(command : Array[String], cwd? : String) -> Map[String, String] {
  guard command is [cmd, .. args] else {
    fail("MCP headersHelper needs an executable")
  }
  let (stdin, writer) = @process.write_to_process()
  writer.close()
  let (stderr, stderr_pipe) = @process.read_from_process()
  defer stderr.close()
  let diagnostics = @buffer.Buffer()
  let (code, stdout) = @async.with_task_group(group => {
    group.spawn_bg(() => {
      while stderr.read_some() is Some(chunk) {
        diagnostics.write_bytes(chunk)
        @stdio.stderr.write(chunk)
      }
    })
    @process.collect_stdout(
      cmd,
      args,
      stdin~,
      stderr=stderr_pipe,
      cwd?=cwd.map(value => value),
      no_console_window=true,
    )
  })
  guard code == 0 else {
    fail(
      "MCP headersHelper exited with status \{code}:\n\{@utf8.decode(diagnostics.to_bytes())}",
    )
  }
  decode_helper_headers(stdout.text())
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
