///|
/// Run a headers helper and decode its stdout as a flat map of HTTP headers.
/// Arguments are passed literally, without a shell, in `cwd` when supplied.
/// The helper inherits the environment, receives EOF on stdin, and has a 45s
/// deadline. A nonzero exit reports the exit status and stderr. Credential
/// expiry, refresh and persistence belong to the helper executable.
pub async fn run(command : Array[String], cwd? : String) -> Map[String, String] {
  guard !command.is_empty() && !command[0].is_empty() else {
    fail("MCP headersHelper needs an executable")
  }
  @async.with_timeout(45000, () => {
    let (stdin, writer) = @process.write_to_process()
    writer.close()
    let (code, stdout, stderr) = @process.collect_output(
      command[0],
      command[1:],
      stdin~,
      cwd?=cwd.map(value => value),
      no_console_window=true,
    )
    guard code == 0 else {
      fail("MCP headersHelper exited with status \{code}:\n\{stderr.text()}")
    }
    decode_helper_headers(stdout.text())
  }) catch {
    @async.TimeoutError => fail("MCP headersHelper timed out")
    error => raise error
  }
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
    guard !name.is_empty() &&
      name
      .iter()
      .all(c => {
        (c >= 'a' && c <= 'z') ||
        (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') ||
        "!#$%&'*+-.^_`|~".contains(c.to_string())
      }) &&
      !value.contains("\r") &&
      !value.contains("\n") &&
      !value.contains("\u0000") else {
      fail("MCP headersHelper returned an invalid HTTP header")
    }
    headers[name] = value
  }
  headers
}
