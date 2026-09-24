///|
/// Bounds, per session, per script, and per request. The README and the
/// model-facing description quote these values; keep them in step.
const MaxPrograms : Int = 64

///|
const MaxConnections : Int = 16

///|
const MaxCallsPerProgram : Int = 1024

///|
const MaxActiveCallsPerProgram : Int = 4

///|
/// Admission (request framing) and reply sends are bounded separately from the
/// executor deadline, which `Service::start` takes as a parameter.
const AdmissionTimeoutMs : Int = 5000

///|
const SendTimeoutMs : Int = 5000

///|
/// A serialized reply above this is replaced by an explicit "executed but
/// oversized" error; the request body cap lives in `request.mbt`.
const MaxReplyChars : Int = 65536

///|
/// Retained trace budget, below the durable job reader's 1 MiB cap.
const MaxTraceBytes : Int = 524288

///|
/// Per-entry headroom reserved for a terminal status and an omitted-result
/// marker, so a rejected reservation never happens after execution.
const TraceEntryReserveBytes : Int = 1024

///|
/// One session-owned listener. Every program has an independent capability.
struct Service {
  server : @socket.TcpServer
  tools : @agent_tool.Tools
  programs : Map[String, Program]
  serial : @async.Mutex
  spawn : (async () -> Json) -> @async.Task[Json]
  mut stop : (async () -> Unit)?
  mut closed : Bool
  call_timeout_ms : Int
  trace_timeout_ms : Int
}

///|
/// A script's capability and trace, retained by its job after background handoff.
struct Program {
  // The owning listener: its tools, its stateful-call mutex, its deadlines,
  // and the registry this program's token lives in.
  service : Service
  token : String
  calls : Array[Json]
  reservations : Array[Int]
  mut trace_bytes : Int
  active : Map[Int, @async.Task[Json]]
  mut closed : Bool
  mut on_trace : async (Json) -> Unit
  // Publications run one at a time and snapshot the trace only once they hold
  // this, so a slow observer can never deliver a stale snapshot after a later
  // one; `close` takes it last and its final publish is therefore final.
  publishing : @async.Mutex
  mut job_id : String?
  mut trace_error : String?
}

///|
/// One retained trace entry. `result` is present only once the call is done.
fn call_entry(
  name : String,
  arguments : Json,
  status : String,
  result? : Json,
) -> Json {
  let fields : Map[String, Json] = {
    "name": name.to_json(),
    "arguments": arguments,
    "status": status.to_json(),
  }
  if result is Some(result) {
    fields["result"] = result
  }
  Json::object(fields)
}

///|
/// Start a listener on the existing session task group. No agent-loop dispatch
/// or file lock is held while the listener waits for requests.
pub async fn[X] Service::start(
  group : @async.TaskGroup[X],
  tools : @agent_tool.Tools,
  call_timeout_ms? : Int = 120000,
  trace_timeout_ms? : Int = 5000,
) -> Service {
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  let service : Service = {
    server,
    tools: tools.program_tools(),
    programs: Map([]),
    serial: Mutex(),
    spawn: operation => group.spawn(operation, no_wait=true, allow_failure=true),
    stop: None,
    closed: false,
    call_timeout_ms,
    trace_timeout_ms,
  }
  let worker = group.spawn(no_wait=true, () => {
    server.run_forever(max_connections=MaxConnections, allow_failure=true, (
      socket,
      _,
    ) => {
      let conn = @http.ServerConnection::new(socket)
      defer conn.close()
      let reader : RequestReader = {
        socket,
        buffer: b"",
        offset: 0,
        wire_bytes: 0,
      }
      // Bound the entire admission phase, starting at acceptance, including
      // partial headers. No executor is reserved until authentication and body
      // framing have both succeeded.
      let admitted = @async.with_timeout(AdmissionTimeoutMs, () => {
        let headers = reader.head()
        let program = match headers.get("authorization") {
          Some(header) if header is [.. "Bearer ", .. token] =>
            service.programs.get(token.to_owned())
          _ => None
        }
        guard !headers.contains("origin") && program is Some(program) else {
          return None
        }
        Some((program, reader.body(headers)))
      }) catch {
        _ => {
          send(
            conn,
            error_result(
              "Invalid PTC request: expected bounded HTTP and UTF-8 JSON within 5 seconds; no tool executed",
            ),
          )
          return
        }
      }
      guard admitted is Some((program, input)) else {
        @async.with_timeout(SendTimeoutMs, () => {
          conn.send_response(403, "Forbidden")
          conn.end_response()
        })
        return
      }
      // Recheck after the body read: close may have revoked this capability
      // while the request was suspended. Registration and reservation never yield.
      guard !program.closed else {
        send(conn, error_result("PTC program has ended; no tool executed"))
        return
      }
      guard input
        is { "version": 1, "name": String(name), "arguments": arguments, .. } else {
        send(conn, error_result("PTC requires version=1, name, and arguments"))
        return
      }
      guard program.calls.length() < MaxCallsPerProgram &&
        program.active.length() < MaxActiveCallsPerProgram else {
        send(
          conn,
          error_result(
            "PTC program exhausted its 1024-call or four-active-call budget",
          ),
        )
        return
      }
      let index = program.calls.length()
      let entry = call_entry(name, arguments, "running")
      let reservation = @utf8.encode(entry.stringify()).length() +
        TraceEntryReserveBytes
      guard program.trace_bytes + reservation <= MaxTraceBytes else {
        send(conn, error_result("PTC trace budget exhausted; no tool executed"))
        return
      }
      program.calls.push(entry)
      program.reservations.push(reservation)
      program.trace_bytes += reservation
      let task = (service.spawn)(() => program.execute(index, name, arguments))
      program.active[index] = task
      defer program.active.remove(index)
      // Cancel the executor and join it: a handler that unwinds, by
      // cancellation or by its deadline, must not orphan it.
      let abandon = () => {
        program.cancel_call(index)
        @async.protect_from_cancel(() => ignore(task.wait()) catch { _ => () })
      }
      errdefer abandon()
      let result = @async.with_task_group(waiters => {
        waiters.spawn_bg(no_wait=true, () => {
          @async.sleep(service.call_timeout_ms)
          // Revoke at expiry, before the waiter unwinds and a granted
          // executor gets a chance to resume.
          program.cancel_call(index)
          fail("PTC call deadline exceeded")
        })
        task.wait()
      }) catch {
        error => {
          abandon()
          let response = error_result(
            "PTC call failed: \{@agent_tool.brief_line("\{error}", limit=128)}; changes may have occurred",
          )
          if !program.closed &&
            program.calls[index] is { "status": "interrupted", .. } {
            // The deadline has joined the call and returns an acknowledged
            // tool error. The script may handle it. This small result fits
            // the entry's reserved 1 KiB; never replace a completed mutation.
            program.calls[index] = call_entry(
              name,
              arguments,
              "done",
              result=response,
            )
            program.publish_trace()
          }
          response
        }
      }
      send(conn, result)
    })
  })
  service.stop = Some(() => {
    worker.cancel()
    @async.protect_from_cancel(() => worker.wait() catch { _ => () })
  })
  group.add_defer(() => @async.protect_from_cancel(() => service.close()))
  service
}

///|
/// Register a fresh capability without changing the script's source.
pub fn Service::register(
  self : Service,
  on_trace? : (Json) -> Unit = _ => (),
) -> Program raise {
  guard !self.closed else { fail("PTC service is closed") }
  guard self.programs.length() < MaxPrograms else {
    fail("PTC session has \{MaxPrograms} active programs")
  }
  guard @env.rand(32) is Some(entropy) else {
    fail("PTC: secure random capability unavailable")
  }
  let token = @crypto.bytes_to_hex_string(entropy)
  let program : Program = {
    service: self,
    token,
    calls: [],
    reservations: [],
    trace_bytes: 0,
    active: Map([]),
    closed: false,
    on_trace: data => on_trace(data),
    publishing: Mutex(),
    job_id: None,
    trace_error: None,
  }
  self.programs[token] = program
  program
}

///|
/// Revoke all capabilities and join their executors before closing the listener.
pub async fn Service::close(self : Service) -> Unit {
  self.closed = true
  @async.protect_from_cancel(() => {
    let programs = self.programs.values().to_array()
    for program in programs {
      program.stop()
    }
    self.programs.clear()
    for program in programs {
      program.close()
    }
    if self.stop is Some(stop) {
      self.stop = None
      stop()
    }
    self.server.close()
  })
}

///|
/// Guest environment for this script only: the SDK's discovery handoff.
pub fn Program::env(self : Program) -> Map[String, String] {
  {
    "OPENSEEK_PTC": (
      {
        "version": 1,
        "url": "http://127.0.0.1:\{self.service.server.addr.port()}/call",
        "token": self.token,
      } : Json).stringify(),
  }
}

///|
/// Immutable bounded trace, without credentials or transport details.
pub fn Program::trace(self : Program) -> Json {
  let fields : Map[String, Json] = { "ptc_calls": self.calls.to_json() }
  if self.job_id is Some(id) {
    fields["ptc_job_id"] = id.to_json()
  }
  if self.trace_error is Some(error) {
    fields["ptc_trace_error"] = error.to_json()
  }
  Json::object(fields)
}

///|
/// Replace the foreground observer when the execution becomes a job. After
/// handoff nothing may publish to the foreground slot: a program whose
/// process already ended during adoption keeps no observer at all, since a
/// closed registration must not acquire the job's either.
pub fn Program::handoff(
  self : Program,
  job_id : String,
  observer : async (Json) -> Unit,
) -> Unit {
  self.job_id = Some(job_id)
  self.on_trace = if self.closed { _ => () } else { observer }
}

///|
/// True once a background job owns this registration and its close.
pub fn Program::adopted(self : Program) -> Bool {
  self.job_id is Some(_)
}

///|
/// Publish the current trace to the current observer, if there is anything
/// to publish. A failure is retained as the trace error, never raised: the
/// caller (a host that just handed the program to a job) has no better place
/// to put it than the program's own final report.
pub async fn Program::republish(self : Program) -> Unit {
  if !self.calls.is_empty() {
    self.publish_trace()
  }
}

///|
/// True when execution ended with unfinished calls; changes may have occurred.
pub fn Program::interrupted(self : Program) -> Bool {
  self.calls.any(call => call is { "status": "interrupted", .. })
}

///|
/// Revoke before the first suspension, then cancel and join without holding a
/// file gate. Idempotent callers all wait for the same active calls to finish.
pub async fn Program::close(self : Program) -> Unit {
  self.stop()
  @async.protect_from_cancel(() => {
    let tasks = self.active.values().to_array()
    for task in tasks {
      ignore(task.wait()) catch {
        _ => ()
      }
    }
    self.active.clear()
    // Wait for any in-flight publication (a timed-out handler's, say) so the
    // final snapshot is delivered last, then release the job observer, which
    // captures the runtime. A publisher still queued behind this sees the
    // final trace and a no-op observer.
    self.publishing.acquire()
    defer self.publishing.release()
    if !self.calls.is_empty() {
      self.deliver_trace()
    }
    self.on_trace = _ => ()
  })
}

///|
/// Revoke admission and cancel active calls without suspending. Call this at
/// process exit or stop initiation; close later joins and persists final data.
pub fn Program::stop(self : Program) -> Unit {
  self.closed = true
  self.service.programs.remove(self.token)
  for index in 0..<self.calls.length() {
    self.cancel_call(index)
  }
}

///|
/// Record revocation even when a queued executor has not started yet.
fn Program::cancel_call(self : Program, index : Int) -> Unit {
  if self.calls[index]
    is { "name": String(name), "arguments": arguments, "status": "running", .. } {
    self.calls[index] = call_entry(name, arguments, "interrupted")
  }
  if self.active.get(index) is Some(task) {
    task.cancel()
  }
}

///|
/// Attach the final trace or handoff snapshot on every ordinary result path.
pub fn Program::result(
  self : Program,
  action : @agent_tool.ToolAction,
) -> @agent_tool.ToolAction {
  match action {
    Respond(output) => {
      let interrupted = self.interrupted()
      @agent_tool.respond(
        (if interrupted {
          "\{output.content}\nPTC stopped unfinished tool calls; changes may have occurred. Await every call before exiting."
        } else {
          output.content
        }) +
        (match self.trace_error {
          Some(error) =>
            "\nPTC trace publication failed: \{error}. Calls may have executed; inspect the retained trace."
          None => ""
        }),
        is_error=output.is_error || interrupted || self.trace_error is Some(_),
        brief?=output.brief,
        data?=self.attach_trace(output.data),
      )
    }
    Control(_) => action
  }
}

///|
/// A script that never called a tool leaves no trace, and the tool's own
/// structured output passes through untouched. Otherwise the trace fields join
/// an object-shaped output (trace keys win) and any other shape is kept under
/// `output`.
fn Program::attach_trace(self : Program, existing : Json?) -> Json? {
  if self.calls.is_empty() && self.trace_error is None {
    return existing
  }
  match (existing, self.trace()) {
    (None, trace) => Some(trace)
    (Some(Object(fields)), Object(trace)) => {
      let merged = fields.copy()
      for key, value in trace {
        merged[key] = value
      }
      Some(Json::object(merged))
    }
    (Some(other), Object(trace)) => {
      let merged = trace.copy()
      merged["output"] = other
      Some(Json::object(merged))
    }
    (Some(other), _) => Some(other)
  }
}

///|
async fn Program::execute(
  self : Program,
  index : Int,
  name : String,
  arguments : Json,
) -> Json {
  let tools = self.service.tools
  errdefer (if @async.is_being_cancelled() {
    self.calls[index] = call_entry(name, arguments, "interrupted")
  })
  let result = try {
    self.publish_trace()
    match tools.find(name) {
      None =>
        @agent_tool.respond(
          "PTC tool unavailable: \{@agent_tool.brief_line(name, limit=128)}",
          is_error=true,
        )
      Some(tool) => {
        let serial = self.service.serial
        if !tool.is_concurrent_safe() {
          serial.acquire()
        }
        defer (if !tool.is_concurrent_safe() { serial.release() })
        guard !self.closed &&
          !@async.is_being_cancelled() &&
          !(self.calls[index] is { "status": "interrupted", .. }) else {
          fail("PTC program ended before execution")
        }
        @agent_tool.execute_tool_call(
          @agent_tool.AgentToolCall::from_arguments(name, arguments),
          tools,
        )
      }
    }
  } catch {
    error => @agent_tool.respond("PTC tool failed: \{error}", is_error=true)
  }
  let response = match result {
    Respond(output) => output_json(output)
    Control(_) => error_result("PTC tool returned unsupported loop control")
  }
  let response = if response.stringify().length() > MaxReplyChars {
    error_result(
      "Tool executed, but its result exceeded the PTC 64K character limit. Do not retry a mutation merely to retrieve output.",
    )
  } else {
    response
  }
  // A cancellation-protected executor may return after stop was requested.
  // Preserve the interruption recorded at revocation, even if it did mutate.
  if self.calls[index] is { "status": "interrupted", .. } {
    return response
  }
  let entry = call_entry(name, arguments, "done", result=response)
  let size = @utf8.encode(entry.stringify()).length()
  if self.trace_bytes - self.reservations[index] + size <= MaxTraceBytes {
    self.trace_bytes += size - self.reservations[index]
    self.reservations[index] = size
    self.calls[index] = entry
  } else {
    // The client still receives the full bounded response. Retained job
    // metadata must fit the existing 1 MiB durable-record reader.
    self.calls[index] = call_entry(name, arguments, "done", result={
      "version": 1,
      "content": "Result omitted from retained trace: trace size limit reached",
      "is_error": match response {
        { "is_error": value, .. } => value
        _ => true
      },
      "trace_truncated": true,
    })
  }
  self.publish_trace()
  response
}

///|
fn error_result(message : String) -> Json {
  { "version": 1, "content": message, "is_error": true }
}

///|
fn output_json(output : @agent_tool.ToolOutput) -> Json {
  let fields : Map[String, Json] = {
    "version": 1,
    "content": output.content.to_json(),
    "is_error": output.is_error.to_json(),
  }
  if output.data is Some(data) {
    fields["data"] = data
  }
  if output.brief is Some(brief) {
    fields["brief"] = brief.to_json()
  }
  Json::object(fields)
}

///|
async fn send(conn : @http.ServerConnection, result : Json) -> Unit {
  @async.with_timeout(SendTimeoutMs, () => {
    conn.send_response(200, "OK", extra_headers={
      "Content-Type": "application/json",
    })
    conn.write(result)
    conn.end_response()
  })
}

///|
/// A publication failure is retained alongside calls, never encoded as a tool
/// failure or silently discarded when a job completes.
pub fn Program::trace_error(self : Program) -> String? {
  self.trace_error
}

///|
/// Publish the current trace, one publication at a time.
async fn Program::publish_trace(self : Program) -> Unit {
  self.publishing.acquire()
  defer self.publishing.release()
  self.deliver_trace()
}

///|
/// Snapshot and deliver under `publishing`, which the caller must hold.
async fn Program::deliver_trace(self : Program) -> Unit {
  @async.with_timeout(self.service.trace_timeout_ms, () => {
    (self.on_trace)(self.trace())
  }) catch {
    error =>
      self.trace_error = Some(@agent_tool.brief_line("\{error}", limit=512))
  }
}
