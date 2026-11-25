// Browser bindings not yet exposed by Rabbita. Keep foreign definitions
// together, separate from application state and interaction policy.

///|
/// Browser preferences are read at startup and when a language is selected.
extern "js" fn browser_language_values() -> FixedArray[String] =
  #|() => typeof navigator === 'undefined' ? [] : Array.from(navigator.languages || [navigator.language]).filter(x => typeof x === 'string')

///|
extern "js" fn titlebar_overlay_classes(
  root : @dom.Element,
  visible : Bool,
  custom : Bool,
) -> Unit =
  #| (root, visible, custom) => {
  #|   root.classList.toggle('native-titlebar-overlay', visible);
  #|   root.classList.toggle('native-titlebar-custom', visible && custom);
  #| }

///|
// A synchronous bridge throw must become a rejected promise as well.
extern "js" fn read_titlebar_area(bridge : @js.Value) -> @js.Promise[@js.Value] = "async bridge => await bridge.getTitlebarArea()"

///|
extern "js" fn subscribe_titlebar_changes(
  bridge : @js.Value,
  refresh : () -> Unit,
) -> () -> Unit = "(bridge, refresh) => bridge.events.on('openseek.window.chrome_changed', refresh)"

///|
extern "js" fn subscribe_titlebar_dialogs(
  change : (Int32) -> Unit,
) -> () -> Unit =
  #| change => {
  #|   const selector = 'dialog[data-slot="dialog"]';
  #|   const modals = () => Array.from(document.querySelectorAll(selector + ':modal'));
  #|   let active = [];
  #|   // Removing an open dialog (or its parent) drops its backdrop without a
  #|   // closing beforetoggle. Only watch while there is a backdrop to lose.
  #|   const removals = new MutationObserver(() => {
  #|     if (active.some(dialog => !dialog.isConnected)) publish(modals());
  #|   });
  #|   function publish(next) {
  #|     if (!active.length && next.length) removals.observe(document, { childList: true, subtree: true });
  #|     if (!next.length) removals.disconnect();
  #|     active = next;
  #|     change(next.length);
  #|   }
  #|   const beforeToggle = event => {
  #|     if (!event.target.matches(selector)) return;
  #|     // SeekMoon opens these dialogs with showModal. Count the *next*
  #|     // set: beforetoggle runs before the target's :modal state changes.
  #|     const next = modals().filter(dialog => dialog !== event.target);
  #|     if (event.newState === 'open') next.push(event.target);
  #|     publish(next);
  #|   };
  #|   document.addEventListener('beforetoggle', beforeToggle, true);
  #|   publish(modals());
  #|   return () => {
  #|     removals.disconnect();
  #|     document.removeEventListener('beforetoggle', beforeToggle, true);
  #|   };
  #| }

///|
// Composite RUI's 50% black backdrop over a #rrggbb titlebar palette token.
extern "js" fn titlebar_dialog_color(color : String, depth : Int32) -> String =
  #| (color, depth) => color.replace(/[\da-f]{2}/gi, hex => {
  #|   let channel = parseInt(hex, 16);
  #|   for (let i = 0; i < depth; i++) channel = Math.round(channel * 127 / 255);
  #|   return channel.toString(16).padStart(2, '0');
  #| })

///|
extern "js" fn titlebar_error(message : String) -> Unit = "message => console.error(message)"

///|
extern "js" fn window_titlebar_overlay_visible() -> Bool =
  #| () => document.documentElement.classList.contains("native-titlebar-overlay")
