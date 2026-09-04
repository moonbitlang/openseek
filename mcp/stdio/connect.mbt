// Launch an MCP server as a subprocess and speak MCP to it over stdio.

///|
/// The default handshake deadline: a server that does not answer `initialize`
/// within this many milliseconds is abandoned (so a non-MCP or wedged child
/// cannot hang the caller).
const DefaultHandshakeTimeoutMs : Int = 30000

///|
/// A live stdio MCP connection: the initialized client plus an idempotent
/// teardown. Its reader/writer tasks run on the task group passed to `connect`;
/// the connection is torn down when that group ends, or eagerly via `shutdown`.
struct StdioConnection {
  client : @mcp.McpClient
  init : @mcp.InitializeResult
  teardown : () -> Unit
}

///|
/// The initialized MCP client to issue `list_tools` / `call_tool` against.
pub fn StdioConnection::client(self : StdioConnection) -> @mcp.McpClient {
  self.client
}

///|
/// Tear the connection down eagerly: cancel the reader/writer tasks, close the
/// pipes (the child sees stdin EOF), and terminate the process. Idempotent.
pub fn StdioConnection::shutdown(self : StdioConnection) -> Unit {
  (self.teardown)()
}

///|
/// Spawn `command args...` as an MCP server, wire an NDJSON transport to a
/// JSON-RPC client (with its reader and writer tasks on `group`), run the MCP
/// handshake under `handshake_timeout_ms`, and return the initialized
/// connection. Returns `None` if the process cannot start, the handshake fails,
/// or the handshake times out — terminating the process and closing the pipes in
/// every failure case so nothing leaks. The server inherits openseek's
/// environment (so it always has `PATH`, `HOME`, etc.); `env` adds to and
/// overrides it.
pub async fn[X] connect(
  group : @async.TaskGroup[X],
  command~ : String,
  args~ : Array[String],
  env? : Map[String, String],
  cwd? : String,
  client_name~ : String,
  client_version~ : String,
  handshake_timeout_ms? : Int = DefaultHandshakeTimeoutMs,
) -> StdioConnection? {
  // The child's stdin/stdout pipes via the process helpers, which create the
  // synchronous, non-overlapped child endpoints a subprocess needs on every
  // platform (including Windows). They hand the child ends back as un-closable
  // trait objects and clean them up in `spawn`'s own teardown, so the only
  // unreachable-in-practice leak is one fd if `read_from_process` raises (fd
  // exhaustion) after `write_to_process` succeeded — accepted, since that end
  // cannot be closed here.
  let (child_stdin, stdin_writer) = @process.write_to_process() catch {
    error if @async.is_being_cancelled() => raise error
    _ => return None
  }
  let (stdout_reader, child_stdout) = @process.read_from_process() catch {
    error if @async.is_being_cancelled() => {
      stdin_writer.close()
      raise error
    }
    _ => {
      stdin_writer.close()
      return None
    }
  }
  // `no_wait`: the group terminates the server at teardown rather than waiting
  // for an exit that only comes once its stdin is closed.
  let process = @process.spawn(
    group,
    command,
    args,
    extra_env?=env,
    inherit_env=true,
    stdin=child_stdin,
    stdout=child_stdout,
    cwd?=cwd.map(dir => dir.view()),
    no_wait=true,
  ) catch {
    error if @async.is_being_cancelled() => {
      stdout_reader.close()
      stdin_writer.close()
      raise error
    }
    // Spawn failed: close our parent ends (spawn's own cleanup releases the
    // child ends).
    _ => {
      stdout_reader.close()
      stdin_writer.close()
      return None
    }
  }
  // The pump and writer tasks own their respective parent pipe ends and close
  // them in defer blocks. Teardown cancels the owner tasks instead of closing a
  // handle from another task while an async read/write is still pending (which
  // can hang on Windows).
  let mut torn_down = false
  let mut pump_task : @async.Task[Unit]? = None
  let mut writer_task : @async.Task[Unit]? = None
  let teardown = () => {
    if !torn_down {
      torn_down = true
      if pump_task is Some(task) {
        task.cancel()
      }
      if writer_task is Some(task) {
        task.cancel()
      }
      // Cancelling the writer closes stdin, letting a well-behaved server exit
      // on EOF; `process.cancel()` is the backstop. Caveat: cancellation only
      // signals the direct child, so a launcher that forks (e.g. `npx`) and
      // ignores stdin EOF may leave descendants running — an upstream
      // group-kill gap.
      process.cancel()
    }
  }
  let transport = NdjsonTransport::NdjsonTransport(
    stdout_reader,
    stdin_writer,
    on_close=teardown,
  )
  let client = @jsonrpc.Client(transport)
  // `no_wait` keeps these standing tasks from delaying normal group completion;
  // it does not stop them while the group is still running. Teardown cancels
  // them for immediate shutdown; a failed send / EOF still closes the client
  // via the transport.
  let pump = group.spawn(
    () => {
      defer stdout_reader.close()
      client.run_message_pump()
    },
    no_wait=true,
    allow_failure=true,
  )
  pump_task = Some(pump)
  let writer = group.spawn(
    () => {
      defer stdin_writer.close()
      client.run_writer()
    },
    no_wait=true,
    allow_failure=true,
  )
  writer_task = Some(writer)
  let mcp_client = @mcp.McpClient(client)
  let init = @async.with_timeout_opt(handshake_timeout_ms, () => {
    mcp_client.initialize(client_name~, client_version~)
  }) catch {
    error if @async.is_being_cancelled() => {
      teardown()
      raise error
    }
    // Handshake raised (transport closed, unsupported protocol version, ...).
    _ => {
      teardown()
      return None
    }
  }
  guard init is Some(init) else {
    // Handshake exceeded the deadline.
    teardown()
    return None
  }
  Some({ client: mcp_client, init, teardown, })
}
