// The dock's browser tabs, host side: every command here talks to the
// desktop window's native web contents views over the bridge-local
// `browser.*` ops, and the pane-geometry plumbing keeps the active view
// glued to the `browser-pane` element the frontend renders. Views exist
// only in the desktop window (`ChannelId::Local`); the routing in update
// never sends a remote console here.

///|
/// The placeholder element the active page's native view overlays. The view
/// is z-ordered above all HTML, so this element renders nothing — it only
/// donates its rectangle.
const BrowserPaneId = "browser-pane"

///|
/// One bridge-local native-window op. Geometry calls (`quiet=true`) fail
/// silently — they are continuous best-effort placement, and a failure just
/// means the view is gone or not yet created; the next sync pass reconverges.
/// Ordered on purpose: Proton may dispatch two fire-and-forget requests into
/// the host in either order, while browser ops are sequences — create-then-
/// place, bounds-before-visibility — whose inversion shows on screen.
fn[Payload : ToJson] browser_op(
  dispatch : @cmd.Emit[Msg],
  command : @commands.Command[Payload, @protocol.EmptyReply],
  payload : Payload,
  quiet~ : Bool,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.async_run(() => {
      let _ : @protocol.EmptyReply = @interop.bridge_request_in_order(
        @interop.ChannelId::Local,
        command,
        payload,
      ) catch {
        error => {
          if !quiet {
            scheduler.add(
              dispatch(HostActionFailed(@interop.bridge_error_text(error))),
            )
          }
          return
        }
      }
    })
  })
}

///|
/// Create page `id`'s native view loading `url`. The view starts hidden;
/// the pane sync shows and places it after the next measurement.
fn browser_open(
  dispatch : @cmd.Emit[Msg],
  id : Int,
  url : String,
  dark : Bool,
) -> @cmd.Cmd {
  browser_op(dispatch, @commands.browser_open, { id, url, dark, }, quiet=false)
}

///|
fn browser_navigate(
  dispatch : @cmd.Emit[Msg],
  id : Int,
  url : String,
  dark : Bool,
) -> @cmd.Cmd {
  browser_op(
    dispatch,
    @commands.browser_navigate,
    { id, url, dark, },
    quiet=false,
  )
}

///|
/// Apply the app's effective light/dark choice to one page. Web pages still
/// own their palettes, so the host expresses this through standard browser
/// color-scheme hints and theme attributes the page already opted into.
fn browser_set_theme(
  dispatch : @cmd.Emit[Msg],
  id : Int,
  dark : Bool,
) -> @cmd.Cmd {
  browser_op(dispatch, @commands.browser_set_theme, { id, dark, }, quiet=true)
}

///|
/// Theme every native page, including pages in parked conversation strips.
/// A page without a URL has no native view yet and is deliberately skipped.
fn browser_set_theme_for_pages(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  dark : Bool,
) -> @cmd.Cmd {
  let commands : Array[@cmd.Cmd] = []
  for id, page in model.preview.pages {
    if page.url is Some(_) {
      commands.push(browser_set_theme(dispatch, id, dark))
    }
  }
  @cmd.batch(commands)
}

///|
/// Apply the effective palette to native caption controls on platforms where
/// Proton supports an explicit per-window theme.
fn app_set_titlebar_theme(dispatch : @cmd.Emit[Msg], dark : Bool) -> @cmd.Cmd {
  browser_op(dispatch, @commands.app_set_titlebar_theme, { dark, }, quiet=true)
}

///|
/// A history op on whatever Browser tab is active — a no-op when none is,
/// or while a blank tab has no view yet.
fn browser_history_for_active(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  command : @commands.Command[@protocol.BrowserIdPayload, @protocol.EmptyReply],
) -> @cmd.Cmd {
  guard @dock.active_browser(model.dock) is Some(id) &&
    @preview.page(model.preview, id) is Some(page) &&
    page.url is Some(_) else {
    return @cmd.none
  }
  browser_op(dispatch, command, { id, }, quiet=false)
}

///|
fn browser_set_bounds(
  dispatch : @cmd.Emit[Msg],
  id : Int,
  rect : @preview.Rect,
) -> @cmd.Cmd {
  browser_op(
    dispatch,
    @commands.browser_set_bounds,
    { id, x: rect.x, y: rect.y, width: rect.width, height: rect.height, },
    quiet=true,
  )
}

///|
fn browser_set_visible(
  dispatch : @cmd.Emit[Msg],
  id : Int,
  visible : Bool,
) -> @cmd.Cmd {
  browser_op(
    dispatch,
    @commands.browser_set_visible,
    { id, visible, },
    quiet=true,
  )
}

///|
fn browser_close_view(dispatch : @cmd.Emit[Msg], id : Int) -> @cmd.Cmd {
  browser_op(dispatch, @commands.browser_close, { id, }, quiet=true)
}

///|
/// The browser pane's current on-screen rectangle in CSS pixels — the same
/// coordinate space as the window's logical view bounds while the zoom is
/// 100% (a known constraint of the native-view design).
fn browser_pane_rect() -> @preview.Rect? {
  guard @dom.document().get_element_by_id(BrowserPaneId).to_option()
    is Some(element) else {
    return None
  }
  let rect = element.get_bounding_client_rect()
  Some({
    x: rect.get_x().to_int(),
    y: rect.get_y().to_int(),
    width: rect.get_width().to_int(),
    height: rect.get_height().to_int(),
  })
}

///|
/// Measure the pane after the render it reacts to has committed, and report
/// the rectangle back into the update loop.
fn measure_browser_pane(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(
    scheduler => {
      match browser_pane_rect() {
        Some(rect) => scheduler.add(dispatch(BrowserPaneMeasured(rect~)))
        None => ()
      }
    },
    kind=@cmd.after_render,
  )
}

///|
let browser_pane_watched : Ref[Bool] = Ref(false)

///|
/// Watch the pane and its layout column once. The pane catches direct size
/// changes; the content column catches a sliding sidebar even when a
/// fixed-width pane only changes position. Both report the pane's current
/// rectangle so a native Browser view follows CSS-driven drawer motion.
fn watch_browser_pane(dispatch : @cmd.Emit[Msg]) -> @cmd.Cmd {
  @cmd.custom_cmd(
    scheduler => {
      guard !browser_pane_watched.val else { return }
      guard @dom.document().get_element_by_id(BrowserPaneId).to_option()
        is Some(element) else {
        return
      }
      guard @interop.js_prop(@js.globalThis, "ResizeObserver") is Some(ctor) else {
        return
      }
      browser_pane_watched.val = true
      let on_resize = (_entries : @js.Value) => {
        match browser_pane_rect() {
          Some(rect) => scheduler.add(dispatch(BrowserPaneMeasured(rect~)))
          None => ()
        }
      }
      let observer : @js.Value = ctor.new([@js.Value::cast_from(on_resize)])
      let _ : @js.Value = observer.apply_with_string("observe", [
        @js.Value::cast_from(element),
      ])
      match @dom.document().query_selector(".content").to_option() {
        Some(content) => {
          let _ : @js.Value = observer.apply_with_string("observe", [
            @js.Value::cast_from(content),
          ])
        }
        None => ()
      }
    },
    kind=@cmd.after_render,
  )
}

///|
/// Focus the address bar — the blank tab a launcher's Browser row opens is
/// for typing into.
fn focus_browser_address() -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      match
        @dom.document().get_element_by_id(@preview.AddressInputId).to_option() {
        Some(element) => {
          let _ : @js.Value = @js.Cast::from(element).apply_with_string(
            "focus",
            ([] : Array[@js.Value]),
          )
        }
        None => ()
      }
    },
    kind=@cmd.after_render,
  )
}

///|
/// Decode one `browser.event` notification into the preview subsystem's
/// message. Unknown kinds and malformed payloads drop.
fn browser_event_msg(payload : Map[String, Json]) -> Msg? {
  guard @jsonx.json_int(payload, "id") is Some(id) &&
    @jsonx.json_text(payload, "kind") is Some(kind) else {
    return None
  }
  match kind {
    "navigated" =>
      @jsonx.json_text(payload, "url").map(url => {
        Preview(@preview.Msg::Navigated(id~, url~))
      })
    "loading" =>
      @jsonx.json_bool(payload, "loading").map(loading => {
        Preview(@preview.Msg::LoadingChanged(id~, loading~))
      })
    "title" =>
      @jsonx.json_text(payload, "title").map(title => {
        Preview(@preview.Msg::TitleUpdated(id~, title~))
      })
    "load_failed" =>
      // CEF reports ERR_ABORTED (-3) whenever a load is superseded — a new
      // navigation, an in-page form submit — not when anything actually
      // failed. It can even arrive after the superseding navigation
      // cleared the failure state, leaving a stale banner over a healthy
      // page; the canonical CEF load-error handler ignores it, so do we.
      if @jsonx.json_int(payload, "code") is Some(-3) {
        None
      } else {
        match
          (@jsonx.json_text(payload, "url"), @jsonx.json_text(payload, "text")) {
          (Some(url), Some(text)) =>
            Some(Preview(@preview.Msg::LoadFailed(id~, url~, text~)))
          _ => None
        }
      }
    _ => None
  }
}

///|
test "browser event decode drops ERR_ABORTED but keeps real failures" {
  let aborted : Map[String, Json] = {
    "id": Json(1),
    "kind": "load_failed",
    "url": "https://www.baidu.com/s?wd=x",
    "code": Json(-3),
    "text": "ERR_ABORTED",
  }
  assert_true(browser_event_msg(aborted) is None)
  let refused : Map[String, Json] = {
    "id": Json(1),
    "kind": "load_failed",
    "url": "http://127.0.0.1:5173/",
    "code": Json(-102),
    "text": "ERR_CONNECTION_REFUSED",
  }
  assert_true(
    browser_event_msg(refused)
    is Some(Preview(LoadFailed(id=1, url="http://127.0.0.1:5173/", ..))),
  )
  let navigated : Map[String, Json] = {
    "id": Json(2),
    "kind": "navigated",
    "url": "https://www.google.com/",
  }
  assert_true(
    browser_event_msg(navigated)
    is Some(Preview(Navigated(id=2, url="https://www.google.com/"))),
  )
}
