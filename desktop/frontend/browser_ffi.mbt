// Browser bindings not yet exposed by Rabbita. Keep foreign definitions
// together, separate from application state and interaction policy.

///|
/// Browser preferences are read at startup and when a language is selected.
extern "js" fn browser_language_values() -> FixedArray[String] =
  #|() => typeof navigator === 'undefined' ? [] : Array.from(navigator.languages || [navigator.language]).filter(x => typeof x === 'string')

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
