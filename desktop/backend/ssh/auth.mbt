///|
priv struct AuthWaiter {
  request : @protocol.SshAuthRequest
  answer : @async.Queue[@protocol.SshAuthAnswer]
}

///|
/// A bounded line is the complete IPC frame, never the SSH protocol stream.
async fn auth_frame(socket : @socket.Tcp) -> Json {
  let bytes = Buffer()
  for ;; {
    guard bytes.length() < 65536 else {
      raise SshError("SSH authentication frame too large")
    }
    let byte = socket.read_exactly(1)
    if byte == b"\n" {
      break
    }
    bytes.write_bytes(byte)
  }
  @json.parse(@utf8.decode(bytes.to_bytes()))
}

///|
fn auth_request(
  prompt : String,
  hint : String,
  id : Int32,
  rejected : Bool,
) -> @protocol.SshAuthRequest {
  let (kind, target) : (@protocol.SshAuthKind, String?) = if hint == "confirm" ||
    prompt.contains("Are you sure you want to continue connecting") {
    (Confirm, None)
  } else if prompt.has_prefix("Enter passphrase for key '") &&
    prompt.has_suffix("': ") {
    (Passphrase, Some(prompt[26:prompt.length() - 3].to_owned()))
  } else if prompt.has_suffix("'s password: ") {
    (Password, Some(prompt[:prompt.length() - 13].to_owned()))
  } else {
    (Challenge, None)
  }
  { request_id: id, kind, prompt, target, retry: rejected && kind == Password, }
}

///|
async fn Connection::serve_auth(
  self : Connection,
  server : @socket.TcpServer,
  token : String,
  emit : (Json) -> Unit,
) -> Unit {
  let mut request_id = 0
  for ;; {
    let (socket, _) = server.accept()
    defer socket.close()
    let frame = @async.with_timeout(5000, () => auth_frame(socket)) catch {
      _ => continue
    }
    guard frame
      is {
        "token": String(actual),
        "prompt": String(prompt),
        "hint": String(hint),
        ..
      } &&
      actual == token &&
      !self.closed else {
      continue
    }
    request_id += 1
    let request = auth_request(prompt, hint, request_id, self.rejected)
    self.rejected = false
    let waiter : AuthWaiter = { request, answer: Queue(kind=Blocking(1)), }
    self.waiter = Some(waiter)
    emit({ "authentication": request.to_json() })
    let answer = waiter.answer.get()
    socket.write(answer.to_json().stringify() + "\n")
    if answer is Cancel {
      return
    }
    emit({ "authentication_submitted": request_id })
  }
}

///|
extern "C" fn askpass_exit(code : Int32) = "exit"
