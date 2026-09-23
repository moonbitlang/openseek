// Browser bindings not yet exposed by Rabbita. Keep foreign definitions
// together, separate from application state and interaction policy.

///|
extern "js" fn js_fetch(
  url : String,
  method_ : String,
  has_body : Bool,
  body : String,
  on_done : (Int, String) -> Unit,
  on_fail : (String) -> Unit,
) =
  #| (url, method, hasBody, body, onDone, onFail) => {
  #|   const config = { method };
  #|   if (hasBody) {
  #|     config.headers = { "Content-Type": "application/json" };
  #|     config.body = body;
  #|   }
  #|   fetch(url, config)
  #|     .then((response) => response.text().then((text) => onDone(response.status, text)))
  #|     .catch((error) => onFail(String(error)));
  #| }

///|
extern "js" fn open_link_in_browser(url : String) -> Unit =
  #| (url) => {
  #|   let parsed;
  #|   try { parsed = new URL(url, document.baseURI); } catch (_) { return; }
  #|   if (parsed.protocol === "mailto:") {
  #|     const anchor = document.createElement("a");
  #|     anchor.href = parsed.href;
  #|     anchor.click();
  #|     return;
  #|   }
  #|   if (parsed.protocol !== "http:" && parsed.protocol !== "https:") return;
  #|   const anchor = document.createElement("a");
  #|   anchor.href = parsed.href;
  #|   anchor.target = "_blank";
  #|   anchor.rel = "noopener noreferrer";
  #|   anchor.click();
  #| }

///|
/// Browser preferences are read at startup and when a language is selected.
extern "js" fn browser_language_values() -> FixedArray[String] =
  #|() => typeof navigator === 'undefined' ? [] : Array.from(navigator.languages || [navigator.language]).filter(x => typeof x === 'string')

///|
extern "js" fn language_storage() -> @js.Value =
  #|() => { const storage = globalThis.localStorage; if (!storage) throw new Error('Language preference storage is unavailable'); return storage; }

///|
extern "js" fn titlebar_overlay_class(
  root : @dom.Element,
  visible : Bool,
) -> Unit = "(root, visible) => root.classList.toggle('native-titlebar-overlay', visible)"

///|
// A synchronous bridge throw must become a rejected promise as well.
extern "js" fn read_titlebar_area(bridge : @js.Value) -> @js.Promise[@js.Value] = "async bridge => await bridge.getTitlebarArea()"

///|
extern "js" fn subscribe_titlebar_changes(
  bridge : @js.Value,
  refresh : () -> Unit,
) -> () -> Unit = "(bridge, refresh) => bridge.events.on('openseek.window.chrome_changed', refresh)"

///|
extern "js" fn titlebar_error(message : String) -> Unit = "message => console.error(message)"

///|
extern "js" fn window_titlebar_overlay_visible() -> Bool =
  #| () => document.documentElement.classList.contains("native-titlebar-overlay")
