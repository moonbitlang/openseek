// Shared helpers for talking to the page's JavaScript through rabbita's
// typed `@js` values. Together with `@dom` they are the frontend's whole
// interop surface: no frontend package embeds raw JavaScript.

///|
/// `value[key]`, with JS `undefined` and `null` both folded to `None`.
pub fn js_prop(value : @js.Value, key : String) -> @js.Value? {
  let prop : @js.Value = value.get_with_string(key)
  if prop.is_undefined() || prop.is_null() {
    None
  } else {
    Some(prop)
  }
}

///|
/// `target.addEventListener(event_type, listener, { capture: true })`.
/// A capture-phase listener on the document sees events that do not bubble
/// (like scroll) and keeps working when a render replaces the elements the
/// events originate from.
pub fn add_capture_listener(
  target : @js.Value,
  event_type : String,
  listener : (@dom.Event) -> Unit,
) -> Unit {
  let options = @js.Object::new()
  options["capture"] = true
  let _ : @js.Value = target.apply_with_string("addEventListener", [
    @js.Value::cast_from(event_type),
    @js.Value::cast_from(listener),
    options.to_value(),
  ])
}

///|
/// `Promise.resolve(target[method](payload))`: one settled promise whether
/// the method returned a promise, returned a plain value, or threw
/// synchronously — the throw surfaces here as the raised error.
pub fn js_method_promise(
  target : @js.Value,
  name : String,
  payload : @js.Value,
) -> @js.Promise raise @js.Error_ {
  @js.Error_::wrap(
    () => {
      let reply : @js.Value = target.apply_with_string(name, [payload])
      let promise : @js.Value = @js.globalThis.get_with_string("Promise")
      promise.apply_with_string("resolve", [reply])
    },
    map_ok=@js.Value::cast,
  )
}

///|
/// `globalThis.__MoonBit__` — the API object lepus injects into its webview.
pub fn moonbit_bridge_root() -> @js.Value? {
  js_prop(@js.globalThis, "__MoonBit__")
}
