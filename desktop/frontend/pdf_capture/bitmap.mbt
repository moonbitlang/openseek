///|
priv struct CapturePiece {
  canvas : @js.Value
  annotations : Array[@js.Value]
  bounds : @selection.Rect
  crop : @selection.Rect
  page : Int32
  page_bounds : @selection.Rect
  viewport : @js.Value
  mut pdf_start : FixedArray[Double]?
  mut pdf_end : FixedArray[Double]?
}

///|
fn collect_pieces(
  host : @js.Value,
  session : @js.Value,
  rect : @selection.Rect,
  failure : String,
  unsupported : String,
) -> Result[Array[CapturePiece], String] {
  let pieces : Array[CapturePiece] = []
  let viewer : @js.Value = session.get_with_string("viewer")
  for page in browser_elements(host, ".pdfViewer .page") {
    let page_bounds = browser_bounds(page)
    if page_bounds.intersection(rect) is None {
      continue
    }
    let number = browser_page_number(page)
    let view : @js.Value = viewer.apply_with_string("getPageView", [number - 1])
    guard browser_query(page, ".canvasWrapper canvas") is Some(canvas) else {
      return Err(failure)
    }
    if browser_present(view) is None ||
      (view.get_with_string("renderingState") : Int32) != 3 {
      return Err(failure)
    }
    let bounds = browser_bounds(canvas)
    guard rect.intersection(bounds) is Some(crop) else { continue }
    if (canvas.get_with_string("width") : Double) <= 0 ||
      (canvas.get_with_string("height") : Double) <= 0 {
      continue
    }
    if has_unsupported_annotation(page, crop) {
      return Err(unsupported)
    }
    pieces.push({
      canvas,
      annotations: browser_elements(
        page, ".annotationLayer canvas, .annotationLayer img",
      ),
      bounds,
      crop,
      page: number,
      page_bounds,
      viewport: view.get_with_string("viewport"),
      pdf_start: None,
      pdf_end: None,
    })
  }
  if pieces.is_empty() {
    Err(failure)
  } else {
    Ok(pieces)
  }
}

///|
fn paint_annotations(
  ctx : @js.Value,
  piece : CapturePiece,
  destination : @selection.Rect,
  rect : @selection.Rect,
  scale : Double,
  failure : String,
) -> Result[Unit, String] {
  for bitmap in piece.annotations {
    let bounds = browser_bounds(bitmap)
    let style = browser_style(bitmap)
    if bounds.width == 0 ||
      bounds.height == 0 ||
      (style.get_with_string("visibility") : String) != "visible" {
      continue
    }
    if bounds.intersection(piece.crop) is None {
      continue
    }
    let image = @dom.HTMLImageElement::into(bitmap)
    let width : Double = bitmap.get_with_string(
      if image is Some(_) {
        "naturalWidth"
      } else {
        "width"
      },
    )
    let height : Double = bitmap.get_with_string(
      if image is Some(_) {
        "naturalHeight"
      } else {
        "height"
      },
    )
    if width == 0 || height == 0 {
      return Err(failure)
    }
    let transforms : Array[@selection.LayerTransform] = []
    let mut snap_image = image is Some(_)
    let mut ancestor = Some(bitmap)
    while ancestor is Some(node) {
      let css = browser_style(node)
      let transform : String = css.get_with_string("transform")
      if transform != "none" {
        snap_image = false
      }
      let matrix : @js.Value = if transform == "none" {
        @js.globalThis.new_with_string("DOMMatrix", ([] : FixedArray[String]))
      } else {
        @js.globalThis.new_with_string("DOMMatrix", [transform])
      }
      transforms.push({
        linear: {
          a: matrix.get_with_string("a"),
          b: matrix.get_with_string("b"),
          c: matrix.get_with_string("c"),
          d: matrix.get_with_string("d"),
        },
        opacity: browser_number(css.get_with_string("opacity")),
      })
      let parent : @js.Nullable[@js.Value] = node.get_with_string(
        "parentElement",
      )
      ancestor = parent.to_option()
    }
    let css_width : Double = @js.globalThis.apply_with_string("parseFloat", [
      (style.get_with_string("width") : String),
    ])
    let css_height : Double = @js.globalThis.apply_with_string("parseFloat", [
      (style.get_with_string("height") : String),
    ])
    // Chromium snaps an untransformed image's painted edges to CSS pixels.
    // Match that rectangle instead of stretching its SVG to fractional DOM
    // bounds, which shifts thin icon strokes in captures of a resized panel.
    let (bounds, css_width, css_height) = if snap_image {
      let x = @math.round(bounds.x)
      let y = @math.round(bounds.y)
      let width = @math.round(bounds.x + bounds.width) - x
      let height = @math.round(bounds.y + bounds.height) - y
      let snapped : @selection.Rect = { x, y, width, height, }
      (snapped, width, height)
    } else {
      (bounds, css_width, css_height)
    }
    let placement = @selection.bitmap_placement(
      transforms,
      bounds,
      { x: css_width, y: css_height, },
      { x: width, y: height, },
      rect,
      scale,
    )
    ctx.apply_with_string("save", ([] : FixedArray[@js.Value]))
    ctx.apply_with_string("beginPath", ([] : FixedArray[@js.Value]))
    ctx.apply_with_string("rect", [
      destination.x,
      destination.y,
      destination.width,
      destination.height,
    ])
    ctx.apply_with_string("clip", ([] : FixedArray[@js.Value]))
    ctx.set_with_string("globalAlpha", placement.opacity)
    ctx.set_with_string("filter", (style.get_with_string("filter") : String))
    ctx.apply_with_string("setTransform", [
      placement.linear.a,
      placement.linear.b,
      placement.linear.c,
      placement.linear.d,
      placement.origin.x,
      placement.origin.y,
    ])
    ctx.apply_with_string("drawImage", [
      bitmap,
      @js.Value::cast_from(0),
      @js.Value::cast_from(0),
    ])
    ctx.apply_with_string("restore", ([] : FixedArray[@js.Value]))
  }
  Ok(())
}

///|
fn render_capture(
  host : @js.Value,
  session : @js.Value,
  rect : @selection.Rect,
  text : String?,
  failure : String,
  too_large : String,
  unsupported : String,
) -> Result[Capture, String] {
  let pieces = match collect_pieces(host, session, rect, failure, unsupported) {
    Ok(pieces) => pieces
    Err(message) => return Err(message)
  }
  let densities : Array[Double] = []
  for piece in pieces {
    densities.push(
      (piece.canvas.get_with_string("width") : Double) / piece.bounds.width,
    )
    densities.push(
      (piece.canvas.get_with_string("height") : Double) / piece.bounds.height,
    )
  }
  guard @selection.output_size(rect, densities) is Some(size) else {
    return Err(too_large)
  }
  let output : @js.Value = browser_document().apply_with_string(
    "createElement",
    ["canvas"],
  )
  output.set_with_string("width", size.width)
  output.set_with_string("height", size.height)
  let context : @js.Nullable[@js.Value] = output.apply_with_string(
    "getContext",
    ["2d"],
  )
  guard context.to_option() is Some(ctx) else { return Err(failure) }
  ctx.set_with_string("fillStyle", "white")
  ctx.apply_with_string("fillRect", [0.0, 0.0, size.width, size.height])
  for piece in pieces {
    let source = piece.crop.mapped(from=piece.bounds, to={
      x: 0,
      y: 0,
      width: piece.canvas.get_with_string("width"),
      height: piece.canvas.get_with_string("height"),
    })
    let destination = piece.crop.mapped(from=rect, to={
      x: 0,
      y: 0,
      width: rect.width * size.scale,
      height: rect.height * size.scale,
    })
    let viewport = piece.crop.mapped(from=piece.bounds, to={
      x: 0,
      y: 0,
      width: piece.viewport.get_with_string("width"),
      height: piece.viewport.get_with_string("height"),
    })
    ctx.apply_with_string("drawImage", [
      piece.canvas,
      @js.Value::cast_from(source.x),
      @js.Value::cast_from(source.y),
      @js.Value::cast_from(source.width),
      @js.Value::cast_from(source.height),
      @js.Value::cast_from(destination.x),
      @js.Value::cast_from(destination.y),
      @js.Value::cast_from(destination.width),
      @js.Value::cast_from(destination.height),
    ])
    piece.pdf_start = Some(
      piece.viewport.apply_with_string("convertToPdfPoint", [
        viewport.x,
        viewport.y,
      ]),
    )
    piece.pdf_end = Some(
      piece.viewport.apply_with_string("convertToPdfPoint", [
        viewport.x + viewport.width,
        viewport.y + viewport.height,
      ]),
    )
    if paint_annotations(ctx, piece, destination, rect, size.scale, failure)
      is Err(message) {
      return Err(message)
    }
  }
  let url : String = output.apply_with_string("toDataURL", ["image/png"])
  let identity : @js.Value = session.get_with_string("identity")
  let document = identity.to_json_string() catch { _ => return Err(failure) }
  let viewer : @js.Value = session.get_with_string("viewer")
  finish_capture(
    url,
    document,
    pieces,
    viewer.get_with_string("pagesRotation"),
    text,
    failure~,
    too_large~,
  )
}
