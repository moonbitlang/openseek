///|
/// Count requests until their replies are written, including output backpressure.
const StdioMaxInFlight : Int32 = 16

///|
/// Serve newline-delimited UTF-8 JSON-RPC on streams owned by the host.
/// The host authenticates the peer and binds its conversation before calling
/// this method. Tool arguments cannot change that identity or the tool groups.
///
/// Each reply is one line. Notifications produce no reply; malformed JSON
/// produces a parse error and the next line can still be read. Calls may run
/// concurrently, up to 16 per connection, with serialized replies. EOF drains
/// accepted calls. I/O failures and cancellation end the adapter and propagate
/// to its owner.
/// The caller closes the streams; process stdin/stdout are never claimed.
pub async fn Dispatcher::serve_stdio(
  self : Dispatcher,
  input : &@io.BinaryReader,
  output : &@io.BinaryWriter,
  session~ : String,
  groups~ : Array[String] = [],
) -> Unit {
  let writing = @async.Mutex()
  let pending = @async.Semaphore(StdioMaxInFlight)
  @async.with_task_group(group => {
    for ;; {
      guard read_stdio_line(input) is Some(line) else { break }
      let incoming = try @json.parse(@utf8.decode(line)) catch {
        _ => Answer(failure(null, -32700, "Parse error"))
      } noraise {
        message => classify_message(message)
      }
      match incoming {
        Ignore => ()
        Answer(answer) => write_stdio_reply(output, writing, answer)
        Request(request) => {
          // Acquire before spawning so waiting requests do not become tasks.
          pending.acquire()
          group.spawn_bg(() => {
            defer pending.release()
            let answer = self.execute_request(request, session~, groups~)
            write_stdio_reply(output, writing, answer)
          })
        }
      }
    }
  })
}

///|
async fn write_stdio_reply(
  output : &@io.BinaryWriter,
  writing : @async.Mutex,
  answer : Json,
) -> Unit {
  writing.acquire()
  defer writing.release()
  output.write(@utf8.encode(answer.stringify() + "\n"))
}

///|
/// Keep the HTTP request-size limit without buffering an unbounded line.
async fn read_stdio_line(input : &@io.BinaryReader) -> Bytes? {
  let line = @buffer.Buffer()
  for ;; {
    guard input.peek() is Some(chunk) else {
      return if line.length() == 0 { None } else { Some(line.contents()) }
    }
    let length = chunk.find(b"\n").unwrap_or(chunk.length())
    guard line.length() + length <= MaxRequestBytes else {
      raise ServerError("MCP message exceeds \{MaxRequestBytes} bytes")
    }
    line.write_bytes(chunk[:length])
    let complete = length < chunk.length()
    input.drop_exactly(length + (if complete { 1 } else { 0 }))
    if complete {
      return Some(line.contents())
    }
  }
}
