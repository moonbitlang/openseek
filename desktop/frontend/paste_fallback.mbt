// Cmd/Ctrl+V fallback for the lepus webview, where the platform paste
// action can be missing: the shortcut reads text through the host's
// clipboard extension (`__MoonBit__.clipboard`) and splices it into the
// focused input or textarea.

///|
let clipboard_paste_installed : Ref[Bool] = Ref(false)

///|
fn install_clipboard_paste_bridge() -> @cmd.Cmd {
  @cmd.custom_cmd(_ => {
    guard !clipboard_paste_installed.val else { return }
    clipboard_paste_installed.val = true
    add_capture_listener(
      @js.Cast::from(@dom.document()),
      "keydown",
      handle_paste_shortcut,
    )
  })
}

///|
fn handle_paste_shortcut(event : @dom.Event) -> Unit {
  guard event.to_keyboard_event() is Some(key) else { return }
  guard (key.key() == "v" || key.key() == "V") &&
    !key.alt_key() &&
    (key.meta_key() || key.ctrl_key()) else {
    return
  }
  guard editable_paste_target(event.target()) is Some(target) else { return }
  guard clipboard_read_api() is Some(clipboard) else { return }
  event.prevent_default()
  @js.async_run(() => {
    paste_from_clipboard(clipboard, target) catch {
      // The shortcut was already consumed; all that is left of a failed read
      // or splice is a diagnostic.
      error => println("OpenSeek clipboard paste fallback failed: \{error}")
    }
  })
}

///|
/// The host's clipboard extension, when its text read is available.
fn clipboard_read_api() -> @js.Value? {
  guard moonbit_bridge_root() is Some(root) else { return None }
  guard js_prop(root, "clipboard") is Some(clipboard) else { return None }
  guard js_prop(clipboard, "readText") is Some(_) else { return None }
  Some(clipboard)
}

///|
async fn paste_from_clipboard(
  clipboard : @js.Value,
  target : @js.Value,
) -> Unit {
  let reply = js_method_promise(
    clipboard,
    "readText",
    @js.Object::new().to_value(),
  ).wait()
  let text = match js_prop(reply, "text") {
    Some(value) =>
      match (@js.Cast::into(value) : String?) {
        Some(text) => text
        None => ""
      }
    None => ""
  }
  if !text.is_empty() {
    insert_paste_text(target, text)
  }
}

///|
/// The keydown target as a text-editable control: a `<textarea>`, or an
/// `<input>` whose type takes free text. Read-only and disabled controls
/// are excluded. Returns the raw JS element because the splice needs the
/// selection and value APIs `@dom` does not type.
fn editable_paste_target(target : @dom.EventTarget) -> @js.Value? {
  guard target.to_element() is Some(element) else { return None }
  let value : @js.Value = @js.Cast::from(element)
  let editable = match element.get_node_name() {
    "TEXTAREA" => true
    "INPUT" =>
      match input_type(value) {
        "email" | "number" | "password" | "search" | "tel" | "text" | "url" =>
          true
        _ => false
      }
    _ => false
  }
  guard editable else { return None }
  let read_only : Bool = value.get_with_string("readOnly")
  let disabled : Bool = value.get_with_string("disabled")
  if read_only || disabled {
    None
  } else {
    Some(value)
  }
}

///|
fn input_type(input : @js.Value) -> String {
  match js_prop(input, "type") {
    Some(value) =>
      match (@js.Cast::into(value) : String?) {
        Some(kind) => kind.to_lower()
        None => "text"
      }
    None => "text"
  }
}

///|
/// Splice `text` over the control's selection, collapsing the caret to its
/// end, and fire the `insertFromPaste` input event so Rabbita's `oninput`
/// handlers see the change. Every webview lepus embeds has `setRangeText`
/// and `InputEvent`; a control that still rejects the splice (selection
/// APIs are undefined on some input types) surfaces here as the raised
/// error.
fn insert_paste_text(
  target : @js.Value,
  text : String,
) -> Unit raise @js.Error_ {
  @js.Error_::wrap(
    fn() {
      let value : String = target.get_with_string("value")
      let start = selection_index(target, "selectionStart", value.length())
      let end = selection_index(target, "selectionEnd", start)
      let _ : @js.Value = target.apply_with_string("setRangeText", [
        @js.Value::cast_from(text),
        @js.Value::cast_from(start),
        @js.Value::cast_from(end),
        @js.Value::cast_from("end"),
      ])
      let init = @js.Object::new()
      init["bubbles"] = true
      init["cancelable"] = true
      init["inputType"] = "insertFromPaste"
      init["data"] = text
      let input_event_constructor : @js.Value = @js.globalThis.get_with_string(
        "InputEvent",
      )
      let input_event : @js.Value = input_event_constructor.new([
        @js.Value::cast_from("input"),
        init.to_value(),
      ])
      target.apply_with_string("dispatchEvent", [input_event])
    },
    map_ok=_ => (),
  )
}

///|
/// `selectionStart`/`selectionEnd`, which are numbers on text controls but
/// `null` on input types without selection support.
fn selection_index(target : @js.Value, key : String, fallback : Int) -> Int {
  guard js_prop(target, key) is Some(value) else { return fallback }
  match (@js.Cast::into(value) : Int?) {
    Some(index) => index
    None => fallback
  }
}
