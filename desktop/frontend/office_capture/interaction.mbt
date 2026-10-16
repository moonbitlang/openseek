///|
priv struct Session {
  host : @js.Value
  viewport : @js.Value
  overlay : @js.Value
  box : @js.Value
  abort : @js.Value
  observer : @js.Value
  resize : @js.Value
  format : Format
  label : String
  failure : String
  too_large : String
  completed : (Result[Capture, String]?) -> Unit
  mut alive : Bool
  mut capturing : Bool
  mut dragging : Bool
  mut start : Point?
  mut pointer : Int32?
  mut target : Rect?
}

///|
fn Session::finish(self : Session, result : Result[Capture, String]?) -> Unit {
  if !self.alive {
    return
  }
  self.alive = false
  self.abort.apply_with_string("abort", ([] : FixedArray[@js.Value]))
  self.observer.apply_with_string("disconnect", ([] : FixedArray[@js.Value]))
  self.resize.apply_with_string("disconnect", ([] : FixedArray[@js.Value]))
  self.overlay.apply_with_string("remove", ([] : FixedArray[@js.Value]))
  let classes : @js.Value = self.viewport.get_with_string("classList")
  classes.apply_with_string("remove", ["office-region-selecting"])
  self.host.set_with_string(
    "__officeRegionCapture",
    (@js.Nullable::null() : @js.Nullable[@js.Value]),
  )
  (self.completed)(result)
}

///|
fn Session::listen(
  self : Session,
  target : @js.Value,
  name : String,
  callback : (@js.Value) -> Unit,
  capture~ : Bool = true,
) -> Unit {
  let options = @js.Object::new()
  options.set("signal", (self.abort.get_with_string("signal") : @js.Value))
  options.set("capture", capture)
  target.apply_with_string("addEventListener", [
    @js.Value::cast_from(name),
    @js.Value::cast_from(callback),
    options.to_value(),
  ])
}

///|
fn position(event : @js.Value) -> Point {
  { x: event.get_with_string("clientX"), y: event.get_with_string("clientY"), }
}

///|
fn Session::visible(self : Session) -> Rect? {
  bounds(self.viewport).intersection({
    x: 0,
    y: 0,
    width: @js.globalThis.get_with_string("innerWidth"),
    height: @js.globalThis.get_with_string("innerHeight"),
  })
}

///|
fn Session::hover(self : Session, point : Point) -> Unit {
  let hit : @js.Nullable[@js.Value] = document().apply_with_string(
    "elementFromPoint",
    [point.x, point.y],
  )
  self.target = hit
    .to_option()
    .bind(node => {
      let contains : Bool = self.host.apply_with_string("contains", [node])
      guard contains else { return None }
      let found : @js.Nullable[@js.Value] = node.apply_with_string("closest", [
        "td[data-cell], text, image, img, figure",
      ])
      found.to_option().map(bounds)
    })
  if self.target is Some(rect) {
    paint(self.box, rect)
    self.box.set_with_string("hidden", false)
  } else {
    self.box.set_with_string("hidden", true)
  }
}

///|
fn Session::wire(self : Session) -> Unit {
  self.host.set_with_string("__officeRegionCapture", () => self.finish(None))
  self.listen(document(), "keydown", event => {
    if (event.get_with_string("key") : String) == "Escape" {
      stop(event)
      self.finish(None)
    }
  })
  self.listen(self.viewport, "contextmenu", event => {
    stop(event)
    self.finish(None)
  })
  self.listen(self.viewport, "pointerdown", event => {
    if self.capturing ||
      (event.get_with_string("button") : Int32) != 0 ||
      !(event.get_with_string("isPrimary") : Bool) {
      return
    }
    let point = position(event)
    guard self.visible() is Some(visible) &&
      visible.contains(point, inclusive=false) else {
      return
    }
    stop(event)
    self.hover(point)
    self.start = Some(point)
    self.dragging = false
    let id : Int32 = event.get_with_string("pointerId")
    self.pointer = Some(id)
    self.viewport.apply_with_string("setPointerCapture", [id])
  })
  self.listen(self.viewport, "pointermove", event => {
    if self.capturing {
      return
    }
    let point = position(event)
    if self.start is Some(start) &&
      self.pointer == Some(event.get_with_string("pointerId")) {
      if self.visible() is Some(visible) &&
        drag_rect(start, visible.clamp_point(point), selecting=false)
        is Some(rect) {
        self.dragging = true
        paint(self.box, rect)
        self.box.set_with_string("hidden", false)
      }
    } else {
      self.hover(point)
    }
  })
  self.listen(self.viewport, "pointerup", event => {
    if self.capturing ||
      self.pointer != Some(event.get_with_string("pointerId")) {
      return
    }
    guard self.start is Some(start) && self.visible() is Some(visible) else {
      return
    }
    stop(event)
    let candidate = match
      drag_rect(
        start,
        visible.clamp_point(position(event)),
        selecting=self.dragging,
      ) {
      Some(rect) => Some(rect)
      None => self.target
    }
    let rect = candidate.bind(rect => rect.intersection(visible))
    self.start = None
    self.pointer = None
    guard rect is Some(rect) && rect.width >= 4 && rect.height >= 4 else {
      return
    }
    self.capturing = true
    paint(self.box, rect)
    self.overlay.apply_with_string("setAttribute", ["aria-busy", "true"])
    snapshot(
      self.host,
      self.format,
      rect,
      visible,
      self.label,
      self.failure,
      self.too_large,
      result => if self.alive { self.finish(Some(result)) },
      () => self.alive,
    )
  })
  self.listen(self.viewport, "click", stop)
  self.listen(self.viewport, "pointercancel", _ => {
    if self.pointer is Some(_) {
      self.finish(None)
    }
  })
  self.listen(self.viewport, "scroll", _ => {
    if self.start is Some(_) || self.capturing {
      self.finish(None)
    } else {
      self.target = None
      self.box.set_with_string("hidden", true)
    }
  })
  self.listen(@js.globalThis, "resize", _ => self.finish(None), capture=false)
  // A button losing focus is not a canceled annotation. Retire an interrupted
  // drag, while letting an idle selection mode survive a window focus change.
  self.listen(
    @js.globalThis,
    "blur",
    _ => if self.pointer is Some(_) || self.capturing { self.finish(None) },
    capture=false,
  )
  let classes : @js.Value = self.viewport.get_with_string("classList")
  classes.apply_with_string("add", ["office-region-selecting"])
  let body : @js.Value = document().get_with_string("body")
  body.apply_with_string("append", [self.overlay])
  let options = @js.Object::new()
  options.set("childList", true)
  self.observer.apply_with_string("observe", [self.host, options.to_value()])
}

///|
pub fn start(
  surface_id : String,
  format : Format,
  label~ : String,
  hint~ : String,
  failure~ : String,
  too_large~ : String,
  unsupported_annotation~ : String,
  emit : @cmd.Emit[Result[Capture, String]?],
) -> @cmd.Cmd {
  if format == Pdf {
    return @cmd.custom_cmd(kind=@cmd.after_render, scheduler => {
      scheduler.add(
        @pdf_capture.start(
          surface_id,
          hint~,
          failure~,
          too_large~,
          unsupported_annotation~,
          annotation=label,
          canceled=() => scheduler.add(emit(None)),
          emit.map(result => Some(result.map(from_pdf))),
        ),
      )
    })
  }
  @cmd.custom_cmd(kind=@cmd.after_render, scheduler => {
    let found : @js.Nullable[@js.Value] = document().apply_with_string(
      "getElementById",
      [surface_id],
    )
    guard found.to_option() is Some(host) else {
      scheduler.add(emit(Some(Err(failure))))
      return
    }
    let parent : @js.Nullable[@js.Value] = host.get_with_string("parentElement")
    let child : @js.Nullable[@js.Value] = host.get_with_string(
      "firstElementChild",
    )
    guard parent.to_option() is Some(viewport) &&
      child.to_option() is Some(root) else {
      scheduler.add(emit(Some(Err(failure))))
      return
    }
    let overlay : @js.Value = document().apply_with_string("createElement", [
      "div",
    ])
    overlay.set_with_string("className", "office-region-capture")
    overlay.apply_with_string("setAttribute", ["role", "region"])
    overlay.apply_with_string("setAttribute", ["aria-label", hint])
    let box : @js.Value = document().apply_with_string("createElement", ["div"])
    box.set_with_string("className", "office-region-capture-box")
    box.set_with_string("hidden", true)
    let tip : @js.Value = document().apply_with_string("createElement", ["div"])
    tip.set_with_string("className", "office-region-capture-hint")
    tip.set_with_string("textContent", hint)
    overlay.apply_with_string("append", [box, tip])
    let abort : @js.Value = @js.globalThis.new_with_string(
      "AbortController",
      ([] : FixedArray[@js.Value]),
    )
    let active : Ref[Session?] = Ref(None)
    let observer : @js.Value = @js.globalThis.new_with_string(
      "MutationObserver",
      [
        () => {
          if active.val is Some(session) {
            let current : @js.Value = host.get_with_string("firstElementChild")
            let object : @js.Value = @js.globalThis.get_with_string("Object")
            let same : Bool = object.apply_with_string("is", [current, root])
            if !same || !(host.get_with_string("isConnected") : Bool) {
              session.finish(None)
            }
          }
        },
      ],
    )
    let initial_bounds = bounds(viewport)
    let resize : @js.Value = @js.globalThis.new_with_string("ResizeObserver", [
      () => {
        if active.val is Some(session) && bounds(viewport) != initial_bounds {
          session.finish(None)
        }
      },
    ])
    let session : Session = {
      host,
      viewport,
      overlay,
      box,
      abort,
      observer,
      resize,
      format,
      label,
      failure,
      too_large,
      completed: result => scheduler.add(emit(result)),
      alive: true,
      capturing: false,
      dragging: false,
      start: None,
      pointer: None,
      target: None,
    }
    active.val = Some(session)
    resize.apply_with_string("observe", [viewport])
    if !attempt(() => session.wire()) {
      session.finish(Some(Err(failure)))
    }
  })
}

///|
pub fn cancel(surface_id : String) -> @cmd.Cmd {
  @cmd.batch([
    @pdf_capture.cancel(surface_id),
    @cmd.custom_cmd(kind=@cmd.after_render, _ => {
      let host : @js.Nullable[@js.Value] = document().apply_with_string(
        "getElementById",
        [surface_id],
      )
      if host.to_option() is Some(host) {
        let cleanup : @js.Nullable[() -> Unit] = host.get_with_string(
          "__officeRegionCapture",
        )
        if cleanup.to_option() is Some(cleanup) {
          cleanup()
        }
      }
    }),
  ])
}
