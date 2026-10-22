// The browser tools this host offers the agents it runs (`@mcp`, reached
// through HTTP MCP): what an agent can do with the dock's Browser
// tabs. They act on the same native views the `browser.*` window commands
// drive, so a tab is one thing whether the user or an agent is looking at
// it.
//
// A tool sees the tabs of the conversation that called it. The dock keeps a
// strip of tabs per conversation and the window keeps every strip's views
// alive, the off-screen ones hidden, so the window's views alone would show
// an agent every other conversation's tabs as well.
//
// Opening a tab is the page's to do, not the host's: the page allocates a
// tab's id, puts it in a strip, and knows the theme its view starts in. So
// `browser_open` asks the page (`browser.event` kind `open_requested`) and
// waits for the `browser.open` the page answers with. Everything else acts
// on a view that already exists, and the page follows along through the
// view events it already listens to.

///|
/// How long the page has to open a tab it was asked for.
const OpenTimeoutMs : Int32 = 10000

///|
/// How long a tool waits for the page it navigated to finish loading before
/// it answers with the page as it stands.
const SettleTimeoutMs : Int32 = 15000

///|
const SettlePollMs : Int32 = 100

///|
/// What a page says of the document it holds. Asked of the page itself: the
/// view's loading events flicker within one navigation, and a tool that
/// counted them answered before the page it asked for had arrived.
priv struct Document {
  // When the document's own clock started, which no two documents share:
  // how a new document is told from the one it replaced.
  origin : Double
  // The key of the history entry the document is showing, which changes
  // when a navigation stays within the document — a fragment, a step in the
  // page's own history — and only once that navigation has happened. `None`
  // for a document that keeps no such entry.
  entry : String?
  complete : Bool
  url : String
  title : String
}

///|
impl @json.FromJson for Document with fn from_json(json, path) {
  guard json
    is {
      "origin": Number(origin, ..),
      "entry": entry,
      "complete": complete,
      "url": String(url),
      "title": String(title),
      ..
    } else {
    raise JsonDecodeError((path, "expected a document's own account"))
  }
  let entry = match entry {
    String(key) => Some(key)
    Null => None
    _ =>
      raise JsonDecodeError(
        (path.add_key("entry"), "expected a history entry key or null"),
      )
  }
  let complete = match complete {
    True => true
    False => false
    _ => raise JsonDecodeError((path.add_key("complete"), "expected a bool"))
  }
  { origin, entry, complete, url, title, }
}

///|
let document_script : String =
  #|({origin: performance.timeOrigin, entry: globalThis.navigation?.currentEntry?.key ?? null, complete: document.readyState === "complete", url: location.href, title: document.title})

///|
/// The tools an agent uses the dock's browser with.
pub fn browser_tools(views : BrowserViews) -> Array[@mcp.Tool] {
  [
    {
      name: "browser_tabs",
      description: "List the browser tabs open beside this conversation in SeekMoon: each tab's id, URL, title, and whether it is the one currently shown to the user.",
      input_schema: {
        "type": "object",
        "properties": {},
        "additionalProperties": false,
      },
      call: call => views.tabs(call.session).stringify(),
    },
    {
      name: "browser_open",
      description: "Open a new browser tab beside this conversation in SeekMoon and load an address in it. The user sees the tab. Answers with the tab once its page has loaded.",
      input_schema: {
        "type": "object",
        "properties": {
          "url": {
            "type": "string",
            "description": "The address to load: http://, https://, or file://.",
          },
        },
        "required": ["url"],
        "additionalProperties": false,
      },
      call: call => views.open_tab(call.session, call.arguments).stringify(),
    },
    {
      name: "browser_navigate",
      description: "Take one of this conversation's browser tabs somewhere else: load an address in it, go back or forward in its history, or reload it. Give exactly one of `url` and `action`. Answers with the tab once its page has loaded.",
      input_schema: {
        "type": "object",
        "properties": {
          "tab": {
            "type": "integer",
            "description": "The tab's id, from browser_tabs or browser_open.",
          },
          "url": {
            "type": "string",
            "description": "An address to load: http://, https://, or file://.",
          },
          "action": { "type": "string", "enum": ["back", "forward", "reload"] },
        },
        "required": ["tab"],
        "additionalProperties": false,
      },
      call: call => views.navigate_tab(call.session, call.arguments).stringify(),
    },
    {
      name: "browser_snapshot",
      description: "Read what one of this conversation's browser tabs shows, as the page's accessibility tree: one line per element with its role, name, and state, indented under the element it sits in. Elements that can be clicked or typed into carry a `ref`, which names the element until the page loads another document. Content inside frames is not included. Answers with the page as it stands, even while it is still loading.",
      input_schema: {
        "type": "object",
        "properties": {
          "tab": {
            "type": "integer",
            "description": "The tab's id, from browser_tabs or browser_open.",
          },
        },
        "required": ["tab"],
        "additionalProperties": false,
      },
      call: call => views.snapshot_tab(call.session, call.arguments),
    },
    {
      name: "browser_click",
      description: "Click an element in one of this conversation's browser tabs, as a person would with the mouse: the element is scrolled into view and clicked in its middle. Refused when something else, such as a dialog, covers it there. Answers with a new snapshot of the tab once the page has settled, which is the page the click led to if it led to one.",
      input_schema: {
        "type": "object",
        "properties": {
          "tab": {
            "type": "integer",
            "description": "The tab's id, from browser_tabs or browser_open.",
          },
          "ref": {
            "type": "integer",
            "description": "The element's ref, from the tab's latest snapshot: browser_snapshot's, or the one the last browser_click or browser_type answered with.",
          },
        },
        "required": ["tab", "ref"],
        "additionalProperties": false,
      },
      call: call => views.click(call.session, call.arguments),
    },
    {
      name: "browser_type",
      description: "Type into a text field in one of this conversation's browser tabs, replacing what it holds, as a person would with the keyboard. Empty text clears the field. Answers with a new snapshot of the tab once the page has settled.",
      input_schema: {
        "type": "object",
        "properties": {
          "tab": {
            "type": "integer",
            "description": "The tab's id, from browser_tabs or browser_open.",
          },
          "ref": {
            "type": "integer",
            "description": "The field's ref, from the tab's latest snapshot: browser_snapshot's, or the one the last browser_click or browser_type answered with.",
          },
          "text": {
            "type": "string",
            "description": "What the field should hold.",
          },
          "submit": {
            "type": "boolean",
            "description": "Press Enter after typing, which submits most forms. Defaults to false.",
          },
        },
        "required": ["tab", "ref", "text"],
        "additionalProperties": false,
      },
      call: call => views.type_text(call.session, call.arguments),
    },
  ]
}

///|
/// One tab as `browser_tabs` lists it.
fn tab_json(id : Int32, view : @proton.ViewHandle) -> Json raise {
  let tab : Map[String, Json] = { "id": Json(id) }
  // A view that has not committed its first navigation has no entry yet:
  // the tab exists, with no page to name.
  if view.web_contents().navigation_history().active_entry() is Some(entry) {
    tab["url"] = Json(entry.url)
    tab["title"] = Json(entry.title)
  }
  tab["visible"] = Json(view.state().visible)
  Json::object(tab)
}

///|
/// `session`'s Browser tabs, in id order. Which views exist is the window's
/// to say, as everywhere else in this package; whose they are is what the
/// page told `open`.
fn BrowserViews::tabs(self : BrowserViews, session : String) -> Json raise {
  let tabs : Array[(Int32, Json)] = []
  for view in self.attached_window().views() {
    guard browser_view_id(view.id()) is Some(id) &&
      self.owners.get(id) == Some(session) else {
      continue
    }
    tabs.push((id, tab_json(id, view)))
  }
  tabs.sort_by_key(tab => tab.0)
  { "tabs": Json(tabs.map(tab => tab.1)) }
}

///|
/// The view of tab `id`, which must be one of `session`'s. A tab of another
/// conversation is, to this one, a tab that does not exist.
fn BrowserViews::tab_view(
  self : BrowserViews,
  session : String,
  id : Int32,
) -> @proton.ViewHandle raise {
  guard self.owners.get(id) == Some(session) else {
    raise @mcp.ToolError(
      "This conversation has no browser tab \{id}; browser_tabs lists the ones it has.",
    )
  }
  self.view(id)
}

///|
fn refuse_unless_page_url(url : String) -> Unit raise @mcp.ToolError {
  guard allowed_page_url(url) else {
    raise ToolError(
      "Only http://, https://, and file:// addresses can be loaded, and this is none of them: \{url}",
    )
  }
}

///|
/// What a tool is waiting for a view to show.
priv enum Awaited {
  // A tab just opened: the page it was opened on, which may be there
  // already. There is no earlier document it has to take the place of.
  Arrival
  // Something the tool asked of a view that shows a page: a load, a reload,
  // a step in history. What it had before must have given way.
  Change
}

///|
/// Whether a tool can answer with `now`, the page's account of its document,
/// given the account it gave `before` the tool acted. The document must have
/// finished loading, and for a change it must not be where the page already
/// was: either another document, or the same one at another history entry,
/// which is how a navigation within a document shows — a fragment, a step in
/// the page's own history. Time is no part of it: a slow navigation that has
/// not committed looks exactly like the page it has not left.
fn settled(awaited : Awaited, before : Document?, now : Document) -> Bool {
  guard now.complete else { return false }
  match (awaited, before) {
    // A page that gave no account before had none to give way.
    (Arrival, _) | (Change, None) => true
    (Change, Some(before)) =>
      now.origin != before.origin || now.entry != before.entry
  }
}

///|
/// The address of the empty document a view holds before its first page.
const BlankDocument = "about:blank"

///|
/// The page's account of its document, or `None` while it has none to give:
/// between two documents there is nothing to ask, and the empty document a
/// new view starts with is not a page. Any other failure to ask is a
/// failure, and is the caller's to report.
async fn document(connection : @cdp.Connection) -> Document? {
  let document : Document = connection.evaluate(document_script).decode_value() catch {
      // The document that was asked has gone and the next has not arrived.
      @cdp.CommandFailed(..) => return None
      error => raise error
    }
  if document.url == BlankDocument {
    None
  } else {
    Some(document)
  }
}

///|
/// A tab once what `act` asked of its view has settled: do `act`, then ask
/// the page until it holds the document awaited. When patience runs out
/// first, the page is reported as it stands and as still loading — it may
/// not even have left the document it had.
async fn BrowserViews::after(
  self : BrowserViews,
  id : Int32,
  view : @proton.ViewHandle,
  awaited : Awaited,
  act : () -> Unit raise,
) -> Json {
  // One navigation of a tab at a time; see `navigating`. A person
  // navigating the tab meanwhile cannot be made to wait, and the answer is
  // then the page they went to — which is what the tab shows, and says so.
  let turn = self.tab_turn(id)
  turn.acquire()
  defer turn.release()
  let mut answer : Document? = None
  let mut arrived = false
  self.with_page(id, connection => {
    let before = match awaited {
      Arrival => None
      Change => document(connection)
    }
    act()
    for waited = 0; waited < SettleTimeoutMs; waited = waited + SettlePollMs {
      answer = document(connection)
      if answer is Some(now) && settled(awaited, before, now) {
        arrived = true
        break
      }
      @async.sleep(SettlePollMs)
    }
  })
  guard answer is Some(document) else {
    raise @mcp.ToolError(
      "Tab \{id} showed no page within \{SettleTimeoutMs / 1000} seconds.",
    )
  }
  {
    "id": Json(id),
    "url": Json(document.url),
    "title": Json(document.title),
    "loading": Json(!arrived),
    "visible": Json(view.state().visible),
  }
}

///|
/// The lock that orders the navigations of tab `id`.
fn BrowserViews::tab_turn(self : BrowserViews, id : Int32) -> @async.Mutex {
  if self.navigating.get(id) is Some(turn) {
    return turn
  }
  let turn = @async.Mutex()
  self.navigating[id] = turn
  turn
}

///|
/// `with_cdp` for a view that may be between documents. It finds the view's
/// page by a mark it leaves in the document, and a document replaced while
/// it looks takes the mark with it; so the search is tried again on a fresh
/// mark.
async fn[T] BrowserViews::with_page(
  self : BrowserViews,
  id : Int32,
  f : async (@cdp.Connection) -> T,
) -> T {
  for attempt = 0; ; attempt = attempt + 1 {
    let mut entered = false
    return self.with_cdp(id, connection => {
      entered = true
      f(connection)
    }) catch {
      error if @async.is_being_cancelled() => raise error
      // Only the search is retried: a failure of `f` itself is the caller's.
      error if entered || attempt >= 4 => raise error
      _ => continue
    }
  }
}

///|
/// Deliver the id of a tab the page opened because it was asked to. Part of
/// every `browser.open`; an open nobody asked for, or one whose asker has
/// stopped waiting, delivers nothing.
fn BrowserViews::answer_open(
  self : BrowserViews,
  payload : @protocol.BrowserOpenPayload,
) -> Unit {
  guard payload.request is Some(request) &&
    self.opening.get(request) is Some(waiting) else {
    return
  }
  // The queue is unbounded and never closed, so this cannot refuse.
  (waiting.try_put(payload.id) catch { _ => false }) |> ignore
}

///|
/// `browser_open`: ask the page for a tab in `session`'s strip, and answer
/// with it once the page it loads has settled.
async fn BrowserViews::open_tab(
  self : BrowserViews,
  session : String,
  arguments : Json,
) -> Json {
  guard arguments is { "url": String(url), .. } else {
    raise @mcp.ToolError("browser_open needs `url`, the address to load.")
  }
  refuse_unless_page_url(url)
  // Asking a page that has not connected would be asking nobody: the bridge
  // drops the request, and the wait below would run out unanswered.
  guard self.page_connected && self.notify is Some(notify) else {
    raise PageNotConnected
  }
  ignore(self.attached_window())
  let request = @uuid.mint()
  let opened : @async.Queue[Int32] = Queue(kind=Unbounded)
  self.opening[request] = opened
  defer self.opening.remove(request)
  notify({
    "kind": "open_requested",
    "request": Json(request),
    "session": Json(session),
    "url": Json(url),
  })
  guard @async.with_timeout_opt(OpenTimeoutMs, () => opened.get()) is Some(id) else {
    raise @mcp.ToolError(
      "SeekMoon did not open the tab within \{OpenTimeoutMs / 1000} seconds.",
    )
  }
  // The view is already loading what was asked for; there is nothing more
  // to ask of it but to arrive.
  self.after(id, self.tab_view(session, id), Arrival, () => ())
}

///|
/// Where `browser_navigate` takes a tab.
priv enum Navigation {
  To(String)
  Back
  Forward
  Reload
}

///|
/// The string a call gives for `key`, or `None` when it gives none. A value
/// that is there and is not a string is not the same as none: the call is
/// malformed, and acting on the rest of it would be acting on a guess.
fn optional_text(
  arguments : Json,
  key : String,
) -> String? raise @mcp.ToolError {
  guard arguments is Object(fields) && fields.get(key) is Some(value) else {
    return None
  }
  guard value is String(text) else {
    raise ToolError("`\{key}` must be a string.")
  }
  Some(text)
}

///|
/// The whole number a call gives for `key`, refused with `needs` when it
/// gives none.
fn integer_argument(
  arguments : Json,
  key : String,
  needs : String,
) -> Int32 raise @mcp.ToolError {
  guard arguments is Object(fields) &&
    fields.get(key) is Some(Number(number, ..)) &&
    number.to_int().to_double() == number else {
    raise ToolError(needs)
  }
  number.to_int()
}

///|
/// The tab and destination a `browser_navigate` call names.
fn navigation(arguments : Json) -> (Int32, Navigation) raise @mcp.ToolError {
  let tab = integer_argument(
    arguments, "tab", "browser_navigate needs `tab`, the id of the tab to navigate.",
  )
  let url = optional_text(arguments, "url")
  let action = optional_text(arguments, "action")
  let destination = match (url, action) {
    (Some(url), None) => To(url)
    (None, Some("back")) => Back
    (None, Some("forward")) => Forward
    (None, Some("reload")) => Reload
    (None, Some(other)) =>
      raise ToolError("`action` is back, forward, or reload, not \{other}.")
    _ =>
      raise ToolError(
        "browser_navigate needs exactly one of `url` (an address to load) and `action` (back, forward, or reload).",
      )
  }
  (tab, destination)
}

///|
/// `browser_navigate`: take one of `session`'s tabs somewhere, and answer
/// with it once the page has settled.
async fn BrowserViews::navigate_tab(
  self : BrowserViews,
  session : String,
  arguments : Json,
) -> Json {
  let (id, destination) = navigation(arguments)
  if destination is To(url) {
    refuse_unless_page_url(url)
  }
  let view = self.tab_view(session, id)
  // The element the user is picking belongs to the page being left.
  if self.pick is Some(pick) && pick.id == id {
    self.cancel_pick()
  }
  self.after(id, view, Change, () => {
    match destination {
      To(url) => view.web_contents().load_url(url)
      Back => {
        guard view.web_contents().can_go_back() else {
          raise @mcp.ToolError("Tab \{id} has no earlier page to go back to.")
        }
        view.web_contents().back()
      }
      Forward => {
        guard view.web_contents().can_go_forward() else {
          raise @mcp.ToolError("Tab \{id} has no later page to go forward to.")
        }
        view.web_contents().forward()
      }
      Reload => view.web_contents().reload(ignore_cache=true)
    }
  })
}

///|
/// What a tool call came to, as the text of its refusal.
async fn refusal(
  views : BrowserViews,
  tool : String,
  session : String,
  arguments : Json,
) -> String? {
  for candidate in browser_tools(views) {
    if candidate.name == tool {
      return try (candidate.call)({ session, arguments, }) catch {
        error => Some("\{error}")
      } noraise {
        _ => None
      }
    }
  }
  fail("no browser tool named \{tool}")
}

///|
async test "browser tools refuse to run without a window" {
  let views = BrowserViews()
  let not_ready = Some("The desktop window is not ready")
  assert_eq(refusal(views, "browser_tabs", "s-1", {}), not_ready)
  // A tab can only be asked of a page that is there to open it: before one
  // has connected the tool says so at once instead of asking nobody.
  let starting = Some(
    "The SeekMoon window is still starting; try again in a moment",
  )
  let open : Json = { "url": "https://example.com/" }
  assert_eq(refusal(views, "browser_open", "s-1", open), starting)
  views.page_attached(_ => ())
  assert_eq(refusal(views, "browser_open", "s-1", open), starting)
  views.page_is_connected()
  assert_eq(refusal(views, "browser_open", "s-1", open), not_ready)
  views.window_closed()
  assert_eq(refusal(views, "browser_open", "s-1", open), starting)
  // A tab the conversation owns but the window cannot produce.
  views.owners[1] = "s-1"
  assert_eq(
    refusal(views, "browser_navigate", "s-1", { "tab": 1, "action": "reload" }),
    not_ready,
  )
}

///|
async test "a tab's conversation is forgotten with the tab" {
  let views = BrowserViews()
  views.owners[1] = "s-1"
  views.owners[2] = "s-1"
  views.owners[3] = "s-2"
  // Closing one tab forgets that tab alone, window or no window.
  assert_true(views.close({ id: 2, }) is Acknowledged)
  assert_eq(views.owners.to_array(), [(1, "s-1"), (3, "s-2")])
  // A reloaded page allocates ids from scratch, so nothing of the previous
  // page's tabs may be left to name a new one's.
  views.close_all()
  assert_true(views.owners.is_empty())
}

///|
async test "navigations of one tab take turns; those of different tabs do not wait" {
  let views = BrowserViews()
  let first = views.tab_turn(1)
  first.acquire()
  // The same tab's next navigation waits behind the one under way.
  assert_false(views.tab_turn(1).try_acquire())
  // Another tab's does not.
  let other = views.tab_turn(2)
  assert_true(other.try_acquire())
  other.release()
  first.release()
  assert_true(views.tab_turn(1).try_acquire())
  // A closed tab's turn is forgotten with it.
  assert_true(views.close({ id: 1, }) is Acknowledged)
  assert_true(views.navigating.get(1) is None)
  assert_true(views.navigating.get(2) is Some(_))
  views.close_all()
  assert_true(views.navigating.is_empty())
}

///|
async test "a conversation cannot navigate a tab that is not its own" {
  let views = BrowserViews()
  views.owners[1] = "s-other"
  for tab in [1, 7] {
    guard refusal(views, "browser_navigate", "s-1", {
        "tab": Json(tab),
        "url": "https://example.com/",
      })
      is Some(message) else {
      fail("navigating tab \{tab} was not refused")
    }
    assert_true(message.contains("has no browser tab \{tab}"))
  }
}

///|
async test "browser_open and browser_navigate refuse what they cannot load or cannot read" {
  let views = BrowserViews()
  views.owners[1] = "s-1"
  let refused = (tool : String, arguments : Json, expected : String) => {
    guard refusal(views, tool, "s-1", arguments) is Some(message) else {
      fail("\{tool} \{arguments.stringify()} was not refused")
    }
    assert_true(message.contains(expected))
  }
  refused("browser_open", {}, "needs `url`")
  refused("browser_open", { "url": "javascript:alert(1)" }, "Only http://")
  refused("browser_navigate", { "url": "https://example.com/" }, "needs `tab`")
  refused(
    "browser_navigate",
    { "tab": 1.5, "url": "https://example.com/" },
    "needs `tab`",
  )
  refused("browser_navigate", { "tab": 1 }, "exactly one of")
  refused(
    "browser_navigate",
    { "tab": 1, "url": "https://example.com/", "action": "reload" },
    "exactly one of",
  )
  refused("browser_navigate", { "tab": 1, "action": "home" }, "not home")
  // A field that is present and malformed is not read as absent: the valid
  // half of such a call is not carried out.
  refused(
    "browser_navigate",
    { "tab": 1, "url": 42, "action": "reload" },
    "`url` must be a string",
  )
  refused(
    "browser_navigate",
    { "tab": 1, "url": "https://example.com/", "action": null },
    "`action` must be a string",
  )
  refused(
    "browser_navigate",
    { "tab": 1, "url": "about:blank" },
    "Only http://",
  )
}

///|
test "a navigation call names its tab and one destination" {
  assert_true(
    navigation({ "tab": 3, "url": "https://example.com/" })
    is (3, To("https://example.com/")),
  )
  assert_true(navigation({ "tab": 3, "action": "back" }) is (3, Back))
  assert_true(navigation({ "tab": 3, "action": "forward" }) is (3, Forward))
  assert_true(navigation({ "tab": 3, "action": "reload" }) is (3, Reload))
}

///|
test "a tool answers with the document it awaited, once that has loaded" {
  let old : Document = {
    origin: 100,
    entry: Some("e-1"),
    complete: true,
    url: "https://example.com/a",
    title: "A",
  }
  let arriving = { ..old, origin: 200, entry: Some("e-2"), complete: false, }
  let arrived = { ..arriving, complete: true, }
  // A navigation that has not committed looks exactly like the page it has
  // not left, however long it has been: that is never the answer.
  assert_false(settled(Change, Some(old), old))
  assert_false(settled(Change, Some(old), arriving))
  assert_true(settled(Change, Some(old), arrived))
  // A reload keeps its history entry and is another document all the same.
  assert_true(settled(Change, Some(old), { ..old, origin: 300, }))
  // A navigation within the document — a fragment, a step in the page's own
  // history — keeps the document and shows as another entry.
  let within = { ..old, entry: Some("e-3"), url: "https://example.com/a#b", }
  assert_true(settled(Change, Some(old), within))
  assert_false(settled(Change, Some(old), { ..within, complete: false, }))
  // A tab just opened is waiting for a page to arrive, not for one to give
  // way: the document it finds complete is the answer at once.
  assert_true(settled(Arrival, None, old))
  assert_false(settled(Arrival, None, arriving))
  // A page that gave no account before takes the first document to load.
  assert_true(settled(Change, None, arrived))
  // Documents that keep no history entry are told apart by origin alone.
  let bare = { ..old, entry: None, }
  assert_false(settled(Change, Some(bare), bare))
  assert_true(settled(Change, Some(bare), { ..bare, origin: 300, }))
}

///|
test "a page's account of its document is read whole or not at all" {
  let account : Map[String, Json] = {
    "origin": 1791903041652.5,
    "entry": "e-1",
    "complete": false,
    "url": "https://example.com/",
    "title": "",
  }
  let document : Document = @json.from_json(Json::object(account))
  assert_true(document.origin == 1791903041652.5)
  assert_eq(document.entry, Some("e-1"))
  assert_false(document.complete)
  assert_eq((document.url, document.title), ("https://example.com/", ""))
  // No history entry is said as null, which is not the same as not saying.
  let without = account.copy()
  without["entry"] = null
  let document : Document = @json.from_json(Json::object(without))
  assert_true(document.entry is None)
  for missing in ["origin", "entry", "complete", "url", "title"] {
    let partial = account.copy()
    partial.remove(missing)
    let refused = try {
      let _ : Document = @json.from_json(Json::object(partial))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
}

///|
async test "the page's open delivers its tab's id to the tool that asked for it" {
  let views = BrowserViews()
  let opened : @async.Queue[Int32] = Queue(kind=Unbounded)
  views.opening["r-1"] = opened
  let payload : @protocol.BrowserOpenPayload = {
    id: 5,
    url: "https://example.com/",
    dark: false,
    session: Some("s-1"),
    request: None,
  }
  // An open nobody asked for, and one answering a request nobody is waiting
  // on any more, deliver nothing.
  views.answer_open(payload)
  views.answer_open({ ..payload, id: 6, request: Some("r-gone"), })
  views.answer_open({ ..payload, id: 7, request: Some("r-1"), })
  assert_eq(opened.get(), 7)
}
