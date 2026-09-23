// Browser capabilities not exposed by the current DOM bindings.

///|
/// WebSocket endpoint for the current page's native remote protocol server.
extern "js" fn protocol_websocket_url() -> String =
  #| () => {
  #|   const location = globalThis.location;
  #|   const protocol = location?.protocol === "https:" ? "wss:" : "ws:";
  #|   const host = location?.host || "127.0.0.1:5173";
  #|   return `${protocol}//${host}/protocol`;
  #| }

///|
/// Emits one harness/browser observability event.
extern "js" fn emit_host_event(name : String, payload : String) -> Unit =
  #| (name, payload) => {
  #|   if (typeof globalThis.__readonlyEditorEvent === "function") {
  #|     globalThis.__readonlyEditorEvent(name, payload);
  #|   }
  #| }

///|
extern "js" fn host_js_function(value : @js.Value) -> Bool = "value => typeof value === 'function'"
