// The browser subsystem behind the dock's `Browser` tabs: per-page address
// state only. Every page is rendered by a native web contents view the host
// owns; this model mirrors what the host reports (URL, title, load state) so
// the toolbar and tab chips can render without asking the host anything.

///|
/// A rectangle in CSS pixels — the browser pane's placement, which at 100%
/// zoom equals the window-logical bounds a native view takes.
pub(all) struct Rect {
  x : Int
  y : Int
  width : Int
  height : Int
} derive(Eq)

///|
/// One browser page's state. `url` is `None` until the first navigation —
/// a blank tab has no native view yet (the host creates it on the first
/// `browser.open`), so nothing covers the pane while the address bar waits
/// for input.
pub(all) struct PageState {
  // The last URL this page was sent to (optimistic) or reported at (from a
  // `Navigated` event). `None` = blank tab, no native view exists.
  url : String?
  // The address bar's draft. Mirrors `url` after a navigation; edited
  // freely in between.
  input : String
  // The page title from the host's `TitleUpdated` events; empty until one
  // arrives.
  title : String
  loading : Bool
  // The last load failure's description, cleared by the next navigation.
  failure : String?
} derive(Eq)

///|
/// The browser subsystem's state: every live page keyed by its dock tab id.
/// Ids are page-global (never per conversation) so parked strips can keep
/// referring to their pages, and only ever grow.
pub(all) struct State {
  pages : Map[Int, PageState]
  next_id : Int
} derive(Eq)

///|
pub fn State::empty() -> State {
  { pages: Map([]), next_id: 1, }
}

///|
/// Allocate a page. A blank tab starts without a URL; a routed link opens
/// with one (the caller also asks the host to create the native view then).
pub fn open_page(state : State, url? : String) -> (State, Int) {
  let id = state.next_id
  let pages = state.pages.copy()
  pages[id] = {
    url,
    input: url.unwrap_or(""),
    title: "",
    loading: url is Some(_),
    failure: None,
  }
  ({ pages, next_id: id + 1, }, id)
}

///|
pub fn close_page(state : State, id : Int) -> State {
  let pages = state.pages.copy()
  pages.remove(id)
  { ..state, pages, }
}

///|
pub fn page(state : State, id : Int) -> PageState? {
  state.pages.get(id)
}

///|
/// Point the page at `url`: it becomes the page's target, the draft mirrors
/// it, and the previous failure clears. The title survives only a
/// same-document jump — a new document's title has to be reported by the
/// host, and nothing guarantees one ever is (a failed load carries no title
/// at all), so keeping the old one would leave the previous site's name
/// labelling the new page indefinitely. Dropped, `page_label` falls back to
/// the destination's host until a `TitleUpdated` lands.
fn PageState::commit_url(self : PageState, url : String) -> PageState {
  let title = if self.url is Some(current) &&
    document_of(current) == document_of(url) {
    self.title
  } else {
    ""
  }
  { ..self, url: Some(url), input: url, title, failure: None, }
}

///|
/// Commit a navigation optimistically. The caller sends the matching
/// `browser.open`/`browser.navigate` to the host.
pub fn navigate(state : State, id : Int, url : String) -> State {
  guard state.pages.get(id) is Some(previous) else { return state }
  let pages = state.pages.copy()
  pages[id] = { ..previous.commit_url(url), loading: true, }
  { ..state, pages, }
}

///|
/// The tab chip's label: the page title once one arrived, else the URL's
/// host, else a blank-tab placeholder.
pub fn page_label(page : PageState) -> String {
  if !page.title.is_empty() {
    return page.title
  }
  match page.url {
    Some(url) => host_of(url).unwrap_or(url)
    None => "New Tab"
  }
}

///|
pub extend PageState with Eq::{equal, not_equal}

///|
pub extend Rect with Eq::{equal, not_equal}

///|
pub extend State with Eq::{equal, not_equal}
