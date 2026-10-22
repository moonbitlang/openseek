// Where an element is on screen, and the input a person would give it.
// Coordinates are CSS pixels from the top left of the page's viewport.

///|
pub(all) struct Point {
  x : Double
  y : Double
} derive(Debug, Eq)

///|
/// Scroll the page, as little as it takes, until `node` is in view.
pub async fn Connection::scroll_into_view(
  self : Connection,
  node : BackendNodeId,
) -> Unit {
  empty_result(
    self.request("DOM.scrollIntoViewIfNeeded", { "backendNodeId": Json(node.0) }),
  )
}

///|
fn decode_quads(json : Json) -> Array[Array[Point]] raise {
  let quads : Array[Array[Double]] = required(json, "quads")
  quads.map(quad => {
    guard quad.length() == 8 else {
      raise Protocol("Expected a quad of four points")
    }
    [
      for i in 0..<4 => { x: quad[2 * i], y: quad[2 * i + 1], }
    ]
  })
}

///|
/// The boxes `node`'s content occupies in the viewport, each as its four
/// corners: one for most elements, one per line for text that wraps, none
/// for an element that is not rendered.
pub async fn Connection::content_quads(
  self : Connection,
  node : BackendNodeId,
) -> Array[Array[Point]] {
  decode_quads(
    self.request("DOM.getContentQuads", { "backendNodeId": Json(node.0) }),
  )
}

///|
/// The size of the viewport, the area of the page on screen, in CSS pixels.
pub async fn Connection::viewport_size(self : Connection) -> (Double, Double) {
  let metrics = self.request("Page.getLayoutMetrics", {})
  let viewport : Json = required(metrics, "cssLayoutViewport")
  (required(viewport, "clientWidth"), required(viewport, "clientHeight"))
}

///|
pub(all) enum MouseAction {
  Move
  Press
  Release
}

///|
/// One event of the mouse's primary button at `at`. A press or release is
/// one click.
pub(all) struct MouseEvent {
  action : MouseAction
  at : Point
}

///|
impl ToJson for MouseEvent with fn to_json(self) {
  let (kind, button, buttons) = match self.action {
    Move => ("mouseMoved", "none", 0)
    // `buttons` is which buttons are down once the event has happened.
    Press => ("mousePressed", "left", 1)
    Release => ("mouseReleased", "left", 0)
  }
  {
    "type": Json(kind),
    "x": Json(self.at.x),
    "y": Json(self.at.y),
    "button": Json(button),
    "buttons": Json(buttons),
    "clickCount": Json(if self.action is Move { 0 } else { 1 }),
  }
}

///|
pub async fn Connection::dispatch_mouse_event(
  self : Connection,
  event : MouseEvent,
) -> Unit {
  empty_result(self.request("Input.dispatchMouseEvent", ToJson::to_json(event)))
}

///|
/// A key on the keyboard, as `Input.dispatchKeyEvent` names it.
pub(all) enum Key {
  Enter
  Backspace
}

///|
pub(all) enum KeyAction {
  Down
  Up
}

///|
pub(all) struct KeyEvent {
  action : KeyAction
  key : Key
}

///|
impl ToJson for KeyEvent with fn to_json(self) {
  let (name, code, text) = match self.key {
    Enter => ("Enter", 13, Some("\r"))
    Backspace => ("Backspace", 8, None)
  }
  // The platform's own key code is left for the browser to derive: it is
  // not the same number on every platform (8 is Backspace on Windows and
  // the C key on macOS).
  let event : Map[String, Json] = {
    "key": Json(name),
    "code": Json(name),
    "windowsVirtualKeyCode": Json(code),
  }
  match (self.action, text) {
    // A key that types a character says so as it goes down; one that does
    // not goes down raw, or the browser would type the character for it.
    (Down, Some(text)) => {
      event["type"] = "keyDown"
      event["text"] = Json(text)
    }
    (Down, None) => event["type"] = "rawKeyDown"
    (Up, _) => event["type"] = "keyUp"
  }
  // On macOS the editing a key does comes from the system as a command,
  // which a synthetic key does not carry unless it names one. Deleting
  // backward once more where there is nothing left to delete does nothing.
  if self is { action: Down, key: Backspace, } {
    event["commands"] = ["deleteBackward"]
  }
  Json::object(event)
}

///|
pub async fn Connection::dispatch_key_event(
  self : Connection,
  event : KeyEvent,
) -> Unit {
  empty_result(self.request("Input.dispatchKeyEvent", ToJson::to_json(event)))
}

///|
/// Type `text` into whatever has focus, as an input method would, replacing
/// the selection.
pub async fn Connection::insert_text(self : Connection, text : String) -> Unit {
  empty_result(self.request("Input.insertText", { "text": Json(text) }))
}

///|
pub extend Point with Debug::{to_repr}

///|
pub extend Point with Eq::{equal, not_equal}
