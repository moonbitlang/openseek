///|
pub(all) struct SshHost {
  ssh : String
  destination : String
  launcher : String
  data_dir : String
  build_id : String
  expected_server_id : String?
}

///|
pub suberror HostClientError {
  HostClientError(String)
  IdentityChanged(String)
}

///|
/// Whether a failed request could have reached the working host. Reconnection
/// must never replay Unknown requests; reconcile their durable state instead.
pub suberror RequestError {
  Unsent(String)
  Refused(String)
  Unknown(String)
}

///|
pub impl Show for RequestError with fn output(self, logger) {
  match self {
    Unsent(message) | Refused(message) | Unknown(message) =>
      logger.write_string(message)
  }
}

///|
pub extend RequestError with Show::{to_string, output}

///|
priv struct Pending {
  reply : @async.Queue[(Json, Int32)]
  mut handed_to_writer : Bool
  mut cancelled : Bool
}

///|
pub struct Client {
  identity : @host_control.Identity
  priv ws : @websocket.Conn
  priv pending : Map[Int32, Pending]
  priv outgoing : @async.Queue[(String, Int32, Pending)]
  priv notifications : @async.Queue[(Json, Int32)]
  priv mut next_id : Int32
  priv mut closed : Bool
  priv mut retained : Int32
}

///|
fn quote(value : String) -> String {
  "'" + value.replace_all(old="'", new="'\\''") + "'"
}

///|
fn remote_command(
  host : SshHost,
  marker : String,
  args : Array[String],
) -> String {
  let command = "printf '%s\\n' " +
    quote(marker) +
    "; exec " +
    ([host.launcher, "app-server"] + args).map(quote).join(" ")
  @ssh_shell.command(command)
}

///|
fn ssh_args(host : SshHost, command? : String) -> Array[String] {
  let args = [
    "-T",
    "-o",
    "BatchMode=yes",
    "-o",
    "ConnectTimeout=10",
    "-o",
    "ServerAliveInterval=15",
    "-o",
    "ServerAliveCountMax=12",
    "-o",
    "ForwardAgent=no",
    "--",
    host.destination,
  ]
  if command is Some(command) {
    args.push(command)
  }
  args
}

///|
async fn line(reader : &@io.Reader, limit : Int32) -> String {
  let bytes = Buffer()
  for ;; {
    guard bytes.length() < limit else {
      raise HostClientError("SSH output limit exceeded")
    }
    let byte = reader.read_exactly(1)
    if byte == b"\n" {
      return @utf8.decode(bytes.to_bytes())
    }
    bytes.write_bytes(byte)
  }
}

///|
async fn marker(reader : &@io.Reader, expected : String) -> Unit {
  deadline("SSH banner/ready marker", 10000, () => {
    let pattern = @utf8.encode(expected + "\n")
    let prefix = Array::make(pattern.length(), 0)
    let mut matched = 0
    for i = 1; i < pattern.length(); i = i + 1 {
      while matched > 0 && pattern[i] != pattern[matched] {
        matched = prefix[matched - 1]
      }
      if pattern[i] == pattern[matched] {
        matched += 1
      }
      prefix[i] = matched
    }
    matched = 0
    for count = 0; count < 65536; count = count + 1 {
      let byte = reader.read_exactly(1)[0]
      while matched > 0 && byte != pattern[matched] {
        matched = prefix[matched - 1]
      }
      if byte == pattern[matched] {
        matched += 1
      }
      if matched == pattern.length() {
        return
      }
    }
    raise HostClientError("SSH ready marker missing or banner exceeds 64 KiB")
  })
}

///|
fn check_identity(host : SshHost, value : Json) -> @host_control.Identity raise {
  let identity : @host_control.Identity = @json.from_json(value)
  guard identity.build_id == host.build_id &&
    identity.protocol_version == @host_control.ProtocolVersion else {
    raise HostClientError("working-host build/protocol changed")
  }
  if host.expected_server_id is Some(expected) && identity.server_id != expected {
    raise IdentityChanged(
      "working-host server identity changed; explicit reassociation is required",
    )
  }
  identity
}

///|
// Drain all stderr so verbose SSH failures cannot block on a full pipe, while
// keeping a bounded diagnostic for the window's connection error.
async fn[T, G] with_ssh_diagnostics(
  group : @async.TaskGroup[G],
  phase : String,
  setup : async (&@process.ProcessOutput) -> T,
) -> T {
  let (errors, stderr) = @process.read_from_process()
  group.add_defer(() => errors.close())
  let retained = Buffer()
  let drained = group.spawn(no_wait=true, allow_failure=true, () => {
    for ;; {
      guard errors.read_some(max_len=4096) is Some(chunk) else { break }
      let room = 8192 - retained.length()
      if room > 0 {
        retained.write_bytes(chunk[:Int32::min(room, chunk.length())])
      }
    }
  })
  setup(stderr) catch {
    error => {
      // Preserve the terminal identity fence. User requests run outside setup.
      if error is IdentityChanged(_) {
        raise error
      }
      // stdout EOF can precede the final stderr chunk / process exit.
      @async.with_timeout(250, () => drained.wait()) catch {
        _ => ()
      }
      let detail = @utf8.decode_lossy(retained.to_bytes()).trim().to_owned()
      raise HostClientError(
        phase +
        ": \{error}" +
        (if detail.is_empty() { "" } else { "\n" + detail }),
      )
    }
  }
}

///|
async fn control(host : SshHost, action : String) -> Json {
  deadline("SSH daemon " + action, 25000, () => {
    @async.with_task_group(group => {
      let mark = "__seekmoon_" + @uuid.mint() + "__"
      let (reader, stdout) = @process.read_from_process()
      group.add_defer(() => reader.close())
      let (input, input_writer) = @process.write_to_process()
      input_writer.close()
      with_ssh_diagnostics(group, "SSH daemon " + action, stderr => {
        let process = @process.spawn(
          group,
          host.ssh,
          ssh_args(
            host,
            command=remote_command(host, mark, [
              "daemon",
              action,
              "--data-dir",
              host.data_dir,
              "--build-id",
              host.build_id,
            ]),
          ),
          stdin=input,
          stdout~,
          stderr~,
          cancel_handler=@process.graceful_cancel(timeout=1000),
        )
        marker(reader, mark)
        let result = @json.parse(line(reader, 65536))
        guard process.wait() == 0 else {
          raise HostClientError("SSH daemon " + action + " failed")
        }
        result
      })
    })
  })
}

///|
/// Discover through SSH before forwarding. Only explicit absence permits start;
/// failure after handing a request to the writer never replays that request.
pub async fn[T] with_client(host : SshHost, body : async (Client) -> T) -> T {
  guard host.launcher.has_prefix("/") && host.data_dir.has_prefix("/") else {
    raise HostClientError("remote launcher and data directory must be absolute")
  }
  let status = control(host, "status")
  let status = if status is { "status": "not_running", .. } {
    control(host, "start")
  } else {
    status
  }
  let identity = check_identity(host, status)
  guard status is { "endpoint": value, .. } else {
    raise HostClientError("working-host discovery did not return an endpoint")
  }
  let endpoint : @transport.Endpoint = @json.from_json(value)
  endpoint.validate()
  guard endpoint.instance_id == identity.instance_id else {
    raise HostClientError("working-host discovery identity mismatch")
  }
  with_tunnel(host, endpoint, client => {
    guard client.identity.server_id == identity.server_id else {
      raise IdentityChanged(
        "working-host server identity changed during forwarding",
      )
    }
    body(client)
  })
}

///|
async fn[T] with_tunnel(
  host : SshHost,
  endpoint : @transport.Endpoint,
  body : async (Client) -> T,
) -> T {
  @async.with_task_group(group => {
    // OpenSSH cannot adopt a listener. Release an ephemeral loopback port just
    // before spawning, and fail closed on collisions with ExitOnForwardFailure.
    let reservation = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
    let address = reservation.addr
    reservation.close()
    let (stdin, input) = @process.write_to_process()
    input.close()
    let (output, stdout) = @process.read_from_process()
    group.add_defer(() => output.close())
    group.spawn_bg(no_wait=true, () => {
      while output.read_some(max_len=4096) is Some(_) {
        ()
      }
    })
    let (process, ws, connected) = with_ssh_diagnostics(group, "SSH tunnel", stderr => {
      let args = ssh_args(host)
      // Own this forwarder even if the user's alias enables multiplexing.
      args.insert(0, "ControlPath=none")
      args.insert(0, "-o")
      args.insert(0, "ControlMaster=no")
      args.insert(0, "-o")
      args.insert(0, "-N")
      args.insert(0, "127.0.0.1:\{address.port()}:127.0.0.1:\{endpoint.port}")
      args.insert(0, "-L")
      args.insert(0, "ExitOnForwardFailure=yes")
      args.insert(0, "-o")
      let process = @process.spawn(
        group,
        host.ssh,
        args,
        stdin~,
        stdout~,
        stderr~,
        cancel_handler=@process.graceful_cancel(timeout=1000),
      )
      let ws = deadline("SSH loopback WebSocket Upgrade", 10000, () => {
        let http = for ;; {
          if process.try_wait() is Some(code) {
            raise HostClientError("SSH forwarding exited \{code}")
          }
          let http = @http.Client("http://127.0.0.1:\{address.port()}") catch {
            _ => {
              @async.sleep(25)
              continue
            }
          }
          break http
        }
        errdefer http.close()
        @websocket.Conn::from_http_client(http, "/host")
      })
      group.add_defer(() => ws.close())
      let connected = deadline("working-host initialize", 10000, () => {
        ws.send_text(
          (
            {
              "jsonrpc": "2.0",
              "id": 0,
              "method": "server.initialize",
              "params": {
                "build_id": host.build_id,
                "protocol_version": @host_control.ProtocolVersion,
              },
            } : Json).stringify(),
        )
        let message = ws.recv()
        guard message.kind is Text else {
          raise HostClientError("non-text initialize response")
        }
        let buffer = Buffer()
        while message.read_some(max_len=4096) is Some(bytes) {
          guard buffer.length() + bytes.length() <= 65536 else {
            raise HostClientError("initialize response too large")
          }
          buffer.write_bytes(bytes)
        }
        guard @json.parse(@utf8.decode(buffer.to_bytes()))
          is { "id": 0, "result": result, .. } else {
          raise HostClientError("working-host initialize rejected")
        }
        check_identity(host, result)
      })
      if connected.instance_id != endpoint.instance_id {
        raise HostClientError(
          "working host changed between bootstrap and tunnel; reconnect explicitly",
        )
      }
      if process.try_wait() is Some(code) {
        raise HostClientError("SSH forwarding exited \{code}")
      }
      (process, ws, connected)
    })
    let client : Client = {
      identity: connected,
      ws,
      pending: Map([]),
      outgoing: Queue(kind=Blocking(64)),
      notifications: Queue(kind=Blocking(64)),
      next_id: 0,
      closed: false,
      retained: 0,
    }
    group.spawn_bg(() => {
      let code = process.wait()
      client.close(reason="SSH forwarding exited \{code}")
      ws.close()
    })
    group.spawn_bg(() => client.drive(() => client.read()))
    group.spawn_bg(() => client.drive(() => client.write()))
    group.spawn_bg(() => client.drive(() => @transport.heartbeat(ws)))
    let result = body(client)
    process.cancel()
    group.return_immediately(result)
    result
  })
}

///|
fn Client::charge(self : Client, bytes : Int32) -> Unit raise {
  guard bytes <= 64 * 1024 * 1024 - self.retained else {
    raise HostClientError("working-host retained payload limit exceeded")
  }
  self.retained += bytes
}

///|
pub async fn Client::request(
  self : Client,
  method_ : String,
  params : Json,
) -> Json {
  guard !self.closed else { raise Unsent("working-host connection is closed") }
  guard self.pending.length() < 32 && self.next_id < 2147483647 else {
    raise Unsent("working-host request capacity exceeded")
  }
  self.next_id += 1
  let id = self.next_id
  let text = (
    { "jsonrpc": "2.0", "id": id, "method": method_, "params": params } : Json).stringify()
  let bytes = @utf8.encode(text).length()
  guard bytes <= 32 * 1024 * 1024 else {
    raise Unsent("working-host request exceeds 32 MiB")
  }
  self.charge(bytes) catch {
    error => raise Unsent("\{error}")
  }
  let reply : @async.Queue[(Json, Int32)] = Queue(kind=Blocking(1))
  let pending : Pending = { reply, handed_to_writer: false, cancelled: false, }
  self.pending[id] = pending
  defer {
    pending.cancelled = true
    self.pending.remove(id)
    self.retained -= bytes
    reply.close()
    if (reply.try_get() catch { _ => None }) is Some((_, bytes)) {
      self.retained -= bytes
    }
  }
  self.charge(bytes) catch {
    error => raise Unsent("\{error}")
  }
  if !self.outgoing.try_put((text, bytes, pending)) {
    self.retained -= bytes
    raise Unsent("working-host outgoing queue full")
  }
  let (response, bytes) = reply.get() catch {
    error => {
      if pending.handed_to_writer {
        raise Unknown("\{error}")
      }
      raise Unsent("\{error}")
    }
  }
  self.retained -= bytes
  if response is { "error": error, .. } {
    raise Refused(error.stringify())
  }
  guard response is { "result": result, .. } else {
    raise Unknown("invalid RPC response")
  }
  result
}

///|
pub async fn Client::next_notification(self : Client) -> Json {
  guard !self.closed else {
    raise HostClientError("working-host connection is closed")
  }
  let (value, bytes) = self.notifications.get()
  self.retained -= bytes
  value
}

///|
async fn Client::read(self : Client) -> Unit {
  defer self.close()
  for ;; {
    let message = self.ws.recv()
    guard message.kind is Text else {
      raise HostClientError("non-text RPC message")
    }
    let body = Buffer()
    let mut owned = 0
    errdefer {
      self.retained -= owned
    }
    while message.read_some(max_len=65536) is Some(bytes) {
      guard bytes.length() <= 32 * 1024 * 1024 - owned else {
        raise HostClientError("working-host message exceeds 32 MiB")
      }
      self.charge(bytes.length())
      owned += bytes.length()
      body.write_bytes(bytes)
    }
    let value = @json.parse(@utf8.decode(body.to_bytes()))
    if value is { "id": Number(id, ..), .. } && id == id.to_int().to_double() {
      if self.pending.get(id.to_int()) is Some(pending) &&
        (pending.reply.try_put((value, owned)) catch { _ => false }) {
        continue
      }
    } else if value is { "method": String(_), .. } {
      guard self.notifications.try_put((value, owned)) else {
        raise HostClientError(
          "working-host notification queue overflow; resync required",
        )
      }
      continue
    }
    self.retained -= owned
  }
}

///|
async fn Client::write(self : Client) -> Unit {
  for ;; {
    let (text, bytes, pending) = self.outgoing.get()
    defer {
      self.retained -= bytes
    }
    if self.closed {
      return
    }
    if pending.cancelled {
      continue
    }
    // Set before the first suspending write: even a partial frame makes the
    // result uncertain. Queueing alone never implies submission.
    pending.handed_to_writer = true
    self.ws.send_text(text)
  }
}

///|
async fn Client::drive(self : Client, action : async () -> Unit) -> Unit {
  action() catch {
    error => self.close(reason="\{error}")
  }
  self.close()
  self.ws.close()
}

///|
fn Client::close(self : Client, reason~ : String = "connection lost") -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  self.pending.each((_, pending) => {
    pending.reply.close(error=HostClientError(reason))
  })
  self.notifications.close(error=HostClientError(reason))
  self.outgoing.close(error=HostClientError(reason))
}

///|
async fn[T] deadline(
  phase : String,
  milliseconds : Int32,
  action : async () -> T,
) -> T {
  match @async.with_timeout_opt(milliseconds, action) {
    Some(value) => value
    None =>
      raise HostClientError(
        phase +
        " deadline exceeded; check SSH authentication, shell envelope and remote service logs",
      )
  }
}

///|
pub impl Show for HostClientError with fn output(self, logger) {
  match self {
    HostClientError(message) | IdentityChanged(message) =>
      logger.write_string(message)
  }
}

///|
pub extend HostClientError with Show::{to_string, output}
