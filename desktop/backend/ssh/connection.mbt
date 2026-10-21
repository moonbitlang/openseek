///|
pub struct Connection {
  profile : @protocol.SshProfile
  epoch : Int32
  priv mut rpc : @jsonrpc.Client?
}

///|
pub fn Connection::Connection(
  profile : @protocol.SshProfile,
  epoch : Int32,
) -> Connection {
  { profile, epoch, rpc: None, }
}

///|
pub fn Connection::close(self : Connection) -> Unit {
  if self.rpc is Some(rpc) {
    rpc.close()
  }
  self.rpc = None
}

///|
/// Own the bootstrap SSH process, TCP forwarder, and local WebSocket as one
/// connection. No RPC travels over SSH stdin/stdout, and requests never replay.
pub async fn Connection::run(
  self : Connection,
  emit : (Json) -> Unit,
  model_environment? : async () -> Map[String, String],
) -> Unit {
  let mut stderr = Buffer()
  let result : Result[Unit, Error] = try {
    let settings = match model_environment {
      Some(load) => Some(model_environment_input(load()))
      None => None
    }
    @async.with_task_group(group => {
      let args = arguments(self.profile.command)
      args.push(
        remote_command(
          self.profile.server,
          model_environment=settings is Some(_),
        ),
      )
      let (input, lifetime) = @process.write_to_process()
      defer lifetime.close()
      let (reader, output) = @process.read_from_process()
      defer reader.close()
      let (errors, error_output) = @process.read_from_process(shared=true)
      defer errors.close()
      group.spawn_bg(allow_failure=true, () => {
        while errors.read_some(max_len=4096) is Some(bytes) {
          if stderr.length() + bytes.length() > 8192 {
            stderr = Buffer()
          }
          stderr.write_bytes(bytes)
        }
      })
      let bootstrap = @process.spawn(
        group,
        "ssh",
        args,
        stdin=input,
        stdout=output,
        stderr=error_output,
        no_console_window=true,
        cancel_handler=@process.graceful_cancel(timeout=1000),
      )
      group.spawn_bg(() => if settings is Some(line) { lifetime.write(line) })
      let endpoint = @async.with_timeout(1_200_000, () => {
        for ;; {
          let line = Buffer()
          for ;; {
            guard line.length() < 65536 else {
              raise SshError("SSH bootstrap output too large")
            }
            let byte = reader.read_exactly(1)
            if byte == b"\n" {
              break
            }
            line.write_bytes(byte)
          }
          let value = @json.parse(@utf8.decode(line.to_bytes()))
          if value is { "stage": String(stage), .. } {
            emit({ "stage": stage })
          } else {
            break value
          }
        }
      })
      guard endpoint
        is {
          "port": Number(port, ..),
          "instance": String(instance),
          "protocol": 1,
          ..
        } &&
        port >= 1 &&
        port <= 65535 else {
        raise SshError(
          "Expected an app-server loopback endpoint; install the matching CLI",
        )
      }
      let reservation = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
      let address = reservation.addr
      reservation.close()
      let forward = arguments(self.profile.command)
      forward.insert(
        0,
        "127.0.0.1:\{address.port()}:127.0.0.1:\{port.to_int()}",
      )
      forward.insert(0, "-L")
      forward.insert(0, "-N")
      forward.insert(0, "-oExitOnForwardFailure=yes")
      let (tunnel_input, tunnel_writer) = @process.write_to_process()
      tunnel_writer.close()
      let tunnel = @process.spawn(
        group,
        "ssh",
        forward,
        stdin=tunnel_input,
        stderr=error_output,
        no_console_window=true,
        cancel_handler=@process.graceful_cancel(timeout=1000),
      )
      let ws = @async.with_timeout(15_000, () => {
        let http = for ;; {
          if tunnel.try_wait() is Some(code) {
            raise SshError("SSH forwarding exited \{code}")
          }
          let client = @http.Client("http://127.0.0.1:\{address.port()}") catch {
            _ => {
              @async.sleep(25)
              continue
            }
          }
          break client
        }
        errdefer http.close()
        @websocket.Conn::from_http_client(http, "/host")
      })
      let stopped : @async.Queue[Unit] = Queue(kind=Blocking(1))
      let rpc = @jsonrpc.Client(TcpTransport::{
        socket: ws,
        teardown: () => {
          bootstrap.cancel()
          tunnel.cancel()
          ignore(stopped.try_put(())) catch {
            _ => ()
          }
        },
      })
      defer rpc.close()
      rpc.set_notification_handler((method_, params) => {
        if self.rpc is Some(_) {
          emit({ "method": method_, "params": params })
        }
      })
      group.spawn_bg(() => rpc.run_message_pump())
      group.spawn_bg(() => rpc.run_writer())
      group.spawn_bg(() => {
        ignore(bootstrap.wait())
        rpc.close()
      })
      group.spawn_bg(() => {
        ignore(tunnel.wait())
        rpc.close()
      })
      let reply = @async.with_timeout(10_000, () => {
        rpc.request(method_="initialize", params={
          "protocol": 1,
          "instance": instance,
        })
      })
      guard reply is { "protocol": 1, "instance": String(actual), .. } &&
        actual == instance else {
        raise SshError("Remote app-server identity changed during forwarding")
      }
      self.rpc = Some(rpc)
      emit({ "method": "agent.connected", "params": { "stage": "accepted" } })
      stopped.get()
      group.return_immediately(())
    })
    Ok(())
  } catch {
    error => Err(error)
  }
  self.rpc = None
  let detail = @utf8.decode_lossy(stderr.to_bytes()).trim().to_owned()
  let message = (match result {
      Ok(_) => "SSH disconnected"
      Err(error) => "SSH connection failed: \{error}"
    }) +
    (if detail.is_empty() { "" } else { "\n" + detail })
  emit({ "disconnected": message })
}

///|
pub async fn Connection::request(
  self : Connection,
  request : @protocol.SshRequest,
) -> @protocol.SshReply {
  guard request.host_id == self.profile.id &&
    request.epoch == self.epoch &&
    self.rpc is Some(rpc) &&
    !rpc.is_closed() else {
    return SshUnsent("SSH connection is unavailable; reconnect this host")
  }
  let value = rpc.request(method_=request.method_, params=request.params) catch {
    @jsonrpc.ResponseError::Failed(message~, ..) => return SshRefused(message)
    error => return SshUnknown("SSH disconnected before the reply: \{error}")
  }
  if self.rpc is None {
    SshUnknown("SSH connection changed before the reply")
  } else {
    SshSuccess(value)
  }
}
