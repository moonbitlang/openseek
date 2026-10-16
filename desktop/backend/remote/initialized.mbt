///|
priv struct QueuedText {
  text : String
  bytes : Int32
  method_ : String?
}

///|
priv struct ConnectionBudget {
  mut bytes : Int32
  mut requests : Int32
  out : @async.Queue[QueuedText]
}

///|
fn ConnectionBudget::charge(self : ConnectionBudget, n : Int32) -> Unit raise {
  guard n <= 64 * 1024 * 1024 - self.bytes else {
    raise SlowClient("connection payload exceeds 64 MiB")
  }
  self.bytes += n
}

///|
fn ConnectionBudget::enqueue(
  self : ConnectionBudget,
  value : Json,
  method_? : String,
) -> Unit raise {
  let text = value.stringify()
  let bytes = @utf8.encode(text).length()
  guard bytes <= InboundFrameMaxBytes else {
    raise SlowClient("outgoing message exceeds 32 MiB")
  }
  self.charge(bytes)
  guard self.out.try_put({ text, bytes, method_, }) else {
    self.bytes -= bytes
    raise SlowClient("client is not draining responses")
  }
}

///|
async fn read_bounded(
  reader : &@io.Reader,
  budget : ConnectionBudget,
  max~ : Int32,
) -> (Inbound, Int32) {
  let buffer = Buffer()
  let mut owned = 0
  errdefer {
    budget.bytes -= owned
  }
  while reader.read_some(max_len=Int32::min(65536, max - owned + 1))
        is Some(chunk) {
    guard chunk.length() <= max - owned else {
      raise SlowClient("incoming message exceeds limit")
    }
    budget.charge(chunk.length())
    owned += chunk.length()
    buffer.write_bytes(chunk)
  }
  (classify(@utf8.decode(buffer.to_bytes())), owned)
}

///|
/// Unlike the relay entry point, direct working-host connections must prove
/// exact build/protocol agreement before subscribing to business notifications.
pub async fn Client::serve_initialized(
  self : Client,
  conn : @websocket.Conn,
  identity~ : @host_control.Identity,
  on_response_sent~ : (String) -> Unit = _ => (),
) -> Unit {
  let budget : ConnectionBudget = {
    bytes: 0,
    requests: 0,
    out: Queue(kind=Blocking(64)),
  }
  @async.with_timeout(10000, () => {
    let message = conn.recv()
    guard message.kind is Text else {
      raise SlowClient("initialize must be JSON text")
    }
    let (inbound, bytes) = read_bounded(message, budget, max=65536)
    defer {
      budget.bytes -= bytes
    }
    guard inbound is Request(id, "server.initialize", params) else {
      raise SlowClient("server.initialize must be the first request")
    }
    let initialize : @host_control.Initialize = @json.from_json(params)
    guard initialize.build_id == identity.build_id &&
      initialize.protocol_version == @host_control.ProtocolVersion else {
      conn.send_text(
        error_envelope(id, -32010, "build/protocol mismatch").stringify(),
      )
      raise SlowClient("build/protocol mismatch")
    }
    conn.send_text(
      ({ "jsonrpc": "2.0", "id": id, "result": identity.to_json() } : Json).stringify(),
    )
  })
  let accepted = Notification::from_host(AgentConnected({ stage: Accepted, }))
  budget.enqueue({
    "jsonrpc": "2.0",
    "method": accepted.wire_name(),
    "params": accepted.params(),
  })
  fn notify(notification : Notification) -> Unit raise {
    if notification.profile() is Some(notification) {
      budget.enqueue({
        "jsonrpc": "2.0",
        "method": notification.wire_name(),
        "params": notification.params(),
      })
    }
  }
  let unsubscribe = (self.subscribe)(
    event => {
      notify(event) catch {
        _ => {
          conn.close()
          return false
        }
      }
      true
    },
    () => conn.close(),
  )
  defer unsubscribe()
  let watch_jobs : @async.Queue[async () -> Unit] = Queue(kind=Blocking(32))
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      for ;; {
        let queued = budget.out.get()
        defer {
          budget.bytes -= queued.bytes
        }
        conn.send_text(queued.text)
        if queued.method_ is Some(method_) {
          on_response_sent(method_)
        }
      }
    })
    group.spawn_bg(() => {
      for ;; {
        watch_jobs.get()()
      }
    })
    group.spawn_bg(() => {
      (self.run_connection)(notification => notify(notification), notification => {
        notify(notification)
      })
    })
    group.spawn_bg(() => heartbeat(conn))
    for ;; {
      let message = conn.recv()
      guard message.kind is Text else {
        raise SlowClient("business message must be JSON text")
      }
      let (inbound, bytes) = read_bounded(
        message,
        budget,
        max=InboundFrameMaxBytes,
      )
      match inbound {
        Request(id, method_, params) => {
          if budget.requests >= 32 {
            budget.bytes -= bytes
            budget.enqueue(
              error_envelope(id, -32011, "32 requests already in flight"),
            )
            continue
          }
          budget.requests += 1
          let job : async () -> Unit = () => {
            defer {
              budget.requests -= 1
              budget.bytes -= bytes
            }
            let response = if method_ == "server.initialize" {
              error_envelope(id, -32600, "connection already initialized")
            } else {
              run_request(self.endpoints, id, method_, params)
            }
            budget.enqueue(response, method_~)
          }
          if method_ == "fs.watch" || method_ == "fs.unwatch" {
            // Preserve arrival order without parking the WebSocket reader.
            guard watch_jobs.try_put(job) else {
              raise SlowClient("watch queue full")
            }
          } else {
            group.spawn_bg(job)
          }
        }
        ClientNotification => budget.bytes -= bytes
        InvalidParams(id) => {
          budget.bytes -= bytes
          budget.enqueue(
            error_envelope(id, CodeInvalidParams, "params must be an object"),
          )
        }
        _ => {
          budget.bytes -= bytes
          budget.enqueue(
            error_envelope(Json::null(), CodeInvalidRequest, "invalid request"),
          )
        }
      }
    }
  })
}

///|
/// A matching pong, not any business traffic, advances the watchdog. Ping
/// waiters are independent of the business writer and bounded to six tasks.
pub async fn heartbeat(conn : @websocket.Conn) -> Unit {
  heartbeat_with_budget(conn, interval_ms=10000, timeout_ms=60000L)
}

///|
async fn heartbeat_with_budget(
  conn : @websocket.Conn,
  interval_ms~ : Int32,
  timeout_ms~ : Int64,
) -> Unit {
  @async.with_task_group(group => {
    let mut last_pong = @async.now()
    let mut pending = 0
    let mut sequence = 0L
    for ;; {
      @async.sleep(interval_ms)
      guard @async.now() - last_pong <= timeout_ms else {
        raise SlowClient("pong deadline exceeded")
      }
      if pending < 6 {
        sequence += 1
        let payload = @utf8.encode("host-ping-\{sequence}")
        pending += 1
        group.spawn_bg(() => {
          defer {
            pending -= 1
          }
          conn.ping(msg=payload)
          last_pong = @async.now()
        })
      }
    }
  })
}
