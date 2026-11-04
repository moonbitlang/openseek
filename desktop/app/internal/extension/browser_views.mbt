// The native half of the dock's Browser tabs: one web contents view per
// page, owned by the window and driven by bridge-local ops. Like
// `shell.open_external`, none of these commands join the shared API catalog
// — a relay browser has no native views to command. View events flow back
// to the page as `browser.event` notifications through the bridge actor.

///|
/// The registry of native browser views. The window handle arrives with
/// Proton's window lifecycle and every view hangs off it by name, so which
/// views exist is never mirrored here — `WindowHandle::find_view` is the
/// truth.
struct BrowserViews {
  mut window : @proton.WindowHandle?
  debug_port : Int32
  mut pick : BrowserPick?
  // The conversation each page's tab belongs to, as the page says whenever
  // it opens or navigates one. The dock's strips are the page's state, and
  // the views of a conversation that is off screen stay alive, hidden; this
  // is what lets a tool an agent calls see its own conversation's tabs and
  // not another's. A page the dock held under no conversation has no entry.
  owners : Map[Int32, String]
  // How the page is told something (a `browser.event`), once the bridge
  // that carries it exists.
  mut notify : (async (@protocol.BrowserEventPayload) -> Unit)?
  // One lock per tab a tool is navigating, so that two navigations of the
  // same tab happen one after the other: each waits for the page to change
  // from what it was, and two waiting at once would both take the first
  // change for their own.
  navigating : Map[Int32, @async.Mutex]
  // Whether a page has connected to the bridge in this window. Until one
  // has, the bridge drops what it is told to deliver — a page that connects
  // reads its state afresh — so nothing sent would ever be answered.
  mut page_connected : Bool
  // Tabs the page has been asked to open and has not answered for yet, by
  // request: where the id it gives the tab is delivered.
  opening : Map[String, @async.Queue[Int32]]
  // Tabs whose view says it is loading: from the moment a navigation
  // starts, before the page it goes to has answered. The page's own account
  // of its document cannot say so, as the document it holds is still there.
  loading : Set[Int32]
  // The document each tab's latest snapshot read, by its time origin. A ref
  // is the browser's id for a node, which another renderer, after the tab
  // has gone to another site, may give a node of its own: refs are acted on
  // only while the tab still shows the document that gave them.
  snapshotted : Map[Int32, Double]
}

///|
/// Configure remote debugging before CEF starts, then attach the native window
/// through window_ready when Proton creates it.
pub async fn BrowserViews::BrowserViews() -> BrowserViews {
  let debug_port = prepare_debugging()
  {
    window: None,
    debug_port,
    pick: None,
    owners: Map([]),
    notify: None,
    navigating: Map([]),
    page_connected: false,
    opening: Map([]),
    loading: Set([]),
    snapshotted: Map([]),
  }
}

///|
pub fn BrowserViews::window_ready(
  self : BrowserViews,
  window : @proton.WindowHandle,
) -> Unit {
  self.window = Some(window)
}

///|
/// Give the views their way to reach the page: `notify` delivers one
/// `browser.event`. Set once the bridge exists, which is after the views do.
pub fn BrowserViews::page_attached(
  self : BrowserViews,
  notify : async (@protocol.BrowserEventPayload) -> Unit,
) -> Unit {
  self.notify = Some(notify)
}

///|
pub fn BrowserViews::window_closed(self : BrowserViews) -> Unit {
  self.cancel_pick()
  self.window = None
  self.page_connected = false
}

///|
/// A page has connected to the bridge, and from here on hears what it is
/// told.
fn BrowserViews::page_is_connected(self : BrowserViews) -> Unit {
  self.page_connected = true
}

///|
/// Drop every browser view. A reloaded page allocates ids from scratch, so
/// views of the previous page must not survive its `host.connect`.
fn BrowserViews::close_all(self : BrowserViews) -> Unit {
  self.cancel_pick()
  self.owners.clear()
  self.navigating.clear()
  self.loading.clear()
  self.snapshotted.clear()
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
fn view_name(id : Int32) -> String {
  "browser-\{id}"
}

///|
/// The page id a view name encodes, or `None` for views that are not
/// browser tabs. The inverse of `view_name`.
pub fn browser_view_id(name : String) -> Int32? {
  guard name.strip_prefix("browser-") is Some(digits) && !digits.is_empty() else {
    return None
  }
  Some(@string.parse_int(digits, base=10)) catch {
    _ => None
  }
}

///|
/// Take note of what the view of tab `id` says of itself.
pub fn BrowserViews::view_event(
  self : BrowserViews,
  id : Int32,
  event : @proton.WebContentsEvent,
) -> Unit {
  match event {
    LoadingChanged(is_loading=true) => self.loading.add(id)
    LoadingChanged(is_loading=false) | Closed => self.loading.remove(id)
    _ => ()
  }
}

///|
/// A view event supported by the window-local frontend contract. Closed tabs
/// are already removed by the frontend's close command; find results have no
/// frontend consumer. Neither becomes a notification.
pub fn view_event_payload(
  id : Int32,
  event : @proton.WebContentsEvent,
) -> @protocol.BrowserEventPayload? {
  let payload : @protocol.BrowserEventPayload = match event {
    DidStartLoading
    | DidFinishLoad
    | BridgeFailed(_)
    | ResourceResponse(..)
    | ResourceCompleted(..)
    | ResourceRequested(..)
    | Closed
    | FoundInPage(..) => return None
    Navigated(url~) => Navigated(id~, url~)
    LoadingChanged(is_loading~) => LoadingChanged(id~, loading=is_loading)
    TitleUpdated(title~) => TitleUpdated(id~, title~)
    LoadFailed(url~, error_code~, error_text~) =>
      LoadFailed(id~, url~, code=error_code, text=error_text)
    RendererProcessTerminated(url~, status~, error_code~, detail~) =>
      // Use the tab's existing error display and reload action. Proton leaves
      // the view open after termination, so this must not become a Closed event.
      RendererProcessTerminated(
        id~,
        url~,
        code=error_code,
        text="Renderer process terminated (status \{status}): \{detail}",
      )
  }
  Some(payload)
}

///|
priv suberror BrowserViewError {
  WindowNotReady
  PageNotConnected
  UnknownView(Int32)
  BlockedURL(String)
} derive(Debug)

///|
impl Show for BrowserViewError with fn output(self, logger) {
  match self {
    WindowNotReady => logger.write_string("The desktop window is not ready")
    PageNotConnected =>
      logger.write_string(
        "The SeekMoon window is still starting; try again in a moment",
      )
    UnknownView(id) => logger.write_string("Unknown browser view \{id}")
    BlockedURL(url) =>
      logger.write_string("Blocked unsupported page URL: \{url}")
  }
}

///|
/// Browser views load web pages and file URLs. Schemes are
/// case-insensitive (RFC 3986), and the
/// frontend passes URLs as typed, so the check lowercases before matching.
fn allowed_page_url(url : String) -> Bool {
  let lower = url.to_lower()
  if lower.strip_prefix("https://") is Some(rest) {
    !rest.is_empty()
  } else if lower.strip_prefix("http://") is Some(rest) {
    !rest.is_empty()
  } else {
    @uri.is_file_url(url)
  }
}

///|
/// The native view's initial paint follows the app canvas instead of flashing
/// the opposite palette while the first document is loading.
fn browser_background(dark : Bool) -> String {
  if dark {
    "#16181D"
  } else {
    "#FBFBF9"
  }
}

///|
/// Best-effort page theme bridge for sites that already expose a conventional
/// light/dark hook (GitHub uses `data-color-mode`). Do not force the root CSS
/// `color-scheme`: it changes the browser canvas and native controls without
/// changing a site's authored foreground colors, which can produce dark-on-dark
/// pages when the site does not support the requested scheme or later restores
/// its own preference.
fn browser_theme_script(dark : Bool) -> String {
  let theme = if dark { "dark" } else { "light" }
  let opposite = if dark { "light" } else { "dark" }
  let script =
    $|(() => {
    $|  const theme = "\{theme}";
    $|  const opposite = "\{opposite}";
    $|  const apply = () => {
    $|    const root = document.documentElement;
    $|    if (!root) return;
    $|    for (const attribute of ["data-color-mode", "data-theme", "data-bs-theme"]) {
    $|      const current = root.getAttribute(attribute);
    $|      if (current !== null && [theme, opposite, "auto", "system"].includes(current.toLowerCase())) {
    $|        root.setAttribute(attribute, theme);
    $|      }
    $|    }
    $|    if (root.classList.contains(theme) || root.classList.contains(opposite)) {
    $|      root.classList.remove(opposite);
    $|      root.classList.add(theme);
    $|    }
    $|  };
    $|  apply();
    $|  if (!document.documentElement) {
    $|    document.addEventListener("DOMContentLoaded", apply, { once: true });
    $|  }
    $|})();
  script
}

///|
/// Theme injection is advisory: a view can be between JavaScript realms while
/// a navigation commits. The later navigated/loading events retry it, so a
/// transient evaluation failure must never turn a successful navigation into
/// a failed browser command.
fn apply_browser_theme(view : @proton.ViewHandle, dark : Bool) -> Unit {
  view.web_contents().eval(browser_theme_script(dark)) catch {
    _ => ()
  }
}

///|
fn BrowserViews::attached_window(
  self : BrowserViews,
) -> @proton.WindowHandle raise BrowserViewError {
  guard self.window is Some(window) else { raise WindowNotReady }
  window
}

///|
fn BrowserViews::view(
  self : BrowserViews,
  id : Int32,
) -> @proton.ViewHandle raise BrowserViewError {
  guard self.attached_window().view(view_name(id)) is Some(view) else {
    raise UnknownView(id)
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
  if self.pick is Some(pick) && pick.id == payload.id {
    self.cancel_pick()
  }
  guard allowed_page_url(payload.url) else { raise BlockedURL(payload.url) }
  let window = self.attached_window()
  match payload.session {
    Some(session) => self.owners[payload.id] = session
    None => self.owners.remove(payload.id)
  }
  let view = match window.view(view_name(payload.id)) {
    Some(view) => {
      view.web_contents().load_url(payload.url)
      view
    }
    None =>
      window.add_view(
        view_name(payload.id),
        ViewConfig(
          initial_url=payload.url,
          web_contents_policy=external_link_policy(),
          width=800,
          height=600,
          visible=false,
          background_color=browser_background(payload.dark),
        ),
      )
  }
  apply_browser_theme(view, payload.dark)
  self.answer_open(payload)
  Acknowledged
}

///|
fn BrowserViews::back(
  self : BrowserViews,
  payload : @protocol.BrowserIdPayload,
) -> @protocol.EmptyReply raise {
  if self.pick is Some(pick) && pick.id == payload.id {
    self.cancel_pick()
  }
  self.view(payload.id).web_contents().back()
  Acknowledged
}

///|
fn BrowserViews::forward(
  self : BrowserViews,
  payload : @protocol.BrowserIdPayload,
) -> @protocol.EmptyReply raise {
  if self.pick is Some(pick) && pick.id == payload.id {
    self.cancel_pick()
  }
  self.view(payload.id).web_contents().forward()
  Acknowledged
}

///|
fn BrowserViews::reload(
  self : BrowserViews,
  payload : @protocol.BrowserIdPayload,
) -> @protocol.EmptyReply raise {
  if self.pick is Some(pick) && pick.id == payload.id {
    self.cancel_pick()
  }
  self.view(payload.id).web_contents().reload(ignore_cache=true)
  Acknowledged
}

///|
fn BrowserViews::set_theme(
  self : BrowserViews,
  payload : @protocol.BrowserThemePayload,
) -> @protocol.EmptyReply raise {
  apply_browser_theme(self.view(payload.id), payload.dark)
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
  if !payload.visible && self.pick is Some(pick) && pick.id == payload.id {
    self.cancel_pick()
  }
  let view = self.view(payload.id)
  view.set_visible(payload.visible)
  if payload.visible && @async.platform is Windows {
    // CEF can raise the main browser's sibling HWND when focus returns to
    // the composer. Restore the view stack without activating the page:
    // Proton applies z-order with SWP_NOACTIVATE, preserving keyboard focus.
    view.set_z_order(0)
  }
  Acknowledged
}

///|
fn BrowserViews::close(
  self : BrowserViews,
  payload : @protocol.BrowserIdPayload,
) -> @protocol.EmptyReply raise {
  if self.pick is Some(pick) && pick.id == payload.id {
    self.cancel_pick()
  }
  self.owners.remove(payload.id)
  self.navigating.remove(payload.id)
  self.loading.remove(payload.id)
  self.snapshotted.remove(payload.id)
  // Closing a view that is already gone is not an error: the close raced a
  // page reload's `close_all`.
  guard self.window is Some(window) else { return Acknowledged }
  if window.view(view_name(payload.id)) is Some(view) {
    let focused = view.web_contents().is_focused()
    if focused {
      window.web_contents().focus()
    }
    window.remove_view(view_name(payload.id))
  }
  Acknowledged
}

///|
fn BrowserViews::focused_browser(
  self : BrowserViews,
) -> @protocol.AppFocusedBrowserReply raise {
  for view in self.attached_window().views() {
    if browser_view_id(view.id()) is Some(id) &&
      view.web_contents().is_focused() {
      return { id: Some(id), }
    }
  }
  { id: None, }
}

///|
/// Native browser-tab endpoints. A relay browser owns no native views, so
/// none enters the shared remote catalog. `browser.navigate` deliberately binds
/// the same create-if-missing handler as `browser.open`.
fn browser_endpoints(views : BrowserViews) -> Array[WindowEndpoint] {
  [
    WindowEndpoint(@commands.browser_pick_element, (_, payload) => {
      views.pick_element(payload)
    }),
    WindowEndpoint(@commands.browser_cancel_pick, (_, payload) => {
      if views.pick is Some(pick) &&
        pick.id == payload.id &&
        pick.request == payload.request {
        views.cancel_pick()
      }
      Acknowledged
    }),
    WindowEndpoint(@commands.app_focused_browser, (_, _) => {
      views.focused_browser()
    }),
    WindowEndpoint(@commands.browser_open, (_, payload) => views.open(payload)),
    WindowEndpoint(@commands.browser_navigate, (_, payload) => {
      views.open(payload)
    }),
    WindowEndpoint(@commands.browser_back, (_, payload) => views.back(payload)),
    WindowEndpoint(@commands.browser_forward, (_, payload) => {
      views.forward(payload)
    }),
    WindowEndpoint(@commands.browser_reload, (_, payload) => {
      views.reload(payload)
    }),
    WindowEndpoint(@commands.browser_set_theme, (_, payload) => {
      views.set_theme(payload)
    }),
    WindowEndpoint(@commands.browser_set_bounds, (_, payload) => {
      views.set_bounds(payload)
    }),
    WindowEndpoint(@commands.browser_set_visible, (_, payload) => {
      views.set_visible(payload)
    }),
    WindowEndpoint(@commands.browser_close, (_, payload) => views.close(payload)),
  ]
}

///|
async test "browser ops refuse to run without a window; close tolerates it" {
  // The ops refuse to run without a window, which is the earliest failure
  // a headless test can observe.
  fn raises(run : () -> @protocol.EmptyReply raise) -> Bool {
    let _ = run() catch { _ => return true }
    false
  }

  let views = BrowserViews::BrowserViews()
  assert_true(
    raises(() => {
      views.open({
        id: 1,
        url: "http://x/",
        dark: true,
        session: None,
        request: None,
      })
    }),
  )
  assert_true(raises(() => views.back({ id: 1, })))
  assert_true(raises(() => views.forward({ id: 1, })))
  assert_true(raises(() => views.reload({ id: 1, })))
  assert_true(raises(() => views.set_theme({ id: 1, dark: true, })))
  assert_true(
    raises(() => views.set_bounds({ id: 1, x: 0, y: 0, width: 10, height: 10, })),
  )
  assert_true(raises(() => views.set_visible({ id: 1, visible: true, })))
  // Closing with no window (or no view) is deliberately not an error:
  // the close raced a page reload's `close_all`.
  assert_true(views.close({ id: 1, }) is Acknowledged)
}

///|
test "browser page theme bridge uses only opted-in theme conventions" {
  assert_eq(browser_background(true), "#16181D")
  assert_eq(browser_background(false), "#FBFBF9")
  let dark = browser_theme_script(true)
  assert_true(dark.contains("const theme = \"dark\";"))
  assert_true(dark.contains("const opposite = \"light\";"))
  assert_true(dark.contains("\"data-color-mode\""))
  assert_true(dark.contains("current.toLowerCase()"))
  assert_false(dark.contains("style.colorScheme"))
  let light = browser_theme_script(false)
  assert_true(light.contains("const theme = \"light\";"))
  assert_true(light.contains("const opposite = \"dark\";"))
}

///|
test "browser page urls support web and local files" {
  assert_true(allowed_page_url("http://127.0.0.1:5173/"))
  assert_true(allowed_page_url("https://github.com/"))
  assert_true(allowed_page_url("HTTPS://Example.COM/x"))
  assert_true(allowed_page_url("HTTP://LOCALHOST:5173/"))
  assert_false(allowed_page_url("proton://app/"))
  assert_true(allowed_page_url("file:///tmp/index.html"))
  assert_true(allowed_page_url("FILE:///tmp/report.pdf"))
  assert_true(allowed_page_url("file:///tmp/image.png"))
  assert_false(allowed_page_url("file://"))
  assert_false(allowed_page_url("javascript:alert(1)"))
  assert_false(allowed_page_url("about:blank"))
}

///|
/// Keep popup handling identical for the application page and browser tabs.
pub fn external_link_policy() -> @proton.WebContentsPolicy {
  WebContentsPolicy(new_window_handler=async fn(_, request) noraise {
    if request.user_gesture {
      ignore(open_external({ url: request.url, })) catch {
        error =>
          @xlog.error() <?
            {
              "event": "external_link_open_failed",
              "url": request.url,
              "error": @debug.render(Repr(error)),
            }
      }
    }
    Deny
  })
}
