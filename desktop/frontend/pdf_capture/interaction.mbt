///|
priv struct CapturePointer {
  position : @selection.Point
  id : Int32
}

///|
priv struct CaptureDrag {
  start : @selection.Point
  pointer_id : Int32
  target : @selection.Target?
  selecting : Bool
}

///|
priv enum CapturePhase {
  Hovering
  Dragging(CaptureDrag)
  Disposed
}

///|
/// Mutable state is confined to this command-owned browser session. It never
/// enters the Rabbita model and never crosses a JavaScript ABI boundary.
priv struct CaptureSession {
  host : @js.Value
  pdf : @js.Value
  container : @js.Value
  overlay : @js.Value
  box : @js.Value
  abort : @js.Value
  bounds : @selection.Rect
  viewport : @selection.Rect
  cache : TargetCache
  cleanups : Array[() -> Unit]
  mut phase : CapturePhase
  mut pointer : CapturePointer?
  failure : String
  too_large : String
  unsupported : String
  completed : (Result[Capture, String]) -> Unit
}

///|
fn CaptureSession::dispose(self : CaptureSession) -> Unit {
  if self.phase is Disposed {
    return
  }
  self.phase = Disposed
  self.abort.apply_with_string("abort", ([] : FixedArray[@js.Value]))
  self.cache.alive = false
  self.cache.pages.clear()
  for cleanup in self.cleanups {
    cleanup()
  }
  self.cleanups.clear()
  self.overlay.apply_with_string("remove", ([] : FixedArray[@js.Value]))
  let classes : @js.Value = self.container.get_with_string("classList")
  classes.apply_with_string("remove", ["pdf-region-capturing"])
  let reflect : @js.Value = @js.globalThis.get_with_string("Reflect")
  ignore(
    (
      reflect.apply_with_string("deleteProperty", [
        self.host,
        @js.Value::cast_from("__pdfRegionCapture"),
      ]) : Bool),
  )
}

///|
fn CaptureSession::listen(
  self : CaptureSession,
  target : @js.Value,
  name : String,
  callback : (@js.Value) -> Unit,
  capture~ : Bool = false,
) -> Unit {
  browser_listen(
    target,
    name,
    callback,
    self.abort.get_with_string("signal"),
    capture~,
  )
}

///|
fn CaptureSession::offset(self : CaptureSession) -> @selection.Point {
  {
    x: (self.container.get_with_string("scrollLeft") : Double) - self.bounds.x,
    y: (self.container.get_with_string("scrollTop") : Double) - self.bounds.y,
  }
}

///|
fn CaptureSession::point(
  self : CaptureSession,
  pointer : CapturePointer,
) -> @selection.Point {
  let point = self.viewport.clamp_point(pointer.position)
  let offset = self.offset()
  { x: point.x + offset.x, y: point.y + offset.y, }
}

///|
fn CaptureSession::contains(
  self : CaptureSession,
  pointer : CapturePointer,
) -> Bool {
  let client : @selection.Rect = {
    ..self.bounds,
    width: self.container.get_with_string("clientWidth"),
    height: self.container.get_with_string("clientHeight"),
  }
  client.intersection(self.viewport) is Some(rect) &&
  rect.contains(pointer.position, inclusive=false)
}

///|
fn CaptureSession::paint(
  self : CaptureSession,
  rect : @selection.Rect,
  kind : String,
) -> Unit {
  let offset = self.offset()
  browser_paint(
    self.box,
    rect.translated({
      x: -offset.x - self.viewport.x,
      y: -offset.y - self.viewport.y,
    }),
  )
  self.box.set_with_string("hidden", false)
  let dataset : @js.Value = self.box.get_with_string("dataset")
  dataset.set_with_string("selectionKind", kind)
}

///|
fn CaptureSession::target(
  self : CaptureSession,
  pointer : CapturePointer,
) -> @selection.Target? {
  self.cache.at(pointer.position.x, pointer.position.y, () => self.hover())
}

///|
fn CaptureSession::hover(self : CaptureSession) -> Unit {
  guard self.phase is Hovering else { return }
  if self.pointer is Some(pointer) &&
    self.contains(pointer) &&
    self.target(pointer) is Some(target) {
    self.paint(target.bounds.translated(self.offset()), "element")
  } else {
    self.box.set_with_string("hidden", true)
  }
}

///|
fn CaptureSession::move_pointer(
  self : CaptureSession,
  pointer : CapturePointer,
) -> Unit {
  if self.phase is Disposed {
    return
  }
  self.pointer = Some(pointer)
  match self.phase {
    Dragging(drag) => {
      if drag.pointer_id != pointer.id {
        return
      }
      if @selection.drag_rect(
          drag.start,
          self.point(pointer),
          selecting=drag.selecting,
        )
        is Some(rect) {
        self.phase = Dragging({ ..drag, selecting: true, })
        self.paint(rect, "region")
      }
    }
    Hovering => self.hover()
    Disposed => ()
  }
}

///|
fn read_pointer(event : @js.Value) -> CapturePointer {
  {
    position: {
      x: event.get_with_string("clientX"),
      y: event.get_with_string("clientY"),
    },
    id: event.get_with_string("pointerId"),
  }
}

///|
fn CaptureSession::release(self : CaptureSession, event : @js.Value) -> Unit {
  let pointer = read_pointer(event)
  guard self.phase is Dragging(drag) && drag.pointer_id == pointer.id else {
    return
  }
  browser_stop(event)
  self.move_pointer(pointer)
  guard self.phase is Dragging(drag) else { return }
  let selected = if drag.selecting {
    @selection.drag_rect(drag.start, self.point(pointer), selecting=true)
  } else {
    None
  }
  let offset = self.offset()
  let rect = if selected is Some(rect) {
    Some(rect.translated({ x: -offset.x, y: -offset.y, }))
  } else {
    drag.target.map(target => target.bounds)
  }
  let text = if selected is Some(_) {
    None
  } else {
    drag.target.map(target => target.text)
  }
  self.phase = Hovering
  guard rect is Some(rect) else {
    self.hover()
    return
  }
  // The pointerup listener is retired now; swallow the following synthetic
  // click using the PDF session lifetime so underlying links do not activate.
  let pdf_abort : @js.Value = self.pdf.get_with_string("abort")
  browser_listen(
    self.container,
    "click",
    browser_stop,
    pdf_abort.get_with_string("signal"),
    capture=true,
    once=true,
  )
  self.dispose()
  if rect.width < 4 || rect.height < 4 {
    return
  }
  if !(self.pdf.get_with_string("alive") : Bool) ||
    !browser_same(self.host.get_with_string("__officeViewerPdf"), self.pdf) {
    return
  }
  let mut result : Result[Capture, String] = Err(self.failure)
  let succeeded = browser_attempt(() => {
    result = render_capture(
      self.host,
      self.pdf,
      rect,
      text,
      self.failure,
      self.too_large,
      self.unsupported,
    )
  })
  (self.completed)(if succeeded { result } else { Err(self.failure) })
}

///|
fn CaptureSession::wire(self : CaptureSession) -> Unit {
  let cleanup = () => self.dispose()
  self.host.set_with_string("__pdfRegionCapture", cleanup)
  self.listen(
    browser_document(),
    "keydown",
    event => {
      if (event.get_with_string("key") : String) == "Escape" {
        event.apply_with_string("preventDefault", ([] : FixedArray[@js.Value]))
        event.apply_with_string(
          "stopImmediatePropagation",
          ([] : FixedArray[@js.Value]),
        )
        self.dispose()
      }
    },
    capture=true,
  )
  self.listen(self.container, "contextmenu", event => {
    event.apply_with_string("preventDefault", ([] : FixedArray[@js.Value]))
    self.dispose()
  })
  self.listen(self.container, "scroll", _ => {
    if self.phase is Dragging(_) && self.pointer is Some(pointer) {
      self.move_pointer(pointer)
    } else {
      self.hover()
    }
  })
  for name in ["resize", "blur"] {
    self.listen(@js.globalThis, name, _ => self.dispose())
  }
  let pdf_abort : @js.Value = self.pdf.get_with_string("abort")
  self.listen(pdf_abort.get_with_string("signal"), "abort", _ => self.dispose())
  let bus : @js.Value = self.pdf.get_with_string("bus")
  for name in ["scalechanging", "rotationchanging"] {
    bus.apply_with_string("on", [
      @js.Value::cast_from(name),
      @js.Value::cast_from(cleanup),
    ])
    self.cleanups.push(() => {
      bus.apply_with_string("off", [
        @js.Value::cast_from(name),
        @js.Value::cast_from(cleanup),
      ])
    })
  }
  let rendered = (event : @js.Value) => {
    let number : Int32 = event.get_with_string("pageNumber")
    if browser_query(self.host, ".page[data-page-number='\{number}']")
      is Some(page) {
      self.cache.pages.remove(number)
      ignore(self.cache.prepare(page, () => self.hover()))
    }
  }
  bus.apply_with_string("on", [
    @js.Value::cast_from("textlayerrendered"),
    @js.Value::cast_from(rendered),
  ])
  self.cleanups.push(() => {
    bus.apply_with_string("off", [
      @js.Value::cast_from("textlayerrendered"),
      @js.Value::cast_from(rendered),
    ])
  })
  self.listen(
    self.container,
    "pointerdown",
    event => {
      if (event.get_with_string("button") : Int32) != 0 ||
        !(event.get_with_string("isPrimary") : Bool) {
        return
      }
      let pointer = read_pointer(event)
      if !self.contains(pointer) {
        return
      }
      browser_stop(event)
      self.pointer = Some(pointer)
      self.hover()
      self.phase = Dragging({
        start: self.point(pointer),
        pointer_id: pointer.id,
        selecting: false,
        target: self.target(pointer),
      })
      self.container.apply_with_string("setPointerCapture", [pointer.id])
    },
    capture=true,
  )
  self.listen(self.container, "pointermove", event => {
    self.move_pointer(read_pointer(event))
  })
  self.listen(self.container, "pointerleave", _ => {
    if self.phase is Hovering {
      self.pointer = None
      self.box.set_with_string("hidden", true)
    }
  })
  self.listen(self.container, "pointercancel", _ => self.dispose())
  self.listen(self.container, "lostpointercapture", _ => {
    if self.phase is Dragging(_) {
      self.dispose()
    }
  })
  self.listen(self.container, "click", browser_stop, capture=true)
  self.listen(
    self.container,
    "pointerup",
    event => self.release(event),
    capture=true,
  )
  let mutation : @js.Value = @js.globalThis.new_with_string(
    "MutationObserver",
    [
      () => {
        let rects : @js.Value = self.container.apply_with_string(
          "getClientRects",
          ([] : FixedArray[@js.Value]),
        )
        if !(self.host.get_with_string("isConnected") : Bool) ||
          !browser_same(
            self.host.get_with_string("__officeViewerPdf"),
            self.pdf,
          ) ||
          (rects.get_with_string("length") : Int32) == 0 {
          self.dispose()
        }
      },
    ],
  )
  self.cleanups.push(() => {
    mutation.apply_with_string("disconnect", ([] : FixedArray[@js.Value]))
  })
  let resize : @js.Value = @js.globalThis.new_with_string("ResizeObserver", [
    () => if browser_bounds(self.container) != self.bounds { self.dispose() },
  ])
  self.cleanups.push(() => {
    resize.apply_with_string("disconnect", ([] : FixedArray[@js.Value]))
  })
  let selection : @js.Nullable[@js.Value] = @js.globalThis.apply_with_string(
    "getSelection",
    ([] : FixedArray[@js.Value]),
  )
  if selection.to_option() is Some(selection) {
    selection.apply_with_string("removeAllRanges", ([] : FixedArray[@js.Value]))
  }
  let classes : @js.Value = self.container.get_with_string("classList")
  classes.apply_with_string("add", ["pdf-region-capturing"])
  let body : @js.Value = browser_document().get_with_string("body")
  body.apply_with_string("append", [self.overlay])
  let options = @js.Object::new()
  options.set("childList", true)
  options.set("subtree", true)
  mutation.apply_with_string("observe", [body, options.to_value()])
  resize.apply_with_string("observe", [self.container])
  for layer in browser_elements(self.host, ".textLayer") {
    let page : @js.Nullable[@js.Value] = layer.apply_with_string("closest", [
      ".page",
    ])
    if page.to_option() is Some(page) && browser_query(layer, "span") is Some(_) {
      ignore(self.cache.prepare(page, () => self.hover()))
    }
  }
}

///|
fn start_region(
  surface_id : String,
  hint : String,
  failure : String,
  too_large : String,
  unsupported : String,
  completed : (Result[Capture, String]) -> Unit,
) -> Unit {
  let found : @js.Nullable[@js.Value] = browser_document().apply_with_string(
    "getElementById",
    [surface_id],
  )
  guard found.to_option() is Some(host) else {
    completed(Err(failure))
    return
  }
  guard browser_present(host.get_with_string("__officeViewerPdf")) is Some(pdf) else {
    completed(Err(failure))
    return
  }
  guard browser_query(host, ".pdf-container") is Some(container) else {
    completed(Err(failure))
    return
  }
  if !(pdf.get_with_string("alive") : Bool) {
    completed(Err(failure))
    return
  }
  if browser_present(host.get_with_string("__pdfRegionCapture")) is Some(_) {
    return
  }
  let bounds = browser_bounds(container)
  guard bounds.intersection({
      x: 0,
      y: 0,
      width: @js.globalThis.get_with_string("innerWidth"),
      height: @js.globalThis.get_with_string("innerHeight"),
    })
    is Some(viewport) else {
    completed(Err(failure))
    return
  }
  let overlay : @js.Value = browser_document().apply_with_string(
    "createElement",
    ["div"],
  )
  overlay.set_with_string("className", "pdf-region-capture")
  overlay.apply_with_string("setAttribute", ["role", "region"])
  overlay.apply_with_string("setAttribute", ["aria-label", hint])
  browser_paint(overlay, viewport)
  let box : @js.Value = browser_document().apply_with_string("createElement", [
    "div",
  ])
  box.set_with_string("className", "pdf-region-capture-box")
  box.set_with_string("hidden", true)
  overlay.apply_with_string("append", [box])
  let abort : @js.Value = @js.globalThis.new_with_string(
    "AbortController",
    ([] : FixedArray[@js.Value]),
  )
  let cache : TargetCache = {
    host,
    session: pdf,
    pages: {},
    generation: 0,
    alive: true,
  }
  let session : CaptureSession = {
    host,
    pdf,
    container,
    overlay,
    box,
    abort,
    bounds,
    viewport,
    cache,
    cleanups: [],
    phase: Hovering,
    pointer: None,
    failure,
    too_large,
    unsupported,
    completed,
  }
  if !browser_attempt(() => session.wire()) {
    session.dispose()
    completed(Err(failure))
  }
}
