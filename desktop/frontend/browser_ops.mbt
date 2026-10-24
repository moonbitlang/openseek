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
/// Open a new tab for either a user action or a host request. The caller
/// chooses the conversation; an off-screen conversation keeps its tab parked.
/// A blank tab has no native view until its first address is submitted.
fn open_browser_tab(
  dispatch : @cmd.Emit[Msg],
  model : Model,
  owner : @interop.ConversationKey?,
  url? : String,
  request? : String,
) -> (@cmd.Cmd, Model) {
  let (preview, id) = @preview.open_page(model.preview, url?)
  // `owner` names the Host conversation for the native view; without one the
  // tab joins the strip on screen, which may be a Cloud conversation's.
  let target_owner = owner
    .map(owner => @interop.Host(owner))
    .unwrap_or(model.dock_owner())
  let dock = @dock.open_browser(model.dock_state_for(target_owner), id)
  let on_screen = target_owner == model.dock_owner()
  let cmd = if url is Some(url) {
    browser_open(
      dispatch,
      id,
      url,
      model.theme.is_dark(model.system_dark),
      owner,
      request?,
    )
  } else {
    @cmd.none
  }
  (
    cmd,
    {
      ..model.with_dock_state_for(target_owner, dock),
      preview,
      right_panel_open: model.right_panel_open || (on_screen && url is Some(_)),
      right_panel_menu_open: model.right_panel_menu_open && !on_screen,
    },
  )
}

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
  on_error? : (String) -> Msg,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    @js.Promise::from_async(() => {
      let _ : @protocol.EmptyReply = @interop.bridge_request_in_order(
        @interop.ChannelId::Local,
        command,
        payload,
      ) catch {
        error => {
          if on_error is Some(on_error) {
            scheduler.add(dispatch(on_error(@interop.bridge_error_text(error))))
          } else if !quiet {
            scheduler.add(
              dispatch(HostActionFailed(@interop.bridge_error_text(error))),
            )
          }
          return
        }
      }
    })
    |> ignore
  })
}

///|
/// Create page `id`'s native view loading `url`. The view starts hidden;
/// the pane sync shows and places it after the next measurement. `owner` is
/// the dock strip the page is in, which is how the host learns whose tab it
/// is.
fn browser_open(
  dispatch : @cmd.Emit[Msg],
  id : Int32,
  url : String,
  dark : Bool,
  owner : @interop.ConversationKey?,
  request? : String,
) -> @cmd.Cmd {
  browser_op(
    dispatch,
    @commands.browser_open,
    { id, url, dark, session: owner.map(owner => owner.session), request, },
    quiet=false,
  )
}

///|
fn browser_navigate(
  dispatch : @cmd.Emit[Msg],
  id : Int32,
  url : String,
  dark : Bool,
  owner : @interop.ConversationKey?,
) -> @cmd.Cmd {
  browser_op(
    dispatch,
    @commands.browser_navigate,
    {
      id,
      url,
      dark,
      session: owner.map(owner => owner.session),
      request: None,
    },
    quiet=false,
  )
}

///|
/// Apply the app's effective light/dark choice to one page. Web pages still
/// own their palettes, so the host expresses this through standard browser
/// color-scheme hints and theme attributes the page already opted into.
fn browser_set_theme(
  dispatch : @cmd.Emit[Msg],
  id : Int32,
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
  @cmd.batch(
    [
      for id, page in model.preview.pages if page.url is Some(_) => {
        browser_set_theme(dispatch, id, dark)
      }
    ],
  )
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
  guard @dock.active_browser(model.dock_state()) is Some(id) &&
    @preview.page(model.preview, id) is Some(page) &&
    page.url is Some(_) else {
    return @cmd.none
  }
  browser_op(dispatch, command, { id, }, quiet=false)
}

///|
fn browser_set_bounds(
  dispatch : @cmd.Emit[Msg],
  id : Int32,
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
  id : Int32,
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
fn browser_close_view(dispatch : @cmd.Emit[Msg], id : Int32) -> @cmd.Cmd {
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
            ([] : FixedArray[@js.Value]),
          )
        }
        None => ()
      }
    },
    kind=@cmd.after_render,
  )
}

///|
/// Apply UI policy to a decoded window-local browser notification. Every
/// supported variant is handled here; malformed wire payloads drop at the
/// bridge boundary before reaching the model.
fn browser_event_msg(payload : @protocol.BrowserEventPayload) -> Msg? {
  match payload {
    OpenRequested(request~, session~, url~) =>
      Some(BrowserOpenRequested(request~, session~, url~))
    Navigated(id~, url~) => Some(Preview(@preview.Msg::Navigated(id~, url~)))
    LoadingChanged(id~, loading~) =>
      Some(Preview(@preview.Msg::LoadingChanged(id~, loading~)))
    TitleUpdated(id~, title~) =>
      Some(Preview(@preview.Msg::TitleUpdated(id~, title~)))
    // CEF reports ERR_ABORTED when a load is superseded. It must not leave
    // a stale failure banner over the replacing navigation.
    LoadFailed(code=-3, ..) => None
    // Renderer termination codes are not navigation errors: even -3 must
    // reach the existing error display and reload action.
    LoadFailed(id~, url~, text~, ..)
    | RendererProcessTerminated(id~, url~, text~, ..) =>
      Some(Preview(@preview.Msg::LoadFailed(id~, url~, text~)))
  }
}

///|
test "browser event policy drops ERR_ABORTED but keeps real failures" {
  let aborted : @protocol.BrowserEventPayload = LoadFailed(
    id=1,
    url="https://www.baidu.com/s?wd=x",
    code=-3,
    text="ERR_ABORTED",
  )
  assert_true(browser_event_msg(aborted) is None)
  let terminated : @protocol.BrowserEventPayload = RendererProcessTerminated(
    id=1,
    url="https://www.baidu.com/s?wd=x",
    code=-3,
    text="Renderer process terminated (status 3): killed",
  )
  assert_true(
    browser_event_msg(terminated)
    is Some(
      Preview(
        LoadFailed(
          id=1,
          text="Renderer process terminated (status 3): killed",
          ..
        )
      )
    ),
  )
  let refused : @protocol.BrowserEventPayload = LoadFailed(
    id=1,
    url="http://127.0.0.1:5173/",
    code=-102,
    text="ERR_CONNECTION_REFUSED",
  )
  assert_true(
    browser_event_msg(refused)
    is Some(Preview(LoadFailed(id=1, url="http://127.0.0.1:5173/", ..))),
  )
  let navigated : @protocol.BrowserEventPayload = Navigated(
    id=2,
    url="https://www.google.com/",
  )
  assert_true(
    browser_event_msg(navigated)
    is Some(Preview(Navigated(id=2, url="https://www.google.com/"))),
  )
}
