// The browser transport: JSON-RPC 2.0 over one WebSocket per device
// channel (docs/remote-protocol.md). Requests are correlated by a
// client-scoped id against the session's pending map; notifications go to
// the handler installed with that connection. Sockets are JS objects, so
// the registry lives here as module state rather than in the Elm model.

///|
/// One live (or connecting) WebSocket session.
priv struct RpcSession {
  socket : @js.Value
  // id → the promise/resolve/reject record of the awaiting request.
  pending : Map[Int, @js.Value]
  mut next_id : Int
  mut open_ : Bool
}

///|
/// Every live (or connecting) WebSocket session, one per device channel.
/// Empty before `ws_connect` (and forever on a proton page, which never
/// calls it).
let channels : Map[ChannelId, RpcSession] = Map([])

///|
/// Build a deferred promise without `Promise.withResolvers`, which older
/// WebKit versions (including mobile Safari before 17.4) do not provide.
/// The Promise constructor itself is available on every browser we support.
extern "js" fn new_deferred() -> @js.Value =
  #| () => {
  #|   let resolve;
  #|   let reject;
  #|   const promise = new Promise((resolvePromise, rejectPromise) => {
  #|     resolve = resolvePromise;
  #|     reject = rejectPromise;
  #|   });
  #|   return { promise, resolve, reject };
  #| }

///|
/// The page's own origin with the WebSocket scheme — `wss://host` for an
/// `https:` page, `ws://host` otherwise; `None` outside a browser page.
pub fn page_ws_origin() -> String? {
  guard js_prop(@js.globalThis, "location") is Some(location) else {
    return None
  }
  guard (
      @js.Cast::into((location.get_with_string("host") : @js.Value)) : String?)
    is Some(host) &&
    !host.is_empty() else {
    return None
  }
  let protocol : String? = @js.Cast::into(
    (location.get_with_string("protocol") : @js.Value),
  )
  let scheme = if protocol is Some("https:") { "wss://" } else { "ws://" }
  Some(scheme + host)
}

///|
/// A device's protocol WebSocket URL: same origin, the relay's
/// `/v1/devices/<device>/ws` route.
fn ws_url(device : String) -> String? {
  guard page_ws_origin() is Some(origin) else { return None }
  Some("\{origin}/v1/devices/\{device}/ws")
}

///|
/// Open (or replace) the connection to one device. `on_notification`
/// receives every notification this host pushes; `on_down` fires once when
/// the socket closes for any reason — the caller owns backoff and calls
/// `ws_connect` again. Requests issued while down fail fast with a
/// user-facing message.
pub fn ws_connect(
  device : String,
  on_notification~ : (String, Map[String, Json]) -> Unit,
  on_down~ : () -> Unit,
) -> Unit {
  guard ws_url(device) is Some(url) else {
    on_down()
    return
  }
  let channel = Remote(device)
  // Replacing the registry entry alone leaves the previous socket's
  // `onmessage` callback alive. Retire it first so at most one connection can
  // forward notifications or hold pending requests for this device.
  ws_close(channel)
  let ctor : @js.Value = @js.globalThis.get_with_string("WebSocket")
  let socket : @js.Value = ctor.new([url])
  let session : RpcSession = {
    socket,
    pending: Map([]),
    next_id: 1,
    open_: false,
  }
  channels[channel] = session
  socket.set_with_string("onopen", (_event : @js.Value) => session.open_ = true)
  socket.set_with_string("onmessage", (event : @js.Value) => {
    handle_message(session, event, on_notification)
  })
  socket.set_with_string("onclose", (_event : @js.Value) => {
    session.open_ = false
    reject_all(session, "OpenSeek connection lost")
    // Only the channel's current session reports down — a replaced socket's
    // late close must not double-trigger that channel's reconnect loop.
    if channels.get(channel) is Some(current) &&
      physical_equal(current, session) {
      channels.remove(channel)
      on_down()
    }
  })
}

///|
/// Close a channel's connection and forget it, failing its in-flight
/// requests. Removing the registry entry before closing makes the socket's
/// own `onclose` a no-op (its identity check fails), so `on_down` never
/// fires and nothing schedules a reconnect — this is how a retired device's
/// channel is stopped for good.
pub fn ws_close(channel : ChannelId) -> Unit {
  guard channels.get(channel) is Some(session) else { return }
  channels.remove(channel)
  session.open_ = false
  reject_all(session, "OpenSeek connection closed")
  let _ : @js.Value = session.socket.apply_with_string(
    "close",
    ([] : Array[@js.Value]),
  )
}

///|
/// Send one request over a channel's connection and wait for its reply.
async fn ws_request(
  channel : ChannelId,
  op : String,
  payload : @js.Value,
) -> @js.Value {
  guard channels.get(channel) is Some(session) && session.open_ else {
    raise BridgeError("OpenSeek connection is down")
  }
  let id = session.next_id
  session.next_id += 1
  let frame = @js.Object::new()
  frame["jsonrpc"] = "2.0"
  frame["id"] = id
  frame["method"] = op
  frame["params"] = payload
  let text = json_text(frame.to_value())
  let deferred = new_deferred()
  session.pending[id] = deferred
  @js.Error_::wrap(
    () => session.socket.apply_with_string("send", [@js.Value::cast_from(text)]),
    map_ok=_ => (),
  ) catch {
    error => {
      // `send` can throw synchronously after insertion but before a promise
      // waiter exists. Remove only our still-current resolver: an exotic
      // synchronous response may already have settled/replaced this id.
      remove_pending_if_same(session, id, deferred)
      raise error
    }
  }
  let promise : @js.Promise = @js.Value::cast(
    (deferred.get_with_string("promise") : @js.Value),
  )
  promise.wait()
}

///|
fn remove_pending_if_same(
  session : RpcSession,
  id : Int,
  deferred : @js.Value,
) -> Unit {
  if session.pending.get(id) is Some(current) &&
    physical_equal(current, deferred) {
    session.pending.remove(id)
  }
}

///|
/// Route one inbound frame: a response settles its pending request; a
/// notification goes to the handler. Anything else is a peer bug and is
/// dropped.
fn handle_message(
  session : RpcSession,
  event : @js.Value,
  on_notification : (String, Map[String, Json]) -> Unit,
) -> Unit {
  guard js_prop(event, "data") is Some(data) &&
    (@js.Cast::into(data) : String?) is Some(text) else {
    return
  }
  let envelope = @js.Value::from_json_string(text) catch { _ => return }
  if js_prop(envelope, "method") is Some(method_value) {
    guard (@js.Cast::into(method_value) : String?) is Some(method_) else {
      return
    }
    let params = match js_prop(envelope, "params") {
      Some(params) => params.to_json() catch { _ => return }
      None => Json::empty_object()
    }
    guard params is Object(fields) else { return }
    on_notification(method_, fields)
    return
  }
  guard js_prop(envelope, "id") is Some(id_value) &&
    (@js.Cast::into(id_value) : Int?) is Some(id) else {
    return
  }
  // A reply for a request this session no longer tracks (settled twice, or
  // raced a reconnect) has no one waiting.
  guard session.pending.get(id) is Some(deferred) else { return }
  session.pending.remove(id)
  match js_prop(envelope, "error") {
    Some(error_value) => {
      let message = match (error_value.to_json() catch { _ => Json::null() }) {
        { "message": String(message), .. } => message
        _ => "request failed"
      }
      // Mark a peer JSON-RPC error separately from a socket loss. Both reject
      // the same JS promise, but submission recovery must restore a draft only
      // when the host definitively answered this exact request.
      settle(deferred, "reject", js_error(message, rpc_rejection=true))
    }
    None => {
      let result = match js_prop(envelope, "result") {
        Some(result) => result
        // A result-less success settles as an empty reply, which
        // `reply_json_text` reads as `{}`.
        None => @js.Object::new().to_value()
      }
      settle(deferred, "resolve", result)
    }
  }
}

///|
/// Fail every in-flight request — the socket is gone; callers surface the
/// message wherever the op's error lands.
fn reject_all(session : RpcSession, message : String) -> Unit {
  for _, deferred in session.pending {
    settle(deferred, "reject", js_error(message, rpc_rejection=false))
  }
  session.pending.clear()
}

///|
fn settle(deferred : @js.Value, way : String, value : @js.Value) -> Unit {
  let _ : @js.Value = deferred.apply_with_string(way, [value])
}

///|
fn js_error(message : String, rpc_rejection~ : Bool) -> @js.Value {
  let ctor : @js.Value = @js.globalThis.get_with_string("Error")
  let error : @js.Value = ctor.new([message])
  if rpc_rejection {
    error.set_with_string("__openseek_rpc_rejection", true)
  }
  error
}

///|
/// `JSON.stringify(value)` — request payloads are plain data objects, so
/// the round trip through text is lossless.
fn json_text(value : @js.Value) -> String {
  let json : @js.Value = @js.globalThis.get_with_string("JSON")
  let text : @js.Value = json.apply_with_string("stringify", [value])
  match (@js.Cast::into(text) : String?) {
    Some(text) => text
    None => "{}"
  }
}

///|
test "synchronous send cleanup removes only its own pending resolver" {
  let socket = @js.Object::new().to_value()
  let original = @js.Object::new().to_value()
  let replacement = @js.Object::new().to_value()
  let session : RpcSession = {
    socket,
    pending: { 7: original },
    next_id: 8,
    open_: true,
  }
  remove_pending_if_same(session, 7, replacement)
  assert_true(session.pending.get(7) is Some(_))
  remove_pending_if_same(session, 7, original)
  assert_true(session.pending.get(7) is None)
}

///|
test "only marked browser RPC errors are definitive refusals" {
  let ctor : @js.Value = @js.globalThis.get_with_string("Error")
  let transport : @js.Value = ctor.new(["connection lost"])
  let rejected : @js.Value = ctor.new(["host refused"])
  rejected.set_with_string("__openseek_rpc_rejection", true)
  assert_false(browser_rpc_error_is_definite(transport))
  assert_true(browser_rpc_error_is_definite(rejected))
  assert_false(bridge_error_is_definite(BridgeError("bridge unavailable")))
}
