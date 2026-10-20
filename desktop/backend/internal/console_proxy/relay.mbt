// Forwarding the console's API requests and device sockets to the relay.
// Requests carry the page's own `Authorization`; the browser's cookies and
// `Origin` stay behind, so the relay sees a bearer client, not this origin.

///|
/// Request headers that describe this hop or this origin, not the request.
fn dropped_request_header(name : String) -> Bool {
  match name.to_lower() {
    "host"
    | "cookie"
    | "origin"
    | "referer"
    | "connection"
    | "keep-alive"
    | "upgrade"
    | "te"
    | "trailer"
    | "transfer-encoding"
    | "content-length"
    // Ask for an identity body; this hop does not recode bodies.
    | "accept-encoding"
    | "proxy-authorization"
    | "proxy-connection" => true
    _ => false
  }
}

///|
/// Response headers this hop recomputes or must not pass to the page.
fn dropped_response_header(name : String) -> Bool {
  match name.to_lower() {
    "connection"
    | "keep-alive"
    | "transfer-encoding"
    | "content-length"
    | "trailer"
    | "upgrade"
    | "set-cookie" => true
    _ => false
  }
}

///|
/// A redirect to the relay's own origin stays on the proxy's origin.
fn local_location(location : String, relay~ : String) -> String {
  match location.strip_prefix(relay) {
    Some(rest) if rest.has_prefix("/") => rest.to_owned()
    _ => location
  }
}

///|
/// The WebSocket origin of an HTTP(S) relay origin.
fn socket_origin(relay : String) -> String {
  if relay.strip_prefix("https://") is Some(rest) {
    "wss://\{rest}"
  } else if relay.strip_prefix("http://") is Some(rest) {
    "ws://\{rest}"
  } else {
    relay
  }
}

///|
/// The request's path and query, as received.
fn target(req : @moonback.Request) -> String {
  match req.search {
    Some(search) => "\{req.path}?\{search}"
    None => req.path.to_owned()
  }
}

///|
async fn forward(
  req : @moonback.Request,
  res : @moonback.Responder,
  relay~ : String,
) -> Unit {
  let body = req.body.binary()
  let headers : @http.Headers = Map([])
  for header in req.headers.iter() {
    let (name, value) = header
    if !dropped_request_header(name) {
      headers[name] = value
    }
  }
  let (response, answer) = @http.request(
    relay + target(req),
    req.meth,
    headers,
    body,
  ) catch {
    error => {
      @xlog.warn(category="console_proxy") <?
        {
          "event": "relay_unreachable",
          "path": target(req),
          "error": "\{error}",
        }
      res.send_void(status=502)
      return
    }
  }
  let answer = answer.binary()
  let reply = @moonback.MutHeaders()
  for name, value in response.headers {
    let key = name.to_string()
    if dropped_response_header(key) {
      continue
    }
    reply.add(
      key,
      if key.to_lower() == "location" {
        local_location(value, relay~)
      } else {
        value
      },
    )
  }
  reply.set("Content-Length", answer.length().to_string())
  let writer = res.respond(status=response.code, headers=reply)
  writer.write(answer)
}

///|
/// Join the page's device socket to the relay's. The relay's handshake goes
/// first, so a rejected ticket reaches the page as the relay's HTTP status
/// instead of an opened and immediately closed socket.
async fn bridge_socket(
  req : @moonback.Request,
  res : @moonback.Responder,
  relay~ : String,
) -> Unit {
  let upstream = @websocket.connect(socket_origin(relay) + target(req)) catch {
    @websocket.HandshakeRejected(_, response) => {
      res.send_void(status=response.code)
      return
    }
    error => {
      @xlog.warn(category="console_proxy") <?
        {
          "event": "relay_socket_unreachable",
          "path": target(req),
          "error": "\{error}",
        }
      res.send_void(status=502)
      return
    }
  }
  defer upstream.close()
  let page = res.upgrade(req)
  defer page.close()
  // Either side ending ends the pair; the other direction is cancelled.
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      relay_messages(from=page, to=upstream)
      group.return_immediately(())
    })
    group.spawn_bg(() => {
      relay_messages(from=upstream, to=page)
      group.return_immediately(())
    })
  })
}

///|
/// Copy messages until `from` closes, then pass its close on to `to`. A
/// failed write means `to` is gone, which also ends the copy.
async fn relay_messages(
  from~ : @websocket.Conn,
  to~ : @websocket.Conn,
) -> Unit noraise {
  for ;; {
    let message = from.recv() catch {
      @websocket.ConnectionClosed(code, reason) => {
        to.send_close(code=sendable_close(code), reason?) catch {
          _ => ()
        }
        return
      }
      _ => {
        to.send_close(code=GoingAway) catch {
          _ => ()
        }
        return
      }
    }
    try {
      let data = message.read_all()
      match message.kind {
        Text => to.send_text(data.text())
        Binary => to.send_binary(data.binary())
      }
    } catch {
      _ => return
    }
  }
}

///|
/// A close code that may appear on the wire. `Abnormal` only describes a
/// connection that ended without a close frame, and codes outside the
/// registered and application ranges cannot be sent either.
fn sendable_close(code : @websocket.CloseCode) -> @websocket.CloseCode {
  match code {
    Abnormal => GoingAway
    Other(value) if value < 3000 || value > 4999 => GoingAway
    code => code
  }
}
