///|
pub struct Connection {
  profile : @protocol.SshProfile
  attempt : Int32
  epoch : Int32
  priv stop : @async.Queue[Unit]
  priv askpass : String?
  priv mut closed : Bool
  priv mut rejected : Bool
  priv mut waiter : AuthWaiter?
  priv mut rpc : @jsonrpc.Client?
}

///|
pub fn Connection::Connection(
  profile : @protocol.SshProfile,
  epoch : Int32,
  attempt~ : Int32 = 0,
  askpass~ : String? = None,
) -> Connection {
  {
    profile,
    epoch,
    attempt,
    askpass,
    stop: Queue(kind=Blocking(1)),
    closed: false,
    rejected: false,
    waiter: None,
    rpc: None,
  }
}

///|
pub fn Connection::close(self : Connection) -> Unit {
  self.closed = true
  ignore(self.stop.try_put(())) catch {
    _ => ()
  }
  if self.waiter is Some(waiter) {
    self.waiter = None
    ignore(waiter.answer.try_put(@protocol.Cancel)) catch {
      _ => ()
    }
  }
  if self.rpc is Some(rpc) {
    rpc.close()
  }
  self.rpc = None
}

///|
/// Bootstrap owns startup; after initialize, the WebSocket owns the remote
/// server and only the TCP forwarder remains. No RPC travels over SSH
/// stdin/stdout, and requests never replay.
pub async fn Connection::run(
  self : Connection,
  emit : (Json) -> Unit,
  model_environment? : async () -> Map[String, String],
) -> Unit {
  let mut stderr = Buffer()
  defer self.close()
  let result : Result[Unit, Error] = try {
    let settings = match model_environment {
      Some(load) => Some(model_environment_input(load()))
      None => None
    }
    guard self.askpass is Some(askpass) else {
      raise SshError("SSH authentication helper is unavailable in this host")
    }
    @async.with_task_group(group => {
      group.spawn_bg(() => {
        self.stop.get()
        raise SshError("SSH connection cancelled")
      })
      let auth_server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
      defer auth_server.close()
      let token = @uuid.mint()
      let environment : Map[String, String] = {
        "SSH_ASKPASS": askpass,
        "SSH_ASKPASS_REQUIRE": "force",
        "SEEKMOON_ASKPASS": "1",
        "SEEKMOON_ASKPASS_TOKEN": token,
        "SEEKMOON_ASKPASS_ADDRESS": auth_server.addr.to_string(),
        "LC_ALL": "C",
      }
      group.spawn_bg(() => self.serve_auth(auth_server, token, emit))
      let args = arguments(self.profile.command)
      args.push(remote_command(model_environment=settings is Some(_)))
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
          if @utf8.decode_lossy(stderr.to_bytes()).contains(
              "Permission denied, please try again.",
            ) {
            self.rejected = true
            // Preserve diagnostics, but consume the rejection marker once.
            stderr = Buffer()
            stderr.write_bytes(b"Authentication was rejected.\n")
          }
        }
      })
      let bootstrap = @process.spawn(
        group,
        "ssh",
        args,
        extra_env=environment,
        stdin=input,
        stdout=output,
        stderr=error_output,
        no_console_window=true,
        cancel_handler=@process.graceful_cancel(timeout=1000),
      )
      group.spawn_bg(() => if settings is Some(line) { lifetime.write(line) })
      let mut released = false
      group.spawn_bg(() => {
        let code = bootstrap.wait()
        if !released || code != 0 {
          raise SshError("SSH bootstrap exited \{code}")
        }
      })
      let (port, instance) = @async.with_timeout(
        1_200_000,
        error=SshError(
          "SSH startup timed out after 20 minutes, including authentication",
        ),
        () => {
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
            match bootstrap_record(@utf8.decode_lossy(line.to_bytes())) {
              Some(Progress(stage)) => emit({ "stage": stage })
              Some(Endpoint(port~, instance~)) => break (port, instance)
              None => continue
            }
          }
        },
      )
      let reservation = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
      let address = reservation.addr
      reservation.close()
      let forward = arguments(self.profile.command)
      forward.insert(0, "127.0.0.1:\{address.port()}:127.0.0.1:\{port}")
      forward.insert(0, "-L")
      forward.insert(0, "-N")
      forward.insert(0, "-oExitOnForwardFailure=yes")
      let (tunnel_input, tunnel_writer) = @process.write_to_process()
      tunnel_writer.close()
      let tunnel = @process.spawn(
        group,
        "ssh",
        forward,
        extra_env=environment,
        stdin=tunnel_input,
        stderr=error_output,
        no_console_window=true,
        cancel_handler=@process.graceful_cancel(timeout=1000),
      )
      group.spawn_bg(() => {
        let code = tunnel.wait()
        raise SshError("SSH forwarding exited \{code}")
      })
      let ws = @async.with_timeout(
        1_200_000,
        error=SshError(
          "SSH forwarding timed out after 20 minutes, including authentication",
        ),
        () => {
          let mut remaining = 15_000
          let http = for ;; {
            if tunnel.try_wait() is Some(code) {
              raise SshError("SSH forwarding exited \{code}")
            }
            let client = @http.Client("http://127.0.0.1:\{address.port()}") catch {
              _ => {
                if self.waiter is None {
                  remaining -= 25
                }
                guard remaining > 0 else {
                  raise SshError(
                    "SSH forwarding did not become ready within 15 seconds outside authentication",
                  )
                }
                @async.sleep(25)
                continue
              }
            }
            break client
          }
          errdefer http.close()
          @async.with_timeout(15_000, () => {
            @websocket.Conn::from_http_client(http, "/host")
          })
        },
      )
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
      let readiness : @async.Queue[Json] = Queue(kind=Blocking(1))
      rpc.set_notification_handler((method_, params) => {
        if self.rpc is Some(_) {
          emit({ "method": method_, "params": params })
        } else if method_ == "agent.connected" {
          // Initialization and notifications share a reader. Retain the real
          // host revision even when readiness arrives before request() resumes.
          ignore(readiness.try_put(params)) catch {
            _ => ()
          }
        }
      })
      group.spawn_bg(() => rpc.run_message_pump())
      group.spawn_bg(() => rpc.run_writer())
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
      // The server has claimed this socket before acknowledging initialize.
      // EOF now ends the bootstrap shell without cancelling the remote service.
      released = true
      lifetime.close()
      let bootstrap_code = @async.with_timeout(10_000, () => bootstrap.wait())
      guard bootstrap_code == 0 else {
        raise SshError("SSH bootstrap exited \{bootstrap_code}")
      }
      let connected = @async.with_timeout(
        10_000,
        error=SshError("Remote app-server did not announce its host protocol"),
        () => readiness.get(),
      )
      self.rpc = Some(rpc)
      emit({ "method": "agent.connected", "params": connected })
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
      Err(SshError(reason)) => "SSH connection failed: \{reason}"
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
