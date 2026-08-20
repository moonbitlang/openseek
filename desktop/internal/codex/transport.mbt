// Newline-delimited JSON transport for one Codex app-server stdio
// connection. App-server reserves stdout for protocol messages and stderr for
// diagnostics; each stdout line is one complete JSON message.

///|
struct StdioTransport {
  reader : &@io.Reader
  writer : &@io.Writer
  teardown : () -> Unit
}

///|
fn StdioTransport::StdioTransport(
  reader : &@io.Reader,
  writer : &@io.Writer,
  teardown~ : () -> Unit,
) -> StdioTransport {
  { reader, writer, teardown }
}

///|
pub impl @jsonrpc.Transport for StdioTransport with fn send(self, message) {
  self.writer.write("\{message.stringify()}\n")
}

///|
pub impl @jsonrpc.Transport for StdioTransport with fn recv(self) {
  for ;; {
    let line = self.reader.read_until("\n") catch {
      error if @async.is_being_cancelled() => raise error
      _ => None
    }
    guard line is Some(line) else { return None }
    let trimmed = line.trim(chars="\r\n")
    if trimmed == "" {
      continue
    }
    // A non-JSON stdout line violates app-server framing. Ignore it instead of
    // killing unrelated in-flight requests; EOF still closes the connection.
    if (Some(@json.parse(trimmed)) catch { _ => None }) is Some(message) {
      return Some(message)
    }
  }
}

///|
pub impl @jsonrpc.Transport for StdioTransport with fn close(self) {
  (self.teardown)()
}

///|
pub extend StdioTransport with @jsonrpc.Transport::{close, recv, send}
