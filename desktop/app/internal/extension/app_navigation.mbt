// Main-frame navigation policy for the application window. The page is a
// single document that routes with the History API, so a main-frame
// navigation that leaves its origin is never intended: it would replace the
// whole UI with someone else's page. Proton reports a plain-click link
// (CEF's CURRENT_TAB disposition) only to the navigation handler, never to
// the new-window handler, so this is where such links are caught.

///|
/// The origin Proton serves an `Asset` entry from, in a packaged build and
/// under `proton dev` alike (`PROTON_ENGINE_APP_ORIGIN` in Proton's
/// `app_origin.h`).
const AppOrigin = "https://proton.localhost"

///|
/// How many external links may wait for the system opener at once. Each one
/// takes a user gesture, so anything beyond this is not a person clicking.
const ExternalLinkBacklog = 16

///|
/// What becomes of a main-frame navigation of the application page.
priv enum AppNavigation {
  Stay
  OpenExternally
  Block
}

///|
/// `about:blank` is the document a window holds before its entry loads.
/// Everything else off the app origin leaves the application: a person's
/// click on a web or mail link goes to the system opener, and the rest is
/// refused outright.
fn app_navigation(url : String, user_gesture~ : Bool) -> AppNavigation {
  if url == "about:blank" || is_app_url(url) {
    Stay
  } else if user_gesture && allowed_external_url(url) {
    OpenExternally
  } else {
    Block
  }
}

///|
fn is_app_url(url : String) -> Bool {
  url.strip_prefix(AppOrigin) is Some(rest) &&
  (
    rest.is_empty() ||
    rest.has_prefix("/") ||
    rest.has_prefix("?") ||
    rest.has_prefix("#")
  )
}

///|
/// Hands the application page's external links to the system opener.
/// Proton asks about navigations synchronously, so the policy only queues
/// the URL; `run` opens it from a task.
struct ExternalLinkOpener {
  requests : @core_async.Queue[String]
}

///|
pub fn ExternalLinkOpener::ExternalLinkOpener() -> ExternalLinkOpener {
  { requests: Queue(kind=Blocking(ExternalLinkBacklog)), }
}

///|
/// Open queued links for as long as the application runs.
pub async fn ExternalLinkOpener::run(self : ExternalLinkOpener) -> Unit {
  for ;; {
    open_page_link(self.requests.get())
  }
}

///|
/// The application window's policy: popups behave as in browser tabs, and
/// main-frame navigations stay on the app origin.
pub fn ExternalLinkOpener::app_page_policy(
  self : ExternalLinkOpener,
) -> @proton.WebContentsPolicy {
  {
    ..external_link_policy(),
    navigation_handler: Some((_, request) => {
      match app_navigation(request.url, user_gesture=request.user_gesture) {
        Stay => Allow
        OpenExternally => {
          self.request(request.url)
          Deny
        }
        Block => {
          @xlog.warn() <?
            { "event": "app_navigation_blocked", "url": request.url }
          Deny
        }
      }
    }),
  }
}

///|
fn ExternalLinkOpener::request(self : ExternalLinkOpener, url : String) -> Unit {
  let queued = self.requests.try_put(url) catch {
    // `run` never closes the queue, so a closed one means the application
    // is already gone and there is nothing left to open the link for.
    _ => false
  }
  if !queued {
    @xlog.warn() <? { "event": "external_link_dropped", "url": url }
  }
}

///|
test "app navigation stays on the app origin" {
  assert_true(
    app_navigation("https://proton.localhost/index.html", user_gesture=false)
    is Stay,
  )
  assert_true(
    app_navigation("https://proton.localhost", user_gesture=false) is Stay,
  )
  assert_true(
    app_navigation("https://proton.localhost?x=1#top", user_gesture=true)
    is Stay,
  )
  assert_true(app_navigation("about:blank", user_gesture=false) is Stay)
  // Lookalike hosts are someone else's origin.
  assert_true(
    app_navigation("https://proton.localhost.example.com/", user_gesture=true)
    is OpenExternally,
  )
  assert_true(
    app_navigation("https://proton.localhostx/", user_gesture=false) is Block,
  )
}

///|
test "app navigation hands clicked web links to the system opener" {
  assert_true(
    app_navigation("https://example.com/", user_gesture=true) is OpenExternally,
  )
  assert_true(
    app_navigation("mailto:hello@example.com", user_gesture=true)
    is OpenExternally,
  )
  assert_true(
    app_navigation("https://example.com/", user_gesture=false) is Block,
  )
  assert_true(app_navigation("file:///etc/passwd", user_gesture=true) is Block)
  assert_true(app_navigation("proton://app/", user_gesture=true) is Block)
}
