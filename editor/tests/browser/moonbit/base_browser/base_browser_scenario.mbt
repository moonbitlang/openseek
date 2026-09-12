// Real-browser fixture for the narrow DOM and global-pointer-monitor helpers
// in `editor/base/browser`. Playwright owns the gestures, Selection/Range
// setup, and final assertions; this MoonBit scenario only calls product APIs
// and mirrors their results into DOM attributes.

///|
pub fn run_base_browser_test() -> Unit {
  let ctx = @support.BrowserTestContext("base_browser")
  let document = @rdom.document()
  guard document.query_selector("#app").to_option() is Some(app) else {
    ctx.fail("missing #app mount point")
    ctx.finish()
    return
  }
  let shell = document.create_element("main")
  shell.set_attribute("id", "base-browser-fixture")
  shell.set_attribute(
    "style", "min-height:100vh;padding:16px;display:grid;gap:16px;align-content:start;",
  )
  app.append_child(shell.as_node())
  setup_focus_fixture(document, shell, ctx)
  setup_event_fixture(document, shell)
  setup_selection_fixture(document, shell)
  setup_pointer_capture_fixture(document, shell, ctx)
  setup_pointer_lifecycle_fixture(document, shell)
  shell.set_attribute("data-ready", "true")
  ctx.finish()
}

///|
fn setup_focus_fixture(
  document : @rdom.Document,
  shell : @rdom.Element,
  ctx : @support.BrowserTestContext,
) -> Unit {
  let action = document.create_element("button")
  action.set_attribute("id", "focus-without-scroll")
  action.set_inner_html("Focus iframe target")
  let result = document.create_element("output")
  result.set_attribute("id", "focus-result")
  let frame = document.create_element("iframe")
  frame.set_attribute("id", "owner-document-frame")
  frame.set_attribute("title", "owner document fixture")
  frame.set_attribute("style", "width:360px;height:180px;border:1px solid;")
  shell.append_child(action.as_node())
  shell.append_child(result.as_node())
  shell.append_child(frame.as_node())
  let frame_document = iframe_document(frame)
  guard frame_document.get_body() is Some(frame_body) else {
    ctx.fail("iframe owner document has no body")
    return
  }
  let scroller = frame_document.create_element("div")
  scroller.set_attribute("id", "focus-scroller")
  scroller.set_attribute(
    "style", "height:80px;width:260px;overflow:auto;border:1px solid;padding:2px;",
  )
  let spacer = frame_document.create_element("div")
  spacer.set_attribute("style", "height:220px;")
  let target = frame_document.create_element("button")
  target.set_attribute("id", "focus-target")
  target.set_inner_html("Focusable target")
  scroller.append_child(spacer.as_node())
  scroller.append_child(target.as_node())
  frame_body.append_child(scroller.as_node())
  action.add_event_listener("click", _ => {
    scroller.set_scroll_top(120.0)
    @browser_api.focus_prevent_scroll(target)
    result.set_attribute(
      "data-contains-target",
      @browser_api.element_contains(scroller, target).to_string(),
    )
    result.set_attribute(
      "data-target-focused",
      @browser_api.element_has_focus(target).to_string(),
    )
    result.set_attribute(
      "data-contains-active",
      @browser_api.element_contains_active_element(scroller).to_string(),
    )
  })
}

///|
fn setup_event_fixture(
  document : @rdom.Document,
  shell : @rdom.Element,
) -> Unit {
  let result = document.create_element("output")
  result.set_attribute("id", "event-result")
  let boundary = document.create_element("section")
  boundary.set_attribute("id", "event-boundary")
  let plain = document.create_element("span")
  plain.set_attribute("id", "event-plain")
  plain.set_inner_html("plain target")
  let owned = document.create_element("div")
  owned.set_attribute("class", "caller-owned")
  let owned_child = document.create_element("span")
  owned_child.set_attribute("id", "event-owned-child")
  owned_child.set_inner_html("owned text target")
  owned.append_child(owned_child.as_node())
  boundary.append_child(plain.as_node())
  boundary.append_child(owned.as_node())
  let outside = document.create_element("div")
  outside.set_attribute("class", "caller-owned")
  let outside_child = document.create_element("span")
  outside_child.set_attribute("id", "event-outside-child")
  outside_child.set_inner_html("outside text target")
  outside.append_child(outside_child.as_node())
  boundary.add_event_listener("ownership-probe", event => {
    record_event_probe(event, boundary, result, ".caller-owned")
  })
  outside.add_event_listener("ownership-probe", event => {
    record_event_probe(event, boundary, result, ".caller-owned")
  })
  boundary.add_event_listener("invalid-selector-probe", event => {
    record_event_probe(event, boundary, result, "[")
  })
  shell.append_child(result.as_node())
  shell.append_child(boundary.as_node())
  shell.append_child(outside.as_node())
}

///|
fn record_event_probe(
  event : @rdom.Event,
  boundary : @rdom.Element,
  result : @rdom.Element,
  selector : String,
) -> Unit {
  result.set_attribute(
    "data-target-is-boundary",
    @browser_api.event_target_is(event, boundary).to_string(),
  )
  result.set_attribute(
    "data-has-bounded-ancestor",
    @browser_api.event_target_has_matching_ancestor(event, boundary, selector).to_string(),
  )
}

///|
fn setup_selection_fixture(
  document : @rdom.Document,
  shell : @rdom.Element,
) -> Unit {
  let result = document.create_element("output")
  result.set_attribute("id", "selection-result")
  let boundary = document.create_element("section")
  boundary.set_attribute("id", "selection-boundary")
  let plain = document.create_element("span")
  plain.set_attribute("id", "selection-plain")
  plain.set_inner_html("plain selection text")
  let owned = document.create_element("span")
  owned.set_attribute("id", "selection-owned")
  owned.set_attribute("class", "caller-owned")
  owned.set_inner_html("owned selection text")
  let outside = document.create_element("span")
  outside.set_attribute("id", "selection-outside-owned")
  outside.set_attribute("class", "caller-owned")
  outside.set_inner_html("outside selection text")
  let check = document.create_element("button")
  check.set_attribute("id", "check-selection")
  check.set_inner_html("Check selection")
  let check_invalid = document.create_element("button")
  check_invalid.set_attribute("id", "check-selection-invalid")
  check_invalid.set_inner_html("Check invalid selector")
  boundary.append_child(plain.as_node())
  boundary.append_child(owned.as_node())
  check.add_event_listener("click", _ => {
    result.set_attribute(
      "data-has-bounded-endpoint",
      @browser_api.native_selection_has_endpoint_in_matching_ancestor(
        boundary, ".caller-owned",
      ).to_string(),
    )
  })
  check_invalid.add_event_listener("click", _ => {
    result.set_attribute(
      "data-invalid-selector-matched",
      @browser_api.native_selection_has_endpoint_in_matching_ancestor(
        boundary, "[",
      ).to_string(),
    )
  })
  shell.append_child(result.as_node())
  shell.append_child(boundary.as_node())
  shell.append_child(outside.as_node())
  shell.append_child(check.as_node())
  shell.append_child(check_invalid.as_node())
}

///|
fn setup_pointer_capture_fixture(
  document : @rdom.Document,
  shell : @rdom.Element,
  ctx : @support.BrowserTestContext,
) -> Unit {
  let capture_target = document.create_element("div")
  capture_target.set_attribute("id", "pointer-capture-target")
  capture_target.set_attribute(
    "style", "width:140px;height:70px;background:#4d7cfe;touch-action:none;user-select:none;",
  )
  capture_target.set_inner_html("capture pointer")
  shell.append_child(capture_target.as_node())
  attach_pointer_monitor(GlobalPointerMoveMonitor(), capture_target, false)

  let frame = document.create_element("iframe")
  frame.set_attribute("id", "pointer-owner-frame")
  frame.set_attribute("title", "pointer owner window fixture")
  frame.set_attribute("style", "width:360px;height:180px;border:1px solid;")
  shell.append_child(frame.as_node())
  let frame_document = iframe_document(frame)
  match frame_document.get_body() {
    Some(frame_body) => {
      let fallback_target = frame_document.create_element("div")
      fallback_target.set_attribute("id", "pointer-fallback-target")
      fallback_target.set_attribute(
        "style", "margin:12px;width:140px;height:70px;background:#bf616a;touch-action:none;user-select:none;",
      )
      fallback_target.set_inner_html("fallback pointer")
      frame_body.append_child(fallback_target.as_node())
      attach_pointer_monitor(GlobalPointerMoveMonitor(), fallback_target, true)
    }
    None => ctx.fail("pointer iframe owner document has no body")
  }
}

///|
fn attach_pointer_monitor(
  monitor : @browser_api.GlobalPointerMoveMonitor,
  target : @rdom.Element,
  force_capture_failure : Bool,
) -> Unit {
  let moves = Ref(0)
  let stops = Ref(0)
  target.set_attribute("data-moves", "0")
  target.set_attribute("data-stops", "0")
  target.add_event_listener("pointerdown", event => {
    let actual_pointer_id = pointer_event_pointer_id(event)
    let monitor_pointer_id = if force_capture_failure {
      actual_pointer_id + 100000
    } else {
      actual_pointer_id
    }
    target.set_attribute("data-pointer-id", actual_pointer_id.to_string())
    monitor.start_monitoring(
      target,
      monitor_pointer_id,
      pointer_event_buttons(event),
      moved => {
        moves.val += 1
        target.set_attribute("data-moves", moves.val.to_string())
        target.set_attribute(
          "data-move-default-prevented",
          moved.get_default_prevented().to_string(),
        )
      },
      _ => {
        stops.val += 1
        target.set_attribute("data-stops", stops.val.to_string())
      },
    )
    target.set_attribute(
      "data-has-pointer-capture",
      target.has_pointer_capture(actual_pointer_id).to_string(),
    )
  })
}

///|
fn setup_pointer_lifecycle_fixture(
  document : @rdom.Document,
  shell : @rdom.Element,
) -> Unit {
  let monitor = @browser_api.GlobalPointerMoveMonitor()
  let target = document.create_element("div")
  target.set_attribute("id", "pointer-lifecycle-target")
  target.set_attribute(
    "style", "width:140px;height:70px;background:#a3be8c;touch-action:none;user-select:none;",
  )
  target.set_inner_html("pointer lifecycle")
  target.set_attribute("data-moves", "0")
  target.set_attribute("data-stops", "0")
  target.set_attribute("data-starts", "0")
  let moves = Ref(0)
  let stops = Ref(0)
  let starts = Ref(0)
  let mut active_pointer : (Int, Int)? = None
  let start = (pointer_id : Int, buttons : Int) => {
    starts.val += 1
    target.set_attribute("data-starts", starts.val.to_string())
    monitor.start_monitoring(
      target,
      pointer_id,
      buttons,
      _ => {
        moves.val += 1
        target.set_attribute("data-moves", moves.val.to_string())
      },
      _ => {
        stops.val += 1
        target.set_attribute("data-stops", stops.val.to_string())
      },
    )
  }
  target.add_event_listener("pointerdown", event => {
    let pointer_id = pointer_event_pointer_id(event)
    let buttons = pointer_event_buttons(event)
    active_pointer = Some((pointer_id, buttons))
    target.set_attribute("data-pointer-id", pointer_id.to_string())
    start(pointer_id, buttons)
    target.set_attribute(
      "data-has-pointer-capture",
      target.has_pointer_capture(pointer_id).to_string(),
    )
  })
  let restart = document.create_element("button")
  restart.set_attribute("id", "pointer-restart")
  restart.set_inner_html("Restart monitor")
  restart.add_event_listener("click", _ => {
    match active_pointer {
      Some((pointer_id, buttons)) => start(pointer_id, buttons)
      None => ()
    }
  })
  let stop_false = document.create_element("button")
  stop_false.set_attribute("id", "pointer-stop-false")
  stop_false.set_inner_html("Stop silently")
  stop_false.add_event_listener("click", _ => monitor.stop_monitoring(false))
  let stop_true = document.create_element("button")
  stop_true.set_attribute("id", "pointer-stop-true")
  stop_true.set_inner_html("Stop with callback")
  stop_true.add_event_listener("click", _ => monitor.stop_monitoring(true))
  let dispose = document.create_element("button")
  dispose.set_attribute("id", "pointer-dispose")
  dispose.set_inner_html("Dispose monitor")
  dispose.add_event_listener("click", _ => monitor.dispose())
  shell.append_child(target.as_node())
  shell.append_child(restart.as_node())
  shell.append_child(stop_false.as_node())
  shell.append_child(stop_true.as_node())
  shell.append_child(dispose.as_node())
}

///|
/// Rabbita does not expose HTMLIFrameElement.contentDocument. This is the one
/// fixture-only DOM gap-fill; all behavior under test still uses real browser
/// objects and the product helpers above.
extern "js" fn iframe_document(iframe : @rdom.Element) -> @rdom.Document = "(iframe) => iframe.contentDocument"

///|
extern "js" fn pointer_event_pointer_id(event : @rdom.Event) -> Int = "(event) => event.pointerId"

///|
extern "js" fn pointer_event_buttons(event : @rdom.Event) -> Int = "(event) => event.buttons"
