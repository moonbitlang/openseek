// A `@jsonrpc.Transport` over a byte-stream reader/writer using the LSP base
// protocol's Content-Length framing — e.g. a language server's stdio.

///|
/// Carries `@jsonrpc` messages over a reader/writer pair, framing each with a
/// `Content-Length` header. Build it with `StreamTransport::new` and hand it to
/// `@jsonrpc.Client::new`.
struct StreamTransport {
  reader : &@io.Reader
  writer : &@io.Writer
  // Serializes writes so concurrent `send`s (the client answers a peer request
  // on the read turn while application requests are sending) never interleave
  // their frames on the wire.
  write_lock : @semaphore.Semaphore
  // Names this server (its module root) in the shared `lsp` traffic log, so the
  // messages of several moon-lsp servers can be told apart.
  label : String
}

///|
/// Build a transport over `reader`/`writer`. Closing either end makes `recv`
/// report end of stream, which the client turns into `Closed`. `label`
/// identifies this server in the `lsp`-category traffic log.
pub fn[R : @io.Reader, W : @io.Writer] StreamTransport::new(
  reader : R,
  writer : W,
  label? : String = "",
) -> StreamTransport {
  {
    reader: reader as &@io.Reader,
    writer: writer as &@io.Writer,
    write_lock: Semaphore(1, initial_value=1),
    label,
  }
}

///|
pub impl @jsonrpc.Transport for StreamTransport with fn send(self, message) {
  self.write_lock.acquire()
  defer self.write_lock.release()
  // Mirror the wire to `lsp.log` so a broken hover/symbol round-trip can be read
  // back after the fact.
  log_traffic("lsp_send", self.label, message)
  self.writer.write(frame_message(message.stringify()))
}

///|
pub impl @jsonrpc.Transport for StreamTransport with fn recv(self) {
  // Skip any frame that does not parse as JSON and keep reading, so one bad
  // message does not tear down the connection; `None` only at end of stream.
  for ;; {
    guard read_frame(self.reader) is Some(text) else { return None }
    if (Some(@json.parse(text)) catch { _ => None }) is Some(message) {
      log_traffic("lsp_recv", self.label, message)
      return Some(message)
    }
  }
}
