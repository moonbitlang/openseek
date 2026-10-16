///|
fn document() -> @js.Value {
  @js.globalThis.get_with_string("document")
}

///|
fn query(host : @js.Value, selector : String) -> @js.Value? {
  let found : @js.Nullable[@js.Value] = host.apply_with_string(
    "querySelector",
    [selector],
  )
  found.to_option()
}

///|
fn elements(host : @js.Value, selector : String) -> Array[@js.Value] {
  let nodes : @js.Value = host.apply_with_string("querySelectorAll", [selector])
  let count : Int32 = nodes.get_with_string("length")
  Array::makei(count, index => nodes.get_with_index(index))
}

///|
fn bounds(node : @js.Value) -> Rect {
  let rect : @js.Value = node.apply_with_string(
    "getBoundingClientRect",
    ([] : FixedArray[@js.Value]),
  )
  {
    x: rect.get_with_string("x"),
    y: rect.get_with_string("y"),
    width: rect.get_with_string("width"),
    height: rect.get_with_string("height"),
  }
}

///|
fn attribute(node : @js.Value, name : String) -> String? {
  let value : @js.Nullable[String] = node.apply_with_string("getAttribute", [
    name,
  ])
  value.to_option()
}

///|
fn paint(node : @js.Value, rect : Rect) -> Unit {
  let style : @js.Value = node.get_with_string("style")
  style.set_with_string("left", "\{rect.x}px")
  style.set_with_string("top", "\{rect.y}px")
  style.set_with_string("width", "\{rect.width}px")
  style.set_with_string("height", "\{rect.height}px")
}

///|
fn stop(event : @js.Value) -> Unit {
  event.apply_with_string("preventDefault", ([] : FixedArray[@js.Value]))
  event.apply_with_string("stopPropagation", ([] : FixedArray[@js.Value]))
}

///|
fn attempt(operation : () -> Unit) -> Bool {
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

///|
fn excerpt(value : String) -> String {
  let out = StringBuilder()
  let mut count = 0
  for ch in value.iter() {
    if count >= 4000 {
      break
    }
    out.write_char(ch)
    count += 1
  }
  out.to_string().trim().to_owned()
}
