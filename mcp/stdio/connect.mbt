// Launch an MCP server as a subprocess and speak MCP to it over stdio.

///|
/// The default handshake deadline: a server that does not answer `initialize`
/// within this many milliseconds is abandoned (so a non-MCP or wedged child
/// cannot hang the caller).
const DefaultHandshakeTimeoutMs : Int = 30000

///|
/// A live stdio MCP connection: the initialized client. Its reader/writer tasks
/// run on the task group passed to `connect`; the connection is torn down when
/// that group ends, or eagerly via `shutdown`.
struct StdioConnection {
  client : @mcp.McpClient
  init : @mcp.InitializeResult
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
  self.client.close()
}

///|
/// Spawn `command args...` as an MCP server, wire an NDJSON transport to a
/// JSON-RPC client (with its reader and writer tasks on `group`), run the MCP
/// handshake under `handshake_timeout_ms`, and return the initialized
/// connection. Raises if the process cannot start, the handshake fails, or the
/// handshake times out (`@async.TimeoutError`) — terminating the process and
/// closing the pipes in every failure case so nothing leaks. The server inherits
/// openseek's environment (so it always has `PATH`, `HOME`, etc.); `env` adds to
/// and overrides it.
pub async fn[X] connect(
  group : @async.TaskGroup[X],
  command~ : String,
  args~ : Array[String],
  env? : Map[String, String],
  cwd? : String,
  client_name~ : String,
  client_version~ : String,
  handshake_timeout_ms? : Int = DefaultHandshakeTimeoutMs,
) -> StdioConnection {
  let (stdin_writer, stdout_reader, process) = {
    // The child's stdin/stdout pipes via the process helpers, which create the
    // synchronous, non-overlapped child endpoints a subprocess needs on every
    // platform (including Windows). They hand the child ends back as un-closable
    // trait objects and clean them up in `spawn`'s own teardown, so the only
    // unreachable-in-practice leak is one fd if `read_from_process` raises (fd
    // exhaustion) after `write_to_process` succeeded — accepted, since that end
    // cannot be closed here.
    let (child_stdin, stdin_writer) = @process.write_to_process()
    errdefer stdin_writer.close()
    let (stdout_reader, child_stdout) = @process.read_from_process()
    errdefer stdout_reader.close()
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
    )
    (stdin_writer, stdout_reader, process)
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
  pump_task = Some(
    group.spawn(
      () => {
        defer stdout_reader.close()
        client.run_message_pump()
      },
      no_wait=true,
      allow_failure=true,
    ),
  )
  writer_task = Some(
    group.spawn(
      () => {
        defer stdin_writer.close()
        client.run_writer()
      },
      no_wait=true,
      allow_failure=true,
    ),
  )
  let mcp_client = @mcp.McpClient(client)
  errdefer teardown()
  let init = @async.with_timeout(handshake_timeout_ms) <| () => {
    mcp_client.initialize(client_name~, client_version~)
  }
  { client: mcp_client, init, }
}
