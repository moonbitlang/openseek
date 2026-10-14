///|
/// Browser primitives use Rabbita's existing JS interop. All branching and
/// resource ownership stays in MoonBit; there is no embedded JavaScript here.
fn browser_document() -> @js.Value {
  @js.globalThis.get_with_string("document")
}

///|
fn browser_query(parent : @js.Value, selector : String) -> @js.Value? {
  let result : @js.Nullable[@js.Value] = parent.apply_with_string(
    "querySelector",
    [selector],
  )
  result.to_option()
}

///|
fn browser_elements(parent : @js.Value, selector : String) -> Array[@js.Value] {
  let nodes : @js.Value = parent.apply_with_string("querySelectorAll", [
    selector,
  ])
  let length : Int32 = nodes.get_with_string("length")
  Array::makei(length, i => nodes.get_with_index(i))
}

///|
fn browser_bounds(element : @js.Value) -> @selection.Rect {
  read_rect(
    element.apply_with_string(
      "getBoundingClientRect",
      ([] : FixedArray[@js.Value]),
    ),
  )
}

///|
fn browser_same(a : @js.Value, b : @js.Value) -> Bool {
  let object : @js.Value = @js.globalThis.get_with_string("Object")
  object.apply_with_string("is", [a, b])
}

///|
fn browser_present(value : @js.Value) -> @js.Value? {
  if value.is_null() || value.is_undefined() {
    None
  } else {
    Some(value)
  }
}

///|
fn browser_style(element : @js.Value) -> @js.Value {
  @js.globalThis.apply_with_string("getComputedStyle", [element])
}

///|
fn browser_listen(
  target : @js.Value,
  name : String,
  callback : (@js.Value) -> Unit,
  signal : @js.Value,
  capture~ : Bool = false,
  once~ : Bool = false,
) -> Unit {
  let options = @js.Object::new()
  options.set("signal", signal)
  options.set("capture", capture)
  options.set("once", once)
  target.apply_with_string("addEventListener", [
    @js.Value::cast_from(name),
    @js.Value::cast_from(callback),
    options.to_value(),
  ])
}

///|
fn browser_stop(event : @js.Value) -> Unit {
  event.apply_with_string("preventDefault", ([] : FixedArray[@js.Value]))
  event.apply_with_string("stopPropagation", ([] : FixedArray[@js.Value]))
}

///|
fn browser_paint(element : @js.Value, rect : @selection.Rect) -> Unit {
  let style : @js.Value = element.get_with_string("style")
  style.set_with_string("left", "\{rect.x}px")
  style.set_with_string("top", "\{rect.y}px")
  style.set_with_string("width", "\{rect.width}px")
  style.set_with_string("height", "\{rect.height}px")
}

///|
fn read_rect(value : @js.Value) -> @selection.Rect {
  {
    x: value.get_with_string("x"),
    y: value.get_with_string("y"),
    width: value.get_with_string("width"),
    height: value.get_with_string("height"),
  }
}

///|
fn browser_number(value : @js.Value) -> Double {
  @js.globalThis.apply_with_string("Number", [value])
}

///|
fn browser_page_number(page : @js.Value) -> Int32 {
  let dataset : @js.Value = page.get_with_string("dataset")
  browser_number(dataset.get_with_string("pageNumber")).to_int()
}

///|
/// Catch native browser exceptions at the effect boundary, without moving
/// failure policy or the operation itself into a JavaScript closure.
fn browser_attempt(operation : () -> Unit) -> Bool {
  @js.Error_::wrap(
    () => {
      operation()
      @js.Value::cast_from(true)
    },
    map_ok=_ => true,
  ) catch {
    _ => false
  }
}
