///|
fn start_mermaid_module_load(
  loader : MermaidModuleLoader,
  url : String,
  loaded : (MermaidApi) -> Unit,
  failed : () -> Unit,
) -> Unit {
  let promise : @js.Value = @js.globalThis.get_with_string("Promise")
  let start : @js.Value = promise.apply_with_string(
    "resolve",
    ([] : FixedArray[@js.Value]),
  )
  let begin : () -> @js.Value = () => @js.Value::cast_from(loader).apply([url])
  let pending : @js.Value = start.apply_with_string("then", [begin])
  let accept = (loaded_module : @js.Value) => {
    if loaded_module.is_null() || loaded_module.is_undefined() {
      failed()
      return
    }
    let api : @js.Value = loaded_module.get_with_string("default")
    if api.is_null() ||
      api.is_undefined() ||
      !is_js_function(api.get_with_string("initialize")) ||
      !is_js_function(api.get_with_string("render")) {
      failed()
    } else {
      loaded(api.cast())
    }
  }
  let _ : @js.Value = pending.apply_with_string("then", [
    @js.Value::cast_from(accept),
    @js.Value::cast_from(failed),
  ])
}

///|
/// Keep native Promise chaining so sync throws, render rejection and callback
/// failures settle the queue exactly once, with the original microtask ordering.
fn start_mermaid_api_render(
  mermaid : MermaidApi,
  theme : String,
  id : String,
  source : String,
  rendered : (MermaidRenderResult) -> Unit,
  failed : () -> Unit,
  settled : () -> Unit,
) -> Unit {
  let begin = () => {
    let options = @js.Object::new()
    options.set("startOnLoad", false)
    options.set("securityLevel", "strict")
    options.set("suppressErrorRendering", true)
    options.set("theme", theme)
    let secure : FixedArray[String] = [
      "secure", "securityLevel", "startOnLoad", "maxTextSize", "suppressErrorRendering",
      "maxEdges", "theme", "darkMode", "themeVariables", "themeCSS",
    ]
    options.set("secure", secure)
    let api = @js.Value::cast_from(mermaid)
    let _ : Unit = api.apply_with_string("initialize", [options.to_value()])
    let result : @js.Value = api.apply_with_string("render", [id, source])
    result
  }
  let promise : @js.Value = @js.globalThis.get_with_string("Promise")
  let start : @js.Value = promise.apply_with_string(
    "resolve",
    ([] : FixedArray[@js.Value]),
  )
  let pending : @js.Value = start.apply_with_string("then", [begin])
  let reported : @js.Value = pending.apply_with_string("then", [
    @js.Value::cast_from(rendered),
    @js.Value::cast_from(failed),
  ])
  let _ : @js.Value = reported.apply_with_string("then", [settled, settled])
}

///|
fn mermaid_id_is_available(
  owner_document : @rdom.Document,
  id : String,
) -> Bool {
  let global_document : @js.Nullable[@rdom.Document] = @js.globalThis.get_with_string(
    "document",
  )
  for candidate in [id, "d" + id, "i" + id] {
    if !document_id_is_available(owner_document, candidate) {
      return false
    }
  }
  if global_document.to_option() is Some(document) &&
    !same_document(owner_document, document) {
    for candidate in [id, "d" + id, "i" + id] {
      if !document_id_is_available(document, candidate) {
        return false
      }
    }
  }
  true
}

///|
fn new_mermaid_id_nonce() -> String {
  let crypto : @js.Nullable[@js.Value] = @js.globalThis.get_with_string(
    "crypto",
  )
  if crypto.to_option() is Some(crypto) {
    if is_js_function(crypto.get_with_string("randomUUID")) {
      return crypto.apply_with_string(
        "randomUUID",
        ([] : FixedArray[@js.Value]),
      )
    }
    if is_js_function(crypto.get_with_string("getRandomValues")) {
      let words : @js.Value = @js.globalThis.new_with_string("Uint32Array", [4])
      let words : @js.Value = crypto.apply_with_string("getRandomValues", [
        words,
      ])
      let array : @js.Value = @js.globalThis.get_with_string("Array")
      let words : FixedArray[@js.Value] = array.apply_with_string("from", [
        words,
      ])
      words
      .iter()
      .map(word => (word.apply_with_string("toString", [36]) : String))
      .join("-")
    } else {
      fallback_mermaid_nonce()
    }
  } else {
    fallback_mermaid_nonce()
  }
}

///|
fn fallback_mermaid_nonce() -> String {
  let date : @js.Value = @js.globalThis.get_with_string("Date")
  let now : @js.Value = date.apply_with_string(
    "now",
    ([] : FixedArray[@js.Value]),
  )
  let now : String = now.apply_with_string("toString", [36])
  let math : @js.Value = @js.globalThis.get_with_string("Math")
  let random : @js.Value = math.apply_with_string(
    "random",
    ([] : FixedArray[@js.Value]),
  )
  let random : @js.Value = random.apply_with_string("toString", [36])
  let suffix : String = random.apply_with_string("slice", [2])
  now + "-" + suffix
}
