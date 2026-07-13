// An NDJSON `@jsonrpc.Transport`: newline-delimited JSON-RPC over a byte
// reader/writer pair — an MCP server subprocess's stdout/stdin. MCP stdio frames
// each message as one line of UTF-8 JSON with no embedded newlines.

///|
/// A `@jsonrpc.Transport` that frames messages as newline-delimited JSON over a
/// reader/writer pair. `on_close` is the synchronous teardown (e.g. terminate
/// the subprocess and close its pipes) run when the client closes.
struct NdjsonTransport {
  reader : &@io.Reader
  writer : &@io.Writer
  on_close : () -> Unit
}

///|
/// Build an NDJSON transport over `reader`/`writer`. `on_close` is the required,
/// synchronous, idempotent teardown the client runs when it closes the
/// transport. It MUST actually unblock a reader/writer parked on this pair —
/// closing the underlying fd does not wake a coroutine suspended on it, so a
/// subprocess transport cancels its reader/writer tasks — and should close the
/// endpoints (and terminate any process). There is deliberately no default: a
/// no-op `on_close` would leave the client's tasks and fds alive.
pub fn NdjsonTransport::new(
  reader : &@io.Reader,
  writer : &@io.Writer,
  on_close~ : () -> Unit,
) -> NdjsonTransport {
  { reader, writer, on_close }
}

///|
pub impl @jsonrpc.Transport for NdjsonTransport with fn send(self, message) {
  // One line per message; JSON stringify never emits a newline, so the frame is
  // unambiguous.
  self.writer.write("\{message.stringify()}\n")
}

///|
pub impl @jsonrpc.Transport for NdjsonTransport with fn recv(self) {
  // Read whole lines until one parses as JSON or the stream ends. A valid-UTF-8
  // line that is not JSON (e.g. a stray log line the server leaked to stdout) is
  // skipped; end of stream, a read error, or invalid UTF-8 (a server violating
  // the "stdout carries only UTF-8 MCP messages" contract) returns `None`, which
  // closes the connection.
  for ;; {
    let line = self.reader.read_until("\n") catch {
      error if @async.is_being_cancelled() => raise error
      _ => None
    }
    guard line is Some(line) else { return None }
    let trimmed = line.trim(chars="\r\n").to_owned()
    if trimmed == "" {
      continue
    }
    if (Some(@json.parse(trimmed)) catch { _ => None }) is Some(message) {
      return Some(message)
    }
  }
}

///|
pub impl @jsonrpc.Transport for NdjsonTransport with fn close(self) {
  (self.on_close)()
}
