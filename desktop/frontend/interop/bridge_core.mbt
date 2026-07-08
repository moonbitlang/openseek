// The engine-host bridge's calling core: locate the API object proton
// injects, call one op, and normalize failures and replies. Shared by every
// frontend package that talks to the host (the main package's engine/session
// commands, the file editor's fs ops), so it lives beside the raw JS helpers
// rather than in any one feature package.

///|
priv suberror BridgeError {
  BridgeError(String)
}

///|
/// `globalThis.__MoonBit__.openseek`, once the proton bridge is injected.
pub fn openseek_api() -> @js.Value? {
  guard moonbit_bridge_root() is Some(root) else { return None }
  js_prop(root, "openseek")
}

///|
/// Call one engine-host op and wait for its reply. Raises when the bridge
/// is missing, the call throws, or the op rejects.
pub async fn bridge_request(op : String, payload : @js.Value) -> @js.Value {
  guard openseek_api() is Some(api) && js_prop(api, op) is Some(_) else {
    raise BridgeError("OpenSeek bridge unavailable")
  }
  js_method_promise(api, op, payload).wait()
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
