// The native half of the dock's Browser tabs: one web contents view per
// page, owned by the window and driven by bridge-local ops. Like
// `shell.open_external`, none of these commands join the shared API catalog
// — a relay browser has no native views to command. View events flow back
// to the page as `browser.event` notifications through the bridge actor.

///|
/// The registry of native browser views. The window handle arrives with
/// Proton's window lifecycle and every view hangs off it by name, so this
/// holds no view map of its own — `WindowHandle::find_view` is the truth.
struct BrowserViews {
  mut window : @proton.WindowHandle?
}

///|
pub fn BrowserViews::new() -> BrowserViews {
  { window: None }
}

///|
pub fn BrowserViews::window_ready(
  self : BrowserViews,
  window : @proton.WindowHandle,
) -> Unit {
  self.window = Some(window)
}

///|
pub fn BrowserViews::window_closed(self : BrowserViews) -> Unit {
  self.window = None
}

///|
/// Drop every browser view. A reloaded page allocates ids from scratch, so
/// views of the previous page must not survive its `host.connect`.
fn BrowserViews::close_all(self : BrowserViews) -> Unit {
  guard self.window is Some(window) else { return }
  for view in window.views() {
    if browser_view_id(view.id()) is Some(_) {
      window.remove_view(view.id()) catch {
        _ => ()
      }
    }
  }
}

///|
fn view_name(id : Int) -> String {
  "browser-\{id}"
}

///|
/// The page id a view name encodes, or `None` for views that are not
/// browser tabs. The inverse of `view_name`.
pub fn browser_view_id(name : String) -> Int? {
  guard name.strip_prefix("browser-") is Some(digits) && !digits.is_empty() else {
    return None
  }
  Some(@string.parse_int(digits, base=10)) catch {
    _ => None
  }
}

///|
/// A view event as the `browser.event` notification payload the frontend
/// decodes.
pub fn view_event_json(id : Int, event : @proton.ViewEvent) -> Json {
  match event {
    Navigated(url~) =>
      { "id": id.to_json(), "kind": "navigated", "url": url.to_json() }
    LoadingChanged(is_loading~) =>
      { "id": id.to_json(), "kind": "loading", "loading": is_loading.to_json() }
    TitleUpdated(title~) =>
      { "id": id.to_json(), "kind": "title", "title": title.to_json() }
    LoadFailed(url~, error_code~, error_text~) =>
      {
        "id": id.to_json(),
        "kind": "load_failed",
        "url": url.to_json(),
        "code": error_code.to_json(),
        "text": error_text.to_json(),
      }
  }
}

///|
priv suberror BrowserViewError {
  BrowserViewError(String)
}

///|
impl Show for BrowserViewError with fn output(self, logger) {
  match self {
    BrowserViewError(message) => logger.write_string(message)
  }
}

///|
/// Browser views navigate to web pages only — never local files or the
/// app's own scheme. Schemes are case-insensitive (RFC 3986), and the
/// frontend passes URLs as typed, so the check lowercases before matching.
fn allowed_page_url(url : String) -> Bool {
  let buf = StringBuilder::new()
  for ch in url {
    buf.write_char(ch.to_ascii_lowercase())
  }
  let lower = buf.to_string()
  if lower.strip_prefix("https://") is Some(rest) {
    !rest.is_empty()
  } else if lower.strip_prefix("http://") is Some(rest) {
    !rest.is_empty()
  } else {
    false
  }
}

///|
fn BrowserViews::attached_window(
  self : BrowserViews,
) -> @proton.WindowHandle raise BrowserViewError {
  guard self.window is Some(window) else {
    raise BrowserViewError("The desktop window is not ready")
  }
  window
}

///|
fn BrowserViews::view(
  self : BrowserViews,
  id : Int,
) -> @proton.ViewHandle raise BrowserViewError {
  guard self.attached_window().view(view_name(id)) is Some(view) else {
    raise BrowserViewError("Unknown browser view \{id}")
  }
  view
}

///|
/// Point page `id`'s native view at `url`, creating the view if it does not
/// exist yet. A fresh view starts hidden at a placeholder size; the frontend
/// shows and places it with the `browser.set_bounds`/`browser.set_visible`
/// that follow its next pane measurement. `browser.open` and
/// `browser.navigate` share this create-if-missing semantic on purpose: the
/// frontend commits a page's URL optimistically, so if the creating call was
/// rejected (or raced a reload's `close_all`), the next navigation must be
/// able to build the view rather than strand the tab.
fn BrowserViews::open(
  self : BrowserViews,
  payload : @protocol.BrowserOpenPayload,
) -> @protocol.EmptyReply raise {
  guard allowed_page_url(payload.url) else {
    raise BrowserViewError("Blocked non-web page URL")
  }
  let window = self.attached_window()
  match window.view(view_name(payload.id)) {
    Some(view) => view.load_url(payload.url)
    None =>
      ignore(
        window.add_view(
          view_name(payload.id),
          @proton.view(payload.url, width=800, height=600, visible=false),
        ),
      )
  }
  Acknowledged
}

///|
fn BrowserViews::back(
  self : BrowserViews,
  payload : @protocol.BrowserIdPayload,
) -> @protocol.EmptyReply raise {
  self.view(payload.id).back()
  Acknowledged
}

///|
fn BrowserViews::forward(
  self : BrowserViews,
  payload : @protocol.BrowserIdPayload,
) -> @protocol.EmptyReply raise {
  self.view(payload.id).forward()
  Acknowledged
}

///|
fn BrowserViews::reload(
  self : BrowserViews,
  payload : @protocol.BrowserIdPayload,
) -> @protocol.EmptyReply raise {
  self.view(payload.id).reload()
  Acknowledged
}

///|
/// Open Chromium's developer tools for the SeekMoon frontend page itself.
fn BrowserViews::open_app_devtools(
  self : BrowserViews,
) -> @protocol.EmptyReply raise {
  self.attached_window().browser().open_devtools()
  Acknowledged
}

///|
fn BrowserViews::set_bounds(
  self : BrowserViews,
  payload : @protocol.BrowserBoundsPayload,
) -> @protocol.EmptyReply raise {
  self
  .view(payload.id)
  .set_bounds(
    x=payload.x,
    y=payload.y,
    width=payload.width,
    height=payload.height,
  )
  Acknowledged
}

///|
fn BrowserViews::set_visible(
  self : BrowserViews,
  payload : @protocol.BrowserVisiblePayload,
) -> @protocol.EmptyReply raise {
  self.view(payload.id).set_visible(payload.visible)
  Acknowledged
}

///|
fn BrowserViews::close(
  self : BrowserViews,
  payload : @protocol.BrowserIdPayload,
) -> @protocol.EmptyReply raise {
  // Closing a view that is already gone is not an error: the close raced a
  // page reload's `close_all`.
  guard self.window is Some(window) else { return Acknowledged }
  if window.view(view_name(payload.id)) is Some(_) {
    window.remove_view(view_name(payload.id))
  }
  Acknowledged
}

///|
/// The dock's browser-tab endpoints, kept beside their handlers so the two
/// cannot drift. All of them are window-only like `shell.open_external`:
/// the native web contents views live in this window, so a relay browser
/// has nothing to command. `browser.navigate` deliberately binds the same
/// create-if-missing handler as `browser.open`.
fn browser_endpoints(views : BrowserViews) -> Array[@endpoint.Endpoint] {
  [
    @endpoint.Endpoint::window(@commands.browser_open, (_, payload) => {
      views.open(payload)
    }),
    @endpoint.Endpoint::window(@commands.browser_navigate, (_, payload) => {
      views.open(payload)
    }),
    @endpoint.Endpoint::window(@commands.browser_back, (_, payload) => {
      views.back(payload)
    }),
    @endpoint.Endpoint::window(@commands.browser_forward, (_, payload) => {
      views.forward(payload)
    }),
    @endpoint.Endpoint::window(@commands.browser_reload, (_, payload) => {
      views.reload(payload)
    }),
    @endpoint.Endpoint::window(@commands.app_open_devtools, (_, _) => {
      views.open_app_devtools()
    }),
    @endpoint.Endpoint::window(@commands.browser_set_bounds, (_, payload) => {
      views.set_bounds(payload)
    }),
    @endpoint.Endpoint::window(@commands.browser_set_visible, (_, payload) => {
      views.set_visible(payload)
    }),
    @endpoint.Endpoint::window(@commands.browser_close, (_, payload) => {
      views.close(payload)
    }),
  ]
}

///|
test "browser ops are absent from the relay method catalog" {
  let state = @api.ApiState::new(engine="unused")
  let connection = @host.HostConnection::new()
  let catalog = @api.endpoints(state, connection)
  for endpoint in browser_endpoints(BrowserViews::new()) {
    let name = endpoint.name()
    assert_false(catalog.iter().any(shared => shared.name() == name))
  }
}

///|
test "browser ops refuse to run without a window; close tolerates it" {
  // The ops refuse to run without a window, which is the earliest failure
  // a headless test can observe.
  fn raises(run : () -> @protocol.EmptyReply raise) -> Bool {
    let _ = run() catch { _ => return true }
    false
  }

  let views = BrowserViews::new()
  assert_true(raises(() => views.open({ id: 1, url: "http://x/" })))
  assert_true(raises(() => views.back({ id: 1 })))
  assert_true(raises(() => views.forward({ id: 1 })))
  assert_true(raises(() => views.reload({ id: 1 })))
  assert_true(raises(() => views.open_app_devtools()))
  assert_true(
    raises(() => views.set_bounds({ id: 1, x: 0, y: 0, width: 10, height: 10 })),
  )
  assert_true(raises(() => views.set_visible({ id: 1, visible: true })))
  // Closing with no window (or no view) is deliberately not an error:
  // the close raced a page reload's `close_all`.
  assert_true(views.close({ id: 1 }) is Acknowledged)
}

///|
test "view names round-trip and reject foreign views" {
  assert_true(browser_view_id("browser-3") == Some(3))
  assert_true(browser_view_id("browser-42") == Some(42))
  assert_true(browser_view_id("browser-") is None)
  assert_true(browser_view_id("sidebar") is None)
  assert_true(browser_view_id("browser-x") is None)
}

///|
test "browser page urls are web-only" {
  assert_true(allowed_page_url("http://127.0.0.1:5173/"))
  assert_true(allowed_page_url("https://github.com/"))
  assert_true(allowed_page_url("HTTPS://Example.COM/x"))
  assert_true(allowed_page_url("HTTP://LOCALHOST:5173/"))
  assert_false(allowed_page_url("proton://app/"))
  assert_false(allowed_page_url("file:///etc/passwd"))
  assert_false(allowed_page_url("javascript:alert(1)"))
  assert_false(allowed_page_url("about:blank"))
}
