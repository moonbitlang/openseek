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
  on_notification~ : (@protocol.Notification) -> Unit,
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
    reject_all(session, "SeekMoon connection lost")
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
  reject_all(session, "SeekMoon connection closed")
  let _ : @js.Value = session.socket.apply_with_string(
    "close",
    ([] : FixedArray[@js.Value]),
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
    raise BridgeUnsent("SeekMoon connection is down")
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
  // A caller-side timeout cancels the waiter while the socket can remain
  // healthy. Retire that resolver on every exit so a peer's eventual late
  // reply cannot leak the pending table or settle an abandoned task.
  defer remove_pending_if_same(session, id, deferred)
  @js.Error_::wrap(
    () => session.socket.apply_with_string("send", [@js.Value::cast_from(text)]),
    map_ok=_ => (),
  ) catch {
    error => {
      // `send` can throw synchronously after insertion but before a promise
      // waiter exists. Remove only our still-current resolver: an exotic
      // synchronous response may already have settled/replaced this id.
      remove_pending_if_same(session, id, deferred)
      // Nothing was transmitted — `send` throws before it queues anything —
      // so this is a call that never left, not an unknown outcome.
      raise BridgeUnsent(bridge_error_text(error))
    }
  }
  let promise : @js.Promise = @js.Value::cast(
    (deferred.get_with_string("promise") : @js.Value),
  )
  promise.wait() catch {
    error => raise ws_reply_failure(error)
  }
}

///|
/// How a rejected reply is reported. `handle_message` marks a peer's own
/// JSON-RPC error; `reject_all` does not, because a socket that dies under an
/// in-flight request is not an answer to it. Name that difference here rather
/// than leaving it to be re-derived downstream from ambient state: a proton
/// page drives remote channels too, so "this page has an embedded host" says
/// nothing about a request that went out over a socket.
fn ws_reply_failure(error : Error) -> Error {
  guard error is @js.Error_(value) && browser_rpc_error_is_definite(value) else {
    return BridgeError(bridge_error_text(error))
  }
  error
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
  on_notification : (@protocol.Notification) -> Unit,
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
    guard params is Object(_) else { return }
    guard @protocol.Notification::from_wire(method_, params)
      is Some(notification) else {
      return
    }
    on_notification(notification)
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
        // A result-less success settles as an empty object, which the typed
        // response adapter decodes for acknowledgement-only methods.
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

///|
/// Throw a JS value — test-only. `@js.Error_` is read-only, so the error a
/// rejected promise raises can only be obtained by producing one for real.
extern "js" fn js_throw(value : @js.Value) -> @js.Value =
  #| (value) => { throw value; }

///|
fn js_raised(value : @js.Value) -> Error {
  @js.Error_::wrap(() => js_throw(value), map_ok=_ => ()) catch {
    error => return error
  }
  BridgeError("nothing was thrown")
}

///|
test "a socket that dies under a sent request is not a refusal" {
  // `reject_all` rejects with an unmarked error, and the classifier's "this
  // page has an embedded host" shortcut would otherwise read that as the
  // host's own answer — a proton page drives remote channels too, and under
  // that reading a lost socket would hand a goal's draft back while the
  // remote host still commits its marker.
  //
  // The shortcut only fires on a page that *has* an embedded host, so stand
  // one up: without it this passes whether or not the transport names its own
  // failures, and proves nothing.
  let previous : @js.Value = @js.globalThis.get_with_string("__MoonBit__")
  let root = @js.Object::new()
  root["openseek"] = @js.Object::new().to_value()
  @js.globalThis.set_with_string("__MoonBit__", root.to_value())
  defer @js.globalThis.set_with_string("__MoonBit__", previous)
  assert_true(openseek_api() is Some(_))
  let lost = ws_reply_failure(
    js_raised(js_error("SeekMoon connection lost", rpc_rejection=false)),
  )
  assert_true(bridge_failure(lost) is Unknown)
  // A peer's own JSON-RPC error is the one remote failure that *is* an
  // answer, and it stays one.
  let refused = ws_reply_failure(
    js_raised(js_error("host refused", rpc_rejection=true)),
  )
  assert_true(bridge_failure(refused) is Refused)
}

///|
test "a call that never left is not the same as one that went unanswered" {
  // The distinction callers actually need. Both are "not a refusal", so the
  // two-state view says the same thing about them — and a caller holding
  // optimistic state then has to keep waiting on a command that provably
  // never reached anything.
  assert_true(
    bridge_failure(BridgeUnsent("SeekMoon bridge unavailable")) is Unsent,
  )
  assert_true(
    bridge_failure(BridgeUnsent("SeekMoon connection is down")) is Unsent,
  )
  // A reply that arrived and could not be decoded went out: the host acted,
  // and it is its answer that was lost.
  assert_true(
    bridge_failure(BridgeError("Malformed reply from agent.goal")) is Unknown,
  )
  // Neither is a refusal, which is what keeps the start and steer paths
  // behaving exactly as before.
  for
    error in [
      BridgeUnsent("SeekMoon bridge unavailable"),
      BridgeError("Malformed reply from agent.goal"),
    ] {
    assert_false(bridge_error_is_definite(error))
  }
}
