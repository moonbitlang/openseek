///|
/// One CDP session. Calls and event reads are serialized by its owner;
/// overlapping reads are rejected instead of competing for WebSocket frames.
struct Connection {
  socket : @websocket.Conn
  mut serial : Int
  events : Array[Event]
  mut reading : Bool
}

///|
async fn connect(url : String) -> Connection {
  { socket: @websocket.connect(url), serial: 0, events: [], reading: false, }
}

///|
pub fn Connection::close(self : Connection) -> Unit {
  self.socket.close()
}

///|
async fn Connection::read(self : Connection) -> Incoming {
  let message = self.socket.recv()
  let buffer = @buffer.Buffer()
  while message.read_some(max_len=65536) is Some(chunk) {
    buffer.write_bytes(chunk)
    guard buffer.length() <= 2 * 1024 * 1024 else {
      raise Protocol("CDP response is too large")
    }
  }
  decode_incoming(@json.parse(@utf8.decode(buffer.to_bytes())))
}

///|
async fn Connection::request(
  self : Connection,
  method_ : String,
  params : Json,
) -> Json {
  guard !self.reading else { raise ConcurrentRead }
  self.reading = true
  let mut completed = false
  defer {
    self.reading = false
    // A cancelled read/write may have consumed only part of a WebSocket frame.
    if !completed {
      self.close()
    }
  }
  let reply = @async.with_timeout(5000, () => {
    self.serial += 1
    let id = self.serial
    let message : Json = {
      "id": id.to_json(),
      "method": method_.to_json(),
      "params": params,
    }
    self.socket.send_text(message.stringify())
    for ;; {
      match self.read() {
        Reply(reply_id, result) if reply_id == id => return result
        Notification(Some(event)) => {
          guard self.events.length() < 16 else {
            raise Protocol("Too many pending CDP events")
          }
          self.events.push(event)
        }
        _ => ()
      }
    }
  })
  completed = true
  match reply {
    Ok(json) => json
    Err(error) => raise error
  }
}

///|
pub async fn Connection::next_event(self : Connection) -> Event {
  guard !self.reading else { raise ConcurrentRead }
  self.reading = true
  let mut completed = false
  defer {
    self.reading = false
    if !completed {
      self.close()
    }
  }
  if !self.events.is_empty() {
    completed = true
    return self.events.remove(0)
  }
  for ;; {
    match self.read() {
      Notification(Some(event)) => {
        completed = true
        return event
      }
      _ => ()
    }
  }
}
