// The MCP Streamable HTTP transport: every outgoing JSON-RPC message is an HTTP
// POST to the server's single MCP endpoint; inbound messages arrive in the POST
// responses — either one `application/json` body or a `text/event-stream` whose
// events each carry a JSON-RPC message — and are queued for the reader.
//
// Each POST runs on its own spawned task, so `send` returns as soon as the POST
// is dispatched. That keeps the jsonrpc writer free: concurrent requests POST
// concurrently, a reply to a server-initiated request (e.g. a `ping` arriving
// mid-stream) can be sent while its stream is still open, and a stalled stream
// wedges only its own request — which is failed fast by a synthesized JSON-RPC
// error reply whenever its POST errors, so callers never wait out an outer
// timeout on a dead exchange.
//
// Scope: the POST flow of the Streamable HTTP spec, including session ids
// (`Mcp-Session-Id`) and the negotiated `MCP-Protocol-Version` header. The
// optional standing GET stream (server-initiated messages between requests) and
// SSE resumability are not implemented: openseek only issues requests and reads
// their (possibly streamed) replies. A server that expires the session answers
// 404; that fails the in-flight call with a clear error (reinitialization is
// not attempted — reconnect by restarting the engine).

///|
/// Cap on concurrently running POST exchanges. A legitimate agent workload
/// stays in single digits; the cap exists so a server flooding peer requests
/// (each answered by a POST) or stalling response streams cannot grow tasks and
/// connections without bound. At the cap, a client request fails fast with a
/// synthesized error and a server-bound reply/notification is dropped.
const MaxInFlightExchanges : Int = 32

///|
/// Deadline for one whole POST exchange, with margin over the bridge's 120s
/// per-call timeout: when a caller has long since timed out, the exchange must
/// not keep holding a socket and a cap slot on an endpoint that never closes
/// its response.
const ExchangeTimeoutMs : Int = 150000

///|
/// Deadline for the best-effort session DELETE sent at close.
const SessionDeleteTimeoutMs : Int = 5000

///|
/// A `@jsonrpc.Transport` speaking MCP Streamable HTTP against `url`.
struct HttpTransport {
  url : String
  // User-supplied headers (e.g. Authorization), sent on every request.
  extra_headers : Map[String, String]
  // Runs one POST's request/response exchange as a cancellable task on the
  // owning task group.
  spawn : (async () -> Unit) -> @async.Task[Unit]
  // In-flight POST tasks by ticket, so `close` can cancel a connecting or
  // streaming exchange instead of leaving its socket alive on the agent scope.
  // Each task removes itself on exit, keeping the map bounded.
  pending_posts : Map[Int, @async.Task[Unit]]
  mut next_post : Int
  // Messages parsed out of POST responses, awaiting the reader.
  inbound : @async.Queue[Json]
  // Fed exactly once, when the `notifications/initialized` POST completes.
  // MCP's lifecycle requires that notification to reach the server before any
  // normal request, but detached POSTs use separate connections and order only
  // task creation — so later POSTs first await this gate.
  mut initialized_gate : @async.Queue[Unit]?
  // The server's session id, captured from the `initialize` response and echoed
  // on every later request.
  mut session_id : String?
  // The id of the in-flight `initialize` request, so its reply (which fixes the
  // negotiated protocol version) can be recognized.
  mut initialize_id : Json?
  // The negotiated protocol version, sent as `MCP-Protocol-Version` on every
  // request after initialization.
  mut protocol_version : String?
  mut closed : Bool
}

///|
/// Build a Streamable HTTP transport for the MCP endpoint at `url`. `spawn`
/// runs one POST exchange as a cancellable task on the connection's group
/// (`connect` wires it); `extra_headers` (e.g. `Authorization`) are added to
/// every request.
pub fn HttpTransport::new(
  url : String,
  spawn~ : (async () -> Unit) -> @async.Task[Unit],
  extra_headers? : Map[String, String] = Map([]),
) -> HttpTransport {
  {
    url,
    extra_headers,
    spawn,
    pending_posts: Map([]),
    next_post: 0,
    inbound: Queue(kind=Unbounded),
    initialized_gate: None,
    session_id: None,
    initialize_id: None,
    protocol_version: None,
    closed: false,
  }
}

///|
/// The headers for one POST: the MCP-required set, the session/version state,
/// and the user's extras. `Accept-Encoding: identity` keeps an intermediary from
/// re-buffering the event stream (same pitfall the DeepSeek client pins).
fn HttpTransport::request_headers(self : HttpTransport) -> Map[String, String] {
  let headers = {
    "Content-Type": "application/json",
    "Accept": "application/json, text/event-stream",
    "Accept-Encoding": "identity",
  }
  if self.session_id is Some(session_id) {
    headers["Mcp-Session-Id"] = session_id
  }
  if self.protocol_version is Some(version) {
    headers["MCP-Protocol-Version"] = version
  }
  for key, value in self.extra_headers {
    if !reserved_header(key) {
      headers[key] = value
    }
  }
  headers
}

///|
/// Whether `name` is a transport-owned header a configured extra must not
/// replace: the protocol-managed set plus the message-framing headers the HTTP
/// layer computes. Case-insensitive (differently cased user keys would
/// otherwise emit conflicting duplicates on the wire).
fn reserved_header(name : String) -> Bool {
  match name.to_lower() {
    "content-type"
    | "accept"
    | "accept-encoding"
    | "mcp-session-id"
    | "mcp-protocol-version"
    | "content-length"
    | "transfer-encoding"
    | "host" => true
    _ => false
  }
}

///|
/// Feed a lifecycle gate, if any: synchronous (a defer cannot await) and total
/// on the unbounded queue unless the transport already closed it.
fn feed_gate(completion : @async.Queue[Unit]?) -> Unit {
  if completion is Some(completion) {
    (completion.try_put(()) catch { _ => false }) |> ignore
  }
}

///|
/// Case-insensitive response-header lookup (header names are case-insensitive
/// on the wire and servers vary).
fn header_value(headers : Map[String, String], name : String) -> String? {
  let wanted = name.to_lower()
  for key, value in headers {
    if key.to_lower() == wanted {
      return Some(value)
    }
  }
  None
}

///|
pub impl @jsonrpc.Transport for HttpTransport with fn send(self, message) {
  guard !self.closed else { fail("transport closed") }
  // The id this POST must answer (None for a notification or a reply): if the
  // exchange fails before delivering that reply, a synthesized error fails the
  // pending request fast instead of leaving it to an outer timeout.
  let request_id : Json? = match message {
    { "method": _, "id": id, .. } => Some(id)
    _ => None
  }
  // Bounded concurrency, checked before any lifecycle bookkeeping: at the cap,
  // fail a client request fast and drop a flood-driven reply/notification
  // rather than growing tasks and connections without bound.
  if self.pending_posts.length() >= MaxInFlightExchanges {
    if request_id is Some(id) {
      self.deliver({
        "jsonrpc": "2.0",
        "id": id,
        "error": {
          "code": -32000,
          "message": "too many in-flight MCP exchanges (server flooding or stalling)",
        },
      })
    }
    return
  }
  // Remember the initialize request's id so its reply can fix the negotiated
  // protocol version for later headers.
  if message is { "method": String("initialize"), "id": id, .. } {
    self.initialize_id = Some(id)
  }
  // The lifecycle notification opens the ordering gate; every later POST must
  // wait behind it (see `initialized_gate`). Which gate (if any) this POST
  // awaits is decided HERE, at dispatch order, not when the task first runs.
  let gate = self.initialized_gate
  let opens_gate = message
    is { "method": String("notifications/initialized"), .. }
  let completion : @async.Queue[Unit]? = if opens_gate {
    let completion : @async.Queue[Unit] = Queue(kind=Unbounded)
    self.initialized_gate = Some(completion)
    Some(completion)
  } else {
    None
  }
  let ticket = self.next_post
  self.next_post = self.next_post + 1
  // Whether the exchange task already ran to completion: TaskGroup::spawn's
  // start timing is undefined, so registration below must not resurrect a
  // ticket whose task finished before `spawn` returned.
  let done : Ref[Bool] = { val: false }
  let task = (self.spawn)(() => {
    // All defers sit at the task-body scope (a defer inside an `if` block
    // would fire at that block's end — i.e. immediately), so they run when the
    // task exits: feeding the gate however this exchange ends means a failed
    // lifecycle notification cannot wedge every later request.
    defer {
      done.val = true
    }
    defer self.pending_posts.remove(ticket)
    defer feed_gate(completion)
    if gate is Some(gate) {
      gate.get() catch {
        error if @async.is_being_cancelled() => raise error
        // Gate closed with the transport: proceed to fail normally below.
        _ => ()
      }
      (gate.try_put(()) catch { _ => false }) |> ignore
    }
    self.run_post(message, request_id)
  })
  // Register only if the task has not already finished (spawn's start timing is
  // undefined): inserting a completed task would strand its ticket and consume
  // the exchange cap forever.
  if !done.val {
    self.pending_posts[ticket] = task
  }
}

///|
pub impl @jsonrpc.Transport for HttpTransport with fn recv(self) {
  Some(self.inbound.get()) catch {
    error if @async.is_being_cancelled() => raise error
    _ => None
  }
}

///|
pub impl @jsonrpc.Transport for HttpTransport with fn close(self) {
  let already_closed = self.closed
  self.closed = true
  self.inbound.close()
  // Cancel a connecting or streaming exchange rather than leaving its socket
  // alive on the agent scope. Idempotent: completed tasks removed themselves,
  // and cancelling twice is a no-op.
  for _, task in self.pending_posts {
    task.cancel()
  }
  self.pending_posts.clear()
  // Release the server-assigned session (spec: DELETE with the session header;
  // 405 means the server declines). Best-effort and bounded, on a detached
  // task — close() itself must never suspend. When close comes from the owning
  // group's own termination, the spawned task is cancelled before it can do
  // I/O; the session then ends by server-side expiry, which the spec requires
  // servers to handle anyway (clients can vanish at any time).
  if !already_closed && self.session_id is Some(session_id) {
    let url = self.url
    let headers = { "Mcp-Session-Id": session_id }
    // A strict server enforces the negotiated version on every
    // post-initialization request, the DELETE included.
    if self.protocol_version is Some(version) {
      headers["MCP-Protocol-Version"] = version
    }
    for key, value in self.extra_headers {
      if !reserved_header(key) {
        headers[key] = value
      }
    }
    (self.spawn)(() => {
      @async.with_timeout_opt(SessionDeleteTimeoutMs, () => {
        delete_session(url, headers)
      })
      |> ignore
    })
    |> ignore
  }
}

///|
/// Best-effort `DELETE <endpoint>` with the session (and negotiated-version)
/// headers; every failure — including 405 from a server that declines
/// client-initiated termination — is swallowed.
async fn delete_session(url : String, headers : Map[String, String]) -> Unit {
  // Split the MCP URL into origin (scheme + host[:port]) and path.
  guard url.find("://") is Some(scheme_end) else { return }
  let host_start = scheme_end + 3
  let (origin, path) = match url[host_start:].find("/") {
    Some(slash) => {
      let cut = host_start + slash
      (url[:cut].to_owned(), url[cut:].to_owned())
    }
    None => (url, "/")
  }
  let client = @http.Client::Client(origin) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return
  }
  defer client.close()
  client.request(Delete, path, extra_headers=headers) catch {
    error if @async.is_being_cancelled() => raise error
    _ => return
  }
  let _ = client.end_request() catch {
    error if @async.is_being_cancelled() => raise error
    _ => return
  }
  client.skip_response_body() catch {
    error if @async.is_being_cancelled() => raise error
    _ => ()
  }
}

///|
/// One POST exchange: send `message`, parse the response (single JSON body or
/// SSE stream), and deliver each inbound message. Any failure before
/// `request_id`'s reply has been delivered fails that request via a synthesized
/// JSON-RPC error reply. Runs on its own task; cancellation propagates.
async fn HttpTransport::run_post(
  self : HttpTransport,
  message : Json,
  request_id : Json?,
) -> Unit {
  let mut answered = false
  let deliver = (inbound : Json) => {
    // Only a reply (result/error) counts as the answer — a server-initiated
    // request whose id happens to collide (both sides number from 1) must not
    // suppress the fail-fast synthesized error.
    if request_id is Some(expected) &&
      inbound is ({ "id": id, "result": _, .. } | { "id": id, "error": _, .. }) &&
      id == expected {
      answered = true
    }
    self.deliver(inbound)
  }
  let bounded = @async.with_timeout_opt(ExchangeTimeoutMs, () => {
    self.exchange(message, deliver, answered=() => answered)
  }) catch {
    error if @async.is_being_cancelled() => raise error
    error => {
      // Fail the pending request fast (the exchange is dead); a notification
      // has nothing to answer.
      if request_id is Some(id) && !answered {
        answered = true
        self.deliver({
          "jsonrpc": "2.0",
          "id": id,
          "error": {
            "code": -32000,
            "message": "MCP endpoint exchange failed: \{error}",
          },
        })
      }
      return
    }
  }
  // Deadline expiry: the endpoint held the exchange open past any useful
  // lifetime; fail the request and release this slot.
  if bounded is None && request_id is Some(id) && !answered {
    answered = true
    self.deliver({
      "jsonrpc": "2.0",
      "id": id,
      "error": {
        "code": -32000,
        "message": "MCP endpoint exchange exceeded \{ExchangeTimeoutMs / 1000}s",
      },
    })
  }
  // The response ended without answering the request (e.g. an SSE stream closed
  // early): fail it rather than leaving the caller to an outer timeout.
  if request_id is Some(id) && !answered {
    self.deliver({
      "jsonrpc": "2.0",
      "id": id,
      "error": {
        "code": -32000,
        "message": "MCP endpoint response ended without answering the request",
      },
    })
  }
}

///|
/// POST `message` and deliver every inbound message in the response. Raises on
/// an HTTP error status or a transport failure.
async fn HttpTransport::exchange(
  self : HttpTransport,
  message : Json,
  deliver : (Json) -> Unit,
  answered~ : () -> Bool,
) -> Unit {
  let client = @http.post_stream(self.url, headers=self.request_headers())
  defer client.close()
  client.write(message.stringify())
  let response = client.end_request()
  // The spec assigns the session id on the initialize response only; capturing
  // it elsewhere would let a later (or misbehaving) response rebind the session.
  if message is { "method": String("initialize"), .. } &&
    header_value(response.headers, "Mcp-Session-Id") is Some(session_id) {
    self.session_id = Some(session_id)
  }
  // < 300: @http follows no redirects, so a 3xx answer is also a dead exchange —
  // name its status rather than reporting a generic unanswered response.
  guard response.code < 300 else {
    // 404 with a session marks an expired session per the spec; name it.
    if response.code == 404 && self.session_id is Some(_) {
      fail("MCP session expired (HTTP 404); reconnect to reinitialize")
    }
    fail("MCP endpoint answered HTTP \{response.code}")
  }
  // Media types are case-insensitive on the wire.
  let content_type = header_value(response.headers, "Content-Type")
    .unwrap_or("")
    .to_lower()
  if content_type.contains("text/event-stream") {
    self.read_sse_stream(client, deliver, answered~)
  } else if content_type.contains("application/json") {
    let text = client.read_all().text()
    deliver(@json.parse(text))
  } else {
    // 202 Accepted (a notification/response was consumed) or an empty body.
    client.skip_response_body()
  }
}

///|
/// Read one SSE response stream to its end, delivering each event's JSON-RPC
/// message. Multi-line `data:` fields are joined with newlines per the SSE spec;
/// `event:`/`id:`/comment lines are ignored. Raises on a read failure (which
/// fails the owning request) rather than masking it as a clean end of stream.
async fn HttpTransport::read_sse_stream(
  self : HttpTransport,
  client : @http.Client,
  deliver : (Json) -> Unit,
  answered~ : () -> Bool,
) -> Unit {
  ignore(self)
  let data = StringBuilder()
  let mut has_data = false
  let lines = SseLineReader::new(client)
  for ;; {
    guard lines.next_line() is Some(line) else { break }
    if line == "" {
      // Event boundary: dispatch the accumulated data, if any.
      if has_data {
        let text = data.to_string()
        data.reset()
        has_data = false
        if (Some(@json.parse(text)) catch { _ => None }) is Some(message) {
          deliver(message)
          // The spec has the server close the stream after the reply; a server
          // that keeps it open instead would pin this exchange's cap slot, so
          // once our request is answered we close from this side (allowed at
          // any time) rather than read to EOF.
          if answered() {
            break
          }
        }
      }
      continue
    }
    if line.has_prefix("data:") {
      let payload = line[5:].trim(chars=" ").to_owned()
      if has_data {
        data.write_string("\n")
      }
      data.write_string(payload)
      has_data = true
    }
    // event:/id:/retry:/comments are irrelevant to the message layer.
  }
  // A final event unterminated by a blank line still counts.
  if has_data &&
    (Some(@json.parse(data.to_string())) catch { _ => None }) is Some(message) {
    deliver(message)
  }
}

///|
/// Incremental SSE line reader over `read_some`, recognizing all three
/// terminators the SSE grammar allows — LF, CRLF, and lone CR — without
/// waiting for an LF (a `read_until("\n")` on a held-open CR-only stream
/// would stall until EOF). The buffer grows with unterminated input, matching
/// `read_until`; the exchange deadline bounds a hostile stream.
priv struct SseLineReader {
  client : @http.Client
  buf : Array[Byte]
  mut start : Int
  // Bytes in [start, scan) are known terminator-free, so a line spanning many
  // network chunks is scanned once, not re-scanned per chunk.
  mut scan : Int
  mut eof : Bool
}

///|
/// Compaction threshold: once this many consumed bytes accumulate, shift the
/// live tail down so a long-lived stream retains only the current line.
const SseCompactAt : Int = 4096

///|
fn SseLineReader::new(client : @http.Client) -> SseLineReader {
  { client, buf: [], start: 0, scan: 0, eof: false }
}

///|
/// The next logical line (terminator excluded), the final unterminated line at
/// end of stream, then `None`. Raises on a read failure or invalid UTF-8 (which
/// fails the owning request) rather than masking either as a clean end.
async fn SseLineReader::next_line(self : SseLineReader) -> String? {
  // Drop consumed bytes so memory tracks the current line, not the stream.
  if self.start >= SseCompactAt {
    let remaining = self.buf.length() - self.start
    for j in 0..<remaining {
      self.buf[j] = self.buf[self.start + j]
    }
    self.buf.truncate(remaining)
    self.scan = self.scan - self.start
    self.start = 0
  }
  for ;; {
    let mut i = if self.scan > self.start { self.scan } else { self.start }
    while i < self.buf.length() {
      let byte = self.buf[i]
      if byte == b'\n' {
        return Some(self.take(i, i + 1))
      }
      if byte == b'\r' {
        if i + 1 < self.buf.length() {
          // Coalesce CRLF into one terminator.
          let after = if self.buf[i + 1] == b'\n' { i + 2 } else { i + 1 }
          return Some(self.take(i, after))
        }
        if self.eof {
          return Some(self.take(i, i + 1))
        }
        // A CR at the buffer's edge may be half of a CRLF: read on before
        // deciding, then resume from this position.
        break
      }
      i = i + 1
    }
    self.scan = i
    if self.eof {
      if self.start < self.buf.length() {
        return Some(self.take(self.buf.length(), self.buf.length()))
      }
      return None
    }
    match self.client.read_some() {
      None => self.eof = true
      Some(chunk) =>
        for byte in chunk {
          self.buf.push(byte)
        }
    }
  }
}

///|
/// Decode `[start, until)` as the line, consume through `consumed`, and return
/// it. Terminator bytes are ASCII, so the cut never splits a UTF-8 sequence;
/// decoding is strict (malformed UTF-8 raises, failing the exchange).
fn SseLineReader::take(
  self : SseLineReader,
  until : Int,
  consumed : Int,
) -> String raise {
  let bytes = Bytes::makei(until - self.start, i => self.buf[self.start + i])
  self.start = consumed
  self.scan = consumed
  @utf8.decode(bytes)
}

///|
/// Queue one inbound message for the reader, noting the initialize reply's
/// negotiated protocol version on the way past.
fn HttpTransport::deliver(self : HttpTransport, message : Json) -> Unit {
  if self.initialize_id is Some(expected) &&
    message is { "id": id, "result": result, .. } &&
    id == expected {
    self.initialize_id = None
    if result is { "protocolVersion": String(version), .. } {
      self.protocol_version = Some(version)
    }
  }
  (self.inbound.try_put(message) catch { _ => false }) |> ignore
}
