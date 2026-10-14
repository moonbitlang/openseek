///|
/// Private browser ABI: only primitives, host objects, arrays and closures cross
/// FFI. Convert DOMRect and locally constructed snapshots to typed geometry here;
/// no MoonBit record representation is inspected by JavaScript.
fn read_rect(value : @js.Value) -> @selection.Rect {
  {
    x: value.get_with_string("x"),
    y: value.get_with_string("y"),
    width: value.get_with_string("width"),
    height: value.get_with_string("height"),
  }
}

///|
fn write_rect(rect : @selection.Rect) -> @js.Value {
  let value = @js.Object::new()
  value.set("x", rect.x)
  value.set("y", rect.y)
  value.set("width", rect.width)
  value.set("height", rect.height)
  value.to_value()
}

///|
fn read_point(value : @js.Value) -> @selection.Point {
  { x: value.get_with_string("x"), y: value.get_with_string("y"), }
}

///|
fn write_point(point : @selection.Point) -> @js.Value {
  let value = @js.Object::new()
  value.set("x", point.x)
  value.set("y", point.y)
  value.to_value()
}

///|
fn content_offset(
  bounds : @js.Value,
  container : @js.Value,
) -> @selection.Point {
  let b = read_rect(bounds)
  let left : Double = container.get_with_string("scrollLeft")
  let top : Double = container.get_with_string("scrollTop")
  { x: left - b.x, y: top - b.y, }
}

///|
fn content_rect(
  rect : @js.Value,
  bounds : @js.Value,
  container : @js.Value,
  inverse : Bool,
) -> @js.Value {
  let offset = content_offset(bounds, container)
  write_rect(
    read_rect(rect).translated(
      if inverse {
        { x: -offset.x, y: -offset.y, }
      } else {
        offset
      },
    ),
  )
}

///|
fn geometry_bridge() -> @js.Value {
  let api = @js.Object::new()
  api.set("viewport", (bounds : @js.Value, width : Double, height : Double) => {
    @js.Nullable::from_option(
      read_rect(bounds)
      .intersection({ x: 0, y: 0, width, height, })
      .map(write_rect),
    )
  })
  api.set("point", (
    event : @js.Value,
    bounds : @js.Value,
    viewport : @js.Value,
    container : @js.Value,
  ) => {
    let point = read_rect(viewport).clamp_point({
      x: event.get_with_string("clientX"),
      y: event.get_with_string("clientY"),
    })
    let offset = content_offset(bounds, container)
    write_point({ x: point.x + offset.x, y: point.y + offset.y, })
  })
  api.set("inViewport", (
    event : @js.Value,
    bounds : @js.Value,
    viewport : @js.Value,
    container : @js.Value,
  ) => {
    let b = read_rect(bounds)
    let client : @selection.Rect = {
      ..b,
      width: container.get_with_string("clientWidth"),
      height: container.get_with_string("clientHeight"),
    }
    client.intersection(read_rect(viewport)) is Some(rect) &&
    rect.contains(
      {
        x: event.get_with_string("clientX"),
        y: event.get_with_string("clientY"),
      },
      inclusive=false,
    )
  })
  api.set("contentRect", content_rect)
  api.set("paintRect", (
    rect : @js.Value,
    bounds : @js.Value,
    viewport : @js.Value,
    container : @js.Value,
  ) => {
    let screen = read_rect(content_rect(rect, bounds, container, true))
    let visible = read_rect(viewport)
    write_rect(screen.translated({ x: -visible.x, y: -visible.y, }))
  })
  api.set("selection", (start : @js.Value, end : @js.Value, selecting : Bool) => {
    @js.Nullable::from_option(
      @selection.drag_rect(read_point(start), read_point(end), selecting~).map(
        write_rect,
      ),
    )
  })
  api.set("intersect", (a : @js.Value, b : @js.Value) => {
    @js.Nullable::from_option(
      read_rect(a).intersection(read_rect(b)).map(write_rect),
    )
  })
  api.set("validCapture", (rect : @js.Value) => {
    let rect = read_rect(rect)
    rect.width >= 4 && rect.height >= 4
  })
  api.set("output", (rect : @js.Value, pieces : FixedArray[@js.Value]) => {
    let densities : Array[Double] = []
    for piece in pieces {
      let bounds = read_rect(piece.get_with_string("b"))
      let canvas : @js.Value = piece.get_with_string("canvas")
      let width : Double = canvas.get_with_string("width")
      let height : Double = canvas.get_with_string("height")
      densities.push(width / bounds.width)
      densities.push(height / bounds.height)
    }
    @js.Nullable::from_option(
      @selection.output_size(read_rect(rect), densities).map(output => {
        let value = @js.Object::new()
        value.set("scale", output.scale)
        value.set("width", output.width)
        value.set("height", output.height)
        value.to_value()
      }),
    )
  })
  api.set("drawing", (piece : @js.Value, rect : @js.Value, scale : Double) => {
    let crop = read_rect(piece)
    let bounds = read_rect(piece.get_with_string("b"))
    let selection = read_rect(rect)
    let canvas : @js.Value = piece.get_with_string("canvas")
    let viewport : @js.Value = piece.get_with_string("viewport")
    let value = @js.Object::new()
    value.set(
      "source",
      write_rect(
        crop.mapped(from=bounds, to={
          x: 0,
          y: 0,
          width: canvas.get_with_string("width"),
          height: canvas.get_with_string("height"),
        }),
      ),
    )
    value.set(
      "destination",
      write_rect(
        crop.mapped(from=selection, to={
          x: 0,
          y: 0,
          width: selection.width * scale,
          height: selection.height * scale,
        }),
      ),
    )
    value.set(
      "viewport",
      write_rect(
        crop.mapped(from=bounds, to={
          x: 0,
          y: 0,
          width: viewport.get_with_string("width"),
          height: viewport.get_with_string("height"),
        }),
      ),
    )
    value.to_value()
  })
  api.set("bitmap", (
    layers : FixedArray[@js.Value],
    bounds : @js.Value,
    css : @js.Value,
    pixels : @js.Value,
    rect : @js.Value,
    scale : Double,
  ) => {
    let transforms = layers
      .iter()
      .map(layer => {
        let matrix : @js.Value = layer.get_with_string("matrix")
        let transform : @selection.LayerTransform = {
          linear: {
            a: matrix.get_with_string("a"),
            b: matrix.get_with_string("b"),
            c: matrix.get_with_string("c"),
            d: matrix.get_with_string("d"),
          },
          opacity: layer.get_with_string("opacity"),
        }
        transform
      })
      .collect()
    let placement = @selection.bitmap_placement(
      transforms,
      read_rect(bounds),
      read_point(css),
      read_point(pixels),
      read_rect(rect),
      scale,
    )
    let value = @js.Object::new()
    value.set("opacity", placement.opacity)
    value.set("a", placement.linear.a)
    value.set("b", placement.linear.b)
    value.set("c", placement.linear.c)
    value.set("d", placement.linear.d)
    value.set("x", placement.origin.x)
    value.set("y", placement.origin.y)
    value.to_value()
  })
  api.to_value()
}
