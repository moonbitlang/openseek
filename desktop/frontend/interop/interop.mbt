// Shared helpers for talking to the page's JavaScript through rabbita's
// typed `@js` values. Native capabilities without an existing typed binding
// keep thin FFI declarations alongside their owning browser adapters.

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
/// `Promise.resolve(target[method](payload))`: one settled promise whether
/// the method returned a promise, returned a plain value, or threw
/// synchronously — the throw surfaces here as the raised error.
pub fn js_method_promise(
  target : @js.Value,
  name : String,
  payload : @js.Value,
) -> @js.Promise[@js.Value] raise @js.Error_ {
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
/// Preserve the original JS rejection value before the async runtime wraps it
/// in its opaque JsError. Bridge classification needs the host refusal marker.
async fn wait_bridge_promise(promise : @js.Promise[@js.Value]) -> @js.Value {
  let value = @js.Value::cast_from(promise)
  let settled : @js.Promise[Result[@js.Value, @js.Value]] = value.apply_with_string(
    "then",
    [(value : @js.Value) => Ok(value), (error : @js.Value) => Err(error)],
  )
  match settled.wait() {
    Ok(value) => value
    Err(error) => raise js_raised(error)
  }
}

///|
async test "bridge promises preserve fulfilled values" {
  let promise_ctor : @js.Value = @js.globalThis.get_with_string("Promise")
  let expected = @js.Object::new().to_value()
  let promise : @js.Promise[@js.Value] = promise_ctor.apply_with_string(
    "resolve",
    [expected],
  )
  assert_true(physical_equal(wait_bridge_promise(promise), expected))
}

///|
async test "bridge promise rejections preserve refusal markers and messages" {
  let promise_ctor : @js.Value = @js.globalThis.get_with_string("Promise")
  let error_constructor : @js.Value = @js.globalThis.get_with_string("Error")
  for refused in [false, true] {
    let original : @js.Value = error_constructor.new(["host refused"])
    if refused {
      original.set_with_string("__openseek_rpc_rejection", true)
    }
    let promise : @js.Promise[@js.Value] = promise_ctor.apply_with_string(
      "reject",
      [original],
    )
    let failure = try {
      ignore(wait_bridge_promise(promise))
      None
    } catch {
      error => Some(error)
    }
    guard failure is Some(error) else { fail("expected a rejected promise") }
    assert_eq(bridge_error_text(error), "host refused")
    let classified = ws_reply_failure(error)
    assert_eq(bridge_error_is_definite(classified), refused)
  }
}

///|
/// `window.innerWidth` in CSS pixels, `None` where there is no window (a
/// headless test runtime). Read once at startup to seed the narrow-layout
/// flag; later changes arrive through the resize subscription.
pub fn viewport_width() -> Int? {
  js_prop(@js.globalThis, "innerWidth").map(width => {
    let width : Double = width.cast()
    width.to_int()
  })
}

///|
/// Whether this page's native/browser window currently owns focus. A headless
/// runtime has no document and defaults to focused so model tests retain the
/// ordinary foreground behavior.
pub fn page_has_focus() -> Bool {
  guard js_prop(@js.globalThis, "document") is Some(document) &&
    js_prop(document, "hasFocus") is Some(_) else {
    return true
  }
  let focused : Bool = document.apply_with_string(
    "hasFocus",
    ([] : FixedArray[@js.Value]),
  )
  let hidden : Bool = js_prop(document, "hidden")
    .map(value => value.cast())
    .unwrap_or(false)
  focused && !hidden
}

///|
/// `Date.now()` in milliseconds. Only ever used for elapsed spans between two
/// readings taken by this page, so the clock's absolute correctness — and its
/// agreement with the host's — does not matter.
pub fn now_ms() -> Double {
  let date_constructor : @js.Value = @js.globalThis.get_with_string("Date")
  date_constructor.apply_with_string("now", ([] : FixedArray[@js.Value]))
}

///|
/// `globalThis.__MoonBit__` — the API object proton injects into its webview.
pub fn moonbit_bridge_root() -> @js.Value? {
  js_prop(@js.globalThis, "__MoonBit__")
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
