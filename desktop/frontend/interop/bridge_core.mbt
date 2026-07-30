// The engine-host calling core: one `bridge_request` for every frontend
// package that talks to a host, routed by channel. `Local` is the desktop
// window's injected `__MoonBit__.openseek` op; `Remote(id)` is currently a
// relay device reached over its WebSocket (docs/remote-protocol.md). The method
// names and payloads are identical either way — callers and reply decoders
// cannot tell the transports apart.

///|
priv suberror BridgeError {
  BridgeError(String)
}

///|
impl Show for BridgeError with fn output(self, logger) {
  match self {
    BridgeError(message) => logger.write_string(message)
  }
}

///|
/// Whether this page is the desktop webview (served from `proton://app/`,
/// where the `__MoonBit__` bridge is injected) as opposed to a browser.
pub fn using_proton_bridge() -> Bool {
  guard js_prop(@js.globalThis, "location") is Some(location) else {
    return false
  }
  (@js.Cast::into((location.get_with_string("protocol") : @js.Value)) : String?)
  is Some("proton:")
}

///|
/// `globalThis.__MoonBit__.openseek`, once the proton bridge is injected.
pub fn openseek_api() -> @js.Value? {
  guard moonbit_bridge_root() is Some(root) else { return None }
  js_prop(root, "openseek")
}

///|
/// Call one engine-host method on a channel and wait for its reply. Raises
/// when the transport is missing/down, the call throws, or the host rejects
/// the method.
pub async fn bridge_request(
  channel : ChannelId,
  op : String,
  payload : @js.Value,
) -> @js.Value {
  match channel {
    Local => {
      guard openseek_api() is Some(api) && js_prop(api, op) is Some(_) else {
        raise BridgeError("OpenSeek bridge unavailable")
      }
      js_method_promise(api, op, payload).wait()
    }
    Remote(_) => ws_request(channel, op, payload)
  }
}

///|
/// Invoke Proton methods through one promise tail. Proton dispatches bridge
/// requests in separate native tasks, so two fire-and-forget calls may enter
/// the host in the opposite order unless the page waits for the first before
/// issuing the second. The rejected request still releases the tail; its own
/// promise remains rejected for the MoonBit caller.
extern "js" fn js_ordered_method_promise(
  target : @js.Value,
  name : String,
  payload : @js.Value,
) -> @js.Promise =
  #| (() => {
  #|   let tail = Promise.resolve();
  #|   return (target, name, payload) => {
  #|     const request = tail
  #|       .catch(() => undefined)
  #|       .then(() => target[name](payload));
  #|     tail = request.catch(() => undefined);
  #|     return request;
  #|   };
  #| })()

///|
/// Call one host method in the page's issue order. The file-panel watcher is
/// the only current user: `watch(A)` followed by `unwatch` is desired state,
/// not two independent queries, so Proton must not reorder their entry into
/// the connection's actor. Remote requests use the same call site; their
/// socket reader additionally preserves these two methods' wire order.
pub async fn bridge_request_in_order(
  channel : ChannelId,
  op : String,
  payload : @js.Value,
) -> @js.Value {
  match channel {
    Local => {
      guard openseek_api() is Some(api) && js_prop(api, op) is Some(_) else {
        raise BridgeError("OpenSeek bridge unavailable")
      }
      js_ordered_method_promise(api, op, payload).wait()
    }
    Remote(_) => ws_request(channel, op, payload)
  }
}

///|
/// A user-facing message for a failed bridge call, preferring the JS
/// error's `message` over its stringified form.
pub fn bridge_error_text(error : Error) -> String {
  match error {
    BridgeError(message) => message
    @js.Error_(value) =>
      if js_prop(value, "message") is Some(message) &&
        (@js.Cast::into(message) : String?) is Some(text) &&
        !text.is_empty() {
        text
      } else {
        value.to_string()
      }
    _ => "\{error}"
  }
}

///|
/// Whether a failed bridge call is a definitive host refusal. Browser
/// JSON-RPC errors carry a marker set by the response decoder; socket close /
/// down errors do not. In the embedded proton bridge, a present method's
/// rejected promise is the direct host answer, while a missing bridge is the
/// separate ambiguous `BridgeError` case.
pub fn bridge_error_is_definite(error : Error) -> Bool {
  match error {
    BridgeError(_) => false
    @js.Error_(value) =>
      using_proton_bridge() || browser_rpc_error_is_definite(value)
    _ => false
  }
}

///|
fn browser_rpc_error_is_definite(value : @js.Value) -> Bool {
  js_prop(value, "__openseek_rpc_rejection") is Some(marker) &&
  (@js.Cast::into(marker) : Bool?) is Some(true)
}

///|
/// The op reply as JSON text for the reply decoders. A reply of
/// `undefined`/`null` (an op that returned nothing) reads as the empty
/// object; an unserializable reply reads as malformed input.
pub fn reply_json_text(reply : @js.Value) -> String {
  if reply.is_undefined() || reply.is_null() {
    return "{}"
  }
  reply.to_json_string() catch {
    _ => ""
  }
}

///|
/// Set `payload[key]` to the trimmed `value`, omitting it entirely when
/// blank — the host documents that a present field always carries
/// non-blank text.
pub fn set_trimmed(payload : @js.Object, key : String, value : String) -> Unit {
  let text = value.trim().to_owned()
  if !text.is_empty() {
    payload[key] = text
  }
}

///|
/// Attach the workspace hint to an op payload, when the conversation has one.
pub fn set_workspace(
  payload : @js.Object,
  workspace : @pathx.Absolute?,
) -> Unit {
  if workspace is Some(workspace) {
    set_trimmed(payload, "workspace", workspace.0)
  }
}
