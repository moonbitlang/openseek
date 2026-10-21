///|
struct TcpTransport {
  socket : @websocket.Conn
  teardown : () -> Unit
}

///|
pub impl @jsonrpc.Transport for TcpTransport with fn send(self, message) {
  self.socket.send_text(message.stringify())
}

///|
pub impl @jsonrpc.Transport for TcpTransport with fn recv(self) {
  let message = self.socket.recv()
  guard message.kind is Text else {
    raise SshError("Expected a JSON WebSocket frame")
  }
  let body = Buffer()
  while message.read_some(max_len=65536) is Some(bytes) {
    guard body.length() + bytes.length() <= 32 * 1024 * 1024 else {
      raise SshError("SSH RPC frame exceeds 32 MiB")
    }
    body.write_bytes(bytes)
  }
  Some(@json.parse(@utf8.decode(body.to_bytes())))
}

///|
pub impl @jsonrpc.Transport for TcpTransport with fn close(self) {
  self.socket.close()
  (self.teardown)()
}

///|
pub extend TcpTransport with @jsonrpc.Transport::{send, recv, close}
